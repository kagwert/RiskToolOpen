function result = decisionTreeStrategy(signals, signalNames, mkt, macro, opts)
%SIGSTRAT.DECISIONTREESTRATEGY Mode 3: Rule-based or CART auto-optimized decision tree.
%   result = sigstrat.decisionTreeStrategy(signals, signalNames, mkt, macro, opts)
%
% Inputs:
%   signals     - TxN signal matrix
%   signalNames - 1xN cell array
%   mkt         - struct from sigstrat.downloadMarketData
%   macro       - table from sigstrat.downloadMacroData (or [])
%   opts        - struct with fields:
%     .mode         - 'RuleBased' or 'AutoOptimize' (default 'AutoOptimize')
%     .rules        - Rx4 cell: {varName, operator, threshold, eqWeight} (for RuleBased)
%     .ruleAgg      - 'FirstMatch' or 'Average' (default 'FirstMatch')
%     .maxDepth     - tree max depth (default 3)
%     .minLeafSize  - minimum leaf size (default 50)
%     .rebalFreq    - forecast horizon / rebalance freq (default 21)
%     .txCost       - transaction cost (default 0.0010)
%     .inSamplePct  - fraction for in-sample (default 0.70)
%     .macroVars    - cell of macro variable names to include as features (default {})
%     .useRegression - true/false, use regression tree for continuous [0,1] (default true)
%     .nFolds       - number of expanding-window CV folds (default 3)
%
% Returns:
%   result.eqWts        - Tx1 equity weights
%   result.mode         - 'RuleBased' or 'AutoOptimize'
%   result.rulesText    - human-readable rule description
%   result.importance   - variable importance (auto mode)
%   result.featureNames - feature names used
%   result.cvMetrics    - per-fold OOS metrics (auto mode with CV)

    if nargin < 4, macro = []; end
    if nargin < 5, opts = struct(); end

    mode        = getOpt(opts, 'mode', 'AutoOptimize');
    rebalFreq   = getOpt(opts, 'rebalFreq', 21);
    txCost      = getOpt(opts, 'txCost', 0.0010); %#ok<NASGU>
    inPct       = getOpt(opts, 'inSamplePct', 0.70);

    [T, N] = size(signals);

    switch mode
        case 'RuleBased'
            result = runRuleBased(signals, signalNames, mkt, macro, opts, T, N);
        case 'AutoOptimize'
            result = runAutoOptimize(signals, signalNames, mkt, macro, opts, T, N, rebalFreq, inPct);
        otherwise
            error('sigstrat:decisionTreeStrategy', 'Unknown mode: %s', mode);
    end

    result.mode = mode;
    fprintf('Decision tree strategy (%s): avg equity weight=%.1f%%\n', ...
        mode, mean(result.eqWts(isfinite(result.eqWts))) * 100);
end

%% ==================== RULE-BASED MODE ====================
function result = runRuleBased(signals, signalNames, mkt, macro, opts, T, ~)
    rules   = getOpt(opts, 'rules', defaultRules(signalNames));
    ruleAgg = getOpt(opts, 'ruleAgg', 'FirstMatch');

    nRules = size(rules, 1);
    eqWts = NaN(T, 1);

    % Build feature matrix: signals + aligned macro
    [featureMatrix, featureNames] = buildFeatures(signals, signalNames, macro, mkt);

    for t = 1:T
        featureRow = featureMatrix(t, :);

        switch ruleAgg
            case 'FirstMatch'
                matched = false;
                for ri = 1:nRules
                    varName  = rules{ri, 1};
                    operator = rules{ri, 2};
                    thresh   = rules{ri, 3};
                    eqW      = rules{ri, 4};

                    varIdx = find(strcmp(featureNames, varName), 1);
                    if isempty(varIdx), continue; end

                    val = featureRow(varIdx);
                    if ~isfinite(val), continue; end

                    if evalCondition(val, operator, thresh)
                        eqWts(t) = eqW;
                        matched = true;
                        break;
                    end
                end
                if ~matched
                    eqWts(t) = 0.5;  % default
                end

            case 'Average'
                matchedWts = [];
                for ri = 1:nRules
                    varName  = rules{ri, 1};
                    operator = rules{ri, 2};
                    thresh   = rules{ri, 3};
                    eqW      = rules{ri, 4};

                    varIdx = find(strcmp(featureNames, varName), 1);
                    if isempty(varIdx), continue; end

                    val = featureRow(varIdx);
                    if ~isfinite(val), continue; end

                    if evalCondition(val, operator, thresh)
                        matchedWts(end+1) = eqW; %#ok<AGROW>
                    end
                end
                if isempty(matchedWts)
                    eqWts(t) = 0.5;
                else
                    eqWts(t) = mean(matchedWts);
                end
        end
    end

    eqWts = max(0, min(1, eqWts));
    eqWts(isnan(eqWts)) = 0.5;

    % Build rules text
    rulesText = buildRulesText(rules);

    result.eqWts        = eqWts;
    result.rulesText    = rulesText;
    result.rules        = rules;
    result.importance   = [];
    result.featureNames = featureNames;
