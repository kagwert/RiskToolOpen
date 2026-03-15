%% runUnderweightStrategy.m
% Main orchestration script for the equity underweight strategy.
%
% STRATEGY OVERVIEW
% -----------------
%   Baseline allocation: 50% equity
%   Underweight targets: 35% (mild) and 20% (severe)
%
%   Two approaches are evaluated and compared:
%     Approach 1 — Static thresholds applied to individual signals and
%                  weighted composites of macro/market indicators.
%     Approach 2 — Shallow decision tree (fitctree, MaxNumSplits=4)
%                  trained on signal features to classify equity regimes.
%
% REGIME LABELS (for training and evaluation)
% -------------------------------------------
%   SevereUW: 3-month forward return < 0  AND  ann. vol > 30%
%   MildUW  : 3-month forward return < 0  (but vol ≤ 30%)
%   Neutral : all other periods
%
% USAGE
% -----
%   Run this script from the SignalBuilder root directory, or add both
%   SignalBuilder/ and SignalBuilder/Underweight/ to the MATLAB path.
%
%   cd('C:\CIO\ClaudeCode\SignalBuilder')
%   run('Underweight\runUnderweightStrategy.m')

clear; clc;

%% ========================================================================
%  0. Path setup
%  ========================================================================
scriptDir = fileparts(mfilename('fullpath'));
rootDir   = fileparts(scriptDir);
addpath(rootDir);
addpath(scriptDir);

%% ========================================================================
%  1. Parameters  (all modifiable — no magic numbers buried in functions)
%  ========================================================================
p = struct();

% --- Data ---
p.EquityTicker    = 'SPY';
p.StartDate       = '1994-01-01';   % BAMLH0A0HYM2 available from 1997;
                                     % start earlier to warm up Z-score windows

% --- Label thresholds ---
p.SevereRetThresh = 0;      % 3m fwd return < 0% → qualifies as severe (with vol gate)
p.SevereVolThresh = 0.30;   % 3m fwd ann vol > 30% → severe (recessionary bear)
p.MildRetThresh   = 0;      % 3m fwd return < 0% → qualifies as mild (lower vol)

% --- Equity allocations ---
p.BaseWeight      = 0.50;   % neutral (baseline)
p.MildWeight      = 0.35;   % mild underweight
p.SevereWeight    = 0.20;   % severe underweight

% --- Signal construction ---
p.MAWindow        = 200;    % equity trend: SPY vs 200-day MA

% --- Decision tree ---
p.TreeMaxSplits   = 4;      % max branch splits → interpretable (≤5 leaves)

% --- Portfolio evaluation: bond/cash return for non-equity portion ---
p.BondAnnReturn   = 0.04;   % assumed 4% p.a. on non-equity (bonds/cash)

%% ========================================================================
%  2. Initialise DataManager
%  ========================================================================
fprintf('=== Initialising DataManager ===\n');
dm = Model.DataManager();
dm.init();

%% ========================================================================
%  3. Build signal feature timetable (monthly)
%  ========================================================================
fprintf('\n=== Building Signals ===\n');
features = buildSignals(dm, p.EquityTicker, ...
    StartDate = p.StartDate, ...
    MAWindow  = p.MAWindow);

%% ========================================================================
%  4. Label equity regimes from forward SPY returns and vol
%  ========================================================================
fprintf('\n=== Labelling Equity Regimes ===\n');
tt_spy = timetable.empty;
try; tt_spy = dm.fetch_yahoo(p.EquityTicker, p.StartDate, ""); catch; end
if height(tt_spy) < 252 * 25
    try
        tt_st = dm.fetch_stooq(p.EquityTicker, p.StartDate, "");
        if height(tt_st) > height(tt_spy); tt_spy = tt_st; end
    catch; end
end
if height(tt_spy) < 252 * 25
    fprintf('[runUnderweightStrategy] Price history shorter than 25yr, using Stooq ^SPX...\n');
    tt_spy = runUW_fredSp500(dm, p.StartDate);
end
md = Model.MarketData(p.EquityTicker);
md.loadFromTimetable(tt_spy, 'Yahoo');

labels = labelEquityRegimes(md.Prices, features.Time, ...
    SevereRetThresh = p.SevereRetThresh, ...
    SevereVolThresh = p.SevereVolThresh, ...
    MildRetThresh   = p.MildRetThresh);

