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
%
% Returns:
%   result.eqWts        - Tx1 equity weights
%   result.mode         - 'RuleBased' or 'AutoOptimize'
%   result.rulesText    - human-readable rule description
%   result.importance   - variable importance (auto mode)
%   result.featureNames - feature names used

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
function result = runRuleBased(signals, signalNames, mkt, macro, opts, T, ~) %#ok<INUSL>
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
function result = runAutoOptimize(signals, signalNames, mkt, macro, opts, T, N, rebalFreq, inPct) %#ok<INUSL>
    maxDepth   = getOpt(opts, 'maxDepth', 3);
    minLeaf    = getOpt(opts, 'minLeafSize', 50);

    % Build feature matrix
    [featureMatrix, featureNames] = buildFeatures(signals, signalNames, macro, mkt);
    nFeatures = numel(featureNames);

    % Target: did equity outperform cash over next rebalFreq days?
    spxRet  = mkt.spxRet;
    cashRet = mkt.cashRet;
    fwdEqRet   = NaN(T, 1);
    fwdCashRet = NaN(T, 1);
    for t = 1:T-rebalFreq
        fwdEqRet(t)   = prod(1 + spxRet(t+1:t+rebalFreq)) - 1;
        fwdCashRet(t) = prod(1 + cashRet(t+1:t+rebalFreq)) - 1;
    end
    target = double(fwdEqRet > fwdCashRet);  % binary

    % Walk-forward: train on first inPct, predict on rest
    splitIdx = round(T * inPct);
    eqWts = NaN(T, 1);
    eqWts(1:splitIdx) = 0.5;  % no prediction for in-sample

    % Identify valid training rows
    validTrain = isfinite(target(1:splitIdx)) & all(isfinite(featureMatrix(1:splitIdx, :)), 2);

    if sum(validTrain) < 100
        warning('sigstrat:decisionTreeStrategy', 'Insufficient valid training data (%d rows).', sum(validTrain));
        result.eqWts = 0.5 * ones(T, 1);
        result.rulesText = 'Insufficient training data';
        result.importance = zeros(1, nFeatures);
        result.featureNames = featureNames;
        return;
    end

    X_train = featureMatrix(validTrain, :);
    Y_train = target(validTrain);

    % Fit classification tree
    maxSplits = 2^maxDepth - 1;
    treeModel = fitctree(X_train, Y_train, ...
        'MaxNumSplits', maxSplits, ...
        'MinLeafSize', minLeaf, ...
        'PredictorNames', featureNames);

    % Predict on out-of-sample
    for t = splitIdx+1:T
        row = featureMatrix(t, :);
        if any(~isfinite(row))
            eqWts(t) = 0.5;
            continue;
        end
        [~, scores] = predict(treeModel, row);
        if size(scores, 2) >= 2
            eqWts(t) = scores(:, 2);  % probability of class 1 (equity outperforms)
        else
            eqWts(t) = 0.5;
        end
    end

    eqWts = max(0, min(1, eqWts));
    eqWts(isnan(eqWts)) = 0.5;

    % Extract rules text
    rulesText = extractTreeRules(treeModel);

    % Variable importance
    importance = predictorImportance(treeModel);

    result.eqWts        = eqWts;
    result.rulesText    = rulesText;
    result.importance   = importance;
    result.featureNames = featureNames;
    result.treeModel    = treeModel;
    result.splitIdx     = splitIdx;
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

%% ---- Get option with default ----
function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
