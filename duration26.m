%% ============================================================
%  SYSTEMATIC DURATION STRATEGY
%  Complete self-contained script: data → signals → backtest → charts
%
%  Sections
%    1. Configuration & FRED data download
%    2. Feature engineering
%    3. Decision tree signal (hard-coded exact thresholds)
%    4. Walk-forward out-of-sample validation
%    5. Persistence filter
%    6. P&L backtest
%    7. Performance statistics
%    8. Charts
%
%  Requirements
%    MATLAB R2020b+  |  Statistics and Machine Learning Toolbox
%    FRED API key    →  set FRED_API_KEY in Section 1
%
%  All thresholds are exact values from the sklearn CART model
%  trained on the calibrated dataset (see methodology document).
%  ============================================================

clear; clc; close all;

%% ============================================================
%  SECTION 1 — CONFIGURATION
%  ============================================================

% ── FRED API key ─────────────────────────────────────────────
FRED_API_KEY = 'YOUR_FRED_API_KEY_HERE';   % get free key at fred.stlouisfed.org

% ── Date range ───────────────────────────────────────────────
DATE_START = '1990-01-01';
DATE_END   = datestr(now, 'yyyy-mm-dd');

% ── Model parameters ─────────────────────────────────────────
PERSIST_MONTHS   = 3;       % persistence filter window
IMPL_LAG_MONTHS  = 1;       % implementation lag (months)
FWD_TARGET_MONTHS = 6;      % forward yield horizon for training target
FWD_THRESH_PCT   = 0.35;    % ±35 bps threshold for FALLING/RISING label
MIN_TRAIN_MONTHS = 60;      % minimum walk-forward training window
RETRAIN_STEP     = 12;      % retrain every N months

% ── Exact decision tree thresholds (from sklearn CART) ───────
Q1_FF_MOM_3M     =  0.2381;   % root: ff_mom_3m <= this → not hiking
Q2_FF_MOM_3M     = -0.0767;   % easing branch: ff_mom_3m <= this → easing
Q3_CPI_LEVEL     =  2.7930;   % decorative: both sides → FALLING
Q4_FF_MOM_3M     =  0.1723;   % on-hold: ff_mom_3m <= this → SIDEWAYS
Q5_CPI_LEVEL     =  5.2704;   % hiking: cpi_level <= this → normal inflation
Q6_RATE_MOM_12M  = -0.9271;   % hiking: rate_mom_12m <= this → early cycle

% ── Duration and tilt maps ───────────────────────────────────
DUR  = struct('FALLING', 6.0, 'SIDEWAYS', 4.0, 'RISING', 2.0);
TILT = struct('FALLING', 2.0, 'SIDEWAYS', 0.0, 'RISING',-2.0);

% ── Output folder ────────────────────────────────────────────
OUT_DIR = fullfile(pwd, 'duration_strategy_output');
if ~exist(OUT_DIR, 'dir'), mkdir(OUT_DIR); end

fprintf('=== SYSTEMATIC DURATION STRATEGY ===\n');
fprintf('Date range:  %s  to  %s\n', DATE_START, DATE_END);

%% ============================================================
%  SECTION 2 — FRED DATA DOWNLOAD
%  ============================================================

fprintf('\n[1] Downloading FRED data...\n');

% FRED series needed
series = struct( ...
    'DGS2',     'yield_2y', ...
    'DGS5',     'yield_5y', ...
    'DGS7',     'yield_7y', ...
    'DFF',      'fed_funds', ...
    'CPIAUCSL', 'cpi_raw' ...
);
series_ids = {'DGS2','DGS5','DGS7','DFF','CPIAUCSL'};

% Download each series and resample to month-end
raw = struct();
for k = 1:length(series_ids)
    sid = series_ids{k};
    url = sprintf( ...
        'https://api.stlouisfed.org/fred/series/observations?series_id=%s&api_key=%s&file_type=json&observation_start=%s&observation_end=%s', ...
        sid, FRED_API_KEY, DATE_START, DATE_END);
    try
        resp = webread(url);
        obs  = resp.observations;
        % Parse dates and values
        n    = length(obs);
        dates_raw = NaT(n,1);
        vals_raw  = NaN(n,1);
        for i = 1:n
            dates_raw(i) = datetime(obs(i).date, 'InputFormat','yyyy-MM-dd');
            v = str2double(obs(i).value);
            vals_raw(i)  = v;  % '.' (missing) → NaN automatically
        end
        % Remove NaNs
        ok = ~isnan(vals_raw);
        dates_raw = dates_raw(ok);
        vals_raw  = vals_raw(ok);
        % Resample to month-end: take last observation in each month
        dates_me = dateshift(dates_raw, 'end', 'month');
        [unique_me, ~, idx_me] = unique(dates_me);
        vals_me  = accumarray(idx_me, vals_raw, [], @(x) x(end));
        raw.(sid) = timetable(unique_me, vals_me, 'VariableNames', {series.(sid)});
        fprintf('  %-10s  %d monthly obs  (%s to %s)\n', sid, height(raw.(sid)), ...
            datestr(unique_me(1),'yyyy-mm'), datestr(unique_me(end),'yyyy-mm'));
    catch ME
        error('Failed to download %s: %s\nCheck your FRED_API_KEY.', sid, ME.message);
    end