end

%% ==================== AUTO-OPTIMIZE MODE ====================
function result = runAutoOptimize(signals, signalNames, mkt, macro, opts, T, ~, rebalFreq, inPct)
    maxDepth      = getOpt(opts, 'maxDepth', 3);
    minLeaf       = getOpt(opts, 'minLeafSize', 50);
    useRegression = getOpt(opts, 'useRegression', true);
    nFolds        = getOpt(opts, 'nFolds', 3);

    % Build feature matrix
    [featureMatrix, featureNames] = buildFeatures(signals, signalNames, macro, mkt);
    nFeatures = numel(featureNames);

    % Construct targets
    spxRet  = mkt.spxRet;
    cashRet = mkt.cashRet;
    fwdEqRet   = NaN(T, 1);
    fwdCashRet = NaN(T, 1);
    for t = 1:T-rebalFreq
        fwdEqRet(t)   = prod(1 + spxRet(t+1:t+rebalFreq)) - 1;
        fwdCashRet(t) = prod(1 + cashRet(t+1:t+rebalFreq)) - 1;
    end

    if useRegression
        % Regression target: excess return (continuous)
        excessRet = fwdEqRet - fwdCashRet;
    end
    targetBinary = double(fwdEqRet > fwdCashRet);  % binary fallback

    % Walk-forward: train on first inPct, predict on rest
    splitIdx = round(T * inPct);
    eqWts = NaN(T, 1);
    eqWts(1:splitIdx) = 0.5;

    %% K-fold expanding-window CV for hyperparameter selection
    depthCands = max(1, maxDepth-1):min(8, maxDepth+2);
    leafCands  = [max(10, minLeaf-20), minLeaf, minLeaf+30];

    bestCVObj = -Inf;
    bestDepth = maxDepth;
    bestLeaf  = minLeaf;

    for di = 1:numel(depthCands)
        for li = 1:numel(leafCands)
            foldObj = zeros(nFolds, 1);
            for fold = 1:nFolds
                foldTrainEnd = round(splitIdx * fold / (nFolds + 1));
                foldTestStart = foldTrainEnd + 1;
                foldTestEnd = round(splitIdx * (fold + 1) / (nFolds + 1));
                if foldTestEnd > splitIdx, foldTestEnd = splitIdx; end
                if foldTestStart >= foldTestEnd, continue; end

                if useRegression
                    target_cv = excessRet;
                else
                    target_cv = targetBinary;
                end
                validTr = isfinite(target_cv(1:foldTrainEnd)) & ...
                    all(isfinite(featureMatrix(1:foldTrainEnd, :)), 2);
                if sum(validTr) < 50, continue; end

                X_tr = featureMatrix(validTr, :);
                Y_tr = target_cv(validTr);
                ms = 2^depthCands(di) - 1;

                if useRegression
                    mdl = fitrtree(X_tr, Y_tr, 'MaxNumSplits', ms, ...
                        'MinLeafSize', leafCands(li), 'PredictorNames', featureNames);
                    predRaw = predict(mdl, featureMatrix(foldTestStart:foldTestEnd, :));
                    % Map predictions to [0,1] via sigmoid
                    predWt = 1 ./ (1 + exp(-10 * predRaw));
                else
                    mdl = fitctree(X_tr, Y_tr, 'MaxNumSplits', ms, ...
                        'MinLeafSize', leafCands(li), 'PredictorNames', featureNames);
                    [~, scores] = predict(mdl, featureMatrix(foldTestStart:foldTestEnd, :));
                    if size(scores, 2) >= 2
                        predWt = scores(:, 2);
                    else
                        predWt = 0.5 * ones(foldTestEnd - foldTestStart + 1, 1);
                    end
                end

                predWt = max(0, min(1, predWt));
                mktFold = subsetMkt(mkt, foldTestStart, foldTestEnd);
                bt = sigstrat.backtestEquityCash(predWt, mktFold, rebalFreq, 0.001);
                r = bt.portRet;
                if numel(r) < 10, continue; end
                annRet = (prod(1 + r))^(252 / numel(r)) - 1;
                annVol = std(r) * sqrt(252);
                foldObj(fold) = annRet / max(1e-12, annVol);
            end

            avgObj = mean(foldObj);
            if avgObj > bestCVObj
                bestCVObj = avgObj;
                bestDepth = depthCands(di);
                bestLeaf  = leafCands(li);
            end
        end
    end

    fprintf('CV selected: depth=%d, minLeaf=%d (avg Sharpe=%.2f)\n', bestDepth, bestLeaf, bestCVObj);

    %% Fit final model with best hyperparameters
    if useRegression
        targetFinal = excessRet;
    else
        targetFinal = targetBinary;
    end
    validTrain = isfinite(targetFinal(1:splitIdx)) & all(isfinite(featureMatrix(1:splitIdx, :)), 2);

    if sum(validTrain) < 100
        warning('sigstrat:decisionTreeStrategy', 'Insufficient valid training data (%d rows).', sum(validTrain));
        result.eqWts = 0.5 * ones(T, 1);
        result.rulesText = 'Insufficient training data';
        result.importance = zeros(1, nFeatures);
        result.featureNames = featureNames;
        result.cvMetrics = struct();
        return;
    end

    X_train = featureMatrix(validTrain, :);
    Y_train = targetFinal(validTrain);
    maxSplits = 2^bestDepth - 1;

    if useRegression
        treeModel = fitrtree(X_train, Y_train, ...
            'MaxNumSplits', maxSplits, ...
            'MinLeafSize', bestLeaf, ...
            'PredictorNames', featureNames);

        % Predict on out-of-sample
        for t = splitIdx+1:T
            row = featureMatrix(t, :);
            if any(~isfinite(row))
                eqWts(t) = 0.5;
                continue;
            end
            predRaw = predict(treeModel, row);
            eqWts(t) = 1 / (1 + exp(-10 * predRaw));
        end
    else
        treeModel = fitctree(X_train, Y_train, ...
            'MaxNumSplits', maxSplits, ...
            'MinLeafSize', bestLeaf, ...
            'PredictorNames', featureNames);

        for t = splitIdx+1:T
            row = featureMatrix(t, :);
            if any(~isfinite(row))
                eqWts(t) = 0.5;
                continue;
            end
            [~, scores] = predict(treeModel, row);
            if size(scores, 2) >= 2
                eqWts(t) = scores(:, 2);
            else
                eqWts(t) = 0.5;
            end
        end
    end

    eqWts = max(0, min(1, eqWts));
    eqWts(isnan(eqWts)) = 0.5;

    rulesText = extractTreeRules(treeModel);
    importance = predictorImportance(treeModel);

    result.eqWts        = eqWts;
    result.rulesText    = rulesText;
    result.importance   = importance;
    result.featureNames = featureNames;
    result.treeModel    = treeModel;
    result.splitIdx     = splitIdx;
    result.cvMetrics    = struct('bestDepth', bestDepth, 'bestLeaf', bestLeaf, ...
        'avgCVSharpe', bestCVObj, 'useRegression', useRegression, 'nFolds', nFolds);
