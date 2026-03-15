%% exportAllResults.m
% Comprehensive export of all strategy results to Excel.
%
% OUTPUT FILE: Underweight/strategy_results.xlsx
%
% SHEETS
% ------
%   SignalData       Monthly time-series: signals, labels, allocations,
%                    FEDFUNDS rate, and portfolio return/equity-curve series
%   Performance      Summary statistics for the three comparison strategies
%   ThresholdResults Optimal thresholds and balanced accuracy per signal variant
%   RegimeStatistics Regime distribution, dwell times, and episode counts
%   Parameters       All model parameters used in this run
%   Metadata         Run information and column definitions

scriptDir = fileparts(mfilename('fullpath'));
rootDir   = fileparts(scriptDir);
addpath(rootDir);
addpath(scriptDir);

%% ========================================================================
%  Parameters  (must match runUnderweightStrategy.m)
%% ========================================================================
p.EquityTicker    = 'SPY';
p.StartDate       = '1994-01-01';
p.SevereRetThresh = 0;
p.SevereVolThresh = 0.30;
p.MildRetThresh   = 0;
p.BaseWeight      = 0.50;
p.MildWeight      = 0.35;
p.SevereWeight    = 0.20;
p.MAWindow        = 200;
p.TreeMaxSplits   = 4;
p.BondAnnReturn   = 0.04;

fprintf('=== exportAllResults: building pipeline ===\n');

%% ========================================================================
%  1. DataManager + pipeline
%% ========================================================================
dm = Model.DataManager();
dm.init();

features = buildSignals(dm, p.EquityTicker, ...
    StartDate = p.StartDate, MAWindow = p.MAWindow);

tt_eq = timetable.empty;
try; tt_eq = dm.fetch_yahoo(p.EquityTicker, p.StartDate, ""); catch; end
if height(tt_eq) < 252 * 25
    try
        tt_st = dm.fetch_stooq(p.EquityTicker, p.StartDate, "");
        if height(tt_st) > height(tt_eq); tt_eq = tt_st; end
    catch; end
end
if height(tt_eq) < 252 * 25
    tt_eq = dm.fetch_stooq('^SPX', p.StartDate, "");
end

md = Model.MarketData(p.EquityTicker);
md.loadFromTimetable(tt_eq, 'Yahoo');

labels = labelEquityRegimes(md.Prices, features.Time, ...
    SevereRetThresh = p.SevereRetThresh, ...
    SevereVolThresh = p.SevereVolThresh, ...
    MildRetThresh   = p.MildRetThresh);

thresh = thresholdApproach(features, labels, ...
    BaseWeight   = p.BaseWeight, ...
    MildWeight   = p.MildWeight, ...
    SevereWeight = p.SevereWeight);

%% ========================================================================
%  2. Monthly price grid + equity returns
%% ========================================================================
monthGrid  = features.Time;
nMonths    = numel(monthGrid);
monthYM    = year(monthGrid)*100   + month(monthGrid);
dailyYM    = year(md.Prices.Time)*100 + month(md.Prices.Time);
closeP     = md.Prices.Close;

monthClose = nan(nMonths, 1);
for k = 1 : nMonths
    idx = find(dailyYM == monthYM(k), 1, 'last');
    if ~isempty(idx); monthClose(k) = closeP(idx); end
end
monthlyRet = [NaN; diff(monthClose) ./ monthClose(1:end-1)];

%% ========================================================================
%  3. MarketComposite over full monthly grid
%% ========================================================================
mktMat  = [features.CreditSpread, features.EquityTrend, features.YieldCurve];
mktW    = [0.30, 0.50, 0.20];
wMat    = repmat(mktW, nMonths, 1);
wMat(isnan(mktMat)) = 0;
wSum    = sum(wMat, 2);
mktComp = sum(wMat .* mktMat, 2, 'omitnan') ./ max(wSum, eps);
mktComp(wSum == 0) = NaN;

%% ========================================================================
%  4. Expand labels to full monthly grid
%% ========================================================================
[~, iM, iL] = intersect(monthGrid, labels.Time);
fwdRet  = nan(nMonths, 1);
fwdVol  = nan(nMonths, 1);
lblVal  = nan(nMonths, 1);
lblName = repmat("NaN", nMonths, 1);
fwdRet(iM) = labels.FwdReturn3m(iL);
fwdVol(iM) = labels.FwdVol3m(iL);
lblVal(iM) = labels.Label(iL);
lblMap = ["Neutral"; "MildUW"; "SevereUW"];
for k = 1 : nMonths
    if ~isnan(lblVal(k)); lblName(k) = lblMap(lblVal(k) + 1); end
