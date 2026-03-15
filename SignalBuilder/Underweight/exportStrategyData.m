%% exportStrategyData.m
% Export all strategy data to Excel for review and reporting.
%
% OUTPUT FILE: Underweight/strategy_export.xlsx
%
% COLUMNS
% -------
%   Date                  Monthly end-of-month date
%   SPX_Close             Index close (monthly last)
%   MonthlyReturn_Pct     Simple monthly equity return (%)
%   Fwd3m_Return_Pct      3-month forward cumulative return used for labelling
%   Fwd3m_AnnVol_Pct      3-month forward annualised realised vol (%)
%   Signal_PayrollsMom    PAYEMS momentum signal        (-1 to +1)
%   Signal_YieldCurve     T10Y2Y slope signal           (-1 to +1)
%   Signal_CreditSpread   BAMLH0A0HYM2 spread signal   (-1 to +1)
%   Signal_EquityTrend    Price vs 200-day MA signal    (-1 to +1)
%   Signal_Composite      Equal-weighted composite      (-1 to +1)
%   Signal_MarketComposite Weighted: Credit30%+Trend50%+Yield20%
%   Label_Value           0=Neutral, 1=MildUW, 2=SevereUW, NaN=no fwd data
%   Label_Name            Text label
%   Allocation_Pct        Active equity allocation (50 / 35 / 20)
%   Allocation_State      Neutral / MildUW / SevereUW
%   Active_Rule           Threshold condition that determined the allocation

scriptDir = fileparts(mfilename('fullpath'));
rootDir   = fileparts(scriptDir);
addpath(rootDir);
addpath(scriptDir);

%% ========================================================================
%  Parameters  (match runUnderweightStrategy.m defaults)
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

%% ========================================================================
%  1. Initialise DataManager and run pipeline
%% ========================================================================
fprintf('=== exportStrategyData: building pipeline ===\n');
dm = Model.DataManager();
dm.init();

features = buildSignals(dm, p.EquityTicker, ...
    StartDate  = p.StartDate, ...
    MAWindow   = p.MAWindow);

% Fetch equity prices (Yahoo -> Stooq SPY -> Stooq ^SPX)
tt_eq = timetable.empty;
try
    tt_eq = dm.fetch_yahoo(p.EquityTicker, p.StartDate, "");
catch
end
if height(tt_eq) < 252 * 25
    try
        tt_st = dm.fetch_stooq(p.EquityTicker, p.StartDate, "");
        if height(tt_st) > height(tt_eq); tt_eq = tt_st; end
    catch
    end
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
%  2. Reconstruct MarketComposite signal over the full monthly grid
%     (thresholdApproach only stores the valid-label subset internally)
%% ========================================================================
%  Weights: CreditSpread=30%, EquityTrend=50%, YieldCurve=20%
mktMat = [features.CreditSpread, features.EquityTrend, features.YieldCurve];
mktW   = [0.30, 0.50, 0.20];
wMat   = repmat(mktW, height(features), 1);
wMat(isnan(mktMat)) = 0;
wSum   = sum(wMat, 2);
mktComp = sum(wMat .* mktMat, 2, 'omitnan') ./ max(wSum, eps);
mktComp(wSum == 0) = NaN;

%% ========================================================================
%  3. Monthly index close and simple return
%% ========================================================================
monthGrid  = features.Time;
nMonths    = numel(monthGrid);
monthYM    = year(monthGrid)   * 100 + month(monthGrid);
dailyYM    = year(md.Prices.Time) * 100 + month(md.Prices.Time);
closeP     = md.Prices.Close;

monthClose = nan(nMonths, 1);
for k = 1 : nMonths
    idx = find(dailyYM == monthYM(k), 1, 'last');
    if ~isempty(idx); monthClose(k) = closeP(idx); end
end
monthlyRet = [NaN; diff(monthClose) ./ monthClose(1:end-1)];

%% ========================================================================
%  4. Determine allocation and active rule for every month
%% ========================================================================
mildThr   = thresh.MarketComposite.BestThresholds(1);
severeThr = thresh.MarketComposite.BestThresholds(2);

allocPct  = repmat(p.BaseWeight * 100, nMonths, 1);
allocPct(mktComp <= mildThr)   = p.MildWeight   * 100;
allocPct(mktComp <= severeThr) = p.SevereWeight * 100;
allocPct(isnan(mktComp))       = p.BaseWeight   * 100;

allocState = repmat("Neutral",  nMonths, 1);
allocState(allocPct == p.MildWeight   * 100) = "MildUW";
allocState(allocPct == p.SevereWeight * 100) = "SevereUW";

