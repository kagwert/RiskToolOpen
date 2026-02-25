function result = optimizeComposite(signals, signalNames, mkt, opts)
%SIGSTRAT.OPTIMIZECOMPOSITE Mode 1: Weighted composite signal with optimized thresholds.
%   result = sigstrat.optimizeComposite(signals, signalNames, mkt, opts)
%
% Inputs:
%   signals     - TxN signal matrix
%   signalNames - 1xN cell array
%   mkt         - struct from sigstrat.downloadMarketData
%   opts        - struct with fields:
%     .nThresh    - number of thresholds (default 3)
%     .alphaObj   - Sharpe weight in objective (default 1.0)
%     .betaObj    - Return weight (default 0.0)
%     .gammaObj   - MaxDD penalty (default 0.5)
%     .rebalFreq  - rebalance frequency (default 21)
%     .txCost     - transaction cost (default 0.0010)
%     .inSamplePct - fraction for in-sample (default 0.70)
%
% Returns:
%   result.weights     - Nx1 optimal signal weights
%   result.thresholds  - Kx1 sorted thresholds
%   result.eqLevels    - (K+1)x1 equity weight levels
%   result.composite   - Tx1 composite signal
%   result.eqWts       - Tx1 equity weights from step-function
%   result.inPerf      - in-sample performance struct
%   result.outPerf     - out-of-sample performance struct
%   result.stepFcnX    - for plotting step function
%   result.stepFcnY    - for plotting step function

    if nargin < 4, opts = struct(); end
    nThresh    = getOpt(opts, 'nThresh', 3);
    alphaObj   = getOpt(opts, 'alphaObj', 1.0);
    betaObj    = getOpt(opts, 'betaObj', 0.0);
    gammaObj   = getOpt(opts, 'gammaObj', 0.5);
    rebalFreq  = getOpt(opts, 'rebalFreq', 21);
    txCost     = getOpt(opts, 'txCost', 0.0010);
    inPct      = getOpt(opts, 'inSamplePct', 0.70);
    constraints = getOpt(opts, 'constraints', struct());
    useSortino   = getOpt(opts, 'useSortino', false);
    useCalmar    = getOpt(opts, 'useCalmar', false);
    minVolFlag   = getOpt(opts, 'minVol', false);
    riskParityFlag = getOpt(opts, 'riskParity', false);
    objFlags = struct('useSortino', useSortino, 'useCalmar', useCalmar, ...
        'minVol', minVolFlag, 'riskParity', riskParityFlag);

    [T, N] = size(signals);
    K = nThresh;

    % Split in-sample / out-of-sample
    splitIdx = round(T * inPct);

    %% Grid search approach (robust, no fmincon dependency)
    fprintf('Optimizing composite signal (grid search, %d signals, %d thresholds)...\n', N, K);

    % Generate weight combinations (10% steps, sum=1, w>=0)
    wCandidates = generateWeightGrid(N, 0.10);
    % Apply signal weight bounds from constraints
    if isfield(constraints, 'sigWtMin') || isfield(constraints, 'sigWtMax')
        swMin = 0; swMax = 1;
        if isfield(constraints, 'sigWtMin'), swMin = constraints.sigWtMin; end
        if isfield(constraints, 'sigWtMax'), swMax = constraints.sigWtMax; end
        keepMask = all(wCandidates >= swMin - 1e-9, 2) & all(wCandidates <= swMax + 1e-9, 2);
        wCandidates = wCandidates(keepMask, :);
        if isempty(wCandidates)
            wCandidates = ones(1, N) / N;
        end
    end
    nW = size(wCandidates, 1);

    bestObj = -Inf;
    bestW = ones(1, N) / N;
    bestThresh = linspace(-0.5, 0.5, K)';
    bestEqLevels = linspace(0, 1, K+1)';

    for wi = 1:nW
        w = wCandidates(wi, :);
        comp = signals * w';
        compIn = comp(1:splitIdx);
        compValid = compIn(isfinite(compIn));

        if numel(compValid) < 50, continue; end

        % Threshold candidates: percentiles
        pctiles = linspace(10, 90, K+2);
        pctiles = pctiles(2:end-1);  % remove extremes
        threshCands = prctile(compValid, pctiles);
        threshCands = sort(threshCands);

        % Equity level candidates: evenly spaced
        eqCands = {0, 0.25, 0.50, 0.75, 1.0};
        eqPerms = generateEqLevelCombos(K+1, eqCands);

        for ei = 1:size(eqPerms, 1)
            eqLevels = eqPerms(ei, :)';

            % Map composite to equity weights (in-sample only)
            eqWtsIn = mapCompositeToEqWt(compIn, threshCands, eqLevels);
            if all(isnan(eqWtsIn)), continue; end
            % Apply equity constraints
            eqWtsIn = applyEqConstraints(eqWtsIn, constraints);

            % Quick backtest on in-sample
            mktIn = subsetMkt(mkt, 1, splitIdx);
            btIn = sigstrat.backtestEquityCash(eqWtsIn, mktIn, rebalFreq, txCost);

            % Objective
            obj = computeObj(btIn.portRet, alphaObj, betaObj, gammaObj, objFlags, constraints);
            if obj > bestObj
                bestObj = obj;
                bestW = w;
                bestThresh = threshCands(:);
                bestEqLevels = eqLevels;
            end
        end
    end

    %% Try fmincon refinement if available
    try
        x0 = [bestW(:); bestThresh(:); bestEqLevels(:)];
        lb = [zeros(N,1); -3*ones(K,1); zeros(K+1,1)];
        ub = [ones(N,1);  3*ones(K,1);  ones(K+1,1)];

        % Weight sum constraint
        Aeq = zeros(1, numel(x0));
        Aeq(1:N) = 1;
        beq = 1;

        objFcn = @(x) -evalCompositeObj(x, N, K, signals(1:splitIdx,:), mkt, splitIdx, rebalFreq, txCost, alphaObj, betaObj, gammaObj, objFlags, constraints);

        fminconOpts = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'sqp', ...
            'MaxIterations', 200, 'MaxFunctionEvaluations', 5000);
        [xOpt, fOpt] = fmincon(objFcn, x0, [], [], Aeq, beq, lb, ub, ...
            @(x) threshOrderConstraint(x, N, K), fminconOpts);

        if -fOpt > bestObj
            bestW = xOpt(1:N)';
            bestThresh = sort(xOpt(N+1:N+K));
            bestEqLevels = xOpt(N+K+1:end);
            fprintf('fmincon improved objective: %.4f -> %.4f\n', bestObj, -fOpt);
        end
    catch
        fprintf('fmincon not available; using grid search result.\n');
    end

    %% Apply best parameters to full sample
    composite = signals * bestW';
    eqWts = mapCompositeToEqWt(composite, bestThresh, bestEqLevels);
    eqWts = applyEqConstraints(eqWts, constraints);

    % In-sample performance
    mktIn = subsetMkt(mkt, 1, splitIdx);
    btIn = sigstrat.backtestEquityCash(eqWts(1:splitIdx), mktIn, rebalFreq, txCost);
    inPerf = sigstrat.computeStrategyPerf(btIn);

    % Out-of-sample performance
    if splitIdx < T
        mktOut = subsetMkt(mkt, splitIdx+1, T);
        btOut = sigstrat.backtestEquityCash(eqWts(splitIdx+1:end), mktOut, rebalFreq, txCost);
        outPerf = sigstrat.computeStrategyPerf(btOut);
    else
        outPerf = struct('annReturn', NaN, 'sharpe', NaN, 'maxDD', NaN);
    end

    % Step function for plotting
    xRange = linspace(min(composite(isfinite(composite)))-0.5, max(composite(isfinite(composite)))+0.5, 200);
    yRange = mapCompositeToEqWt(xRange(:), bestThresh, bestEqLevels);

    result.weights    = bestW(:);
    result.thresholds = bestThresh(:);
    result.eqLevels   = bestEqLevels(:);
    result.composite  = composite;
    result.eqWts      = eqWts;
    result.inPerf     = inPerf;
    result.outPerf    = outPerf;
    result.stepFcnX   = xRange;
    result.stepFcnY   = yRange;
    result.signalNames = signalNames;
    result.splitIdx   = splitIdx;

    fprintf('Composite optimized: IS Sharpe=%.2f, OOS Sharpe=%.2f\n', ...
        inPerf.sharpe, outPerf.sharpe);
