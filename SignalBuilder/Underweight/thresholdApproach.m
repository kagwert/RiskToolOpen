function results = thresholdApproach(features, labels, opts)
% thresholdApproach  Evaluate static threshold rules for equity underweighting.
%
%   results = thresholdApproach(features, labels)
%   results = thresholdApproach(features, labels, BaseWeight=0.50, MildWeight=0.35)
%
%   For each signal column (individual + composites), sweeps a grid of
%   (MildThreshold, SevereThreshold) pairs and returns the allocation
%   implied by each threshold setting, along with balanced accuracy
%   versus the regime labels.
%
%   Allocation rule (applied in priority order):
%       signal ≤ SevereThresh  →  SevereWeight  (default 20%)
%       signal ≤ MildThresh    →  MildWeight    (default 35%)
%       otherwise              →  BaseWeight    (default 50%)
%
%   All signals are constructed negative = risk-off, so LOWER thresholds
%   correspond to MORE negative (worse) conditions.
%
%   NaN signal rows are mapped to BaseWeight (conservative: stay neutral).
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   features       timetable  – from buildSignals()
%   labels         timetable  – from labelEquityRegimes()
%
%   BaseWeight     (1,1) dbl  – full equity allocation    [default 0.50]
%   MildWeight     (1,1) dbl  – mild underweight alloc    [default 0.35]
%   SevereWeight   (1,1) dbl  – severe underweight alloc  [default 0.20]
%   MildGrid       (1,:) dbl  – mild threshold candidates [default -0.5:0.1:0.1]
%   SevereGrid     (1,:) dbl  – severe threshold candidates [default -0.9:0.1:-0.2]
%
% -------------------------------------------------------------------------
%  OUTPUT STRUCTURE
% -------------------------------------------------------------------------
%   results — struct with one field per signal variant, each containing:
%     .Times          – datetime vector (common sample)
%     .Signal         – signal values (n×1)
%     .ActualLabel    – regime labels (n×1)
%     .ThreshGrid     – [nPairs × 2] [MildThr, SevereThr]
%     .AllocMat       – [n × nPairs] equity allocation over time
%     .BalAccuracy    – [nPairs × 1] balanced accuracy vs labels
%     .AvgAllocation  – [nPairs × 1] mean equity allocation
%     .BestIdx        – index of best threshold pair by balanced accuracy
%     .BestThresholds – [1×2] [MildThr, SevereThr] at best accuracy
%     .BestAlloc      – [n×1] allocation series at best thresholds
%     .BestBalAcc     – scalar balanced accuracy at best thresholds
%
%   Signal variants evaluated:
%     PayrollsMom, YieldCurve, CreditSpread, EquityTrend   (individual)
%     Composite                                             (equal-weighted)
%     MacroComposite   (PayrollsMom 40%, YieldCurve 35%, CreditSpread 25%)
%     MarketComposite  (CreditSpread 30%, EquityTrend 50%, YieldCurve 20%)
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   r = thresholdApproach(features, labels);
%   fprintf('Best composite thresholds: Mild=%.1f, Severe=%.1f (BalAcc=%.2f)\n', ...
%       r.Composite.BestThresholds(1), r.Composite.BestThresholds(2), ...
%       r.Composite.BestBalAcc);

    arguments
        features      timetable
        labels        timetable
        opts.BaseWeight    (1,1) double {mustBeInRange(opts.BaseWeight,0,1)}   = 0.50
        opts.MildWeight    (1,1) double {mustBeInRange(opts.MildWeight,0,1)}   = 0.35
        opts.SevereWeight  (1,1) double {mustBeInRange(opts.SevereWeight,0,1)} = 0.20
        opts.MildGrid      (1,:) double = -0.5 : 0.1 : 0.1
        opts.SevereGrid    (1,:) double = -0.9 : 0.1 : -0.2
    end

    if opts.SevereWeight >= opts.MildWeight || opts.MildWeight >= opts.BaseWeight
        error('SignalBuilder:thresholdApproach:badParam', ...
            'Weights must satisfy SevereWeight < MildWeight < BaseWeight.');
    end

    % ------------------------------------------------------------------ %
    % Align features and labels to common time grid; drop NaN-label rows
    % ------------------------------------------------------------------ %
    % Both timetables use no-timezone datetime; synchronize by matching times
    [~, iF, iL] = intersect(features.Time, labels.Time);
    feat  = features(iF, :);
    lbl   = labels(iL, :);
    valid = ~isnan(lbl.Label);
    feat  = feat(valid, :);
    lbl   = lbl(valid, :);
    n     = height(feat);

    if n < 30
        error('SignalBuilder:thresholdApproach:insufficientData', ...
            'Need at least 30 labelled months; got %d.', n);
    end

    % ------------------------------------------------------------------ %
    % Build threshold pairs grid (enforce SevereThr < MildThr)
    % ------------------------------------------------------------------ %
    [mG, sG]   = ndgrid(opts.MildGrid, opts.SevereGrid);
    mG         = mG(:);
    sG         = sG(:);
    validPairs = sG < mG;
    mG         = mG(validPairs);
    sG         = sG(validPairs);
    nPairs     = numel(mG);

    % ------------------------------------------------------------------ %
    % Define signal variants to evaluate
    %   Each variant is a n×1 vector; names match output struct fieldnames
    % ------------------------------------------------------------------ %
    sigNames = {};
    sigMats  = {};

    % Individual signals
    indivCols = {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend','Composite'};
    for k = 1 : numel(indivCols)
        col = indivCols{k};
        if ismember(col, feat.Properties.VariableNames)
            sigNames{end+1} = col; %#ok<AGROW>
            sigMats{end+1}  = feat.(col); %#ok<AGROW>
        end
    end

    % Macro composite: macro signals only, pre-set weights
    macroMat = [feat.PayrollsMom, feat.YieldCurve, feat.CreditSpread];
    macroW   = [0.40; 0.35; 0.25];
    macroSig = thresholdApproach_weightedComposite(macroMat, macroW);
    sigNames{end+1} = 'MacroComposite';
    sigMats{end+1}  = macroSig;

    % Market composite: credit + equity trend, yield curve as filter
    mktMat = [feat.CreditSpread, feat.EquityTrend, feat.YieldCurve];
    mktW   = [0.30; 0.50; 0.20];
    mktSig = thresholdApproach_weightedComposite(mktMat, mktW);
    sigNames{end+1} = 'MarketComposite';
    sigMats{end+1}  = mktSig;

    actualLabel = lbl.Label;
    results     = struct();

    % ------------------------------------------------------------------ %
    % Sweep thresholds for each signal variant
    % ------------------------------------------------------------------ %
    for s = 1 : numel(sigNames)
        sig = sigMats{s};

        balAcc  = nan(nPairs, 1);
        avgAlloc = nan(nPairs, 1);
        allocMat = nan(n, nPairs);

        for p = 1 : nPairs
            alloc = thresholdApproach_mapAlloc(sig, mG(p), sG(p), ...
                opts.BaseWeight, opts.MildWeight, opts.SevereWeight);
            allocMat(:, p) = alloc;
            avgAlloc(p)    = mean(alloc, 'omitnan');

            % Predicted label from allocation
            predLabel = thresholdApproach_allocToLabel(alloc, ...
                opts.BaseWeight, opts.MildWeight, opts.SevereWeight);

            % Balanced accuracy = mean per-class recall (handles class imbalance)
            balAcc(p) = thresholdApproach_balancedAccuracy(actualLabel, predLabel);
        end

        [bestAcc, bestIdx] = max(balAcc);

        res.Times          = feat.Time;
        res.Signal         = sig;
        res.ActualLabel    = actualLabel;
        res.ThreshGrid     = [mG, sG];
        res.AllocMat       = allocMat;
        res.BalAccuracy    = balAcc;
        res.AvgAllocation  = avgAlloc;
        res.BestIdx        = bestIdx;
        res.BestThresholds = [mG(bestIdx), sG(bestIdx)];
        res.BestAlloc      = allocMat(:, bestIdx);
        res.BestBalAcc     = bestAcc;

        results.(sigNames{s}) = res;
    end

    % ------------------------------------------------------------------ %
    % Print summary table
    % ------------------------------------------------------------------ %
    fprintf('\n[thresholdApproach] Best thresholds per signal variant:\n');
    fprintf('  %-20s  %7s  %9s  %8s  %7s\n', ...
        'Signal', 'MildThr', 'SevereThr', 'BalAcc', 'AvgAlloc');
    fprintf('  %s\n', repmat('-', 1, 60));
    for s = 1 : numel(sigNames)
        r = results.(sigNames{s});
        fprintf('  %-20s  %7.2f  %9.2f  %8.3f  %7.1f%%\n', ...
            sigNames{s}, r.BestThresholds(1), r.BestThresholds(2), ...
            r.BestBalAcc, r.AvgAllocation(r.BestIdx)*100);
    end
    fprintf('\n');
end

% =========================================================================
% Local helpers
% =========================================================================
function alloc = thresholdApproach_mapAlloc(sig, mildThr, severeThr, ...
        baseW, mildW, severeW)
    alloc = repmat(baseW, numel(sig), 1);
    alloc(sig <= mildThr)   = mildW;
    alloc(sig <= severeThr) = severeW;
    alloc(isnan(sig))       = baseW;   % NaN signal → stay at base
end

function predLabel = thresholdApproach_allocToLabel(alloc, ~, mildW, severeW)
    predLabel = zeros(numel(alloc), 1);
    predLabel(alloc <= mildW + eps & alloc > severeW + eps) = 1;   % Mild
    predLabel(alloc <= severeW + eps) = 2;                         % Severe
end

function bacc = thresholdApproach_balancedAccuracy(actual, pred)
    classes = [0; 1; 2];
    recalls = nan(numel(classes), 1);
    for k = 1 : numel(classes)
        c = classes(k);
        isClass = actual == c;
        if sum(isClass) == 0
            recalls(k) = NaN;   % class absent — exclude from average
        else
            recalls(k) = sum(pred(isClass) == c) / sum(isClass);
        end
    end
    bacc = mean(recalls, 'omitnan');
end

function sig = thresholdApproach_weightedComposite(mat, weights)
    % Normalised weighted average of columns; NaN-tolerant per row
    wMat   = repmat(weights(:)', size(mat, 1), 1);   % n × nCols
    wMat(isnan(mat)) = 0;
    wSum   = sum(wMat, 2);
    sig    = sum(wMat .* mat, 2, 'omitnan') ./ max(wSum, eps);
    sig(wSum == 0) = NaN;
end
