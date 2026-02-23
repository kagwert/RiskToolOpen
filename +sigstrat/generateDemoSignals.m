function [signalData, signalNames] = generateDemoSignals(macro, mkt)
%SIGSTRAT.GENERATEDEMOSIGNALS Generate 5 example signals from FRED + momentum.
%   [signalData, signalNames] = sigstrat.generateDemoSignals(macro, mkt)
%
% Inputs:
%   macro - table from sigstrat.downloadMacroData (with Date + derived columns)
%   mkt   - struct from sigstrat.downloadMarketData
%
% Returns:
%   signalData  - TxN double matrix (aligned to mkt.retDates), values in [-1, +1]
%   signalNames - 1xN cell array of signal names
%
% Signals (all robust z-scored, tanh-mapped to [-1, +1]):
%   1. YieldSlope_Z     - z-score of 10Y-2Y spread (positive = growth, bullish)
%   2. VIX_Z            - negated z-score of VIX (lower VIX = bullish)
%   3. CreditSpread_Z   - negated z-score of HY spread (tighter = bullish)
%   4. SPX_Mom_6m       - 126d cumulative return / expanding vol (momentum)
%   5. MacroComposite   - average z-score of GDP_YoY and RetailSales_YoY

    signalNames = {'YieldSlope_Z', 'VIX_Z', 'CreditSpread_Z', 'SPX_Mom_6m', 'MacroComposite'};
    nSig = numel(signalNames);
    T = numel(mkt.retDates);
    signalData = NaN(T, nSig);

    % Align macro to return dates via forward-fill lookup
    macroAligned = alignMacro(macro, mkt.retDates);

    %% Signal 1: YieldSlope_Z
    if isfield(macroAligned, 'YieldSlope')
        slope = macroAligned.YieldSlope;
        for t = 252:T
            z = robustZScoreScalar(slope(t), slope(1:t));
            signalData(t, 1) = tanh(z / 2);
        end
    end

    %% Signal 2: VIX_Z (negated — lower VIX = bullish)
    if isfield(macroAligned, 'VIX')
        vix = macroAligned.VIX;
        for t = 252:T
            z = robustZScoreScalar(vix(t), vix(1:t));
            signalData(t, 2) = tanh(-z / 2);  % negate
        end
    end

    %% Signal 3: CreditSpread_Z (negated — tighter = bullish)
    if isfield(macroAligned, 'HY_Spread')
        hy = macroAligned.HY_Spread;
        for t = 252:T
            z = robustZScoreScalar(hy(t), hy(1:t));
            signalData(t, 3) = tanh(-z / 2);  % negate
        end
    end

    %% Signal 4: SPX_Mom_6m (126d cumulative return / expanding vol)
    spxRet = mkt.spxRet;
    for t = 126:T
        cumRet = sum(spxRet(t-125:t));
        volEst = std(spxRet(1:t));
        volEst = max(volEst, 1e-8);
        momRaw = cumRet / (volEst * sqrt(126));
        % Use expanding z-score of momentum
        if t >= 252
            momHist = NaN(t-125, 1);
            for s = 126:t
                cr = sum(spxRet(s-125:s));
                momHist(s-125) = cr / (max(std(spxRet(1:s)), 1e-8) * sqrt(126));
            end
            momHist = momHist(isfinite(momHist));
            z = robustZScoreScalar(momRaw, momHist);
        else
            z = momRaw;
        end
        signalData(t, 4) = tanh(z / 2);
    end

    %% Signal 5: MacroComposite (average z-score of GDP_YoY + RetailSales_YoY)
    hasGDP = isfield(macroAligned, 'GDP_YoY');
    hasRS  = isfield(macroAligned, 'RetailSales_YoY');
    if hasGDP && hasRS
        gdp = macroAligned.GDP_YoY;
        rs  = macroAligned.RetailSales_YoY;
        for t = 252:T
            nValid = 0; zSum = 0;
            gdpSeries = gdp(1:t);
            gdpSeries = gdpSeries(isfinite(gdpSeries));
            if numel(gdpSeries) >= 20 && isfinite(gdp(t))
                zSum = zSum + robustZScoreScalar(gdp(t), gdpSeries);
                nValid = nValid + 1;
            end
            rsSeries = rs(1:t);
            rsSeries = rsSeries(isfinite(rsSeries));
            if numel(rsSeries) >= 20 && isfinite(rs(t))
                zSum = zSum + robustZScoreScalar(rs(t), rsSeries);
                nValid = nValid + 1;
            end
            if nValid > 0
                signalData(t, 5) = tanh(zSum / nValid / 2);
            end
        end
    elseif hasGDP
        gdp = macroAligned.GDP_YoY;
        for t = 252:T
            gdpSeries = gdp(1:t);
            gdpSeries = gdpSeries(isfinite(gdpSeries));
            if numel(gdpSeries) >= 20 && isfinite(gdp(t))
                z = robustZScoreScalar(gdp(t), gdpSeries);
                signalData(t, 5) = tanh(z / 2);
            end
        end
    end

    fprintf('Demo signals generated: %d signals x %d days.\n', nSig, T);
end

%% ---- Align macro table to target dates ----
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

%% ---- Robust z-score scalar ----
function z = robustZScoreScalar(val, series)
    med = median(series, 'omitnan');
    mad_val = median(abs(series - med), 'omitnan');
    scale = 1.4826 * max(mad_val, 1e-8);
    z = (val - med) / scale;
end