end

% Synchronise all series to a common monthly date index
DT = raw.DGS5.Time;
for k = 1:length(series_ids)
    sid = series_ids{k};
    DT  = intersect(DT, raw.(sid).Time);
end
% Extend to cover all months from 1990-01 to today
all_months = (datetime(DATE_START,'InputFormat','yyyy-MM-dd') : calmonths(1) : ...
              dateshift(datetime(DATE_END,'InputFormat','yyyy-MM-dd'),'end','month'))';
all_months = dateshift(all_months,'end','month');

% Build master table (forward-fill missing months)
DATA = timetable(all_months);
for k = 1:length(series_ids)
    sid  = series_ids{k};
    vnam = series.(sid);
    tmp  = retime(raw.(sid), all_months, 'previous');  % forward-fill
    DATA.(vnam) = tmp.(vnam);
end
DATA = rmmissing(DATA, 'DataVariables', {'yield_5y','fed_funds'});

% ── CPI: compute YoY % from index level ──────────────────────
DATA.cpi_yoy = (DATA.cpi_raw ./ lag(DATA.cpi_raw, 12) - 1) * 100;

fprintf('  Master table: %d monthly obs  (%s to %s)\n', height(DATA), ...
    datestr(DATA.Time(1),'yyyy-mm'), datestr(DATA.Time(end),'yyyy-mm'));

%% ============================================================
%  SECTION 3 — FEATURE ENGINEERING
%  ============================================================

fprintf('\n[2] Engineering features...\n');

% ── Rate momentum (12-month, positive = yields fell = bullish) ──
DATA.rate_mom_12m = -(DATA.yield_5y - lag(DATA.yield_5y, 12));

% ── Policy momentum (3-month change in Fed Funds) ────────────
DATA.ff_mom_3m    =   DATA.fed_funds - lag(DATA.fed_funds, 3);

% ── Inflation level ──────────────────────────────────────────
DATA.cpi_level    =   DATA.cpi_yoy;

% ── Forward target for training (6-month ahead yield direction) ──
DATA.fwd_change   =   [lag(DATA.yield_5y, -6) - DATA.yield_5y];   % shift -6 = lead 6
DATA.regime_raw   =   categorical(repmat("SIDEWAYS", height(DATA), 1), ...
                       ["FALLING","RISING","SIDEWAYS"]);
DATA.regime_raw(DATA.fwd_change < -FWD_THRESH_PCT) = "FALLING";
DATA.regime_raw(DATA.fwd_change >  FWD_THRESH_PCT) = "RISING";

% ── 5-month rolling majority vote to smooth target ───────────
DATA.target = smooth_majority(DATA.regime_raw, 5);

% ── Drop rows with any missing features ──────────────────────
feat_vars = {'ff_mom_3m','cpi_level','rate_mom_12m'};
keep = ~any(ismissing(DATA(:, [feat_vars, {'target'}])), 2);
FEAT = DATA(keep, :);
% Drop last 6 months (forward target not yet realised)
cutoff_idx = find(FEAT.Time < FEAT.Time(end) - calmonths(7));
FEAT = FEAT(cutoff_idx, :);

fprintf('  Feature table: %d months  (%s to %s)\n', height(FEAT), ...
    datestr(FEAT.Time(1),'yyyy-mm'), datestr(FEAT.Time(end),'yyyy-mm'));

%% ============================================================
%  SECTION 4 — DECISION TREE SIGNAL (exact thresholds)
%  ============================================================

fprintf('\n[3] Applying decision tree rules...\n');

function regime = apply_tree(ff3, cpi, rmom, Q1,Q2,Q3,Q4,Q5,Q6)
    % Exact sklearn CART rules — 6 splits, 7 leaves
    if ff3 <= Q1                    % Q1: not hiking
        if ff3 <= Q2                % Q2: easing
            % Q3 decorative (both sides FALLING)
            regime = "FALLING";
        else                        % on-hold
            if ff3 <= Q4            % Q4: firm hold
                regime = "SIDEWAYS";
            else                    % near-hike boundary (49% purity — ambiguous)
                regime = "FALLING";
            end
        end
    else                            % hiking
        if cpi <= Q5                % Q5: normal inflation
            if rmom <= Q6           % Q6: early hike (52% purity — ambiguous)
                regime = "RISING";
            else                    % confirmed bear (81% purity)
                regime = "RISING";
            end
        else                        % structural inflation (98% purity)
            regime = "RISING";
        end
    end
end

% ── Apply tree row-by-row ────────────────────────────────────
n = height(FEAT);
regime_signal = strings(n,1);
for i = 1:n
    regime_signal(i) = apply_tree( ...
        FEAT.ff_mom_3m(i), FEAT.cpi_level(i), FEAT.rate_mom_12m(i), ...
        Q1_FF_MOM_3M, Q2_FF_MOM_3M, Q3_CPI_LEVEL, Q4_FF_MOM_3M, ...
        Q5_CPI_LEVEL, Q6_RATE_MOM_12M);
end
FEAT.signal_raw = categorical(regime_signal, ["FALLING","RISING","SIDEWAYS"]);

