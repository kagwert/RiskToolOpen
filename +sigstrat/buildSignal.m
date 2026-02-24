function [signal, metadata] = buildSignal(signalType, params, mkt, macro)
%SIGSTRAT.BUILDSIGNAL Build a single custom signal.
%   [signal, metadata] = sigstrat.buildSignal(signalType, params, mkt, macro)
%
% Signal types:
%   'Momentum'      - Vol-adjusted price momentum, expanding z-score -> activation
%   'EWMAC'         - EMA crossover trend signal (Levine-Pedersen 2016)
%   'Ensemble'      - Multi-lookback momentum ensemble
%   'MacroZ'        - Expanding robust z-score of a macro variable
%   'MeanReversion' - Distance from rolling MA, z-scored, sign-flipped
%   'Composite'     - Weighted average of multiple macro z-scores
%
% Inputs:
%   signalType - char: 'Momentum', 'EWMAC', 'Ensemble', 'MacroZ',
%                      'MeanReversion', or 'Composite'
%   params     - struct with type-specific parameters (see below)
%   mkt        - struct from sigstrat.downloadMarketData
%   macro      - table from sigstrat.downloadMacroData
%
% Common params:
%   tanhScale  - scaling divisor for activation (default 2)
%
% Momentum params:
%   lookback     - days (21-504, default 126)
%   minHistory   - min observations for expanding z (default 252)
%   volHalflife  - EWMA vol halflife in days (default 32, range 10-120)
%   skipDays     - skip recent days to avoid reversal (default 0, range 0-21)
%   volFloor     - min vol estimate; 0 = auto 5th pctile (default 0)
%   activation   - 'tanh', 'sigmoid', or 'revertSigmoid' (default 'tanh')
%
% EWMAC params:
%   fastSpan     - fast EMA span (default 16)
%   slowSpan     - slow EMA span (default 64)
%   volHalflife  - EWMA vol halflife (default 32)
%   volFloor     - min vol estimate (default 0)
%   activation   - activation function (default 'tanh')
%
% Ensemble params:
%   lookbacks    - vector of lookback windows (default [21 63 126 252])
%   method       - 'equal' or 'riskparity' (default 'equal')
%   volHalflife  - EWMA vol halflife (default 32)
%   skipDays     - skip recent days (default 0)
%   volFloor     - min vol estimate (default 0)
%   activation   - activation function (default 'tanh')
%
% MacroZ params:
%   variable   - char name of macro column (e.g. 'VIX', 'HY_Spread')
%   minWindow  - min observations for z-score (default 126)
%   negate     - logical, flip sign (default false)
%
% MeanReversion params:
%   lookback   - MA window in days (21-504, default 63)
%   minHistory - min observations for expanding z (default 126)
%
% Composite params:
%   variables  - cell array of macro column names
%   weights    - numeric vector of weights (same length as variables)
%   negate     - logical vector, per-variable sign flip
%   minWindow  - min observations (default 126)
%
% Returns:
%   signal   - Tx1 double in [-1, +1], aligned to mkt.retDates
%   metadata - struct with .name, .description, .type, .params

    T = numel(mkt.retDates);

    % Default tanh scale
    tanhScale = getParam(params, 'tanhScale', 2);

    % Align macro data
    macroAligned = alignMacro(macro, mkt.retDates);

    switch signalType
        case 'Momentum'
            [signal, metadata] = buildMomentum(mkt.spxRet, T, params, tanhScale);

        case 'EWMAC'
            [signal, metadata] = buildEWMAC(mkt.spxRet, T, params, tanhScale);

        case 'Ensemble'
            [signal, metadata] = buildEnsemble(mkt.spxRet, T, params, tanhScale);

        case 'MacroZ'
            [signal, metadata] = buildMacroZ(macroAligned, T, params, tanhScale);

        case 'MeanReversion'
            [signal, metadata] = buildMeanReversion(mkt.spxRet, T, params, tanhScale);

        case 'Composite'
            [signal, metadata] = buildComposite(macroAligned, T, params, tanhScale);

        otherwise
            error('sigstrat:buildSignal', 'Unknown signal type: %s', signalType);
    end

    metadata.type = signalType;
    metadata.params = params;
end

