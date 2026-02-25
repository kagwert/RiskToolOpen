function result = robustOptimize(signals, signalNames, mkt, opts)
%SIGSTRAT.ROBUSTOPTIMIZE Robust walk-forward optimization with K-fold CV.
%   result = sigstrat.robustOptimize(signals, signalNames, mkt, opts)
%
% Inputs:
%   signals     - TxN signal matrix
%   signalNames - 1xN cell array
%   mkt         - struct from sigstrat.downloadMarketData
%   opts        - struct with fields:
%     .nThresh      - number of thresholds for Step mapping (default 3)
%     .alphaObj     - Sharpe weight in objective (default 1.0)
%     .betaObj      - Return weight (default 0.0)
%     .gammaObj     - MaxDD penalty (default 0.5)
%     .rebalFreq    - rebalance frequency (default 21)
%     .txCost       - transaction cost (default 0.0010)
%     .mappingMethod - 'Step','Sigmoid','PiecewiseLinear','Spline','Power' (default 'Sigmoid')
%     .sigmoidK     - sigmoid steepness (default 5)
%     .nFolds       - number of CV folds (default 5)
%     .lambda       - L2 weight regularization (default 0.1)
%     .kappa        - turnover penalty (default 0.05)
%     .walkForward  - true/false, use rolling walk-forward (default false)
%     .reoptFreq    - re-optimization frequency in days (default 252)
%     .sensitivity  - true/false, run bootstrap sensitivity (default false)
%     .useSortino   - use Sortino ratio objective (default false)
%     .useCalmar    - use Calmar ratio objective (default false)
%     .minVol       - minimize annualized vol (default false)
%     .riskParity   - risk parity objective (default false)
%     .constraints  - struct with constraint fields (optional)
%
% Returns:
%   result.weights      - Nx1 optimal signal weights
%   result.composite    - Tx1 composite signal
%   result.eqWts        - Tx1 equity weights
%   result.inPerf       - in-sample performance struct
%   result.outPerf      - out-of-sample performance struct
%   result.cvFolds      - struct array with per-fold OOS metrics
%   result.weightStability - struct with bootstrap weight stats (if sensitivity=true)
%   result.mappingMethod - mapping method used
%   result.regularization - struct with lambda, kappa
%   result.mappingFcnX  - for plotting mapping function
%   result.mappingFcnY  - for plotting mapping function
%   result.signalNames  - signal names
%   result.splitIdx     - train/test split index (last fold boundary)

    if nargin < 4, opts = struct(); end
    nThresh      = getOpt(opts, 'nThresh', 3);
    alphaObj     = getOpt(opts, 'alphaObj', 1.0);
    betaObj      = getOpt(opts, 'betaObj', 0.0);
    gammaObj     = getOpt(opts, 'gammaObj', 0.5);
    rebalFreq    = getOpt(opts, 'rebalFreq', 21);
    txCost       = getOpt(opts, 'txCost', 0.0010);
    mappingMethod = getOpt(opts, 'mappingMethod', 'Sigmoid');
    sigmoidK     = getOpt(opts, 'sigmoidK', 5);
    nFolds       = getOpt(opts, 'nFolds', 5);
    lambda       = getOpt(opts, 'lambda', 0.1);
    kappa        = getOpt(opts, 'kappa', 0.05);
    doWalkFwd    = getOpt(opts, 'walkForward', false);
    reoptFreq    = getOpt(opts, 'reoptFreq', 252);
    doSensitivity = getOpt(opts, 'sensitivity', false);
    useSortino   = getOpt(opts, 'useSortino', false);
    useCalmar    = getOpt(opts, 'useCalmar', false);
    minVolFlag   = getOpt(opts, 'minVol', false);
    riskParityFlag = getOpt(opts, 'riskParity', false);
    constraints  = getOpt(opts, 'constraints', struct());

    [T, N] = size(signals);

    mappingParams = buildMappingParams(mappingMethod, sigmoidK, nThresh);

    % Build objective flags struct
    objFlags = struct('useSortino', useSortino, 'useCalmar', useCalmar, ...
        'minVol', minVolFlag, 'riskParity', riskParityFlag);

    %% Walk-forward rolling mode
    if doWalkFwd
        result = runWalkForward(signals, signalNames, mkt, T, N, ...
            reoptFreq, rebalFreq, txCost, alphaObj, betaObj, gammaObj, ...
            lambda, kappa, mappingMethod, mappingParams, objFlags, constraints);
        result.mappingMethod = mappingMethod;
        result.regularization = struct('lambda', lambda, 'kappa', kappa);
        result.signalNames = signalNames;
        return;
    end

    %% K-fold expanding-window cross-validation
    fprintf('Robust optimization: %d-fold CV, %d signals, mapping=%s...\n', nFolds, N, mappingMethod);

    % Apply signal weight bounds from constraints
    sigWtMin = 0;
    sigWtMax = 1;
    if isfield(constraints, 'sigWtMin'), sigWtMin = constraints.sigWtMin; end
    if isfield(constraints, 'sigWtMax'), sigWtMax = constraints.sigWtMax; end
    wCandidates = generateWeightGrid(N, 0.10);
    % Filter candidates by signal weight bounds
    if sigWtMin > 0 || sigWtMax < 1
        keepMask = all(wCandidates >= sigWtMin - 1e-9, 2) & all(wCandidates <= sigWtMax + 1e-9, 2);
        wCandidates = wCandidates(keepMask, :);
        if isempty(wCandidates)
            wCandidates = ones(1, N) / N;
        end
    end
    nW = size(wCandidates, 1);

    cvFolds = struct('foldIdx', {}, 'trainEnd', {}, 'testStart', {}, 'testEnd', {}, ...
        'oosSharpe', {}, 'oosReturn', {}, 'oosMaxDD', {});

    foldObjByW = zeros(nW, nFolds);

    for fold = 1:nFolds
        trainEnd = round(T * fold / (nFolds + 1));
        testStart = trainEnd + 1;
        testEnd = round(T * (fold + 1) / (nFolds + 1));
        if testEnd > T, testEnd = T; end
        if testStart >= testEnd, continue; end

        for wi = 1:nW
            w = wCandidates(wi, :);
            compTest  = signals(testStart:testEnd, :) * w';

            eqWtTest = sigstrat.mapSignalToWeight(compTest, mappingMethod, mappingParams);
            % Apply equity weight constraints
            eqWtTest = applyEqConstraints(eqWtTest, constraints);

            mktTest = subsetMkt(mkt, testStart, testEnd);
            bt = sigstrat.backtestEquityCash(eqWtTest, mktTest, rebalFreq, txCost);

            obj = computeRegularizedObj(bt.portRet, w, eqWtTest, N, ...
                alphaObj, betaObj, gammaObj, lambda, kappa, objFlags, constraints);
            foldObjByW(wi, fold) = obj;
        end

        cvFolds(fold).foldIdx = fold;
        cvFolds(fold).trainEnd = trainEnd;
        cvFolds(fold).testStart = testStart;
        cvFolds(fold).testEnd = testEnd;
    end

    % Select weights maximizing average OOS objective across folds
    avgObj = mean(foldObjByW, 2);
    [~, bestIdx] = max(avgObj);
    bestW = wCandidates(bestIdx, :);

    % Report per-fold OOS metrics for best weights
    for fold = 1:nFolds
        testStart = cvFolds(fold).testStart;
        testEnd = cvFolds(fold).testEnd;
        if testStart >= testEnd, continue; end

        comp = signals(testStart:testEnd, :) * bestW';
        eqWt = sigstrat.mapSignalToWeight(comp, mappingMethod, mappingParams);
        mktTest = subsetMkt(mkt, testStart, testEnd);
        bt = sigstrat.backtestEquityCash(eqWt, mktTest, rebalFreq, txCost);
        metrics = quickMetrics(bt.portRet);
        cvFolds(fold).oosSharpe = metrics.sharpe;
        cvFolds(fold).oosReturn = metrics.annRet;
        cvFolds(fold).oosMaxDD  = metrics.maxDD;
    end

    %% Apply best weights to full sample
    composite = signals * bestW';
    eqWts = sigstrat.mapSignalToWeight(composite, mappingMethod, mappingParams);
    eqWts = applyEqConstraints(eqWts, constraints);

    % Use last fold boundary as IS/OOS split for reporting
    splitIdx = cvFolds(end).trainEnd;

    mktIn = subsetMkt(mkt, 1, splitIdx);
    btIn = sigstrat.backtestEquityCash(eqWts(1:splitIdx), mktIn, rebalFreq, txCost);
    inPerf = sigstrat.computeStrategyPerf(btIn);

    if splitIdx < T
        mktOut = subsetMkt(mkt, splitIdx+1, T);
        btOut = sigstrat.backtestEquityCash(eqWts(splitIdx+1:end), mktOut, rebalFreq, txCost);
        outPerf = sigstrat.computeStrategyPerf(btOut);
    else
        outPerf = struct('annReturn', NaN, 'sharpe', NaN, 'maxDD', NaN);
    end

    % Mapping function curve for plotting
    xRange = linspace(-1, 1, 200)';
    yRange = sigstrat.mapSignalToWeight(xRange, mappingMethod, mappingParams);

    %% Sensitivity analysis (bootstrap)
    weightStability = struct();
    if doSensitivity
        weightStability = runSensitivity(signals, mkt, wCandidates, splitIdx, ...
            rebalFreq, txCost, alphaObj, betaObj, gammaObj, lambda, kappa, ...
            mappingMethod, mappingParams, N);
    end

    %% Assemble result
    result.weights       = bestW(:);
    result.composite     = composite;
    result.eqWts         = eqWts;
    result.inPerf        = inPerf;
    result.outPerf       = outPerf;
    result.cvFolds       = cvFolds;
    result.weightStability = weightStability;
    result.mappingMethod = mappingMethod;
    result.regularization = struct('lambda', lambda, 'kappa', kappa);
    result.mappingFcnX   = xRange;
    result.mappingFcnY   = yRange;
    result.signalNames   = signalNames;
    result.splitIdx      = splitIdx;

    % Backward compatibility fields
    result.thresholds = [];
    result.eqLevels   = [];
    result.stepFcnX   = xRange;
    result.stepFcnY   = yRange;

    fprintf('Robust optimize: IS Sharpe=%.2f, OOS Sharpe=%.2f, Avg CV Sharpe=%.2f\n', ...
        inPerf.sharpe, outPerf.sharpe, mean([cvFolds.oosSharpe], 'omitnan'));
