function perf = computeStrategyPerf(bt, annFactor)
%SIGSTRAT.COMPUTESTRATEGYPERF Compute performance metrics for equity/cash strategy.
%   perf = sigstrat.computeStrategyPerf(bt, annFactor)
%
% Inputs:
%   bt        - struct from sigstrat.backtestEquityCash
%   annFactor - annualization factor (default 252)
%
% Returns:
%   perf - struct with strategy, 60/40, and 100% equity metrics
%   perf.table       - comparison table (Strategy vs 60/40 vs 100% Equity)
%   perf.rollingVol  - 63d rolling annualized vol
%   perf.rollingSharpe - 252d rolling Sharpe
%   perf.drawdown    - drawdown series
%   perf.monthlyRet  - monthly returns table
%   perf.monthlyMatrix - year x month matrix for heatmap

    if nargin < 2 || isempty(annFactor), annFactor = 252; end

    k = annFactor;

    %% Compute metrics for strategy, 60/40, and 100% equity
    [s.annRet, s.annVol, s.sharpe, s.sortino, s.calmar, s.maxDD, ...
     s.hitRate, s.skew, s.kurt, s.dd] = calcMetrics(bt.portRet, k);

    [b.annRet, b.annVol, b.sharpe, b.sortino, b.calmar, b.maxDD, ...
     b.hitRate, b.skew, b.kurt, b.dd] = calcMetrics(bt.ret6040, k);

    [e.annRet, e.annVol, e.sharpe, e.sortino, e.calmar, e.maxDD, ...
     e.hitRate, e.skew, e.kurt, e.dd] = calcMetrics(bt.retEq, k);

    % Store strategy metrics at top level
    perf.annReturn = s.annRet;
    perf.annVol    = s.annVol;
    perf.sharpe    = s.sharpe;
    perf.sortino   = s.sortino;
    perf.calmar    = s.calmar;
    perf.maxDD     = s.maxDD;
    perf.hitRate   = s.hitRate;
    perf.skewness  = s.skew;
    perf.kurtosis  = s.kurt;
    perf.drawdown  = s.dd;

    perf.dd6040    = b.dd;
    perf.ddEq      = e.dd;

    %% Summary comparison table
    metrics = {'Ann. Return (%)'; 'Ann. Vol (%)'; 'Sharpe'; 'Sortino'; 'Calmar'; ...
               'Max DD (%)'; 'Hit Rate (%)'; 'Skewness'; 'Kurtosis'};
    stratVals = [s.annRet*100; s.annVol*100; s.sharpe; s.sortino; s.calmar; ...
                 s.maxDD*100; s.hitRate*100; s.skew; s.kurt];
    benchVals = [b.annRet*100; b.annVol*100; b.sharpe; b.sortino; b.calmar; ...
                 b.maxDD*100; b.hitRate*100; b.skew; b.kurt];
    eqVals    = [e.annRet*100; e.annVol*100; e.sharpe; e.sortino; e.calmar; ...
                 e.maxDD*100; e.hitRate*100; e.skew; e.kurt];

    perf.table = table(metrics, stratVals, benchVals, eqVals, ...
        'VariableNames', {'Metric','Strategy','Bench_60_40','Equity_100'});

    %% Rolling metrics
    r = bt.portRet;
    M = numel(r);

    rollWin = 63;
    perf.rollingVol = NaN(M, 1);
    for i = rollWin:M
        perf.rollingVol(i) = std(r(i-rollWin+1:i)) * sqrt(k);
    end

    rollWin252 = min(252, M);
    perf.rollingSharpe = NaN(M, 1);
    for i = rollWin252:M
        chunk = r(i-rollWin252+1:i);
        annR = (prod(1 + chunk))^(k / rollWin252) - 1;
        annV = std(chunk) * sqrt(k);
        perf.rollingSharpe(i) = annR / max(1e-12, annV);
    end

    %% Monthly returns table + heatmap matrix
    dates = bt.dates;
    if isdatetime(dates)
        ym = year(dates) * 100 + month(dates);
        uniqueYM = unique(ym);
        nMon = numel(uniqueYM);
        monRet = zeros(nMon, 1);
        monDate = NaT(nMon, 1);
        monYear = zeros(nMon, 1);
        monMonth = zeros(nMon, 1);
        for mi = 1:nMon
            idx = ym == uniqueYM(mi);
            monRet(mi) = prod(1 + r(idx)) - 1;
            datesInMonth = dates(idx);
            monDate(mi) = datesInMonth(end);
            monYear(mi) = floor(uniqueYM(mi) / 100);
            monMonth(mi) = mod(uniqueYM(mi), 100);
        end
        perf.monthlyRet = table(monDate, monRet, 'VariableNames', {'Date','Return'});

        % Year x Month matrix for heatmap
        uniqueYears = unique(monYear);
        nYears = numel(uniqueYears);
        perf.monthlyMatrix = NaN(nYears, 12);
        perf.monthlyYears  = uniqueYears;
        for mi = 1:nMon
            yIdx = find(uniqueYears == monYear(mi), 1);
            perf.monthlyMatrix(yIdx, monMonth(mi)) = monRet(mi);
        end
    else
        perf.monthlyRet = table();
        perf.monthlyMatrix = [];
        perf.monthlyYears  = [];
    end

    fprintf('Strategy Perf: Return=%.2f%%, Vol=%.2f%%, Sharpe=%.2f, MaxDD=%.2f%%\n', ...
        s.annRet*100, s.annVol*100, s.sharpe, s.maxDD*100);
end

%% ---- Compute all metrics for a return series ----
function [annRet, annVol, sharpe, sortino, calmar, maxDD, hitRate, skew, kurt, dd] = calcMetrics(r, k)
    M = numel(r);
    annRet = (prod(1 + r))^(k / M) - 1;
    annVol = std(r) * sqrt(k);
    sharpe = annRet / max(1e-12, annVol);

    downside = r(r < 0);
    downsideVol = sqrt(mean(downside.^2)) * sqrt(k);
    sortino = annRet / max(1e-12, downsideVol);

    cumWealth = cumprod(1 + r);
    runMax = cummax(cumWealth);
    dd = cumWealth ./ runMax - 1;
    maxDD = abs(min(dd));

    calmar = annRet / max(1e-12, maxDD);
    hitRate = mean(r > 0);
    skew = skewness(r);
    kurt = kurtosis(r) - 3;
end
