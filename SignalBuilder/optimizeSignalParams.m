function result = optimizeSignalParams(dm, ~, startDate, labels, monthGrid, equityPrices)
% optimizeSignalParams  Grid-search per-signal parameters for the underweight strategy.
%
%   result = optimizeSignalParams(dm, equityTicker, startDate, labels, monthGrid, equityPrices)
%
%   Sweeps internal construction parameters for each of the four signals
%   (PayrollsMom, YieldCurve, CreditSpread, EquityTrend) and returns the
%   parameter combination that maximises balanced accuracy against regime
%   labels. FRED data is already cached in dm → fast repeated calls.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm             (1,1) Model.DataManager  – initialised, data already fetched
%   equityTicker   (1,1) string             – e.g. 'SPY'
%   startDate      (1,1) string             – fetch start 'yyyy-MM-dd'
%   labels         timetable               – from labelEquityRegimes()
%   monthGrid      (:,1) datetime           – monthly end-of-month grid
%   equityPrices   timetable               – daily OHLCV with 'Close' column
%
% -------------------------------------------------------------------------
%  OUTPUT STRUCT FIELDS  (one sub-struct per signal)
% -------------------------------------------------------------------------
%   result.PayrollsMom.BestParams      struct  (PrefilterWindow, SmoothHalfLife)
%   result.PayrollsMom.BestBalAcc      double
%   result.PayrollsMom.AccuracyMatrix  double [nRow × nCol]
%   result.PayrollsMom.RowLabels       cell   (Param1 values)
%   result.PayrollsMom.ColLabels       cell   (Param2 values)
%   result.PayrollsMom.OptSignal       double [nMonths × 1]
%
%   result.YieldCurve   — same structure (ZScoreWindow, SmoothHalfLife)
%   result.CreditSpread — same structure (ZScoreWindow, SmoothHalfLife)
%   result.EquityTrend  — same structure (MAWindow, TrendScale)

    % ------------------------------------------------------------------ %
    % Align labels to monthGrid; find valid (non-NaN label) months
    % ------------------------------------------------------------------ %
    [~, iM, iL] = intersect(monthGrid, labels.Time);
    actualLabel  = labels.Label(iL);
    validMask    = ~isnan(actualLabel);
    actualLabel  = actualLabel(validMask);

    nValid = numel(actualLabel);
    if nValid < 30
        error('SignalBuilder:optimizeSignalParams:insufficientData', ...
            'Need at least 30 labelled months; got %d.', nValid);
    end

    % ------------------------------------------------------------------ %
    % Threshold sweep grids (same defaults as thresholdApproach)
    % ------------------------------------------------------------------ %
    mildGrid   = -0.5 : 0.1 : 0.1;
    severeGrid = -0.9 : 0.1 : -0.2;
    [mG, sG]   = ndgrid(mildGrid, severeGrid);
    mG = mG(:);  sG = sG(:);
    validPairs = sG < mG;
    mG = mG(validPairs);  sG = sG(validPairs);

    % ------------------------------------------------------------------ %
    % 1. PayrollsMom  —  PrefilterWindow × SmoothHalfLife
    % ------------------------------------------------------------------ %
    fprintf('[optimizeSignalParams] Optimising PayrollsMom...\n');
    pf_grid  = [1, 2, 3, 4, 5];
    hl_grid  = [1, 2, 3, 4, 6];
    nR = numel(pf_grid);  nC = numel(hl_grid);
    accMat   = nan(nR, nC);
    bestAcc  = -Inf;
    bestR = 1;  bestC = 1;

    for r = 1 : nR
        for c = 1 : nC
            try
                tt_sig = Model.payrollsMomentum(dm, ...
                    PrefilterWindow = pf_grid(r), ...
                    SmoothHalfLife  = hl_grid(c), ...
                    StartDate       = startDate);
                sigV = resampleMonthly(tt_sig.Time, tt_sig.Signal, monthGrid);
                sigV = sigV(iM(validMask));
                acc  = optimizeSignalParams_evalSignal(sigV, actualLabel, mG, sG);
                accMat(r, c) = acc;
                if acc > bestAcc
                    bestAcc = acc;  bestR = r;  bestC = c;
                end
            catch ME
                fprintf('  [PayrollsMom] r=%d c=%d failed: %s\n', r, c, ME.message);
            end
        end
    end

    tt_best = Model.payrollsMomentum(dm, ...
        PrefilterWindow = pf_grid(bestR), ...
        SmoothHalfLife  = hl_grid(bestC), ...
        StartDate       = startDate);
    optSig = resampleMonthly(tt_best.Time, tt_best.Signal, monthGrid);

    result.PayrollsMom.BestParams   = struct('PrefilterWindow', pf_grid(bestR), ...
                                             'SmoothHalfLife',  hl_grid(bestC));
    result.PayrollsMom.BestBalAcc   = bestAcc;
    result.PayrollsMom.AccuracyMatrix = accMat;
    result.PayrollsMom.RowLabels    = num2cell(pf_grid);
    result.PayrollsMom.ColLabels    = num2cell(hl_grid);
    result.PayrollsMom.OptSignal    = optSig;

    fprintf('  Best: PrefilterWindow=%d, SmoothHL=%.0f  BalAcc=%.3f\n', ...
        pf_grid(bestR), hl_grid(bestC), bestAcc);

    % ------------------------------------------------------------------ %
    % 2. YieldCurve  —  ZScoreWindow × SmoothHalfLife
    % ------------------------------------------------------------------ %
    fprintf('[optimizeSignalParams] Optimising YieldCurve...\n');
    zw_grid  = [24, 36, 60, 84, 120];
    hl2_grid = [1, 2, 3, 6];
    nR = numel(zw_grid);  nC = numel(hl2_grid);
    accMat   = nan(nR, nC);
    bestAcc  = -Inf;
    bestR = 1;  bestC = 1;

    for r = 1 : nR
        for c = 1 : nC
            try
                tt_sig = Model.yieldCurveSlope(dm, ...
                    ZScoreWindow   = zw_grid(r), ...
                    SmoothHalfLife = hl2_grid(c), ...
                    StartDate      = startDate);
                sigV = resampleMonthly(tt_sig.Time, tt_sig.Signal, monthGrid);
                sigV = sigV(iM(validMask));
                acc  = optimizeSignalParams_evalSignal(sigV, actualLabel, mG, sG);
                accMat(r, c) = acc;
                if acc > bestAcc
                    bestAcc = acc;  bestR = r;  bestC = c;
                end
            catch ME
                fprintf('  [YieldCurve] r=%d c=%d failed: %s\n', r, c, ME.message);
            end
        end
    end

    tt_best = Model.yieldCurveSlope(dm, ...
        ZScoreWindow   = zw_grid(bestR), ...
        SmoothHalfLife = hl2_grid(bestC), ...
        StartDate      = startDate);
    optSig = resampleMonthly(tt_best.Time, tt_best.Signal, monthGrid);

    result.YieldCurve.BestParams    = struct('ZScoreWindow',  zw_grid(bestR), ...
                                             'SmoothHalfLife', hl2_grid(bestC));
    result.YieldCurve.BestBalAcc    = bestAcc;
    result.YieldCurve.AccuracyMatrix = accMat;
    result.YieldCurve.RowLabels     = num2cell(zw_grid);
    result.YieldCurve.ColLabels     = num2cell(hl2_grid);
    result.YieldCurve.OptSignal     = optSig;

    fprintf('  Best: ZScoreWindow=%d, SmoothHL=%.0f  BalAcc=%.3f\n', ...
        zw_grid(bestR), hl2_grid(bestC), bestAcc);

    % ------------------------------------------------------------------ %
    % 3. CreditSpread  —  ZScoreWindow × SmoothHalfLife
    % ------------------------------------------------------------------ %
    fprintf('[optimizeSignalParams] Optimising CreditSpread...\n');
    zw3_grid  = [24, 36, 60, 84, 120];
    hl3_grid  = [0.5, 1, 2, 3];
    nR = numel(zw3_grid);  nC = numel(hl3_grid);
    accMat    = nan(nR, nC);
    bestAcc   = -Inf;
    bestR = 1;  bestC = 1;

    for r = 1 : nR
        for c = 1 : nC
            try
                tt_sig = Model.creditSpreadSignal(dm, ...
                    ZScoreWindow   = zw3_grid(r), ...
                    SmoothHalfLife = hl3_grid(c), ...
                    StartDate      = startDate);
                sigV = resampleMonthly(tt_sig.Time, tt_sig.Signal, monthGrid);
                sigV = sigV(iM(validMask));
                acc  = optimizeSignalParams_evalSignal(sigV, actualLabel, mG, sG);
                accMat(r, c) = acc;
                if acc > bestAcc
                    bestAcc = acc;  bestR = r;  bestC = c;
                end
            catch ME
                fprintf('  [CreditSpread] r=%d c=%d failed: %s\n', r, c, ME.message);
            end
        end
    end

    tt_best = Model.creditSpreadSignal(dm, ...
        ZScoreWindow   = zw3_grid(bestR), ...
        SmoothHalfLife = hl3_grid(bestC), ...
        StartDate      = startDate);
    optSig = resampleMonthly(tt_best.Time, tt_best.Signal, monthGrid);

    result.CreditSpread.BestParams    = struct('ZScoreWindow',  zw3_grid(bestR), ...
                                               'SmoothHalfLife', hl3_grid(bestC));
    result.CreditSpread.BestBalAcc    = bestAcc;
    result.CreditSpread.AccuracyMatrix = accMat;
    result.CreditSpread.RowLabels     = num2cell(zw3_grid);
    result.CreditSpread.ColLabels     = num2cell(hl3_grid);
    result.CreditSpread.OptSignal     = optSig;

    fprintf('  Best: ZScoreWindow=%d, SmoothHL=%.1f  BalAcc=%.3f\n', ...
        zw3_grid(bestR), hl3_grid(bestC), bestAcc);

    % ------------------------------------------------------------------ %
    % 4. EquityTrend  —  MAWindow × TrendScale  (inline, no I/O)
    % ------------------------------------------------------------------ %
    fprintf('[optimizeSignalParams] Optimising EquityTrend...\n');
    ma_grid  = [50, 100, 150, 200, 300];
    ts_grid  = [5, 10, 15, 20];
    nR = numel(ma_grid);  nC = numel(ts_grid);
    accMat   = nan(nR, nC);
    bestAcc  = -Inf;
    bestR = 1;  bestC = 1;

    close  = equityPrices.Close;
    eqTime = equityPrices.Time;

    for r = 1 : nR
        for c = 1 : nC
            try
                N      = ma_grid(r);
                scale  = ts_grid(c);
                ma     = movmean(close, [N-1, 0], 'omitnan');
                trend  = tanh(scale .* ((close ./ ma) - 1));
                trend(1 : N-1) = NaN;
                sigV = resampleMonthly(eqTime, trend, monthGrid);
                sigV = sigV(iM(validMask));
                acc  = optimizeSignalParams_evalSignal(sigV, actualLabel, mG, sG);
                accMat(r, c) = acc;
                if acc > bestAcc
                    bestAcc = acc;  bestR = r;  bestC = c;
                end
            catch ME
                fprintf('  [EquityTrend] r=%d c=%d failed: %s\n', r, c, ME.message);
            end
        end
    end

    % Build optimal signal series at best params
    N_best     = ma_grid(bestR);
    sc_best    = ts_grid(bestC);
    ma_best    = movmean(close, [N_best-1, 0], 'omitnan');
    trend_best = tanh(sc_best .* ((close ./ ma_best) - 1));
    trend_best(1 : N_best-1) = NaN;
    optSig = resampleMonthly(eqTime, trend_best, monthGrid);

    result.EquityTrend.BestParams    = struct('MAWindow',    ma_grid(bestR), ...
                                              'TrendScale',  ts_grid(bestC));
    result.EquityTrend.BestBalAcc    = bestAcc;
    result.EquityTrend.AccuracyMatrix = accMat;
    result.EquityTrend.RowLabels     = num2cell(ma_grid);
    result.EquityTrend.ColLabels     = num2cell(ts_grid);
    result.EquityTrend.OptSignal     = optSig;

    fprintf('  Best: MAWindow=%d, TrendScale=%.0f  BalAcc=%.3f\n', ...
        ma_grid(bestR), ts_grid(bestC), bestAcc);

    fprintf('[optimizeSignalParams] Done.\n');