end

%% ---- Build feature matrix ----
function [featureMatrix, featureNames] = buildFeatures(signals, signalNames, macro, mkt)
    featureMatrix = signals;
    featureNames = signalNames(:)';

    if ~isempty(macro) && istable(macro)
        macroVars = macro.Properties.VariableNames;
        macroVars = macroVars(~strcmp(macroVars, 'Date'));
        macroDates = macro.Date;

        for j = 1:numel(macroVars)
            aligned = forwardFill(macroDates, macro.(macroVars{j}), mkt.retDates);
            featureMatrix = [featureMatrix, aligned]; %#ok<AGROW>
            featureNames{end+1} = macroVars{j}; %#ok<AGROW>
        end
    end

    % Replace NaN with 0 in feature matrix for tree fitting
    featureMatrix(~isfinite(featureMatrix)) = 0;
end

%% ---- Evaluate condition ----
function match = evalCondition(val, operator, thresh)
    switch operator
        case '>'
            match = val > thresh;
        case '>='
            match = val >= thresh;
        case '<'
            match = val < thresh;
        case '<='
            match = val <= thresh;
        case '=='
            match = abs(val - thresh) < 1e-10;
        otherwise
            match = false;
    end
end

%% ---- Default rules ----
function rules = defaultRules(signalNames)
    % Simple default: if first signal > 0 → 80% equity, else 30%
    if isempty(signalNames)
        rules = {'Signal1', '>', 0, 0.80; 'Signal1', '<=', 0, 0.30};
    else
        rules = {signalNames{1}, '>', 0, 0.80; signalNames{1}, '<=', 0, 0.30};
    end