%% ========================================================================
%  5. Approach 1 — Static thresholds
%  ========================================================================
fprintf('\n=== Approach 1: Static Thresholds ===\n');
thresh = thresholdApproach(features, labels, ...
    BaseWeight   = p.BaseWeight, ...
    MildWeight   = p.MildWeight, ...
    SevereWeight = p.SevereWeight);

%% ========================================================================
%  6. Approach 2 — Decision tree
%  ========================================================================
fprintf('\n=== Approach 2: Decision Tree ===\n');
dtree = decisionTreeApproach(features, labels, ...
    MaxNumSplits = p.TreeMaxSplits, ...
    BaseWeight   = p.BaseWeight, ...
    MildWeight   = p.MildWeight, ...
    SevereWeight = p.SevereWeight);

%% ========================================================================
%  7. Portfolio performance evaluation
%     equity_return × equity_alloc + bond_return × (1 − equity_alloc)
%  ========================================================================
fprintf('\n=== Portfolio Performance Evaluation ===\n');

% Monthly equity return from SPY prices (resampled to monthly)
monthGrid   = features.Time;
monthYM     = year(monthGrid)*100 + month(monthGrid);
dailyYM     = year(md.Prices.Time)*100 + month(md.Prices.Time);
closePrices = md.Prices.Close;
monthClose  = nan(numel(monthGrid), 1);

for k = 1 : numel(monthGrid)
    idx = find(dailyYM == monthYM(k), 1, 'last');
    if ~isempty(idx)
        monthClose(k) = closePrices(idx);
    end
end
equityMonthRet = [NaN; diff(monthClose) ./ monthClose(1:end-1)];

bondMonthRet = (1 + p.BondAnnReturn)^(1/12) - 1;   % simple monthly equivalent

% Benchmark allocation placeholder (correctly sized version built after alignment)
benchAlloc = repmat(p.BaseWeight, numel(monthGrid), 1);

% Best threshold variants
variantNames = {'Benchmark50pct', 'Composite', 'MacroComposite', ...
                'MarketComposite', 'DecisionTree'};

allocSeries = {benchAlloc, ...
    thresh.Composite.BestAlloc, ...
    thresh.MacroComposite.BestAlloc, ...
    thresh.MarketComposite.BestAlloc, ...
    dtree.Allocation};

% Align features and labels to common valid subset (used in perf eval + charts)
[~, iF_align, iL_align] = intersect(features.Time, labels.Time);
lbl_all   = labels(iL_align, :);
validMask = ~isnan(lbl_all.Label);           % logical index into intersection
eqRet_v   = equityMonthRet(iF_align(validMask));  % equity returns at valid months
benchAlloc_v = repmat(p.BaseWeight, sum(validMask), 1);

% Replace benchmark entry with correctly sized vector
allocSeries{1} = benchAlloc_v;

perfRows = cell(numel(variantNames), 1);
for v = 1 : numel(variantNames)
    alloc_v = allocSeries{v};   % all already sized to sum(validMask)
    m = runUW_evalPortfolio(alloc_v, eqRet_v, bondMonthRet);
    perfRows{v} = {variantNames{v}, m.TotalReturn, m.AnnReturn, ...
        m.SharpeRatio, m.MaxDrawdown, m.AvgEquityAlloc};
end

% Assemble display table (cellfun avoids cell2mat type issues in R2021b)
variantCol = variantNames(:);
totalRet   = cellfun(@(r) r{2}, perfRows);
annRet     = cellfun(@(r) r{3}, perfRows);
sharpe     = cellfun(@(r) r{4}, perfRows);
maxDD      = cellfun(@(r) r{5}, perfRows);
avgAlloc   = cellfun(@(r) r{6}, perfRows);
perfTable  = table(variantCol, totalRet(:), annRet(:), sharpe(:), maxDD(:), avgAlloc(:), ...
    'VariableNames', {'Variant','TotalReturn','AnnReturn', ...
    'SharpeRatio','MaxDrawdown','AvgEquityAlloc'});

fprintf('\nPortfolio performance (equity + %.0f%% p.a. bonds on non-equity):\n', ...
    p.BondAnnReturn*100);
disp(perfTable)

%% ========================================================================
%  8. Charts
%  ========================================================================
% Reuse alignment already computed in section 7
featAligned = features(iF_align, :);
validIdx    = validMask;                              % same logical mask
T           = featAligned.Time(validIdx);
lbl_v       = lbl_all.Label(validIdx);