%% ==================== MOMENTUM ====================
function [sig, meta] = buildMomentum(spxRet, T, params, tanhScale)
    lookback     = getParam(params, 'lookback', 126);
    minHistory   = getParam(params, 'minHistory', 252);
    volHalflife  = getParam(params, 'volHalflife', 32);
    skipDays     = getParam(params, 'skipDays', 0);
    volFloorVal  = getParam(params, 'volFloor', 0);
    activationType = getParam(params, 'activation', 'tanh');

    % Precompute EWMA vol series
    volSeries = ewmaVol(spxRet, volHalflife);

    % Apply vol floor
    volSeries = applyVolFloor(volSeries, volFloorVal);

    totalLook = lookback + skipDays;
    sig = NaN(T, 1);
    for t = totalLook:T
        winStart = t - totalLook + 1;
        winEnd   = t - skipDays;
        cumRet   = sum(spxRet(winStart:winEnd));
        volEst   = max(volSeries(winEnd), 1e-8);
        momRaw   = cumRet / (volEst * sqrt(lookback));

        if t >= minHistory
            momHist = NaN(t - totalLook + 1, 1);
            for s = totalLook:t
                ws = s - totalLook + 1;
                we = s - skipDays;
                cr = sum(spxRet(ws:we));
                v  = max(volSeries(we), 1e-8);
                momHist(s - totalLook + 1) = cr / (v * sqrt(lookback));
            end
            momHist = momHist(isfinite(momHist));
            z = robustZScore(momRaw, momHist);
        else
            z = momRaw;
        end
        sig(t) = applyActivation(z, tanhScale, activationType);
    end

    meta.name = sprintf('SPX_Mom_%dd', lookback);
    meta.description = sprintf('Momentum: %dd lookback, skip=%d, volHL=%d, act=%s', ...
        lookback, skipDays, volHalflife, activationType);
end

%% ==================== EWMAC ====================
function [sig, meta] = buildEWMAC(spxRet, T, params, tanhScale)
    fastSpan    = getParam(params, 'fastSpan', 16);
    slowSpan    = getParam(params, 'slowSpan', 64);
    volHalflife = getParam(params, 'volHalflife', 32);
    volFloorVal = getParam(params, 'volFloor', 0);
    activationType = getParam(params, 'activation', 'tanh');
    minHistory  = max(slowSpan * 2, 126);

    % Compute EMAs of cumulative price
    price = cumprod(1 + spxRet);
    alphaFast = 2 / (fastSpan + 1);
    alphaSlow = 2 / (slowSpan + 1);

    emaFast = NaN(T, 1);
    emaSlow = NaN(T, 1);
    emaFast(1) = price(1);
    emaSlow(1) = price(1);
    for t = 2:T
        emaFast(t) = alphaFast * price(t) + (1 - alphaFast) * emaFast(t-1);
        emaSlow(t) = alphaSlow * price(t) + (1 - alphaSlow) * emaSlow(t-1);
    end

    % EWMA vol of returns
    volSeries = ewmaVol(spxRet, volHalflife);
    volSeries = applyVolFloor(volSeries, volFloorVal);

    % Raw EWMAC: crossover normalized by vol
    rawSignal = (emaFast - emaSlow) ./ max(volSeries .* price, 1e-8);

    % Expanding z-score -> activation
    sig = NaN(T, 1);
    for t = slowSpan:T
        if ~isfinite(rawSignal(t)), continue; end
        if t >= minHistory
            hist = rawSignal(slowSpan:t);
            hist = hist(isfinite(hist));
            z = robustZScore(rawSignal(t), hist);
        else
            z = rawSignal(t);
        end
        sig(t) = applyActivation(z, tanhScale, activationType);
    end

    meta.name = sprintf('EWMAC_%d_%d', fastSpan, slowSpan);
    meta.description = sprintf('EWMAC: fast=%d, slow=%d, volHL=%d, act=%s', ...
        fastSpan, slowSpan, volHalflife, activationType);
end