end

%% ========================================================================
%  5. Allocation and active rule (MarketComposite thresholds)
%% ========================================================================
mildThr   = thresh.MarketComposite.BestThresholds(1);
severeThr = thresh.MarketComposite.BestThresholds(2);

allocPct   = repmat(p.BaseWeight * 100, nMonths, 1);
allocPct(mktComp <= mildThr)   = p.MildWeight   * 100;
allocPct(mktComp <= severeThr) = p.SevereWeight * 100;
allocPct(isnan(mktComp))       = p.BaseWeight   * 100;

allocState = repmat("Neutral", nMonths, 1);
allocState(allocPct == p.MildWeight   * 100) = "MildUW";
allocState(allocPct == p.SevereWeight * 100) = "SevereUW";

ruleStr = strings(nMonths, 1);
for k = 1 : nMonths
    v = mktComp(k);
    if isnan(v)
        ruleStr(k) = "MktComp=NaN -> Neutral (50%, default)";
    elseif v <= severeThr
        ruleStr(k) = sprintf("MktComp=%.3f <= %.2f (severe thr) -> 20%% Severe", v, severeThr);
    elseif v <= mildThr
        ruleStr(k) = sprintf("MktComp=%.3f <= %.2f (mild thr) -> 35%% Mild", v, mildThr);
    else
        ruleStr(k) = sprintf("MktComp=%.3f > %.2f (mild thr) -> 50%% Neutral", v, mildThr);
    end
end

%% ========================================================================
%  6. FEDFUNDS aligned to full monthly grid (annualised %)
%% ========================================================================
fedRateMonthly = nan(nMonths, 1);
avgCashAnn     = p.BondAnnReturn * 100;
try
    tt_fed = dm.fetch_fred('FEDFUNDS', p.StartDate);
    fedYM  = year(tt_fed.Time)*100 + month(tt_fed.Time);
    fedR   = tt_fed.FEDFUNDS;   % in percent
    for k = 1 : nMonths
        idx = find(fedYM == monthYM(k), 1, 'last');
        if ~isempty(idx); fedRateMonthly(k) = fedR(idx); end
    end
    for k = 2 : nMonths   % forward-fill
        if isnan(fedRateMonthly(k)); fedRateMonthly(k) = fedRateMonthly(k-1); end
    end
catch
end

%% ========================================================================
%  7. Valid subset (labelled months) — portfolio evaluation
%% ========================================================================
[~, iF_align, iL_align] = intersect(features.Time, labels.Time);
lbl_all   = labels(iL_align, :);
validMask = ~isnan(lbl_all.Label);
T         = features.Time(iF_align(validMask));
nValid    = sum(validMask);
eqRet_v   = monthlyRet(iF_align(validMask));
bondMonthRet = (1 + p.BondAnnReturn)^(1/12) - 1;

% FEDFUNDS at valid months
cashMonthRet_v = repmat(bondMonthRet, nValid, 1);
try
    validYM  = year(T)*100 + month(T);
    fedYM_v  = year(tt_fed.Time)*100 + month(tt_fed.Time);
    fedR_v   = tt_fed.FEDFUNDS / 100;
    cashAnn_v = nan(nValid, 1);
    for k = 1 : nValid
        idx = find(fedYM_v == validYM(k), 1, 'last');
        if ~isempty(idx); cashAnn_v(k) = fedR_v(idx); end
    end
    for k = 2 : nValid
        if isnan(cashAnn_v(k)); cashAnn_v(k) = cashAnn_v(k-1); end
    end
    cashAnn_v(isnan(cashAnn_v)) = p.BondAnnReturn;
    cashMonthRet_v = (1 + cashAnn_v).^(1/12) - 1;
    avgCashAnn = mean(cashAnn_v) * 100;
catch
end

%% ========================================================================
%  8. Portfolio returns for three comparison strategies
%% ========================================================================
alloc_2step  = thresh.MarketComposite.BestAlloc;
avgEqAlloc   = mean(alloc_2step, 'omitnan');
alloc_100eq  = ones(nValid, 1);
alloc_match  = repmat(avgEqAlloc, nValid, 1);

portRet_100eq = eqRet_v;
portRet_match = alloc_match  .* eqRet_v + (1 - alloc_match)  .* bondMonthRet;
portRet_2step = alloc_2step  .* eqRet_v + p.BaseWeight .* bondMonthRet ...
              + (p.BaseWeight - alloc_2step) .* cashMonthRet_v;

