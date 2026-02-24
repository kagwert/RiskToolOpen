function [signalData, signalNames] = generateExtendedSignals(macro, mkt)
%SIGSTRAT.GENERATEEXTENDEDSIGNALS Generate fast and slow moving indicators.
%   [signalData, signalNames] = sigstrat.generateExtendedSignals(macro, mkt)
%
% Generates 12 signals across three speed categories, all bounded [-1, +1]:
%
% FAST (short lookback, responsive):
%   1. SPX_Mom_1m    - 21d equity momentum z-score
%   2. SPX_Mom_3m    - 63d equity momentum z-score
%   3. VIX_Fast      - negated 63d expanding z-score of VIX
%   4. CreditFast    - negated 63d z-score of HY spread
%
% MEDIUM (moderate lookback):
%   5. SPX_Mom_6m    - 126d equity momentum z-score
%   6. VIX_Med       - negated 126d expanding z-score of VIX
%   7. YieldSlope_Med - 126d z-score of 10Y-2Y spread
%   8. FinConditions  - composite of VIX + credit spread + yield slope (126d)
%
% SLOW (long lookback, trend-following):
%   9.  SPX_Mom_12m  - 252d equity momentum z-score
%  10.  VIX_Slow     - negated 252d expanding z-score of VIX
%  11.  MacroTrend   - slow composite of GDP + retail sales + industrial prod (252d)
%  12.  CreditSlow   - negated 252d z-score of HY spread
%
% All signals use tanh mapping to ensure [-1, +1] bounds.
%
% Inputs:
%   macro - table from sigstrat.downloadMacroData (with Date + derived columns)
%   mkt   - struct from sigstrat.downloadMarketData
%
% Returns:
%   signalData  - Tx12 double matrix (aligned to mkt.retDates)
%   signalNames - 1x12 cell array of signal names

    signalNames = { ...
        'SPX_Mom_1m', 'SPX_Mom_3m', 'VIX_Fast', 'CreditFast', ...   % Fast
        'SPX_Mom_6m', 'VIX_Med', 'YieldSlope_Med', 'FinConditions', ... % Medium
        'SPX_Mom_12m', 'VIX_Slow', 'MacroTrend', 'CreditSlow'};     % Slow

    nSig = numel(signalNames);
    T = numel(mkt.retDates);
    signalData = NaN(T, nSig);
    spxRet = mkt.spxRet;

    % Align macro to return dates
    macroAligned = alignMacro(macro, mkt.retDates);

    %% ===== FAST SIGNALS =====

    % 1. SPX_Mom_1m — 21d momentum
    signalData(:, 1) = momentumSignal(spxRet, 21, 63);

    % 2. SPX_Mom_3m — 63d momentum
    signalData(:, 2) = momentumSignal(spxRet, 63, 126);

    % 3. VIX_Fast — negated 63d expanding z-score
    if isfield(macroAligned, 'VIX')
        signalData(:, 3) = macroZSignal(macroAligned.VIX, 63, true);
    end

    % 4. CreditFast — negated 63d z-score of HY spread
    if isfield(macroAligned, 'HY_Spread')
        signalData(:, 4) = macroZSignal(macroAligned.HY_Spread, 63, true);
    end

    %% ===== MEDIUM SIGNALS =====

    % 5. SPX_Mom_6m — 126d momentum
    signalData(:, 5) = momentumSignal(spxRet, 126, 252);

    % 6. VIX_Med — negated 126d expanding z-score
    if isfield(macroAligned, 'VIX')
        signalData(:, 6) = macroZSignal(macroAligned.VIX, 126, true);
    end

    % 7. YieldSlope_Med — 126d z-score (positive = bullish)
    if isfield(macroAligned, 'YieldSlope')
        signalData(:, 7) = macroZSignal(macroAligned.YieldSlope, 126, false);
    end

    % 8. FinConditions — composite of VIX + credit + yield slope (126d window)
    signalData(:, 8) = financialConditionsSignal(macroAligned, 126);

    %% ===== SLOW SIGNALS =====

    % 9. SPX_Mom_12m — 252d momentum
    signalData(:, 9) = momentumSignal(spxRet, 252, 504);

    % 10. VIX_Slow — negated 252d expanding z-score
    if isfield(macroAligned, 'VIX')
        signalData(:, 10) = macroZSignal(macroAligned.VIX, 252, true);
    end

    % 11. MacroTrend — slow composite of GDP + retail sales + indprod (252d)
    signalData(:, 11) = macroTrendSignal(macroAligned, 252);

    % 12. CreditSlow — negated 252d z-score of HY spread
    if isfield(macroAligned, 'HY_Spread')
        signalData(:, 12) = macroZSignal(macroAligned.HY_Spread, 252, true);
    end

    fprintf('Extended signals generated: %d signals x %d days (fast/medium/slow).\n', nSig, T);
end