ruleStr = strings(nMonths, 1);
for k = 1 : nMonths
    v = mktComp(k);
    if isnan(v)
        ruleStr(k) = "MktComp=NaN -> Neutral (50%, default)";
    elseif v <= severeThr
        ruleStr(k) = sprintf("MktComp=%.3f <= %.2f (severe thr) -> 20%% Severe", ...
            v, severeThr);
    elseif v <= mildThr
        ruleStr(k) = sprintf("MktComp=%.3f <= %.2f (mild thr) -> 35%% Mild", ...
            v, mildThr);
    else
        ruleStr(k) = sprintf("MktComp=%.3f > %.2f (mild thr) -> 50%% Neutral", ...
            v, mildThr);
    end
end

%% ========================================================================
%  5. Expand labels to full monthly grid (NaN for unlabelled tail months)
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
    if ~isnan(lblVal(k))
        lblName(k) = lblMap(lblVal(k) + 1);
    end
end

%% ========================================================================
%  6. Assemble export table
%% ========================================================================
T_export = table( ...
    monthGrid,                                  ...  % datetime
    round(monthClose,         2),               ...
    round(monthlyRet    * 100, 4),              ...
    round(fwdRet        * 100, 4),              ...
    round(fwdVol        * 100, 4),              ...
    round(features.PayrollsMom,  4),            ...
    round(features.YieldCurve,   4),            ...
    round(features.CreditSpread, 4),            ...
    round(features.EquityTrend,  4),            ...
    round(features.Composite,    4),            ...
    round(mktComp,               4),            ...
    lblVal,                                     ...
    lblName,                                    ...
    allocPct,                                   ...
    allocState,                                 ...
    ruleStr,                                    ...
    'VariableNames', { ...
        'Date', ...
        'SPX_Close', ...
        'MonthlyReturn_Pct', ...
        'Fwd3m_Return_Pct', ...
        'Fwd3m_AnnVol_Pct', ...
        'Signal_PayrollsMom', ...
        'Signal_YieldCurve', ...
        'Signal_CreditSpread', ...
        'Signal_EquityTrend', ...
        'Signal_Composite', ...
        'Signal_MarketComposite', ...
        'Label_Value', ...
        'Label_Name', ...
        'Allocation_Pct', ...
        'Allocation_State', ...
        'Active_Rule' });

%% ========================================================================
%  7. Write to Excel
%% ========================================================================
outFile = fullfile(scriptDir, 'strategy_export.xlsx');

% Write data sheet
writetable(T_export, outFile, 'Sheet', 'StrategyData', 'WriteRowNames', false);

% Write a metadata / legend sheet
meta = { ...
    'Export generated',   datestr(now, 'yyyy-mm-dd HH:MM:SS');
    'Equity ticker',      p.EquityTicker;
    'Equity data source', 'Stooq ^SPX (Jan 1994+)';
    'Start date',         p.StartDate;
    'Monthly grid',       sprintf('%s to %s (%d months)', ...
                            datestr(monthGrid(1),'mmm-yyyy'), ...
                            datestr(monthGrid(end),'mmm-yyyy'), nMonths);
    '',                   '';
    '--- Allocation Levels ---', '';
    'Neutral (base)',     sprintf('%.0f%%', p.BaseWeight   * 100);
    'Mild underweight',   sprintf('%.0f%%', p.MildWeight   * 100);
    'Severe underweight', sprintf('%.0f%%', p.SevereWeight * 100);
    '',                   '';
    '--- MarketComposite Thresholds ---', '';
    'Mild threshold',     sprintf('%.4f  (signal <= this -> 35%% Mild)', mildThr);
    'Severe threshold',   sprintf('%.4f  (signal <= this -> 20%% Severe)', severeThr);
    '',                   '';
    '--- MarketComposite Weights ---', '';
    'CreditSpread',       '30%';
    'EquityTrend',        '50%';
    'YieldCurve',         '20%';
    '',                   '';
    '--- Label Definitions ---', '';
    'Label 0 = Neutral',  '3m fwd return >= 0%';
    'Label 1 = MildUW',   '3m fwd return < 0%  AND  ann vol <= 30%';
    'Label 2 = SevereUW', '3m fwd return < 0%  AND  ann vol >  30%';
    'Label NaN',          'Insufficient forward data (last 3 months of sample)';
    };
writecell(meta, outFile, 'Sheet', 'Metadata');

fprintf('\nExported %d rows x %d columns to:\n  %s\n\n', ...
    height(T_export), width(T_export), outFile);

%% ========================================================================
%  8. Print recent rows as a preview
%% ========================================================================
fprintf('--- Latest 12 months ---\n');
disp(T_export(end-11:end, ...
    {'Date','SPX_Close','Signal_MarketComposite', ...
     'Allocation_Pct','Allocation_State','Active_Rule'}));