%% ==================== ENSEMBLE ====================
function [sig, meta] = buildEnsemble(spxRet, T, params, tanhScale)
    lookbacks   = getParam(params, 'lookbacks', [21 63 126 252]);
    method      = getParam(params, 'method', 'equal');
    volHalflife = getParam(params, 'volHalflife', 32);
    skipDays    = getParam(params, 'skipDays', 0);
    volFloorVal = getParam(params, 'volFloor', 0);
    activationType = getParam(params, 'activation', 'tanh');

    nLB = numel(lookbacks);

    % Precompute EWMA vol
    volSeries = ewmaVol(spxRet, volHalflife);
    volSeries = applyVolFloor(volSeries, volFloorVal);

    % Build individual momentum signals (raw, before activation)
    rawSigs = NaN(T, nLB);
    for k = 1:nLB
        lb = lookbacks(k);
        totalLook = lb + skipDays;
        minHist = max(lb * 2, 126);
        for t = totalLook:T
            ws = t - totalLook + 1;
            we = t - skipDays;
            cumRet = sum(spxRet(ws:we));
            volEst = max(volSeries(we), 1e-8);
            momRaw = cumRet / (volEst * sqrt(lb));

            if t >= minHist
                momHist = NaN(t - totalLook + 1, 1);
                for s = totalLook:t
                    sws = s - totalLook + 1;
                    swe = s - skipDays;
                    cr = sum(spxRet(sws:swe));
                    v  = max(volSeries(swe), 1e-8);
                    momHist(s - totalLook + 1) = cr / (v * sqrt(lb));
                end
                momHist = momHist(isfinite(momHist));
                rawSigs(t, k) = robustZScore(momRaw, momHist);
            else
                rawSigs(t, k) = momRaw;
            end
        end
    end

    % Combine signals
    sig = NaN(T, 1);
    for t = 1:T
        valid = isfinite(rawSigs(t, :));
        if ~any(valid), continue; end
        vals = rawSigs(t, valid);

        if strcmp(method, 'riskparity') && sum(valid) > 1
            % Risk-parity: 1/sigma weighting using trailing std of each signal
            trailLen = min(t, 252);
            trailStart = max(1, t - trailLen + 1);
            wts = ones(1, sum(valid));
            validIdx = find(valid);
            for k = 1:numel(validIdx)
                trailData = rawSigs(trailStart:t, validIdx(k));
                trailData = trailData(isfinite(trailData));
                if numel(trailData) >= 20
                    wts(k) = 1 / max(std(trailData), 1e-4);
                end
            end
            wts = wts / sum(wts);
            combined = sum(vals .* wts);
        else
            combined = mean(vals);
        end
        sig(t) = applyActivation(combined, tanhScale, activationType);
    end

    if strcmp(method, 'riskparity')
        methodTag = 'RP';
    else
        methodTag = 'EW';
    end
    meta.name = sprintf('Ensemble_%dlb_%s', nLB, methodTag);
    meta.description = sprintf('Ensemble: %s, method=%s, skip=%d, volHL=%d, act=%s', ...
        mat2str(lookbacks), method, skipDays, volHalflife, activationType);
end

%% ==================== MACRO Z-SCORE ====================
function [sig, meta] = buildMacroZ(macroAligned, T, params, tanhScale)
    variable  = getParam(params, 'variable', 'VIX');
    minWindow = getParam(params, 'minWindow', 126);
    negate    = getParam(params, 'negate', false);

    sig = NaN(T, 1);
    signFlip = 1;
    if negate, signFlip = -1; end

    if ~isfield(macroAligned, variable)
        meta.name = sprintf('%s_Z', variable);
        meta.description = sprintf('MacroZ: %s not available', variable);
        return;
    end

    series = macroAligned.(variable);
    for t = minWindow:T
        window = series(1:t);
        window = window(isfinite(window));
        if numel(window) < 20, continue; end
        if ~isfinite(series(t)), continue; end
        z = robustZScore(series(t), window);
        sig(t) = tanh(signFlip * z / tanhScale);
    end

    negStr = '';
    if negate, negStr = '_Neg'; end
    meta.name = sprintf('%s_Z%s', variable, negStr);
    meta.description = sprintf('MacroZ: %s, %dd min window, negate=%d', variable, minWindow, negate);
end

%% ==================== MEAN REVERSION ====================
function [sig, meta] = buildMeanReversion(spxRet, T, params, tanhScale)
    lookback   = getParam(params, 'lookback', 63);
    minHistory = getParam(params, 'minHistory', 126);

    % Reconstruct cumulative price index from returns
    price = cumprod(1 + spxRet);

    sig = NaN(T, 1);
    for t = lookback:T
        % Rolling MA of price
        ma = mean(price(t-lookback+1:t));
        % Distance from MA (positive = above MA)
        dist = (price(t) - ma) / max(ma, 1e-8);

        if t >= minHistory
            % Expanding z-score of distance readings
            distHist = NaN(t - lookback + 1, 1);
            for s = lookback:t
                maS = mean(price(s-lookback+1:s));
                distHist(s - lookback + 1) = (price(s) - maS) / max(maS, 1e-8);
            end
            distHist = distHist(isfinite(distHist));
            z = robustZScore(dist, distHist);
        else
            z = dist * 100;  % rough scaling before enough history
        end
        % Negate: price above MA -> expect reversion down -> bearish
        sig(t) = tanh(-z / tanhScale);
    end

    meta.name = sprintf('MeanRev_%dd', lookback);
    meta.description = sprintf('MeanReversion: %dd MA, %dd min history', lookback, minHistory);