portRet_100eq(isnan(portRet_100eq)) = 0;
portRet_match(isnan(portRet_match)) = 0;
portRet_2step(isnan(portRet_2step)) = 0;

eq_100eq = cumprod(1 + portRet_100eq);
eq_match = cumprod(1 + portRet_match);
eq_2step = cumprod(1 + portRet_2step);

% Expand to full monthly grid (NaN outside valid window)
portRet_100eq_full = nan(nMonths, 1);
portRet_match_full = nan(nMonths, 1);
portRet_2step_full = nan(nMonths, 1);
eq_100eq_full      = nan(nMonths, 1);
eq_match_full      = nan(nMonths, 1);
eq_2step_full      = nan(nMonths, 1);

validIdx = iF_align(validMask);
portRet_100eq_full(validIdx) = portRet_100eq;
portRet_match_full(validIdx) = portRet_match;
portRet_2step_full(validIdx) = portRet_2step;
eq_100eq_full(validIdx)      = eq_100eq;
eq_match_full(validIdx)      = eq_match;
eq_2step_full(validIdx)      = eq_2step;

%% ========================================================================
%  9. Performance metrics
%% ========================================================================
stratPortRet = {portRet_100eq, portRet_match, portRet_2step};
stratCurves  = {eq_100eq, eq_match, eq_2step};
stratNames   = {'100% Equities', ...
    sprintf('Matched Benchmark (%.0f%% eq)', avgEqAlloc*100), ...
    'Two-Step De-Risk + Cash'};
allocList    = {alloc_100eq, alloc_match, alloc_2step};

perfData = cell(3, 6);
for s = 1 : 3
    r   = stratPortRet{s};
    eq  = stratCurves{s};
    yrs = numel(r) / 12;
    annRet   = round(eq(end)^(1/yrs) - 1, 6) * 100;
    annVol   = round(std(r,'omitnan') * sqrt(12), 6) * 100;
    running  = cummax(eq);
    mdd      = round(min((eq - running) ./ running), 6) * 100;
    sharpe   = round(annRet / max(annVol, eps/100), 4);
    avgAlloc = round(mean(allocList{s},'omitnan') * 100, 2);
    perfData(s,:) = {stratNames{s}, annRet, annVol, mdd, sharpe, avgAlloc};
end

%% ========================================================================
%  10. Regime dwell statistics (on labelled valid-subset allocation)
%% ========================================================================
lbl_v   = lbl_all.Label(validMask);
alloc_v = alloc_2step * 100;   % as percentage

d        = [true; diff(alloc_v) ~= 0; true];
idx_d    = find(d);
rle_lens = diff(idx_d);
rle_vals = alloc_v(idx_d(1:end-1));

dwell_N  = rle_lens(rle_vals == 50);
dwell_MU = rle_lens(rle_vals == 35);
dwell_SU = rle_lens(rle_vals == 20);

%% ========================================================================
%  Write to Excel
%% ========================================================================
outFile = fullfile(scriptDir, 'strategy_results.xlsx');
fprintf('\nWriting %s ...\n', outFile);

% ---- Sheet 1: SignalData ----
T_signal = table( ...
    monthGrid,                                   ...
    round(monthClose,               2),          ...
    round(monthlyRet          * 100, 4),         ...
    round(fwdRet              * 100, 4),         ...
    round(fwdVol              * 100, 4),         ...
    round(features.PayrollsMom,     4),          ...
    round(features.YieldCurve,      4),          ...
    round(features.CreditSpread,    4),          ...
    round(features.EquityTrend,     4),          ...
    round(features.Composite,       4),          ...
    round(mktComp,                  4),          ...
    round(fedRateMonthly,           4),          ...
    lblVal,                                      ...
    lblName,                                     ...
    allocPct,                                    ...
    allocState,                                  ...
    round(portRet_100eq_full  * 100, 4),         ...
    round(portRet_match_full  * 100, 4),         ...
    round(portRet_2step_full  * 100, 4),         ...
    round(eq_100eq_full,            4),          ...
    round(eq_match_full,            4),          ...
    round(eq_2step_full,            4),          ...
    ruleStr,                                     ...
    'VariableNames', { ...
        'Date', 'SPX_Close', 'MonthlyReturn_Pct', ...
        'Fwd3m_Return_Pct', 'Fwd3m_AnnVol_Pct', ...
        'Signal_PayrollsMom', 'Signal_YieldCurve', ...
        'Signal_CreditSpread', 'Signal_EquityTrend', ...
        'Signal_Composite', 'Signal_MarketComposite', ...
        'FEDFUNDS_Ann_Pct', ...
        'Label_Value', 'Label_Name', ...
        'Allocation_Pct', 'Allocation_State', ...
        'PortRet_100eq_Pct', 'PortRet_Matched_Pct', 'PortRet_2Step_Pct', ...
        'EquityCurve_100eq', 'EquityCurve_Matched', 'EquityCurve_2Step', ...
        'Active_Rule' });