%% ============================================================
%  SECTION 5 — WALK-FORWARD OUT-OF-SAMPLE VALIDATION
%  ============================================================

fprintf('\n[4] Running walk-forward OOS validation...\n');

FEAT.signal_wf = categorical(repmat("SIDEWAYS", n, 1), ["FALLING","RISING","SIDEWAYS"]);

for t_start = MIN_TRAIN_MONTHS : RETRAIN_STEP : n - RETRAIN_STEP
    t_end   = min(t_start + RETRAIN_STEP - 1, n);
    X_train = [FEAT.ff_mom_3m(1:t_start), FEAT.cpi_level(1:t_start), FEAT.rate_mom_12m(1:t_start)];
    Y_train = FEAT.target(1:t_start);
    X_test  = [FEAT.ff_mom_3m(t_start+1:t_end+1), FEAT.cpi_level(t_start+1:t_end+1), FEAT.rate_mom_12m(t_start+1:t_end+1)];
    if t_end + 1 > n, break; end
    % Fit tree
    mdl = fitctree(X_train, Y_train, ...
        'MaxNumSplits', 7, ...
        'MinLeafSize',  20, ...
        'Prior',        'uniform');   % uniform = class-weight balanced
    FEAT.signal_wf(t_start+1:t_end+1) = predict(mdl, X_test);
end

% IS accuracy (full-sample fit)
X_all = [FEAT.ff_mom_3m, FEAT.cpi_level, FEAT.rate_mom_12m];
Y_all = FEAT.target;
mdl_full = fitctree(X_all, Y_all, 'MaxNumSplits',7,'MinLeafSize',20,'Prior','uniform');
Y_pred_is = predict(mdl_full, X_all);
acc_is  = mean(Y_pred_is == Y_all);

% OOS accuracy (walk-forward, skip first MIN_TRAIN_MONTHS)
wf_idx   = MIN_TRAIN_MONTHS+1 : n;
acc_oos  = mean(FEAT.signal_wf(wf_idx) == FEAT.target(wf_idx));

fprintf('  IS  accuracy: %.1f%%\n', acc_is*100);
fprintf('  OOS accuracy: %.1f%%  (walk-forward)\n', acc_oos*100);

%% ============================================================
%  SECTION 6 — PERSISTENCE FILTER
%  ============================================================

fprintf('\n[5] Applying %d-month persistence filter...\n', PERSIST_MONTHS);

FEAT.signal_final = apply_persistence(FEAT.signal_raw, PERSIST_MONTHS);
FEAT.signal_oos   = apply_persistence(FEAT.signal_wf,  PERSIST_MONTHS);

sw_total = sum(diff(double(FEAT.signal_oos)) ~= 0);
fprintf('  Regime switches (OOS, filtered): %d\n', sw_total);

%% ============================================================
%  SECTION 7 — P&L BACKTEST
%  ============================================================

fprintf('\n[6] Running P&L backtest...\n');

% Align to DATA table (full date range)
DATA = join(DATA, FEAT(:, {'Time','signal_oos','signal_raw'}), 'Keys','Time', 'RightVariables',{'signal_oos','signal_raw'});

% Implementation lag: signal at T → position at T+1
DATA.position = lag_signal(DATA.signal_oos, IMPL_LAG_MONTHS);  % helper below

% Monthly yield changes for each bucket
DATA.dy_2y = [NaN; diff(DATA.yield_2y)] / 100;
DATA.dy_5y = [NaN; diff(DATA.yield_5y)] / 100;
DATA.dy_7y = [NaN; diff(DATA.yield_7y)] / 100;

% P&L: -Duration × ΔYield per instrument
N = height(DATA);
strat_ret  = NaN(N,1);
bmark_ret  = NaN(N,1);

for i = 2:N
    pos = string(DATA.position(i));
    if ismissing(pos) || pos == "", continue; end
    dur = DUR.(pos);
    switch pos
        case 'FALLING', dy = DATA.dy_7y(i);
        case 'SIDEWAYS', dy = DATA.dy_5y(i);
        case 'RISING',   dy = DATA.dy_2y(i);
    end
    strat_ret(i) = -dur * dy;
    bmark_ret(i) = -4.0  * DATA.dy_5y(i);
end
DATA.strat_ret = strat_ret;
DATA.bmark_ret = bmark_ret;

% Remove NaN rows for stat computation
ok = ~isnan(DATA.strat_ret) & ~isnan(DATA.bmark_ret);

%% ============================================================
%  SECTION 8 — PERFORMANCE STATISTICS
%  ============================================================

fprintf('\n[7] Computing performance statistics...\n');

[ar_s,av_s,sr_s,mdd_s,hit_s] = ann_stats(DATA.strat_ret(ok));
[ar_b,av_b,sr_b,mdd_b,~    ] = ann_stats(DATA.bmark_ret(ok));
act = DATA.strat_ret(ok) - DATA.bmark_ret(ok);
[ar_a,av_a,ir_a,mdd_a,hit_a] = ann_stats(act);

cum_s = cumprod(1 + fillmissing(DATA.strat_ret,'constant',0)) * 100;
cum_b = cumprod(1 + fillmissing(DATA.bmark_ret,'constant',0)) * 100;
active_pct = (cum_s ./ cum_b - 1) * 100;