end

%% ==================== COMPOSITE ====================
function [sig, meta] = buildComposite(macroAligned, T, params, tanhScale)
    variables = getParam(params, 'variables', {'VIX', 'HY_Spread'});
    weights   = getParam(params, 'weights', ones(1, numel(variables)));
    negFlags  = getParam(params, 'negate', false(1, numel(variables)));
    minWindow = getParam(params, 'minWindow', 126);

    % Normalize weights to sum to 1
    weights = weights(:)' / max(sum(abs(weights)), 1e-8);

    sig = NaN(T, 1);
    nVars = numel(variables);

    for t = minWindow:T
        zSum = 0;
        wSum = 0;
        for k = 1:nVars
            vName = variables{k};
            if ~isfield(macroAligned, vName), continue; end
            series = macroAligned.(vName);
            if ~isfinite(series(t)), continue; end
            window = series(1:t);
            window = window(isfinite(window));
            if numel(window) < 20, continue; end

            z = robustZScore(series(t), window);
            if negFlags(k), z = -z; end
            zSum = zSum + weights(k) * z;
            wSum = wSum + abs(weights(k));
        end
        if wSum > 0
            sig(t) = tanh(zSum / wSum / tanhScale);
        end
    end

    meta.name = sprintf('Composite_%dvars', nVars);
    meta.description = sprintf('Composite: %s', strjoin(variables, '+'));
end

%% ==================== HELPERS ====================
function val = getParam(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end

function aligned = alignMacro(macro, targetDates)
    aligned = struct();
    if ~istable(macro), return; end
    vn = macro.Properties.VariableNames;
    macroDates = macro.Date;
    for i = 1:numel(vn)
        if strcmp(vn{i}, 'Date'), continue; end
        aligned.(vn{i}) = forwardFill(macroDates, macro.(vn{i}), targetDates);
    end
end

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

function z = robustZScore(val, series)
    med = median(series, 'omitnan');
    mad_val = median(abs(series - med), 'omitnan');
    scale = 1.4826 * max(mad_val, 1e-8);
    z = (val - med) / scale;
end

function vol = ewmaVol(ret, halflife)
%EWMAVOL Compute EWMA volatility series.
%   vol = ewmaVol(ret, halflife) returns a Tx1 vector of EWMA standard
%   deviation estimates using the specified halflife in days.
    T = numel(ret);
    lambda = exp(-log(2) / halflife);
    vol = NaN(T, 1);
    ewmaVar = ret(1)^2;
    vol(1) = sqrt(ewmaVar);
    for t = 2:T
        ewmaVar = lambda * ewmaVar + (1 - lambda) * ret(t)^2;
        vol(t) = sqrt(ewmaVar);
    end
end

function vol = applyVolFloor(vol, volFloorVal)
%APPLYVOLFLOOR Apply a floor to the vol series.
%   If volFloorVal > 0, use it directly. If 0, compute auto floor from
%   5th percentile of trailing 504-day EWMA vol.
    T = numel(vol);
    if volFloorVal > 0
        vol = max(vol, volFloorVal);
    else
        % Auto floor: 5th percentile of trailing 504-day window
        for t = 1:T
            trailStart = max(1, t - 503);
            trailVol = vol(trailStart:t);
            trailVol = trailVol(isfinite(trailVol));
            if numel(trailVol) >= 20
                floorVal = prctile(trailVol, 5);
                vol(t) = max(vol(t), floorVal);
            end
        end
    end
end

function y = applyActivation(z, scale, activationType)
%APPLYACTIVATION Apply activation function to z-scored signal.
%   activationType: 'tanh', 'sigmoid', or 'revertSigmoid'
    switch activationType
        case 'tanh'
            y = tanh(z / scale);
        case 'sigmoid'
            y = 2 * normcdf(z / scale) - 1;
        case 'revertSigmoid'
            % Dao et al. 2021: dampens overextended trends
            c = (1 + 2 / scale^2)^(3/4);
            y = c * (z / scale) .* exp(-z.^2 / (2 * scale^2));
            % Clip to [-1, 1] for safety
            y = max(-1, min(1, y));
        otherwise
            y = tanh(z / scale);
    end
end