writetable(T_signal, outFile, 'Sheet', 'SignalData', 'WriteRowNames', false);
fprintf('  [1/6] SignalData  (%d rows x %d cols)\n', height(T_signal), width(T_signal));

% ---- Sheet 2: Performance ----
T_perf = table( ...
    perfData(:,1), ...
    cell2mat(perfData(:,2)), ...
    cell2mat(perfData(:,3)), ...
    cell2mat(perfData(:,4)), ...
    cell2mat(perfData(:,5)), ...
    cell2mat(perfData(:,6)), ...
    'VariableNames', { ...
        'Strategy', 'AnnReturn_Pct', 'AnnVol_Pct', ...
        'MaxDrawdown_Pct', 'SharpeRatio', 'AvgEqAlloc_Pct' });
writetable(T_perf, outFile, 'Sheet', 'Performance', 'WriteRowNames', false);
fprintf('  [2/6] Performance (%d strategies)\n', height(T_perf));

% ---- Sheet 3: ThresholdResults ----
sigNames  = {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend', ...
             'Composite','MacroComposite','MarketComposite'};
threshRows = cell(numel(sigNames), 5);
for k = 1 : numel(sigNames)
    sn  = sigNames{k};
    thr = thresh.(sn).BestThresholds;
    ba  = thresh.(sn).BestBalAcc;
    aa  = round(mean(thresh.(sn).BestAlloc,'omitnan') * 100, 2);
    threshRows(k,:) = {sn, thr(1), thr(2), ba, aa};
end
T_thresh = table( ...
    threshRows(:,1), ...
    cell2mat(threshRows(:,2)), cell2mat(threshRows(:,3)), ...
    cell2mat(threshRows(:,4)), cell2mat(threshRows(:,5)), ...
    'VariableNames', { ...
        'Signal', 'MildThreshold', 'SevereThreshold', ...
        'BalancedAccuracy', 'AvgEquityAlloc_Pct' });
writetable(T_thresh, outFile, 'Sheet', 'ThresholdResults', 'WriteRowNames', false);
fprintf('  [3/6] ThresholdResults (%d signal variants)\n', height(T_thresh));

% ---- Sheet 4: RegimeStatistics ----
nN  = sum(lbl_v == 0);
nMU = sum(lbl_v == 1);
nSU = sum(lbl_v == 2);

regStats = { ...
    'Neutral (50%)',   nN,  round(nN/nValid*100,1),  ...
        numel(dwell_N),  round(mean(dwell_N),1),  max(dwell_N);  ...
    'Mild UW (35%)',   nMU, round(nMU/nValid*100,1), ...
        numel(dwell_MU), round(mean(dwell_MU),1), max(dwell_MU); ...
    'Severe UW (20%)', nSU, round(nSU/nValid*100,1), ...
        numel(dwell_SU), round(mean(dwell_SU),1), max(dwell_SU) };
T_regime = cell2table(regStats, 'VariableNames', { ...
    'Regime', 'MonthCount', 'Pct', ...
    'NumEpisodes', 'AvgDwell_Months', 'MaxDwell_Months' });
writetable(T_regime, outFile, 'Sheet', 'RegimeStatistics', 'WriteRowNames', false);
fprintf('  [4/6] RegimeStatistics\n');