fprintf('\n  %-25s  %8s  %8s  %8s\n', 'Metric', 'Strategy', 'Benchmark', 'Active');
fprintf('  %s\n', repmat('-',1,55));
fprintf('  %-25s  %+7.2f%%  %+7.2f%%  %+7.2f%%\n', 'Ann. Return',  ar_s*100, ar_b*100, ar_a*100);
fprintf('  %-25s  %7.2f%%  %7.2f%%  %7.2f%%\n',  'Ann. Volatility', av_s*100, av_b*100, av_a*100);
fprintf('  %-25s  %8.2f  %8.2f  %8.2f\n',        'Sharpe / IR',    sr_s,     sr_b,     ir_a);
fprintf('  %-25s  %7.1f%%  %7.1f%%  %7.1f%%\n',  'Max Drawdown',   mdd_s*100, mdd_b*100, mdd_a*100);
fprintf('  %-25s  %7.0f%%  —         %7.0f%%\n', 'Monthly Hit Rate', hit_s*100, hit_a*100);
fprintf('  %-25s  —         —         %8d\n',    'Regime switches', sw_total);

% Save results to CSV
results_tbl = timetable(DATA.Time, DATA.strat_ret, DATA.bmark_ret, ...
    cum_s, cum_b, active_pct, fillmissing(string(DATA.position),'constant',''), ...
    'VariableNames', {'strat_ret','bmark_ret','cum_strat','cum_bmark','active_pct','position'});
writetimetable(results_tbl, fullfile(OUT_DIR, 'backtest_results.csv'));
fprintf('\n  Results saved → backtest_results.csv\n');

%% ============================================================
%  SECTION 9 — CHARTS
%  ============================================================

fprintf('\n[8] Generating charts...\n');

DATES   = DATA.Time;
Y2      = DATA.yield_2y;
FF      = DATA.fed_funds;
pos_str = string(DATA.position);

% ── Colour map ───────────────────────────────────────────────
C_FALL = [0.18 0.44 0.64];   % blue
C_RISE = [0.75 0.22 0.17];   % red
C_SIDE = [0.50 0.50 0.50];   % grey
C_DARK = [0.10 0.13 0.18];
C_GRN  = [0.12 0.52 0.25];

% ────────────────────────────────────────────────────────────
% CHART 1: Decision Tree (static diagram)
% ────────────────────────────────────────────────────────────
fig1 = figure('Name','Decision Tree','NumberTitle','off', ...
    'Position',[100 100 1400 820],'Color','w');
ax = axes(fig1,'Visible','off'); ax.Position = [0 0 1 1];
hold(ax,'on');

% helper: draw a node box
drawbox = @(x,y,w,h,txt1,txt2,fc,ec,lw) draw_node(ax,x,y,w,h,txt1,txt2,fc,ec,lw);
drawleaf = @(x,y,w,h,action,regime,detail,n,pur,fc,ec) ...
    draw_leaf(ax,x,y,w,h,action,regime,detail,n,pur,fc,ec);
drawarrow = @(x1,y1,x2,y2,lbl) draw_arrow(ax,x1,y1,x2,y2,lbl);

% Coordinate system 0-28 x 0-11
xlim(ax,[0 28]); ylim(ax,[-0.5 11.8]);

FC_FALL=[0.84 0.91 0.97]; EC_FALL=C_FALL;
FC_RISE=[0.99 0.91 0.91]; EC_RISE=C_RISE;
FC_SIDE=[0.92 0.92 0.93]; EC_SIDE=C_SIDE;
FC_WEAK=[1.00 0.97 0.84]; EC_WEAK=[0.83 0.67 0.05];
FC_NODE=[0.99 0.99 1.00]; EC_NODE=[0.67 0.68 0.72];

% Split nodes
drawbox(14, 10.5, 6.2, 1.0, 'Q1:  ff\_mom\_3m  \leq  +0.24%', 'Policy momentum: not actively hiking', FC_NODE, EC_NODE, 1.5);
drawbox( 6,  8.3, 5.8, 1.0, 'Q2:  ff\_mom\_3m  \leq  -0.08%', 'Active easing vs on hold', FC_NODE, EC_NODE, 1.5);
drawbox(22,  8.3, 5.8, 1.0, 'Q5:  cpi\_level  \leq  5.27%',   'Normal vs structural inflation', FC_NODE, EC_NODE, 1.5);
drawbox( 2,  6.1, 4.6, 1.0, 'Q3:  cpi\_level  \leq  2.79%',   'Low vs elevated CPI (decorative)', FC_NODE, EC_NODE, 1.5);
drawbox(10,  6.1, 5.0, 1.0, 'Q4:  ff\_mom\_3m  \leq  +0.17%', 'Firm hold vs near-hike boundary', FC_NODE, EC_NODE, 1.5);
drawbox(19.5,6.1, 5.4, 1.0, 'Q6:  rate\_mom  \leq  -0.93%',   'Early vs confirmed bear move', FC_NODE, EC_NODE, 1.5);