end

%% ==================== WALK-FORWARD ROLLING ====================
function result = runWalkForward(signals, ~, mkt, T, N, ...
        reoptFreq, rebalFreq, txCost, alphaObj, betaObj, gammaObj, ...
        lambda, kappa, mappingMethod, mappingParams, objFlags, constraints)
    if nargin < 17, objFlags = struct(); end
    if nargin < 18, constraints = struct(); end

    fprintf('Walk-forward optimization: reopt every %d days, %d signals...\n', reoptFreq, N);

    wCandidates = generateWeightGrid(N, 0.10);
    nW = size(wCandidates, 1);

    eqWts = NaN(T, 1);
    eqWts(1:reoptFreq) = 0.5;  % neutral until first optimization

    currentW = ones(1, N) / N;
    reoptPoints = reoptFreq:reoptFreq:T;

    for ri = 1:numel(reoptPoints)
        trainEnd = reoptPoints(ri);
        testEnd = min(trainEnd + reoptFreq, T);

        bestObj = -Inf;
        for wi = 1:nW
            w = wCandidates(wi, :);
            comp = signals(1:trainEnd, :) * w';
            eqWt = sigstrat.mapSignalToWeight(comp, mappingMethod, mappingParams);
            eqWt = applyEqConstraints(eqWt, constraints);

            mktTrain = subsetMkt(mkt, 1, trainEnd);
            bt = sigstrat.backtestEquityCash(eqWt, mktTrain, rebalFreq, txCost);
            obj = computeRegularizedObj(bt.portRet, w, eqWt, N, ...
                alphaObj, betaObj, gammaObj, lambda, kappa, objFlags, constraints);

            if obj > bestObj
                bestObj = obj;
                currentW = w;
            end
        end

        % Apply current best weights to next segment
        segStart = trainEnd + 1;
        segEnd = testEnd;
        if segStart <= T && segStart <= segEnd
            comp = signals(segStart:segEnd, :) * currentW';
            segEq = sigstrat.mapSignalToWeight(comp, mappingMethod, mappingParams);
            eqWts(segStart:segEnd) = applyEqConstraints(segEq, constraints);
        end
    end

    eqWts(isnan(eqWts)) = 0.5;

    composite = signals * currentW';
    splitIdx = round(T * 0.7);

    mktIn = subsetMkt(mkt, 1, splitIdx);
    btIn = sigstrat.backtestEquityCash(eqWts(1:splitIdx), mktIn, rebalFreq, txCost);
    inPerf = sigstrat.computeStrategyPerf(btIn);

    mktOut = subsetMkt(mkt, splitIdx+1, T);
    btOut = sigstrat.backtestEquityCash(eqWts(splitIdx+1:end), mktOut, rebalFreq, txCost);
    outPerf = sigstrat.computeStrategyPerf(btOut);

    xRange = linspace(-1, 1, 200)';
    yRange = sigstrat.mapSignalToWeight(xRange, mappingMethod, mappingParams);

    result.weights      = currentW(:);
    result.composite    = composite;
    result.eqWts        = eqWts;
    result.inPerf       = inPerf;
    result.outPerf      = outPerf;
    result.cvFolds      = struct([]);
    result.weightStability = struct();
    result.mappingFcnX  = xRange;
    result.mappingFcnY  = yRange;
    result.splitIdx     = splitIdx;
    result.thresholds   = [];
    result.eqLevels     = [];
    result.stepFcnX     = xRange;
    result.stepFcnY     = yRange;