% ---- Sheet 5: Parameters ----
paramRows = { ...
    'EquityTicker',      p.EquityTicker,       'Equity index / ETF ticker'; ...
    'StartDate',         p.StartDate,          'Data fetch start date'; ...
    'SevereRetThresh',   p.SevereRetThresh,    '3m fwd return threshold for Severe label'; ...
    'SevereVolThresh',   p.SevereVolThresh,    '3m fwd ann vol threshold for Severe label'; ...
    'MildRetThresh',     p.MildRetThresh,      '3m fwd return threshold for Mild label'; ...
    'BaseWeight',        p.BaseWeight,         'Neutral equity allocation'; ...
    'MildWeight',        p.MildWeight,         'Mild underweight equity allocation'; ...
    'SevereWeight',      p.SevereWeight,       'Severe underweight equity allocation'; ...
    'MAWindow',          p.MAWindow,           'EquityTrend: trailing MA window (days)'; ...
    'TrendScale',        10,                   'EquityTrend: tanh scale factor'; ...
    'PayrollsPrefilter', 3,                    'PayrollsMom: median prefilter window (months)'; ...
    'PayrollsSmoothHL',  3,                    'PayrollsMom: EMA half-life (months)'; ...
    'PayrollsNormWin',   60,                   'PayrollsMom: rolling std window (months)'; ...
    'YieldZScoreWin',    60,                   'YieldCurve: rolling z-score window (months)'; ...
    'YieldSmoothHL',     3,                    'YieldCurve: EMA half-life (months)'; ...
    'CreditZScoreWin',   60,                   'CreditSpread: rolling z-score window (months)'; ...
    'CreditSmoothHL',    1,                    'CreditSpread: EMA half-life (months)'; ...
    'CreditWinsorPct',   97,                   'CreditSpread: expanding winsorization percentile'; ...
    'MktComp_w_Credit',  0.30,                 'MarketComposite: CreditSpread weight'; ...
    'MktComp_w_Trend',   0.50,                 'MarketComposite: EquityTrend weight'; ...
    'MktComp_w_Yield',   0.20,                 'MarketComposite: YieldCurve weight'; ...
    'TreeMaxSplits',     p.TreeMaxSplits,      'Decision tree: maximum splits'; ...
    'BondAnnReturn',     p.BondAnnReturn,      'Bond allocation: assumed annual return'; ...
    'AvgFedFunds_Ann',   round(avgCashAnn/100,4), 'Cash rate: average FEDFUNDS over sample' };
writecell([{'Parameter','Value','Description'}; paramRows], ...
    outFile, 'Sheet', 'Parameters');
fprintf('  [5/6] Parameters (%d entries)\n', size(paramRows,1));

% ---- Sheet 6: Metadata ----
meta = { ...
    'Export generated',      datestr(now, 'yyyy-mm-dd HH:MM:SS'); ...
    'Script',                'exportAllResults.m'; ...
    'Equity source',         'Stooq ^SPX (Jan 1994+)'; ...
    'Macro data',            'FRED API: PAYEMS, T10Y2Y, BAMLH0A0HYM2, FEDFUNDS'; ...
    'Full monthly grid',     sprintf('%s to %s (%d months)', ...
                               datestr(monthGrid(1),'mmm-yyyy'), ...
                               datestr(monthGrid(end),'mmm-yyyy'), nMonths); ...
    'Labelled subset',       sprintf('%s to %s (%d months)', ...
                               datestr(T(1),'mmm-yyyy'), ...
                               datestr(T(end),'mmm-yyyy'), nValid); ...
    '',                      ''; ...
    '--- MarketComposite ---',          ''; ...
    'Mild threshold',        sprintf('%.4f  (signal <= this -> 35%% Mild)', mildThr); ...
    'Severe threshold',      sprintf('%.4f  (signal <= this -> 20%% Severe)', severeThr); ...
    '',                      ''; ...
    '--- Label Definitions ---',        ''; ...
    'Neutral  (Label=0)',    '3m fwd return >= 0%'; ...
    'MildUW   (Label=1)',    '3m fwd return < 0%  AND  ann vol <= 30%'; ...
    'SevereUW (Label=2)',    '3m fwd return < 0%  AND  ann vol >  30%'; ...
    'NaN',                   'Insufficient forward data (last 3 months of sample)'; ...
    '',                      ''; ...
    '--- Portfolio Construction ---',   ''; ...
    'Neutral (50% eq)',      '50% eq + 50% bonds + 0% cash'; ...
    'Mild    (35% eq)',      '35% eq + 50% bonds + 15% cash (FEDFUNDS)'; ...
    'Severe  (20% eq)',      '20% eq + 50% bonds + 30% cash (FEDFUNDS)'; ...
    'Bond rate',             sprintf('%.0f%% p.a. (constant assumption)', p.BondAnnReturn*100); ...
    'Cash rate (avg)',       sprintf('%.2f%% p.a. (FRED FEDFUNDS average over sample)', avgCashAnn) };
writecell(meta, outFile, 'Sheet', 'Metadata');
fprintf('  [6/6] Metadata\n');

fprintf('\nDone. Output: %s\n', outFile);
fprintf('Sheets: SignalData | Performance | ThresholdResults | RegimeStatistics | Parameters | Metadata\n\n');
