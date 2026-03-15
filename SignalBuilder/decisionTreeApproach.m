function results = decisionTreeApproach(features, labels, opts)
% decisionTreeApproach  Shallow classification tree for equity regime identification.
%
%   results = decisionTreeApproach(features, labels)
%   results = decisionTreeApproach(features, labels, MaxNumSplits=4)
%
%   Fits a CART decision tree (fitctree) using the signal columns as
%   predictors and the regime labels (0=Neutral, 1=MildUW, 2=SevereUW)
%   as the response.  Tree depth is constrained to produce interpretable
%   rules (MaxNumSplits default = 4 → at most 5 leaf nodes).
%
%   Class imbalance is addressed via a cost matrix that penalises
%   misclassifying Severe periods more heavily than Neutral periods.
%
%   Both in-sample and cross-validated metrics are reported.
%
%   Requires: Statistics and Machine Learning Toolbox (fitctree).
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   features         timetable  – from buildSignals()
%   labels           timetable  – from labelEquityRegimes()
%
%   MaxNumSplits     (1,1) int  – maximum number of branch splits
%                                 [default 4]
%   PredictorCols    (1,:) str  – signal columns to use as predictors
%                                 [default all: PayrollsMom, YieldCurve,
%                                  CreditSpread, EquityTrend]
%   CostSevere       (1,1) dbl  – cost weight for missing a SevereUW period
%                                 (relative to missing a Neutral period = 1)
%                                 [default 5]
%   CostMild         (1,1) dbl  – cost weight for missing a MildUW period
%                                 [default 2]
%   NumKFolds        (1,1) int  – number of cross-validation folds
%                                 [default 5]
%   BaseWeight       (1,1) dbl  – equity allocation for Neutral  [default 0.50]
%   MildWeight       (1,1) dbl  – equity allocation for MildUW   [default 0.35]
%   SevereWeight     (1,1) dbl  – equity allocation for SevereUW [default 0.20]
%
% -------------------------------------------------------------------------
%  OUTPUT STRUCTURE
% -------------------------------------------------------------------------
%   results.Tree            – fitted ClassificationTree object
%   results.CVModel         – cross-validated model (ClassificationPartitionedModel)
%   results.Times           – datetime vector (common labelled sample)
%   results.ActualLabel     – actual regime labels (n×1)
%   results.PredictedLabel  – in-sample predicted labels (n×1)
%   results.Allocation      – equity allocation from tree predictions (n×1)
%   results.BalAccuracy     – in-sample balanced accuracy
%   results.CVBalAccuracy   – cross-validated balanced accuracy
%   results.ConfusionMat    – 3×3 confusion matrix [Neutral/Mild/Severe]
%   results.FeatureNames    – predictor column names used
%   results.AllocWeights    – struct: BaseWeight, MildWeight, SevereWeight
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   r = decisionTreeApproach(features, labels);
%   view(r.Tree, 'Mode', 'graph')   % interactive tree viewer
%   fprintf('CV balanced accuracy: %.3f\n', r.CVBalAccuracy)

    arguments
        features        timetable
        labels          timetable
        opts.MaxNumSplits    (1,1) double {mustBePositive, mustBeInteger} = 4
        opts.PredictorCols   (1,:) string = ["PayrollsMom","YieldCurve","CreditSpread","EquityTrend"]
        opts.CostSevere      (1,1) double {mustBePositive}               = 5
        opts.CostMild        (1,1) double {mustBePositive}               = 2
        opts.NumKFolds       (1,1) double {mustBePositive, mustBeInteger} = 5
        opts.BaseWeight      (1,1) double = 0.50
        opts.MildWeight      (1,1) double = 0.35
        opts.SevereWeight    (1,1) double = 0.20
    end

    % Check toolbox
    if ~(exist('fitctree', 'file') == 2 || exist('fitctree', 'builtin') == 5)
        error('SignalBuilder:decisionTreeApproach:toolboxMissing', ...
            ['fitctree requires the Statistics and Machine Learning Toolbox.\n' ...
             'Use thresholdApproach() instead for a toolbox-free alternative.']);
    end

    % ------------------------------------------------------------------ %
    % Align features and labels; drop NaN-label rows
    % ------------------------------------------------------------------ %
    [~, iF, iL] = intersect(features.Time, labels.Time);
    feat  = features(iF, :);
    lbl   = labels(iL, :);
    valid = ~isnan(lbl.Label);
    feat  = feat(valid, :);
    lbl   = lbl(valid, :);
    n     = height(feat);

    if n < 20
        error('SignalBuilder:decisionTreeApproach:insufficientData', ...
            'Need at least 20 labelled months; got %d.', n);
    end

    % ------------------------------------------------------------------ %
    % Build predictor matrix (drop NaN rows for training)
    % ------------------------------------------------------------------ %
    predCols = opts.PredictorCols;
    missing  = predCols(~ismember(predCols, string(feat.Properties.VariableNames)));
    if ~isempty(missing)
        error('SignalBuilder:decisionTreeApproach:missingColumn', ...
            'Predictor columns not found: %s', strjoin(missing, ', '));
    end

    X      = table2array(feat(:, cellstr(predCols)));
    Y      = lbl.Label;
    rowOK  = all(~isnan(X), 2);   % rows with complete predictors
    Xtrain = X(rowOK, :);
    Ytrain = Y(rowOK);

    nTrain = sum(rowOK);
    if nTrain < 15
        error('SignalBuilder:decisionTreeApproach:insufficientData', ...
            'Only %d complete rows after removing NaNs; need at least 15.', nTrain);
    end

    % ------------------------------------------------------------------ %
    % Cost matrix (asymmetric misclassification costs)
    %   rows = true class, columns = predicted class
    %   order: [0 Neutral, 1 MildUW, 2 SevereUW]
    %
    %   Cost(i,j) = cost of predicting class j when true class is i
    %   Diagonal = 0 (correct prediction)
    %   High cost for missing Severe: Cost(3,1), Cost(3,2)
    % ------------------------------------------------------------------ %
    c = opts.CostMild;
    s = opts.CostSevere;
    %         Pred: Neutral  Mild    Severe
    costMat = [ 0,      c,      s;   ...  % True: Neutral  (FP costs)
                1,      0,      c;   ...  % True: MildUW   (FN=1, FP=c)
                s,      c,      0  ];     % True: SevereUW (FN=s, FP=c)

    % ------------------------------------------------------------------ %
    % Fit classification tree
    % ------------------------------------------------------------------ %
    tree = fitctree(Xtrain, Ytrain, ...
        'MaxNumSplits',  opts.MaxNumSplits, ...
        'PredictorNames', cellstr(predCols), ...
        'ResponseName',  'EquityRegime', ...
        'ClassNames',    [0; 1; 2], ...
        'Cost',          costMat, ...
        'MinLeafSize',   max(3, floor(nTrain * 0.03)));   % min 3% of sample per leaf

    % ------------------------------------------------------------------ %
    % Cross-validation (non-stratified to avoid warnings with rare classes)
    % ------------------------------------------------------------------ %
    k       = min(opts.NumKFolds, nTrain);
    cvpart  = cvpartition(nTrain, 'KFold', k);   % non-stratified by sample count
    cvModel = crossval(tree, 'CVPartition', cvpart);
    cvPred  = kfoldPredict(cvModel);

    % ------------------------------------------------------------------ %
    % In-sample predictions over full aligned sample
    %   Rows with NaN predictors get NaN label → map to base allocation
    % ------------------------------------------------------------------ %
    predLabel    = nan(n, 1);
    predLabel(rowOK) = predict(tree, Xtrain);

    % ------------------------------------------------------------------ %
    % Convert labels to equity allocations
    % ------------------------------------------------------------------ %
    alloc = decisionTreeApproach_labelToAlloc(predLabel, ...
        opts.BaseWeight, opts.MildWeight, opts.SevereWeight);

    % ------------------------------------------------------------------ %
    % Performance metrics
    % ------------------------------------------------------------------ %
    actualLabel = Y;

    balAcc   = decisionTreeApproach_balancedAccuracy( ...
        actualLabel(rowOK), predLabel(rowOK));
    cvBalAcc = decisionTreeApproach_balancedAccuracy(Ytrain, cvPred);

    confMat = confusionmat(actualLabel(rowOK), predLabel(rowOK), ...
        'Order', [0; 1; 2]);

    % ------------------------------------------------------------------ %
    % Pack results
    % ------------------------------------------------------------------ %
    results.Tree           = tree;
    results.CVModel        = cvModel;
    results.Times          = feat.Time;
    results.ActualLabel    = actualLabel;
    results.PredictedLabel = predLabel;
    results.Allocation     = alloc;
    results.BalAccuracy    = balAcc;
    results.CVBalAccuracy  = cvBalAcc;
    results.ConfusionMat   = confMat;
    results.FeatureNames   = predCols;
    results.AllocWeights   = struct('Base', opts.BaseWeight, ...
        'Mild', opts.MildWeight, 'Severe', opts.SevereWeight);

    % ------------------------------------------------------------------ %
    % Print summary
    % ------------------------------------------------------------------ %
    fprintf('\n[decisionTreeApproach] MaxNumSplits=%d, %d training rows\n', ...
        opts.MaxNumSplits, nTrain);
    fprintf('  In-sample balanced accuracy : %.3f\n', balAcc);
    fprintf('  %d-fold CV balanced accuracy: %.3f\n', opts.NumKFolds, cvBalAcc);

    nNeutral = sum(actualLabel == 0, 'omitnan');
    nMild    = sum(actualLabel == 1, 'omitnan');
    nSevere  = sum(actualLabel == 2, 'omitnan');

    fprintf('  Confusion matrix (rows=actual, cols=predicted):\n');
    fprintf('                    Pred:Neutral  Pred:Mild  Pred:Severe\n');
    fprintf('  Actual:Neutral    %8d      %8d    %8d\n', confMat(1,:));
    fprintf('  Actual:Mild       %8d      %8d    %8d\n', confMat(2,:));
    fprintf('  Actual:Severe     %8d      %8d    %8d\n', confMat(3,:));

    fprintf('  Class prevalence: Neutral=%d, Mild=%d, Severe=%d\n\n', ...
        nNeutral, nMild, nSevere);

    % Print the tree rules as text
    fprintf('[decisionTreeApproach] Decision rules:\n');
    view(tree);
    fprintf('\n');
end

% =========================================================================
% Local helpers
% =========================================================================
function alloc = decisionTreeApproach_labelToAlloc(label, baseW, mildW, severeW)
    alloc = repmat(baseW, numel(label), 1);
    alloc(label == 1) = mildW;
    alloc(label == 2) = severeW;
    alloc(isnan(label)) = baseW;   % NaN (incomplete features) → base
end

function bacc = decisionTreeApproach_balancedAccuracy(actual, pred)
    classes = [0; 1; 2];
    recalls = nan(numel(classes), 1);
    for k = 1 : numel(classes)
        c = classes(k);
        isClass = actual == c;
        if sum(isClass) == 0
            recalls(k) = NaN;
        else
            recalls(k) = sum(pred(isClass) == c) / sum(isClass);
        end
    end
    bacc = mean(recalls, 'omitnan');
end
