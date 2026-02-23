function stress = stressTestStrategy(bt)
%SIGSTRAT.STRESSTESTSTRATEGY Analyze strategy performance during historical stress episodes.
%   stress = sigstrat.stressTestStrategy(bt)
%
% Inputs:
%   bt - struct from sigstrat.backtestEquityCash
%
% Returns:
%   stress - table with columns: Episode, StartDate, EndDate,
%            StrategyReturn, Bench6040Return, EquityReturn,
%            AvgEqWeight, StratMaxDD

    episodes = {
        'GFC',           datetime('2007-10-01'), datetime('2009-03-31');
        'Euro Crisis',   datetime('2011-07-01'), datetime('2011-10-31');
        'Taper Tantrum', datetime('2013-05-01'), datetime('2013-09-30');
        '2018 Q4',       datetime('2018-10-01'), datetime('2018-12-31');
        'COVID',         datetime('2020-02-19'), datetime('2020-03-23');
        'Rate Shock',    datetime('2022-01-01'), datetime('2022-10-31');
    };

    nEp = size(episodes, 1);
    epNames   = cell(nEp, 1);
    startDts  = NaT(nEp, 1);
    endDts    = NaT(nEp, 1);
    stratRet  = NaN(nEp, 1);
    benchRet  = NaN(nEp, 1);
    eqRet     = NaN(nEp, 1);
    avgEqWt   = NaN(nEp, 1);
    stratDD   = NaN(nEp, 1);

    dates = bt.dates;

    for i = 1:nEp
        epNames{i} = episodes{i, 1};
        d1 = episodes{i, 2};
        d2 = episodes{i, 3};
        startDts(i) = d1;
        endDts(i)   = d2;

        idx = dates >= d1 & dates <= d2;
        if sum(idx) < 2
            continue;
        end

        % Strategy return (cumulative)
        stratRet(i) = prod(1 + bt.portRet(idx)) - 1;

        % 60/40 return
        benchRet(i) = prod(1 + bt.ret6040(idx)) - 1;

        % Equity return
        eqRet(i) = prod(1 + bt.retEq(idx)) - 1;

        % Average equity weight during episode
        avgEqWt(i) = mean(bt.eqWeight(idx));

        % Strategy max drawdown during episode
        epWealth = cumprod(1 + bt.portRet(idx));
        epRunMax = cummax(epWealth);
        epDD = epWealth ./ epRunMax - 1;
        stratDD(i) = abs(min(epDD));
    end

    stress = table(epNames, startDts, endDts, ...
        stratRet * 100, benchRet * 100, eqRet * 100, ...
        avgEqWt * 100, stratDD * 100, ...
        'VariableNames', {'Episode','StartDate','EndDate', ...
        'Strategy_pct','Bench6040_pct','Equity_pct', ...
        'AvgEqWt_pct','StratMaxDD_pct'});

    fprintf('Stress test: %d episodes analyzed.\n', nEp);
end