end

% =========================================================================
% Local helpers
% =========================================================================
function bestAcc = optimizeSignalParams_evalSignal(sigV, actualLabel, mG, sG)
% Sweep threshold pairs and return the maximum balanced accuracy.
    nPairs  = numel(mG);
    accVec  = nan(nPairs, 1);
    for p = 1 : nPairs
        alloc    = optimizeSignalParams_mapAlloc(sigV, mG(p), sG(p));
        predLbl  = optimizeSignalParams_allocToLabel(alloc);
        accVec(p) = optimizeSignalParams_balAcc(actualLabel, predLbl);
    end
    bestAcc = max(accVec, [], 'omitnan');
    if isnan(bestAcc)
        bestAcc = 0;
    end
end

function alloc = optimizeSignalParams_mapAlloc(sig, mildThr, severeThr)
    alloc = repmat(0.50, numel(sig), 1);
    alloc(sig <= mildThr)   = 0.35;
    alloc(sig <= severeThr) = 0.20;
    alloc(isnan(sig))       = 0.50;
end

function predLabel = optimizeSignalParams_allocToLabel(alloc)
    predLabel = zeros(numel(alloc), 1);
    predLabel(alloc <= 0.35 + eps & alloc > 0.20 + eps) = 1;
    predLabel(alloc <= 0.20 + eps) = 2;
end

function bacc = optimizeSignalParams_balAcc(actual, pred)
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