end

%% ---- Map composite to equity weight via step function ----
function eqWt = mapCompositeToEqWt(comp, thresholds, eqLevels)
    T = numel(comp);
    K = numel(thresholds);
    eqWt = NaN(T, 1);
    thresholds = sort(thresholds);

    for t = 1:T
        if ~isfinite(comp(t))
            eqWt(t) = 0.5;  % default
            continue;
        end
        assigned = false;
        for k = 1:K
            if comp(t) < thresholds(k)
                eqWt(t) = eqLevels(k);
                assigned = true;
                break;
            end
        end
        if ~assigned
            eqWt(t) = eqLevels(K+1);
        end
    end
end

%% ---- Compute objective ----
function obj = computeObj(portRet, alpha, beta, gamma, objFlags, constraints)
    if nargin < 5, objFlags = struct(); end
    if nargin < 6, constraints = struct(); end
    r = portRet;
    M = numel(r);
    k = 252;
    annRet = (prod(1 + r))^(k / M) - 1;
    annVol = std(r) * sqrt(k);
    sharpe = annRet / max(1e-12, annVol);
    cumW = cumprod(1 + r);
    maxDD = abs(min(cumW ./ cummax(cumW) - 1));
    obj = alpha * sharpe + beta * annRet - gamma * maxDD;

    % Extended objectives
    if isfield(objFlags, 'useSortino') && objFlags.useSortino
        downRet = r(r < 0);
        if numel(downRet) > 5
            sortino = annRet / max(1e-12, std(downRet) * sqrt(k));
            obj = obj + sortino;
        end
    end
    if isfield(objFlags, 'useCalmar') && objFlags.useCalmar
        obj = obj + annRet / max(1e-8, maxDD);
    end
    if isfield(objFlags, 'minVol') && objFlags.minVol
        obj = obj - annVol;
    end
    % Constraint penalties
    if isfield(constraints, 'maxDD')
        priority = '';
        if isfield(constraints, 'priority'), priority = constraints.priority; end
        if maxDD > constraints.maxDD
            if strcmp(priority, 'Drawdown')
                obj = -Inf;
            else
                obj = obj - 10 * (maxDD - constraints.maxDD);
            end
        end
    end