% Colour palette for regimes
cNeutral = [0.85, 0.92, 1.00];   % light blue
cMild    = [1.00, 0.93, 0.80];   % light orange
cSevere  = [1.00, 0.80, 0.80];   % light red

%% --- Figure 1: Four signals + regime shading ---
figure('Name','Underweight Strategy — Signals', 'NumberTitle','off', ...
    'Position',[50 50 1200 800]);
sigCols = {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend'};
sigTitles = {'Payrolls Momentum (PAYEMS)', 'Yield Curve Slope (T10Y2Y)', ...
    'HY Credit Spread (BAMLH0A0HYM2)', sprintf('%s Price Trend (vs %d-d MA)', ...
    p.EquityTicker, p.MAWindow)};

for k = 1 : 4
    ax = subplot(2, 2, k);
    sig_k = featAligned.(sigCols{k})(validIdx);
    runUW_shadeRegimes(ax, T, lbl_v, cNeutral, cMild, cSevere);
    hold on
    plot(T, sig_k, 'Color', [0.1 0.3 0.7], 'LineWidth', 1.5);
    yline(0, 'k--', 'LineWidth', 0.8);
    ylim([-1.1 1.1]);
    ylabel('Signal'); title(sigTitles{k});
    set(ax, 'XGrid','on', 'YGrid','on');
end
sgtitle('Signal Components — shading: blue=Neutral, orange=MildUW, red=SevereUW', ...
    'FontWeight','bold');

%% --- Figure 2: Composite signal vs best threshold lines ---
figure('Name','Underweight Strategy — Composite Signal', 'NumberTitle','off', ...
    'Position',[100 100 1100 400]);
ax2 = gca;
comp_v = featAligned.Composite(validIdx);
runUW_shadeRegimes(ax2, T, lbl_v, cNeutral, cMild, cSevere);
hold on
plot(T, comp_v, 'Color', [0.1 0.3 0.7], 'LineWidth', 2, 'DisplayName','Composite');
bestMild   = thresh.Composite.BestThresholds(1);
bestSevere = thresh.Composite.BestThresholds(2);
yline(bestMild,   '--', 'Color', [0.9 0.5 0], 'LineWidth', 1.5, ...
    'Label', sprintf('Mild thr = %.2f', bestMild),   'LabelHorizontalAlignment','right');
yline(bestSevere, '--', 'Color', [0.8 0 0],   'LineWidth', 1.5, ...
    'Label', sprintf('Severe thr = %.2f', bestSevere), 'LabelHorizontalAlignment','right');
yline(0, 'k:', 'LineWidth', 0.8);
ylim([-1.1 1.1]);
ylabel('Composite Signal'); title('Equal-Weighted Composite Signal with Best Threshold Lines');
legend({'Composite'}, 'Location','best');
set(ax2, 'XGrid','on', 'YGrid','on');

%% --- Figure 3: Equity allocation over time (all variants) ---
figure('Name','Underweight Strategy — Equity Allocation', 'NumberTitle','off', ...
    'Position',[150 150 1100 500]);
ax3 = gca;
runUW_shadeRegimes(ax3, T, lbl_v, cNeutral, cMild, cSevere);
hold on
yline(p.BaseWeight,    'k-',  'LineWidth', 1.2, 'Label', 'Benchmark 50%');
plot(T, thresh.Composite.BestAlloc,      '-',  'Color',[0.2 0.5 0.9], ...
    'LineWidth', 2, 'DisplayName', 'Composite Threshold');
plot(T, thresh.MacroComposite.BestAlloc, '--', 'Color',[0.1 0.7 0.4], ...
    'LineWidth', 1.5, 'DisplayName', 'Macro Composite Threshold');
plot(T, dtree.Allocation,                '-',  'Color',[0.8 0.2 0.2], ...
    'LineWidth', 2, 'DisplayName', 'Decision Tree');
ylim([0.15, 0.55]);
yticks([0.20 0.35 0.50]);
yticklabels({'20% (severe UW)', '35% (mild UW)', '50% (neutral)'});
ylabel('Equity Allocation'); title('Equity Allocation Over Time');
legend({'Composite Threshold','Macro Composite','Decision Tree'}, 'Location','best');
set(ax3, 'XGrid','on', 'YGrid','on');

%% --- Figure 4: Decision tree visualisation ---
figure('Name','Decision Tree', 'NumberTitle','off', 'Position',[200 200 900 500]);
view(dtree.Tree, 'Mode', 'graph');

%% ========================================================================
%  9. Composite relative performance chart + summary statistics
%     Three strategies:
%       (A) 100% Equities   – always fully invested, no risk management
%       (B) Benchmark 50/50 – constant 50% equity / 50% bonds
%       (C) Two-Step De-Risk – MarketComposite signal; steps down to 35%
%                              (mild) and 20% (severe) based on signals
%  ========================================================================

alloc_100eq = ones(sum(validMask), 1);
alloc_bench = repmat(p.BaseWeight, sum(validMask), 1);
alloc_2step = thresh.MarketComposite.BestAlloc;

stratLabels = {'100% Equities', 'Benchmark (50/50)', 'Two-Step De-Risk'};
allocList   = {alloc_100eq, alloc_bench, alloc_2step};
nStrat      = 3;
colours     = {[0.85, 0.20, 0.20], [0.30, 0.30, 0.30], [0.10, 0.45, 0.85]};
lineStyles  = {'--', ':', '-'};

% Compute equity curves and metrics for each strategy
stratCurves = cell(nStrat, 1);
sm          = struct('AnnReturn', 0, 'AnnVol', 0, 'MaxDrawdown', 0, ...
                     'SharpeRatio', 0, 'AvgEquityAlloc', 0);
stratMetrics = repmat(sm, nStrat, 1);

for s = 1 : nStrat
    alloc_s   = allocList{s};
    portRet_s = alloc_s .* eqRet_v + (1 - alloc_s) .* bondMonthRet;
    portRet_s(isnan(portRet_s)) = 0;
    eq_s = cumprod(1 + portRet_s);
    stratCurves{s} = eq_s;

    yrs_s = numel(portRet_s) / 12;
    stratMetrics(s).AnnReturn      = (eq_s(end))^(1/yrs_s) - 1;
    stratMetrics(s).AnnVol         = std(portRet_s, 'omitnan') * sqrt(12);
    running_s = cummax(eq_s);
    stratMetrics(s).MaxDrawdown    = min((eq_s - running_s) ./ running_s);
    stratMetrics(s).SharpeRatio    = stratMetrics(s).AnnReturn / ...
                                     max(stratMetrics(s).AnnVol, eps);
    stratMetrics(s).AvgEquityAlloc = mean(alloc_s, 'omitnan');
end

% ---- Print summary table ----
nYrs = numel(T) / 12;
fprintf('\n=== Composite Performance Summary (%d-year backtest, %s to %s) ===\n', ...
    round(nYrs), datestr(T(1),'mmm-yyyy'), datestr(T(end),'mmm-yyyy'));
fprintf('%-20s  %11s  %8s  %12s  %8s  %11s\n', ...
    'Strategy', 'Return p.a.', 'Vol p.a.', 'Max Drawdown', 'Sharpe', 'Avg Eq Alloc');
fprintf('%s\n', repmat('-', 1, 78));
for s = 1 : nStrat
    m = stratMetrics(s);
    fprintf('%-20s  %10.2f%%  %7.2f%%  %11.2f%%  %8.2f  %10.1f%%\n', ...
        stratLabels{s}, m.AnnReturn*100, m.AnnVol*100, ...
        m.MaxDrawdown*100, m.SharpeRatio, m.AvgEquityAlloc*100);
end
fprintf('%s\n', repmat('-', 1, 78));
fprintf('Non-equity portion earns %.0f%% p.a. (bonds/cash assumption)\n', ...
    p.BondAnnReturn * 100);

% ---- Figure 5: Composite relative performance ----
figure('Name', 'Underweight Strategy — Composite Relative Performance', ...
    'NumberTitle', 'off', 'Position', [350, 80, 1100, 750]);

% Top panel: Absolute cumulative performance ($1 invested)
ax_abs = subplot(2, 1, 1);
runUW_shadeRegimes(ax_abs, T, lbl_v, cNeutral, cMild, cSevere);
hold on
for s = 1 : nStrat
    plot(ax_abs, T, stratCurves{s}, lineStyles{s}, ...
        'Color', colours{s}, 'LineWidth', 2.0, 'DisplayName', stratLabels{s});
end
ylabel(ax_abs, 'Portfolio Value ($1 Invested)');
title(ax_abs, sprintf('Cumulative Performance — %s to %s', ...
    datestr(T(1),'mmm-yyyy'), datestr(T(end),'mmm-yyyy')));
legend(ax_abs, 'Location', 'northwest');
set(ax_abs, 'XGrid', 'on', 'YGrid', 'on');

% Bottom panel: Cumulative relative performance vs 100% equities
ax_rel = subplot(2, 1, 2);
runUW_shadeRegimes(ax_rel, T, lbl_v, cNeutral, cMild, cSevere);
hold on
for s = 2 : nStrat   % benchmark and two-step vs 100% equity baseline
    relPerf = (stratCurves{s} ./ stratCurves{1} - 1) .* 100;
    plot(ax_rel, T, relPerf, lineStyles{s}, ...
        'Color', colours{s}, 'LineWidth', 2.0, ...
        'DisplayName', [stratLabels{s} ' vs 100% Equities']);
end
yline(ax_rel, 0, 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8, ...
    'HandleVisibility', 'off');
ylabel(ax_rel, 'Relative Performance (%)');
title(ax_rel, 'Relative Performance vs 100% Equities (positive = outperformance)');
legend(ax_rel, 'Location', 'best');
set(ax_rel, 'XGrid', 'on', 'YGrid', 'on');

sgtitle('Two-Step Equity De-Risking: Composite Analysis', ...
    'FontWeight', 'bold', 'FontSize', 12);

fprintf('\n=== Run complete ===\n');
fprintf('Edit p.* parameters at the top of this script to adjust thresholds,\n');
fprintf('allocations, and tree depth, then re-run.\n\n');

%% ========================================================================
%  Local functions
%  ========================================================================
function tt = runUW_fredSp500(dm, startDate)
% runUW_fredSp500  Stooq ^SPX fallback (FRED SP500 only starts 2016-01-04).
    try
        tt = dm.fetch_stooq('^SPX', startDate, "");
        fprintf('[runUnderweightStrategy] Stooq ^SPX fallback: %d bars (%s to %s)\n', ...
            height(tt), datestr(tt.Time(1), 'mmm-yyyy'), datestr(tt.Time(end), 'mmm-yyyy'));
    catch ME_spx
        error('SignalBuilder:runUnderweightStrategy:noEquityData', ...
            ['Could not fetch equity prices from Yahoo, Stooq SPY, or Stooq ^SPX.\n' ...
             'Last error: %s'], ME_spx.message);
    end
end

function m = runUW_evalPortfolio(allocVec, equityRet, bondRet)
    % Compute portfolio return series and scalar metrics.
    % equityRet: monthly equity return (may contain NaN at start)
    % bondRet:   scalar monthly bond/cash return
    portRet = allocVec .* equityRet + (1 - allocVec) .* bondRet;
    portRet(isnan(portRet)) = 0;   % NaN months (warm-up) → 0

    equity = cumprod(1 + portRet);
    T      = numel(portRet);
    years  = T / 12;

    m.TotalReturn      = equity(end) - 1;
    m.AnnReturn        = (equity(end))^(1/years) - 1;
    m.SharpeRatio      = mean(portRet,'omitnan') / ...
                         max(std(portRet,'omitnan'), eps) * sqrt(12);
    running            = cummax(equity);
    m.MaxDrawdown      = min((equity - running) ./ running);
    m.AvgEquityAlloc   = mean(allocVec, 'omitnan');
end

function runUW_shadeRegimes(ax, T, label, cNeutral, cMild, cSevere)
    % Shade plot background by regime.  Called before plotting lines.
    axes(ax);
    hold on
    xl = [T(1), T(end)];
    for k = 1 : numel(T)
        if label(k) == 2
            clr = cSevere;
        elseif label(k) == 1
            clr = cMild;
        else
            clr = cNeutral;
        end
        if k < numel(T)
            xpatch = [T(k), T(k+1), T(k+1), T(k)];
        else
            xpatch = [T(k), T(k)+calmonths(1), T(k)+calmonths(1), T(k)];
        end
        patch(ax, xpatch, [-2 -2 2 2], clr, 'EdgeColor','none', ...
            'FaceAlpha', 0.6, 'HandleVisibility','off');
    end
    xlim(xl);
end