%% ==================== MOMENTUM SIGNAL ====================
function sig = momentumSignal(ret, lookback, minHistory)
%MOMENTUMSIGNAL Cumulative return over lookback, z-scored with expanding window.
%   Positive momentum -> positive signal (bullish equity).
%   Uses EWMA vol (halflife=32) instead of equal-weight std for smoother estimates.
    T = numel(ret);
    sig = NaN(T, 1);

    % Precompute EWMA vol series
    volSeries = ewmaVolLocal(ret, 32);

    % Pre-compute cumulative returns for each valid time
    for t = lookback:T
        cumRet = sum(ret(t-lookback+1:t));
        volEst = max(volSeries(t), 1e-8);
        momRaw = cumRet / (volEst * sqrt(lookback));

        if t >= minHistory
            % Expanding z-score of the momentum reading
            momHist = NaN(t - lookback + 1, 1);
            for s = lookback:t
                cr = sum(ret(s-lookback+1:s));
                v = max(volSeries(s), 1e-8);
                momHist(s - lookback + 1) = cr / (v * sqrt(lookback));
            end
            momHist = momHist(isfinite(momHist));
            z = robustZScore(momRaw, momHist);
        else
            z = momRaw;
        end
        sig(t) = tanh(z / 2);
    end
end

%% ==================== MACRO Z-SCORE SIGNAL ====================
function sig = macroZSignal(series, minWindow, negate)
%MACROZSIGNAL Expanding robust z-score of a macro series.
%   negate=true inverts the signal (e.g., lower VIX = positive signal).
    T = numel(series);
    sig = NaN(T, 1);
    signFlip = 1;
    if negate, signFlip = -1; end

    for t = minWindow:T
        window = series(1:t);
        window = window(isfinite(window));
        if numel(window) < 20, continue; end
        if ~isfinite(series(t)), continue; end
        z = robustZScore(series(t), window);
        sig(t) = tanh(signFlip * z / 2);
    end
end

%% ==================== FINANCIAL CONDITIONS COMPOSITE ====================
function sig = financialConditionsSignal(macroAligned, minWindow)
%FINANCIALCONDITIONSSIGNAL Composite: negated VIX z + negated credit z + yield slope z.
    T = 0;
    hasVIX = isfield(macroAligned, 'VIX');
    hasHY  = isfield(macroAligned, 'HY_Spread');
    hasYS  = isfield(macroAligned, 'YieldSlope');

    if hasVIX, T = numel(macroAligned.VIX); end
    if hasHY,  T = max(T, numel(macroAligned.HY_Spread)); end
    if hasYS,  T = max(T, numel(macroAligned.YieldSlope)); end

    if T == 0
        sig = [];
        return;
    end

    sig = NaN(T, 1);

    for t = minWindow:T
        nValid = 0;
        zSum = 0;

        if hasVIX && isfinite(macroAligned.VIX(t))
            w = macroAligned.VIX(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum - robustZScore(macroAligned.VIX(t), w);  % negated
                nValid = nValid + 1;
            end
        end

        if hasHY && isfinite(macroAligned.HY_Spread(t))
            w = macroAligned.HY_Spread(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum - robustZScore(macroAligned.HY_Spread(t), w);  % negated
                nValid = nValid + 1;
            end
        end

        if hasYS && isfinite(macroAligned.YieldSlope(t))
            w = macroAligned.YieldSlope(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum + robustZScore(macroAligned.YieldSlope(t), w);  % positive
                nValid = nValid + 1;
            end
        end

        if nValid > 0
            sig(t) = tanh(zSum / nValid / 2);
        end
    end
end

%% ==================== MACRO TREND COMPOSITE ====================
function sig = macroTrendSignal(macroAligned, minWindow)
%MACROTRENDSIGNAL Slow composite z-score of GDP_YoY + RetailSales_YoY + IndProd_YoY.
    hasGDP = isfield(macroAligned, 'GDP_YoY');
    hasRS  = isfield(macroAligned, 'RetailSales_YoY');
    hasIP  = isfield(macroAligned, 'IndProd_YoY');

    T = 0;
    if hasGDP, T = numel(macroAligned.GDP_YoY); end
    if hasRS,  T = max(T, numel(macroAligned.RetailSales_YoY)); end
    if hasIP,  T = max(T, numel(macroAligned.IndProd_YoY)); end

    if T == 0
        sig = [];
        return;
    end

    sig = NaN(T, 1);

    for t = minWindow:T
        nValid = 0;
        zSum = 0;

        if hasGDP && isfinite(macroAligned.GDP_YoY(t))
            w = macroAligned.GDP_YoY(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum + robustZScore(macroAligned.GDP_YoY(t), w);
                nValid = nValid + 1;
            end
        end

        if hasRS && isfinite(macroAligned.RetailSales_YoY(t))
            w = macroAligned.RetailSales_YoY(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum + robustZScore(macroAligned.RetailSales_YoY(t), w);
                nValid = nValid + 1;
            end
        end

        if hasIP && isfinite(macroAligned.IndProd_YoY(t))
            w = macroAligned.IndProd_YoY(1:t);
            w = w(isfinite(w));
            if numel(w) >= 20
                zSum = zSum + robustZScore(macroAligned.IndProd_YoY(t), w);
                nValid = nValid + 1;
            end
        end

        if nValid > 0
            sig(t) = tanh(zSum / nValid / 2);
        end
    end
end

%% ==================== HELPERS ====================

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

function vol = ewmaVolLocal(ret, halflife)
%EWMAVOLLOCAL Compute EWMA volatility series.
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
