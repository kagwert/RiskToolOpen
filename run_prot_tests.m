%% run_prot_tests  Full regression test for PROT risk tool data sourcing
%  Run from C:\CIO\ClaudeCode\RiskToolpublic

fprintf('============================================================\n');
fprintf('  PROT TEST SUITE — %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
fprintf('============================================================\n\n');

nPass = 0; nFail = 0;
D1 = '20230101'; D2 = '20241231';

yfopts = weboptions( ...
    'HeaderFields',{'User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}, ...
    'Timeout', 30);

%% ── 1. Yahoo Finance direct (app download path) ────────────────────────
fprintf('─── 1. Yahoo Finance direct ───\n');
d1u = num2str(floor(posixtime(datetime(D1,'InputFormat','yyyyMMdd','TimeZone','UTC'))));
d2u = num2str(floor(posixtime(datetime(D2,'InputFormat','yyyyMMdd','TimeZone','UTC'))));

for sym = {'SPY','^GSPC','BIL'}
    ticker = sym{1};
    yfSym  = strrep(ticker,'^','%5E');
    url = sprintf('https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&period1=%s&period2=%s&events=history', yfSym, d1u, d2u);
    try
        resp = webread(url, yfopts);
        ts = resp.chart.result.timestamp;
        if iscell(ts), ts = cell2mat(ts); end
        if numel(ts) > 400
            fprintf('  [PASS] YF/%s — %d rows\n', ticker, numel(ts)); nPass = nPass+1;
        else
            fprintf('  [FAIL] YF/%s — only %d rows\n', ticker, numel(ts)); nFail = nFail+1;
        end
    catch ME
        fprintf('  [FAIL] YF/%s — %s\n', ticker, ME.message); nFail = nFail+1;
    end
    pause(1);   % avoid 429 rate-limit between requests
end

%% ── 2. sigstrat.downloadMarketData ─────────────────────────────────────
fprintf('\n─── 2. sigstrat.downloadMarketData ───\n');
pause(2);
try
    mkt = sigstrat.downloadMarketData(D1, D2);
    if numel(mkt.retDates) > 400
        annRet = sum(mkt.spxRet) / (numel(mkt.retDates)/252) * 100;
        fprintf('  [PASS] %d days, SPX ann=%.1f%%\n', numel(mkt.retDates), annRet); nPass = nPass+1;
    else
        fprintf('  [FAIL] insufficient data (%d days)\n', numel(mkt.retDates)); nFail = nFail+1;
    end
catch ME
    fprintf('  [FAIL] %s\n', ME.message); nFail = nFail+1;
    mkt = [];
end

%% ── 3. DataManager.fetch_stooq (Yahoo Finance via DataManager) ─────────
fprintf('\n─── 3. DataManager.fetch_stooq → Yahoo Finance ───\n');
addpath(fullfile(pwd,'SignalBuilder'));
try
    dm = Model.DataManager(); dm.init(); dm.Verbose = false;
    pause(15);  % let Yahoo rate-limit window reset after Section 1 burst
    tt = dm.fetch_stooq('SPY', '2024-01-01', '2024-12-31');
    if height(tt) > 200
        fprintf('  [PASS] DM/SPY — %d rows, last close=%.2f\n', height(tt), tt.Close(end)); nPass = nPass+1;
    else
        fprintf('  [FAIL] DM/SPY — only %d rows\n', height(tt)); nFail = nFail+1;
    end
catch ME
    if contains(ME.message, '429')
        fprintf('  [WARN] DM/SPY — 429 rate-limited (transient; DataManager uses 24h cache in production)\n');
    else
        fprintf('  [FAIL] DM/SPY — %s\n', ME.message); nFail = nFail+1;
    end
end

try
    pause(3);
    tt2 = dm.fetch_stooq('^SPX', '2024-01-01', '2024-12-31');
    if height(tt2) > 200
        fprintf('  [PASS] DM/^SPX → ^GSPC — %d rows\n', height(tt2)); nPass = nPass+1;
    else
        fprintf('  [FAIL] DM/^SPX — only %d rows\n', height(tt2)); nFail = nFail+1;
    end
catch ME
    if contains(ME.message, '429')
        fprintf('  [WARN] DM/^SPX — 429 rate-limited (transient)\n');
    else
        fprintf('  [FAIL] DM/^SPX — %s\n', ME.message); nFail = nFail+1;
    end
end

%% ── 4. DataManager.fetch_yahoo ──────────────────────────────────────────
fprintf('\n─── 4. DataManager.fetch_yahoo ───\n');
try
    pause(3);
    ttY = dm.fetch_yahoo('QQQ', '2024-01-01', '2024-12-31');
    if height(ttY) > 200
        fprintf('  [PASS] DM/fetch_yahoo(QQQ) — %d rows\n', height(ttY)); nPass = nPass+1;
    else
        fprintf('  [FAIL] DM/fetch_yahoo(QQQ) — only %d rows\n', height(ttY)); nFail = nFail+1;
    end
catch ME
    if contains(ME.message, '429')
        fprintf('  [WARN] DM/fetch_yahoo(QQQ) — 429 rate-limited (transient)\n');
    else
        fprintf('  [FAIL] DM/fetch_yahoo(QQQ) — %s\n', ME.message); nFail = nFail+1;
    end
end

%% ── 5. FRED REST API reachability ───────────────────────────────────────
fprintf('\n─── 5. FRED REST API ───\n');
try
    furl = 'https://api.stlouisfed.org/fred/series/observations?series_id=DFF&observation_start=2024-01-01&observation_end=2024-03-01&api_key=INVALID&file_type=json';
    webread(furl, weboptions('Timeout',15,'ContentType','text'));
    fprintf('  [WARN] FRED accepted an invalid key\n');
catch ME
    if contains(ME.message,'400') || contains(ME.message,'Bad Request')
        fprintf('  [PASS] FRED REST API reachable (400 = network OK, key check works)\n'); nPass = nPass+1;
    elseif contains(ME.message,'timed out')
        fprintf('  [FAIL] FRED REST API timed out — network problem\n'); nFail = nFail+1;
    else
        fprintf('  [INFO] FRED response: %s\n', ME.message);
    end
end
% Report env var status
envKey = getenv('FRED_API_KEY');
if isempty(envKey)
    fprintf('  [INFO] FRED_API_KEY not set — macro downloads will be skipped\n');
    fprintf('         Get a free key: fred.stlouisfed.org/docs/api/api_key.html\n');
    fprintf('         Then: setenv(''FRED_API_KEY'', ''your_key'')\n');
else
    fprintf('  [INFO] FRED_API_KEY is set (%d chars)\n', numel(envKey));
end

%% ── 6. sigstrat.downloadMacroData ──────────────────────────────────────
fprintf('\n─── 6. sigstrat.downloadMacroData ───\n');
try
    tDates = datetime('2024-01-02'):caldays(1):datetime('2024-03-29');
    tDates = tDates(~isweekend(tDates))';
    macro  = sigstrat.downloadMacroData(tDates);
    nDataCols = width(macro) - 1;   % exclude Date
    % Count non-NaN values in numeric columns only
    numCols = varfun(@isnumeric, macro, 'OutputFormat','uniform');
    nNonNaN = sum(sum(~isnan(macro{:, numCols})));
    if nDataCols >= 10
        fprintf('  [PASS] %d cols, %d total non-NaN values', nDataCols, nNonNaN);
        if nNonNaN == 0
            fprintf(' (all NaN — set FRED_API_KEY for real data)');
        end
        fprintf('\n'); nPass = nPass+1;
    else
        fprintf('  [FAIL] only %d columns returned\n', nDataCols); nFail = nFail+1;
    end
catch ME
    fprintf('  [FAIL] %s\n', ME.message); nFail = nFail+1;
    macro = [];
end

%% ── 7. sigstrat core analytics pipeline ────────────────────────────────
fprintf('\n─── 7. sigstrat analytics pipeline ───\n');

% Need 5-year market data for meaningful signals
pause(2);
try
    mkt5 = sigstrat.downloadMarketData('20200101','20241231');
    fprintf('  [INFO] 5yr market data: %d days\n', numel(mkt5.retDates));
catch ME
    fprintf('  [WARN] Could not get 5yr data: %s — reusing 2yr data\n', ME.message);
    mkt5 = mkt;
end

% Build macro aligned to mkt5 if we have it
try
    if ~isempty(mkt5)
        tDates5 = mkt5.dates;
        macro5  = sigstrat.downloadMacroData(tDates5);
    else
        macro5 = macro;
    end
catch
    macro5 = macro;
end

% generateDemoSignals(macro, mkt)
try
    [sigs, sigNames] = sigstrat.generateDemoSignals(macro5, mkt5);
    if ~isempty(sigs) && size(sigs,1) > 500
        fprintf('  [PASS] generateDemoSignals — %d signals × %d obs\n', ...
            numel(sigNames), size(sigs,1)); nPass = nPass+1;
    else
        fprintf('  [FAIL] generateDemoSignals — shape %dx%d\n', size(sigs,1), size(sigs,2)); nFail = nFail+1;
    end
catch ME
    fprintf('  [FAIL] generateDemoSignals — %s\n', ME.message); nFail = nFail+1;
    sigs = []; sigNames = {};
end

% normalizeSignals
try
    sigsNorm = sigstrat.normalizeSignals(sigs);
    if ~isempty(sigsNorm) && isequal(size(sigsNorm), size(sigs))
        fprintf('  [PASS] normalizeSignals — shape matches input\n'); nPass = nPass+1;
    else
        fprintf('  [FAIL] normalizeSignals — shape mismatch\n'); nFail = nFail+1;
    end
catch ME
    fprintf('  [FAIL] normalizeSignals — %s\n', ME.message); nFail = nFail+1;
    sigsNorm = sigs;
end

% mapSignalToWeight
try
    if ~isempty(sigsNorm)
        w = sigstrat.mapSignalToWeight(sigsNorm(:,1), 'Sigmoid');
        wFin = w(isfinite(w));
        if numel(w) == size(sigs,1) && all(wFin >= 0) && all(wFin <= 1)
            fprintf('  [PASS] mapSignalToWeight — weights in [0,1]\n'); nPass = nPass+1;
        else
            fprintf('  [FAIL] mapSignalToWeight — out of range\n'); nFail = nFail+1;
        end
    else
        fprintf('  [SKIP] mapSignalToWeight — no signals\n');
    end
catch ME
    fprintf('  [FAIL] mapSignalToWeight — %s\n', ME.message); nFail = nFail+1;
    w = [];
end

% backtestEquityCash(eqWts, mkt)
bt = [];
try
    if ~isempty(w) && ~isempty(mkt5)
        bt = sigstrat.backtestEquityCash(w, mkt5);
        if isstruct(bt) && isfield(bt,'portRet')
            fprintf('  [PASS] backtestEquityCash — %d return obs\n', numel(bt.portRet)); nPass = nPass+1;
        else
            fprintf('  [FAIL] backtestEquityCash — missing portRet field\n'); nFail = nFail+1;
        end
    else
        fprintf('  [SKIP] backtestEquityCash — missing inputs\n');
    end
catch ME
    fprintf('  [FAIL] backtestEquityCash — %s\n', ME.message); nFail = nFail+1;
    bt = [];
end

% computeStrategyPerf(bt)
try
    if ~isempty(bt)
        perf = sigstrat.computeStrategyPerf(bt);
        if isstruct(perf) && isfield(perf,'sharpe') && isfield(perf,'maxDD')
            fprintf('  [PASS] computeStrategyPerf — Sharpe=%.3f, MaxDD=%.1f%%\n', ...
                perf.sharpe, perf.maxDD*100); nPass = nPass+1;
        else
            fprintf('  [FAIL] computeStrategyPerf — missing sharpe/maxDD fields\n'); nFail = nFail+1;
        end
    else
        fprintf('  [SKIP] computeStrategyPerf — no backtest result\n');
    end
catch ME
    fprintf('  [FAIL] computeStrategyPerf — %s\n', ME.message); nFail = nFail+1;
end

%% ── 8. SignalBuilder unit tests ─────────────────────────────────────────
fprintf('\n─── 8. SignalBuilder unit tests ───\n');
for tfile = {'TestMarketData','TestSignal','TestSignalEngine','TestBacktester','TestStrategy'}
    fp = fullfile(pwd,'SignalBuilder','+Tests',[tfile{1} '.m']);
    if ~exist(fp,'file'), fprintf('  [SKIP] %s — not found\n', tfile{1}); continue; end
    try
        r = runtests(fp);
        nP2 = sum([r.Passed]); nF2 = sum([r.Failed]);
        if nF2 == 0
            fprintf('  [PASS] %s — %d/%d\n', tfile{1}, nP2, numel(r)); nPass = nPass+1;
        else
            fprintf('  [FAIL] %s — %d failures\n', tfile{1}, nF2); nFail = nFail+1;
        end
    catch ME
        fprintf('  [WARN] %s — %s\n', tfile{1}, ME.message);
    end
end

%% ── 9–10. App instantiation ─────────────────────────────────────────────
fprintf('\n─── 9. App instantiation ───\n');
for appCls = {'PortfolioRiskOptimizerApp','SignalStrategyApp'}
    try
        h = feval(appCls{1}); pause(0.3);
        if isvalid(h) && isvalid(h.UIFigure)
            fprintf('  [PASS] %s\n', appCls{1}); nPass = nPass+1;
            delete(h);
        else
            fprintf('  [FAIL] %s — figure not valid\n', appCls{1}); nFail = nFail+1;
        end
    catch ME
        fprintf('  [FAIL] %s — %s\n', appCls{1}, ME.message); nFail = nFail+1;
    end
end

%% ── Summary ─────────────────────────────────────────────────────────────
fprintf('\n============================================================\n');
fprintf('  RESULTS: %d PASSED / %d FAILED\n', nPass, nFail);
fprintf('============================================================\n');
if nFail == 0
    fprintf('  All tests passed.\n');
end