end

%% ==================== SENSITIVITY ANALYSIS ====================
function ws = runSensitivity(signals, mkt, wCandidates, splitIdx, ...
        rebalFreq, txCost, alphaObj, betaObj, gammaObj, lambda, kappa, ...
        mappingMethod, mappingParams, N)

    nBoot = 100;
    nW = size(wCandidates, 1);
    bootWeights = zeros(nBoot, N);

    signalsIS = signals(1:splitIdx, :);
    T_IS = splitIdx;

    for b = 1:nBoot
        % Bootstrap resample of IS rows
        idx = randi(T_IS, T_IS, 1);
        sigBoot = signalsIS(idx, :);
        mktBoot = subsetMkt(mkt, 1, splitIdx);
        mktBoot.spxRet = mkt.spxRet(idx);
        mktBoot.cashRet = mkt.cashRet(idx);

        bestObj = -Inf;
        bestW = ones(1, N) / N;
        for wi = 1:nW
            w = wCandidates(wi, :);
            comp = sigBoot * w';
            eqWt = sigstrat.mapSignalToWeight(comp, mappingMethod, mappingParams);
            bt = sigstrat.backtestEquityCash(eqWt, mktBoot, rebalFreq, txCost);
            obj = computeRegularizedObj(bt.portRet, w, eqWt, N, ...
                alphaObj, betaObj, gammaObj, lambda, kappa);
            if obj > bestObj
                bestObj = obj;
                bestW = w;
            end
        end
        bootWeights(b, :) = bestW;
    end

    ws.mean   = mean(bootWeights, 1);
    ws.std    = std(bootWeights, 0, 1);
    ws.pct5   = prctile(bootWeights, 5, 1);
    ws.pct95  = prctile(bootWeights, 95, 1);
    ws.nBoot  = nBoot;

    fprintf('Sensitivity: weight std range [%.3f, %.3f]\n', min(ws.std), max(ws.std));
