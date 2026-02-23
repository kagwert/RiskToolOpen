function result = riskBudgetStrategy(signals, signalNames, mkt, macro, opts) %#ok<INUSL>
%SIGSTRAT.RISKBUDGETSTRATEGY Mode 2: Per-signal risk budget allocation.
%   result = sigstrat.riskBudgetStrategy(signals, signalNames, mkt, macro, opts)
%
% Inputs:
%   signals     - TxN signal matrix (values typically in [-1, +1])
%   signalNames - 1xN cell array
%   mkt         - struct from sigstrat.downloadMarketData
%   macro       - table from sigstrat.downloadMacroData (or [])
%   opts        - struct with fields:
%     .budgets       - 1xN budget allocation per signal (default equal, sum=1)
%     .translations  - 1xN cell of translation types: 'Linear','Threshold','Sigmoid','Quantile'
%     .thresholds    - 1xN thresholds for Threshold translation (default 0)
%     .sigmoidK      - sigmoid steepness (default 3)
%     .macroCond     - true/false, apply macro conditioning (default false)
%     .macroVar      - macro variable name for conditioning (default 'YieldSlope')
%     .macroThresh   - threshold for macro conditioning (default 0)
%     .rebalFreq     - rebalance frequency (default 21)
%     .txCost        - transaction cost (default 0.0010)
%
% Returns:
%   result.eqWts       - Tx1 total equity weights
%   result.allocations - TxN per-signal allocation matrix
%   result.budgets     - 1xN budgets used
%   result.translations - 1xN translation types used

    if nargin < 4, macro = []; end
    if nargin < 5, opts = struct(); end

    [T, N] = size(signals);

    budgets = getOpt(opts, 'budgets', ones(1, N) / N);
    if numel(budgets) ~= N
        budgets = ones(1, N) / N;
    end
    % Normalize budgets to sum to 1
    budgets = budgets / sum(budgets);

    defaultTrans = repmat({'Linear'}, 1, N);
    translations = getOpt(opts, 'translations', defaultTrans);
    if numel(translations) ~= N
        translations = defaultTrans;
    end

    thresholds = getOpt(opts, 'thresholds', zeros(1, N));
    sigmoidK   = getOpt(opts, 'sigmoidK', 3);
    macroCond  = getOpt(opts, 'macroCond', false);
    macroVar   = getOpt(opts, 'macroVar', 'YieldSlope');
    macroThresh = getOpt(opts, 'macroThresh', 0);
    rebalFreq  = getOpt(opts, 'rebalFreq', 21);
    txCost     = getOpt(opts, 'txCost', 0.0010);

    %% Compute per-signal allocations
    allocations = zeros(T, N);

    for j = 1:N
        sig = signals(:, j);
        b = budgets(j);

        switch translations{j}
            case 'Linear'
                % Maps [-1, +1] to [0, budget]
                allocations(:, j) = b * (sig + 1) / 2;

            case 'Threshold'
                % Binary: full budget if signal > threshold, else 0
                th = thresholds(min(j, numel(thresholds)));
                allocations(:, j) = b * double(sig > th);

            case 'Sigmoid'
                % Smooth sigmoid mapping
                allocations(:, j) = b ./ (1 + exp(-sigmoidK * sig));

            case 'Quantile'
                % Expanding percentile rank → [0, budget]
                for t = 20:T
                    history = sig(1:t);
                    history = history(isfinite(history));
                    if numel(history) < 10
                        allocations(t, j) = b * 0.5;
                        continue;
                    end
                    pctRank = mean(history <= sig(t));
                    allocations(t, j) = b * pctRank;
                end

            otherwise
                % Default to linear
                allocations(:, j) = b * (sig + 1) / 2;
        end

        % Handle NaN signals
        nanIdx = ~isfinite(sig);
        allocations(nanIdx, j) = b * 0.5;  % neutral default
    end

    %% Macro conditioning (optional)
    if macroCond && ~isempty(macro) && istable(macro) && ismember(macroVar, macro.Properties.VariableNames)
        macroSeries = alignToRetDates(macro.Date, macro.(macroVar), mkt.retDates);
        scaleDown = double(macroSeries < macroThresh);
        macroScale = ones(T, 1) - 0.5 * scaleDown;  % scale by 0.5 when below threshold
        allocations = allocations .* macroScale;
    end

    %% Total equity weight: clipped sum
    eqWts = sum(allocations, 2);
    eqWts = max(0, min(1, eqWts));

    result.eqWts       = eqWts;
    result.allocations = allocations;
    result.budgets     = budgets;
    result.translations = translations;

    fprintf('Risk budget strategy: %d signals, avg equity weight=%.1f%%\n', ...
        N, mean(eqWts(isfinite(eqWts))) * 100);
end

%% ---- Align macro series to return dates ----
function vals = alignToRetDates(srcDates, srcVals, targetDates)
    N = numel(targetDates);
    vals = NaN(N, 1);
    srcDates = srcDates(:);
    srcVals  = srcVals(:);
    [srcDates, si] = sort(srcDates);
    srcVals = srcVals(si);
    j = 1;
    lastVal = NaN;
    for i = 1:N
        while j <= numel(srcDates) && srcDates(j) <= targetDates(i)
            lastVal = srcVals(j);
            j = j + 1;
        end
        vals(i) = lastVal;
    end
end

%% ---- Get option with default ----
function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