% Leaf nodes
drawleaf( 0.4, 3.6, 3.6, 2.0, 'LONG +2Y', 'FALLING', 'easing + low CPI',       73,  62, FC_FALL, EC_FALL);
drawleaf( 4.2, 3.6, 3.6, 2.0, 'LONG +2Y', 'FALLING', 'easing + elevated CPI',  65,  86, FC_FALL, EC_FALL);
drawleaf( 8.0, 3.6, 3.6, 2.0, 'NEUTRAL',  'SIDEWAYS','firm hold',              137,  83, FC_SIDE, EC_SIDE);
drawleaf(12.0, 3.6, 3.6, 2.0, 'LONG +2Y', 'FALLING*','near-hike boundary',      28,  49, FC_WEAK, EC_WEAK);
drawleaf(17.2, 3.6, 3.6, 2.0, 'SHORT -2Y','RISING*', 'early hike',              23,  52, FC_WEAK, EC_WEAK);
drawleaf(21.0, 3.6, 3.6, 2.0, 'SHORT -2Y','RISING',  'hiking confirmed',        52,  81, FC_RISE, EC_RISE);
drawleaf(25.2, 3.6, 3.6, 2.0, 'SHORT -2Y','RISING',  'CPI > 5.27%',            23,  98, FC_RISE, EC_RISE);

% Arrows
drawarrow(14,10.0,  6,  8.8, 'NO');
drawarrow(14,10.0, 22,  8.8, 'YES');
drawarrow( 6, 7.8,  2,  6.6, 'YES');
drawarrow( 6, 7.8, 10,  6.6, 'NO');
drawarrow( 2, 5.6, 0.4, 4.6, 'YES');
drawarrow( 2, 5.6, 4.2, 4.6, 'NO');
drawarrow(10, 5.6,  8,  4.6, 'YES');
drawarrow(10, 5.6, 12,  4.6, 'NO');
drawarrow(22, 7.8,19.5, 6.6, 'YES');
drawarrow(22, 7.8,25.2, 4.6, 'NO');
drawarrow(19.5,5.6,17.2,4.6, 'YES');
drawarrow(19.5,5.6,21.0,4.6, 'NO');

title(ax, sprintf('Decision Tree — 3 features · 6 splits · 7 leaves   |   IS acc %.1f%%   OOS acc %.1f%%', acc_is*100, acc_oos*100), ...
    'FontSize',12,'FontWeight','bold','Color',C_DARK);

% Legend
legend_x = [0.2 5.5 11.0 16.5];
legend_labels = {'FALLING → LONG 6Y','SIDEWAYS → NEUTRAL 4Y','RISING → SHORT 2Y','Ambiguous leaf (purity<60%)'};
legend_fc     = {FC_FALL, FC_SIDE, FC_RISE, FC_WEAK};
legend_ec     = {EC_FALL, EC_SIDE, EC_RISE, EC_WEAK};
for k = 1:4
    rectangle('Parent',ax,'Position',[legend_x(k) 0.2 0.5 0.35], ...
        'FaceColor',legend_fc{k},'EdgeColor',legend_ec{k},'LineWidth',1.5);
    text(ax, legend_x(k)+0.65, 0.38, legend_labels{k}, 'FontSize',8,'Color',C_DARK);
end

exportgraphics(fig1, fullfile(OUT_DIR,'fig1_decision_tree.png'), 'Resolution',180);
fprintf('  Fig 1 saved\n');

% ────────────────────────────────────────────────────────────
% CHART 2: 2Y Yield + Allocation + P&L (3-panel)
% ────────────────────────────────────────────────────────────
fig2 = figure('Name','Allocation and Performance','NumberTitle','off', ...
    'Position',[100 100 1200 1000],'Color','w');

% Panel 1: yield + shading
ax1 = subplot(3,1,1,'Parent',fig2); hold(ax1,'on');
shade_regimes(ax1, DATES, pos_str, Y2, C_FALL, C_RISE);
plot(ax1, DATES, Y2, 'Color',C_DARK, 'LineWidth',1.8, 'DisplayName','2Y Yield');
plot(ax1, DATES, FF, 'Color',C_SIDE, 'LineWidth',0.9, 'LineStyle',':', 'DisplayName','Fed Funds');
% Episode annotations
episodes = {'1994-02','2001-06','2008-10','2020-05','2022-04'};
ep_labels = {'1994 Hike','2001 Bust','GFC','COVID','2022 Hike'};
ep_ypos   = [8.0, 4.5, 3.5, 0.45, 2.7];
for k = 1:length(episodes)
    ep_dt = datetime(episodes{k},'InputFormat','yyyy-MM');
    [~,ep_i] = min(abs(DATES - ep_dt));
    annotation_arrow(ax1, DATES(ep_i), Y2(ep_i), ep_dt, ep_ypos(k), ep_labels{k});
end
ylim(ax1,[-0.3 11]); ylabel(ax1,'Yield (%)');
ax1.YTick = 0:2:10;
legend(ax1,'Location','northeast','FontSize',8);
title(ax1, sprintf('2Y Treasury Yield with Duration Allocation  (%s–%s)', ...
    datestr(DATES(1),'yyyy'), datestr(DATES(end),'yyyy')), 'FontWeight','bold','FontSize',10);