end

%% ==================== HELPER FUNCTIONS ====================

function obj = computeRegularizedObj(portRet, w, eqWt, N, alpha, beta, gamma, lambda, kappa, objFlags, constraints)
    if nargin < 10, objFlags = struct(); end
    if nargin < 11, constraints = struct(); end

    r = portRet;
    M = numel(r);
    k = 252;
    if M < 10
        obj = -Inf;
        return;
    end
    annRet = (prod(1 + r))^(k / M) - 1;
    annVol = std(r) * sqrt(k);
    sharpe = annRet / max(1e-12, annVol);
    cumW = cumprod(1 + r);
    maxDD = abs(min(cumW ./ cummax(cumW) - 1));

    % Regularization
    equalW = ones(1, N) / N;
    weightPenalty = sum((w - equalW).^2);
    turnover = mean(abs(diff(eqWt)));

    obj = alpha * sharpe + beta * annRet - gamma * maxDD ...
        - lambda * weightPenalty - kappa * turnover;

    % Extended objectives
    if isfield(objFlags, 'useSortino') && objFlags.useSortino
        downRet = r(r < 0);
        if numel(downRet) > 5
            downVol = std(downRet) * sqrt(k);
            sortino = annRet / max(1e-12, downVol);
            obj = obj + sortino;
        end
    end

    if isfield(objFlags, 'useCalmar') && objFlags.useCalmar
        calmar = annRet / max(1e-8, maxDD);
        obj = obj + calmar;
    end

    if isfield(objFlags, 'minVol') && objFlags.minVol
        obj = obj - annVol;
    end

    if isfield(objFlags, 'riskParity') && objFlags.riskParity && N > 1
        % Minimize variance of risk contributions
        wVec = w(:)';
        sigmaW = wVec .* annVol;
        riskContrib = sigmaW / max(sum(sigmaW), 1e-8);
        rpPenalty = var(riskContrib);
        obj = obj - 10 * rpPenalty;
    end

    % Constraint penalties
    if isfield(constraints, 'maxTurnover')
        annTurnover = sum(abs(diff(eqWt))) * k / M;
        excess = max(0, annTurnover - constraints.maxTurnover);
        obj = obj - 5 * excess;
    end

    if isfield(constraints, 'maxDD')
        priority = '';
        if isfield(constraints, 'priority'), priority = constraints.priority; end
        if maxDD > constraints.maxDD
            if strcmp(priority, 'Drawdown')
                obj = -Inf;  % hard constraint
            else
                obj = obj - 10 * (maxDD - constraints.maxDD);
            end
        end
    end
