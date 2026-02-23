function bt = backtestEquityCash(eqWts, mkt, rebalFreq, txCost)
%SIGSTRAT.BACKTESTEQUITYCASH Walk-forward equity/cash backtest.
%   bt = sigstrat.backtestEquityCash(eqWts, mkt, rebalFreq, txCost)
%
% Inputs:
%   eqWts     - Tx1 target equity weight (0 to 1), aligned to mkt.retDates
%   mkt       - struct from sigstrat.downloadMarketData
%   rebalFreq - rebalance frequency in days (default 21)
%   txCost    - transaction cost per unit turnover (default 0.0010 = 10 bps)
%
% Returns:
%   bt.portRet   - Tx1 daily portfolio returns
%   bt.cumRet    - Tx1 cumulative wealth (starting at 1)
%   bt.eqWeight  - Tx1 actual equity weight (after drift)
%   bt.bench6040 - Tx1 cumulative wealth of 60/40 benchmark
%   bt.benchEq   - Tx1 cumulative wealth of 100% equity
%   bt.dates     - Tx1 datetime
%   bt.turnover  - Tx1 absolute weight change at rebalance
%   bt.ret6040   - Tx1 daily 60/40 returns
%   bt.retEq     - Tx1 daily 100% equity returns

    if nargin < 3 || isempty(rebalFreq), rebalFreq = 21; end
    if nargin < 4 || isempty(txCost),    txCost = 0.0010; end

    spxRet  = mkt.spxRet;
    cashRet = mkt.cashRet;
    T = numel(spxRet);

    if numel(eqWts) ~= T
        error('sigstrat:backtestEquityCash', ...
            'eqWts length (%d) must match return length (%d).', numel(eqWts), T);
    end

    portRet   = zeros(T, 1);
    eqWeight  = zeros(T, 1);
    turnover  = zeros(T, 1);

    % Initialize: use first signal weight
    w_eq = max(0, min(1, eqWts(1)));
    daysSinceRebal = 0;

    for t = 1:T
        % Portfolio return using prior weight
        portRet(t) = w_eq * spxRet(t) + (1 - w_eq) * cashRet(t);

        % Drift: update weight after return
        if abs(w_eq * (1 + spxRet(t)) + (1 - w_eq) * (1 + cashRet(t))) > 1e-12
            w_eq_drifted = w_eq * (1 + spxRet(t)) / (w_eq * (1 + spxRet(t)) + (1 - w_eq) * (1 + cashRet(t)));
        else
            w_eq_drifted = w_eq;
        end

        daysSinceRebal = daysSinceRebal + 1;

        % Rebalance check
        targetW = max(0, min(1, eqWts(t)));
        if daysSinceRebal >= rebalFreq || t == 1
            dW = abs(targetW - w_eq_drifted);
            turnover(t) = dW;
            portRet(t) = portRet(t) - dW * txCost;
            w_eq = targetW;
            daysSinceRebal = 0;
        else
            w_eq = w_eq_drifted;
        end

        eqWeight(t) = w_eq;
    end

    % Cumulative wealth
    cumRet = cumprod(1 + portRet);

    % 60/40 benchmark (constant rebalance)
    ret6040 = 0.6 * spxRet + 0.4 * cashRet;
    bench6040 = cumprod(1 + ret6040);

    % 100% equity benchmark
    retEq = spxRet;
    benchEq = cumprod(1 + retEq);

    bt.portRet   = portRet;
    bt.cumRet    = cumRet;
    bt.eqWeight  = eqWeight;
    bt.bench6040 = bench6040;
    bt.benchEq   = benchEq;
    bt.dates     = mkt.retDates;
    bt.turnover  = turnover;
    bt.ret6040   = ret6040;
    bt.retEq     = retEq;

    fprintf('Backtest: %d days, Final wealth=%.2f, 60/40=%.2f, Equity=%.2f\n', ...
        T, cumRet(end), bench6040(end), benchEq(end));
end