grid(ax1,'on'); ax1.GridAlpha=0.15; box(ax1,'off');

% Panel 2: tilt bars
ax2 = subplot(3,1,2,'Parent',fig2); hold(ax2,'on');
tilt_vals = pos_to_tilt(pos_str);
pos_fall = tilt_vals == 2;  pos_rise = tilt_vals == -2;  pos_side = tilt_vals == 0;
bar(ax2, DATES(pos_fall), tilt_vals(pos_fall), 'FaceColor',C_FALL, 'EdgeColor','none', 'BarWidth',1);
bar(ax2, DATES(pos_rise), tilt_vals(pos_rise), 'FaceColor',C_RISE, 'EdgeColor','none', 'BarWidth',1);
bar(ax2, DATES(pos_side), tilt_vals(pos_side), 'FaceColor',C_SIDE, 'EdgeColor','none', 'BarWidth',1, 'FaceAlpha',0.4);
yline(ax2,0,'Color',[0.7 0.7 0.7],'LineWidth',0.8);
ylim(ax2,[-2.8 2.8]); yticks(ax2,[-2 0 2]);
yticklabels(ax2,{'-2Y (SHORT)','0 (NEUT.)','+2Y (LONG)'});
ylabel(ax2,'Tilt'); grid(ax2,'on'); ax2.GridAlpha=0.1; box(ax2,'off');

% Panel 3: cumulative P&L
ax3 = subplot(3,1,3,'Parent',fig2); hold(ax3,'on');
yyaxis(ax3,'left');
plot(ax3, DATES, cum_s, 'Color',C_DARK, 'LineWidth',1.8, 'DisplayName','Strategy');
plot(ax3, DATES, cum_b, 'Color',C_SIDE, 'LineWidth',1.2, 'LineStyle','--', 'DisplayName','Benchmark (4Y)');
ylabel(ax3,'Cumulative P&L (base 100)');
yyaxis(ax3,'right');
fill([DATES; flipud(DATES)], [max(active_pct,0); zeros(length(DATES),1)], C_GRN, ...
    'FaceAlpha',0.18,'EdgeColor','none');
fill([DATES; flipud(DATES)], [min(active_pct,0); zeros(length(DATES),1)], C_RISE, ...
    'FaceAlpha',0.18,'EdgeColor','none');
plot(ax3, DATES, active_pct, 'Color',C_GRN, 'LineWidth',1.2, 'DisplayName','Active ret. %');
yline(ax3,0,'Color',C_GRN,'LineStyle',':','LineWidth',0.6,'HandleVisibility','off');
ylabel(ax3,'Active Return (%)','Color',C_GRN);
ax3.YAxis(2).Color = C_GRN;
yyaxis(ax3,'left');
legend(ax3,'Location','southeast','FontSize',8);
% Stats box
stats_str = sprintf('Strategy  Ann=%+.1f%%  SR=%.2f  MDD=%.1f%%\nBenchmark Ann=%+.1f%%  SR=%.2f\nActive    Ann=%+.1f%%  IR=%.2f  Hit=%d%%', ...
    ar_s*100,sr_s,mdd_s*100, ar_b*100,sr_b, ar_a*100,ir_a,round(hit_a*100));
text(ax3, DATES(5), min(cum_s)*1.01, stats_str, 'FontSize',8, 'FontName','Courier', ...
    'VerticalAlignment','bottom', 'BackgroundColor','w', 'EdgeColor',[0.8 0.8 0.8]);
grid(ax3,'on'); ax3.GridAlpha=0.15; box(ax3,'off');
title(ax3,'OOS Cumulative P&L vs 4Y Benchmark  (gross of costs)','FontWeight','bold','FontSize',10);

for ax = [ax1 ax2 ax3]
    xlim(ax,[DATES(1) DATES(end)]);
    ax.XAxis.TickLabelFormat = 'yyyy';
    ax.XAxis.TickValues = datetime(1996:4:2028,1,1);
end
linkaxes([ax1 ax2 ax3],'x');

exportgraphics(fig2, fullfile(OUT_DIR,'fig2_allocation_performance.png'), 'Resolution',180);
fprintf('  Fig 2 saved\n');

% ────────────────────────────────────────────────────────────
% CHART 3a: OOS Confusion Matrix
% ────────────────────────────────────────────────────────────
wf_pred = FEAT.signal_oos(wf_idx);
wf_true = FEAT.target(wf_idx);
cats    = {'FALLING','RISING','SIDEWAYS'};
CM      = confusionmat(string(wf_true), string(wf_pred), 'Order', cats);
CM_pct  = CM ./ sum(CM,2) * 100;

fig3a = figure('Name','Confusion Matrix','NumberTitle','off', ...
    'Position',[100 100 480 420],'Color','w');
axc = axes(fig3a); hold(axc,'on');
imagesc(axc, CM_pct); colormap(axc, blues_cmap()); clim([0 100]);
cb = colorbar(axc); cb.Label.String = '% of true class'; cb.FontSize=8.5;
for i=1:3
    for j=1:3
        clr = 'w'; if CM_pct(i,j)<55, clr='k'; end
        text(axc,j,i,sprintf('%d\n(%.0f%%)',CM(i,j),CM_pct(i,j)), ...
            'HorizontalAlignment','center','FontSize',10,'FontWeight','bold','Color',clr);
    end