end

function metrics = quickMetrics(portRet)
    r = portRet;
    M = numel(r);
    k = 252;
    if M < 10
        metrics = struct('sharpe', NaN, 'annRet', NaN, 'maxDD', NaN);
        return;
    end
    annRet = (prod(1 + r))^(k / M) - 1;
    annVol = std(r) * sqrt(k);
    sharpe = annRet / max(1e-12, annVol);
    cumW = cumprod(1 + r);
    maxDD = abs(min(cumW ./ cummax(cumW) - 1));
    metrics = struct('sharpe', sharpe, 'annRet', annRet, 'maxDD', maxDD);
end

function params = buildMappingParams(mappingMethod, sigmoidK, nThresh)
    params = struct();
    switch mappingMethod
        case 'Sigmoid'
            params.k = sigmoidK;
        case 'Step'
            params.thresholds = linspace(-0.5, 0.5, nThresh)';
            params.levels = linspace(0, 1, nThresh + 1)';
        case 'Power'
            params.p = 1;
    end
end

function W = generateWeightGrid(N, step)
    if N == 1
        W = 1;
        return;
    end
    levels = 0:step:1;
    nL = numel(levels);

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

function mktSub = subsetMkt(mkt, i1, i2)
    mktSub.retDates = mkt.retDates(i1:i2);
    mktSub.spxRet   = mkt.spxRet(i1:i2);
    mktSub.cashRet  = mkt.cashRet(i1:i2);
    mktSub.spxPrice = mkt.spxPrice(i1:min(i2+1, numel(mkt.spxPrice)));
    mktSub.dates    = mkt.dates(i1:min(i2+1, numel(mkt.dates)));
end

function eqWts = applyEqConstraints(eqWts, constraints)
%APPLYEQCONSTRAINTS Clamp equity weights by eqMin/eqMax constraints.
    if isfield(constraints, 'eqMin')
        eqWts = max(constraints.eqMin, eqWts);
    end
    if isfield(constraints, 'eqMax')
        eqWts = min(constraints.eqMax, eqWts);
    end
end

function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