end

%% ---- Build rules text from rule definitions ----
function txt = buildRulesText(rules)
    lines = cell(size(rules, 1), 1);
    for i = 1:size(rules, 1)
        lines{i} = sprintf('IF %s %s %.3f THEN EqWt = %.0f%%', ...
            rules{i,1}, rules{i,2}, rules{i,3}, rules{i,4}*100);
    end
    lines{end+1} = 'ELSE EqWt = 50% (default)';
    txt = strjoin(lines, '\n');
end

%% ---- Extract tree rules as text ----
function txt = extractTreeRules(treeModel)
    try
        treeView = treeModel.view('Mode', 'text');
        if ischar(treeView)
            txt = treeView;
        elseif iscell(treeView)
            txt = strjoin(treeView, '\n');
        else
            txt = 'Tree rules extracted (see model).';
        end
    catch
        % Fallback: manual extraction
        try
            nNodes = numel(treeModel.NodeClass);
            lines = {};
            for i = 1:nNodes
                if treeModel.IsBranchNode(i)
                    cutVar = treeModel.CutPredictor{i};
                    cutVal = treeModel.CutPoint(i);
                    lines{end+1} = sprintf('Node %d: IF %s < %.4f', i, cutVar, cutVal); %#ok<AGROW>
                else
                    nodeClass = treeModel.NodeClass{i};
                    lines{end+1} = sprintf('Node %d: Leaf -> class %s', i, string(nodeClass)); %#ok<AGROW>
                end
            end
            txt = strjoin(lines, '\n');
        catch
            txt = 'Could not extract tree rules.';
        end
    end
end

%% ---- Forward-fill alignment ----
function vals = forwardFill(srcDates, srcVals, targetDates)
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

%% ---- Subset market data ----
function mktSub = subsetMkt(mkt, i1, i2)
    mktSub.retDates = mkt.retDates(i1:i2);
    mktSub.spxRet   = mkt.spxRet(i1:i2);
    mktSub.cashRet  = mkt.cashRet(i1:i2);
    mktSub.spxPrice = mkt.spxPrice(i1:min(i2+1, numel(mkt.spxPrice)));
    mktSub.dates    = mkt.dates(i1:min(i2+1, numel(mkt.dates)));
end

%% ---- Get option with default ----
function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