end
axc.XTick=1:3; axc.YTick=1:3;
axc.XTickLabel=cats; axc.YTickLabel=cats;
xlabel(axc,'Predicted'); ylabel(axc,'True');
title(axc,sprintf('OOS Confusion Matrix  (walk-forward, acc=%.1f%%)',acc_oos*100), ...
    'FontWeight','bold','FontSize',10);
exportgraphics(fig3a, fullfile(OUT_DIR,'fig3a_confusion_matrix.png'), 'Resolution',180);
fprintf('  Fig 3a saved\n');

% ────────────────────────────────────────────────────────────
% CHART 3b: Feature Correlations
% ────────────────────────────────────────────────────────────
feat_show  = {'ff_mom_3m','ff_mom_6m','rate_mom_12m','rate_mom_6m','cpi_level','cpi_yoy'};
feat_labs  = {'Policy mom 3m','Policy mom 6m','Rate mom 12m','Rate mom 6m','CPI level','CPI YoY'};
tgt_num    = double(FEAT.target == 'RISING') - double(FEAT.target == 'FALLING');

% Add extra features if available
if any(strcmp(FEAT.Properties.VariableNames,'ff_mom_6m'))
    feat_show = feat_show; 
else
    feat_show = {'ff_mom_3m','rate_mom_12m','cpi_level'};
    feat_labs = {'Policy mom 3m','Rate mom 12m','CPI level'};
end

corrs = zeros(length(feat_show),1);
for k = 1:length(feat_show)
    if any(strcmp(FEAT.Properties.VariableNames, feat_show{k}))
        v = FEAT.(feat_show{k});
        r = corrcoef(v(~isnan(v)), tgt_num(~isnan(v)));
        corrs(k) = r(1,2);
    end
end

fig3b = figure('Name','Feature Correlations','NumberTitle','off', ...
    'Position',[100 100 480 420],'Color','w');
axf = axes(fig3b); hold(axf,'on');
nf = length(corrs);
bar_colors = [C_RISE; C_RISE; C_FALL; C_FALL; C_RISE; C_RISE];
for k = 1:nf
    bc = C_RISE; if corrs(k) < 0, bc = C_FALL; end
    barh(axf, k, corrs(k), 0.65, 'FaceColor',bc, 'FaceAlpha',0.82, 'EdgeColor','none');
end
xline(axf, 0, 'Color',[0.7 0.7 0.7],'LineWidth',0.9);
axf.YTick = 1:nf; axf.YTickLabel = feat_labs;
xlabel(axf,'Correlation with 6m forward yield direction');
title(axf,'Feature Correlations  (★ = used in final model)', 'FontWeight','bold','FontSize',10);
% Star markers for the 3 used features
used = {'ff_mom_3m','rate_mom_12m','cpi_level'};
for k = 1:nf
    if any(strcmp(feat_show{k}, used))
        text(axf, max(abs(corrs))+0.04, k, '★', 'FontSize',12, 'FontWeight','bold');
    end
end
grid(axf,'on','XGrid','on','YGrid','off'); axf.GridAlpha=0.18; box(axf,'off');
exportgraphics(fig3b, fullfile(OUT_DIR,'fig3b_feature_correlations.png'), 'Resolution',180);
fprintf('  Fig 3b saved\n');

fprintf('\n=== DONE ===\n');
fprintf('All outputs saved to: %s\n', OUT_DIR);

%% ============================================================
%  LOCAL HELPER FUNCTIONS
%  ============================================================

function result = smooth_majority(cat_series, window)
    % Rolling majority vote over ±floor(window/2) months
    n = length(cat_series);
    result = cat_series;
    hw = floor(window/2);
    for i = 1:n
        lo = max(1, i-hw); hi = min(n, i+hw);
        chunk = cat_series(lo:hi);
        chunk = chunk(~ismissing(chunk));
        if isempty(chunk), continue; end
        cats = categories(chunk);
        counts = countcats(chunk);
        [~,idx] = max(counts);
        result(i) = cats{idx};
    end
end

function out = apply_persistence(signal, min_months)
    % Hold current regime until new signal sustained for min_months
    n   = length(signal);
    out = signal;
    current   = signal(1);
    candidate = missing;
    count     = 0;
    for i = 2:n
        s = signal(i);
        if s == current
            candidate = missing; count = 0;
            out(i) = current;
        else
            if ~ismissing(candidate) && s == candidate
                count = count + 1;
            else
                candidate = s; count = 1;
            end
            if count >= min_months
                current = candidate; candidate = missing; count = 0;
            end
            out(i) = current;
        end
    end
end

function out = lag_signal(signal, lag_months)
    % Shift categorical signal forward by lag_months (NaN-fill at start)
    n   = length(signal);
    out = categorical(repmat(missing, n, 1), categories(signal));
    out(lag_months+1:end) = signal(1:end-lag_months);
end