end

%% ---- Evaluate composite objective (for fmincon) ----
function obj = evalCompositeObj(x, N, K, signalsIn, mkt, splitIdx, rebalFreq, txCost, alpha, beta, gamma, objFlags, constraints)
    if nargin < 12, objFlags = struct(); end
    if nargin < 13, constraints = struct(); end
    w = x(1:N)';
    thresh = sort(x(N+1:N+K));
    eqLevels = x(N+K+1:end);

    comp = signalsIn * w';
    eqWts = mapCompositeToEqWt(comp, thresh, eqLevels);
    eqWts = applyEqConstraints(eqWts, constraints);

    mktIn = subsetMkt(mkt, 1, splitIdx);
    bt = sigstrat.backtestEquityCash(eqWts, mktIn, rebalFreq, txCost);
    obj = computeObj(bt.portRet, alpha, beta, gamma, objFlags, constraints);
end

%% ---- Threshold ordering nonlinear constraint ----
function [c, ceq] = threshOrderConstraint(x, N, K)
    thresh = x(N+1:N+K);
    c = zeros(K-1, 1);
    for i = 1:K-1
        c(i) = thresh(i) - thresh(i+1) + 0.01;  % thresh(i) < thresh(i+1) - 0.01
    end
    ceq = [];
end

%% ---- Generate weight grid (simplex discretization) ----
function W = generateWeightGrid(N, step)
    if N == 1
        W = 1;
        return;
    end
    levels = 0:step:1;
    nL = numel(levels);

    % Generate all N-tuples that sum to 1
    if N <= 5
        combos = cell(1, N);
        [combos{:}] = ndgrid(levels);
        allCombos = zeros(nL^N, N);
        for i = 1:N
            allCombos(:, i) = combos{i}(:);
        end
        sumOk = abs(sum(allCombos, 2) - 1) < 1e-6;
        W = allCombos(sumOk, :);
    else
        % For >5 signals, use random sampling
        nSamp = 500;
        W = zeros(nSamp, N);
        for i = 1:nSamp
            r = -log(rand(1, N));
            W(i, :) = round(r / sum(r) / step) * step;
            W(i, :) = W(i, :) / sum(W(i, :));
        end
        W = unique(W, 'rows');
    end
end

%% ---- Generate equity level combinations ----
function combos = generateEqLevelCombos(nLevels, candidates)
    nC = numel(candidates);
    if nLevels <= 4
        idx = cell(1, nLevels);
        [idx{:}] = ndgrid(1:nC);
        nTotal = nC^nLevels;
        combos = zeros(nTotal, nLevels);
        for i = 1:nLevels
            combos(:, i) = candidates{idx{i}(:)};
        end
    else
        % Subsample for large nLevels
        nSamp = min(500, nC^nLevels);
        combos = zeros(nSamp, nLevels);
        for i = 1:nSamp
            for j = 1:nLevels
                combos(i, j) = candidates{randi(nC)};
            end
        end
        combos = unique(combos, 'rows');
    end
end

%% ---- Subset market data ----
function mktSub = subsetMkt(mkt, i1, i2)
    mktSub.retDates = mkt.retDates(i1:i2);
    mktSub.spxRet   = mkt.spxRet(i1:i2);
    mktSub.cashRet  = mkt.cashRet(i1:i2);
    mktSub.spxPrice = mkt.spxPrice(i1:min(i2+1, numel(mkt.spxPrice)));
    mktSub.dates    = mkt.dates(i1:min(i2+1, numel(mkt.dates)));
end

%% ---- Apply equity constraints ----
function eqWts = applyEqConstraints(eqWts, constraints)
    if isfield(constraints, 'eqMin')
        eqWts = max(constraints.eqMin, eqWts);
    end
    if isfield(constraints, 'eqMax')
        eqWts = min(constraints.eqMax, eqWts);
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