function [ar,av,sr,mdd,hit] = ann_stats(r)
    % Annualised stats from monthly return vector
    r   = r(~isnan(r));
    n   = length(r);
    tot = prod(1 + r) - 1;
    ar  = (1 + tot)^(12/n) - 1;
    av  = std(r) * sqrt(12);
    sr  = ar / av;
    cum = cumprod(1 + r);
    mdd = min(cum ./ cummax(cum) - 1);
    hit = mean(r > 0);
end

function tv = pos_to_tilt(pos_str)
    n  = length(pos_str);
    tv = zeros(n,1);
    tv(pos_str == "FALLING") =  2;
    tv(pos_str == "RISING")  = -2;
end

function shade_regimes(ax, dates, pos_str, y_vals, c_fall, c_rise)
    n = length(dates);
    ylims = [min(y_vals)*0.98 max(y_vals)*1.02];
    prev_pos = ""; prev_d = dates(1);
    for i = 1:n
        p = pos_str(i);
        if p ~= prev_pos
            if prev_pos == "FALLING"
                fill(ax,[prev_d prev_d dates(i) dates(i)], ...
                    [ylims(1) ylims(2) ylims(2) ylims(1)], c_fall, ...
                    'FaceAlpha',0.18,'EdgeColor','none','HandleVisibility','off');
            elseif prev_pos == "RISING"
                fill(ax,[prev_d prev_d dates(i) dates(i)], ...
                    [ylims(1) ylims(2) ylims(2) ylims(1)], c_rise, ...
                    'FaceAlpha',0.18,'EdgeColor','none','HandleVisibility','off');
            end
            prev_pos = p; prev_d = dates(i);
        end
    end
end

function annotation_arrow(ax, x_data, y_data, x_text, y_text, label_str)
    % Simple annotation arrow within axes
    annotation('textarrow', ...
        [x_data x_text], [y_data y_text], ...
        'String', label_str, 'FontSize',7, ...
        'HeadSize',5,'HeadStyle','plain','Color',[0.6 0.6 0.6]);
end

function draw_node(ax,x,y,w,h,txt1,txt2,fc,ec,lw)
    rectangle('Parent',ax,'Position',[x-w/2 y-h/2 w h], ...
        'Curvature',0.12,'FaceColor',fc,'EdgeColor',ec,'LineWidth',lw);
    text(ax,x,y+0.14,txt1,'HorizontalAlignment','center','FontSize',9.5, ...
        'FontWeight','bold','Color',[0.10 0.13 0.18],'Interpreter','tex');
    text(ax,x,y-0.22,txt2,'HorizontalAlignment','center','FontSize',7.5, ...
        'FontAngle','italic','Color',[0.35 0.35 0.35]);
end

function draw_leaf(ax,x,y,w,h,action,regime,detail,n,purity,fc,ec)
    rectangle('Parent',ax,'Position',[x-w/2 y-h/2 w h], ...
        'Curvature',0.12,'FaceColor',fc,'EdgeColor',ec,'LineWidth',2.0);
    % Coloured top bar
    rectangle('Parent',ax,'Position',[x-w/2 y+h/2-0.36 w 0.36], ...
        'Curvature',[0 0],'FaceColor',ec,'EdgeColor','none');
    text(ax,x,y+h/2-0.18,action,'HorizontalAlignment','center','FontSize',8.5, ...
        'FontWeight','bold','Color','w');
    text(ax,x,y+0.20,regime,'HorizontalAlignment','center','FontSize',8, ...
        'FontWeight','bold','Color',[0.10 0.13 0.18]);
    text(ax,x,y-0.16,detail,'HorizontalAlignment','center','FontSize',7.2, ...
        'FontAngle','italic','Color',[0.35 0.35 0.35]);
    pc = [0.12 0.52 0.25];
    if purity < 75, pc = [0.83 0.67 0.05]; end
    if purity < 60, pc = [0.75 0.22 0.17]; end
    text(ax,x,y-0.56,sprintf('n=%d   purity %d%%',n,purity), ...
        'HorizontalAlignment','center','FontSize',7.2,'FontWeight','bold','Color',pc);
end

function draw_arrow(ax,x1,y1,x2,y2,lbl)
    plot(ax,[x1 x2],[y1 y2],'Color',[0.55 0.55 0.55],'LineWidth',1.2);
    % Arrowhead
    dx=(x2-x1); dy=(y2-y1); L=sqrt(dx^2+dy^2);
    ux=dx/L; uy=dy/L; hw=0.18; hl=0.30;
    px=x2-hl*ux; py=y2-hl*uy;
    nx=-uy; ny=ux;
    patch(ax,[x2 px+hw*nx px-hw*nx],[y2 py+hw*ny py-hw*ny], ...
        [0.55 0.55 0.55],'EdgeColor','none');
    % Label
    mx=(x1+x2)/2; my=(y1+y2)/2;
    dx_off = -0.35*sign(x2-x1);
    text(ax,mx+dx_off,my,lbl,'HorizontalAlignment','center','FontSize',8, ...
        'FontWeight','bold','Color',[0.25 0.25 0.25], ...
        'BackgroundColor','w','Margin',1);
end

function cm = blues_cmap()
    % Simple white-to-dark-blue colormap
    n = 64;
    cm = [linspace(1,0.18,n)' linspace(1,0.44,n)' linspace(1,0.64,n)'];
end
