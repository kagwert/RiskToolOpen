function tests = test_momentum_upgrades
%TEST_MOMENTUM_UPGRADES Unit tests for momentum signal enhancements.
    tests = functiontests(localfunctions);
end

%% Setup: create synthetic market and macro data
function setupOnce(testCase)
    rng(42);
    T = 600;
    dates = busdays(datetime(2020,1,2), datetime(2020,1,2) + caldays(T*2));
    dates = dates(1:T);
    ret = 0.0003 + 0.01 * randn(T, 1);

    mkt.retDates = dates;
    mkt.spxRet = ret;
    mkt.spxPrice = cumprod(1 + ret);

    % Minimal macro table
    macro = table(dates, 15 + 5*randn(T,1), 3 + randn(T,1), ...
        'VariableNames', {'Date', 'VIX', 'HY_Spread'});

    testCase.TestData.mkt = mkt;
    testCase.TestData.macro = macro;
    testCase.TestData.T = T;
end

%% Test 1: Momentum default params produces valid signal
function testMomentumDefault(testCase)
    params = struct('tanhScale', 2);
    [sig, meta] = sigstrat.buildSignal('Momentum', params, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    verifyEqual(testCase, numel(sig), testCase.TestData.T);
    valid = sig(isfinite(sig));
    verifyGreaterThan(testCase, numel(valid), 0, 'Should have valid values');
    verifyGreaterThanOrEqual(testCase, min(valid), -1);
    verifyLessThanOrEqual(testCase, max(valid), 1);
    verifySubstring(testCase, meta.name, 'Mom');
end

%% Test 2: Momentum with EWMA vol differs from old std approach
function testMomentumEWMAVol(testCase)
    params32 = struct('tanhScale', 2, 'volHalflife', 32);
    params60 = struct('tanhScale', 2, 'volHalflife', 60);
    [sig32, ~] = sigstrat.buildSignal('Momentum', params32, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    [sig60, ~] = sigstrat.buildSignal('Momentum', params60, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    % Different halflife should produce different signals
    both = isfinite(sig32) & isfinite(sig60);
    verifyFalse(testCase, all(sig32(both) == sig60(both)), ...
        'Different vol halflife should produce different signals');
end

%% Test 3: SkipDays shifts the signal
function testMomentumSkipDays(testCase)
    params0 = struct('tanhScale', 2, 'skipDays', 0);
    params5 = struct('tanhScale', 2, 'skipDays', 5);
    [sig0, ~] = sigstrat.buildSignal('Momentum', params0, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    [sig5, ~] = sigstrat.buildSignal('Momentum', params5, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    both = isfinite(sig0) & isfinite(sig5);
    verifyFalse(testCase, all(sig0(both) == sig5(both)), ...
        'SkipDays should produce different signals');
end

%% Test 4: All 3 activation functions produce valid [-1,+1] output
function testActivationFunctions(testCase)
    activations = {'tanh', 'sigmoid', 'revertSigmoid'};
    for i = 1:numel(activations)
        params = struct('tanhScale', 2, 'lookback', 63, 'minHistory', 126, ...
            'activation', activations{i});
        [sig, ~] = sigstrat.buildSignal('Momentum', params, ...
            testCase.TestData.mkt, testCase.TestData.macro);
        valid = sig(isfinite(sig));
        verifyGreaterThan(testCase, numel(valid), 0, ...
            sprintf('%s should produce valid values', activations{i}));
        verifyGreaterThanOrEqual(testCase, min(valid), -1, ...
            sprintf('%s min >= -1', activations{i}));
        verifyLessThanOrEqual(testCase, max(valid), 1, ...
            sprintf('%s max <= 1', activations{i}));
    end
end

%% Test 5: EWMAC produces valid signal
function testEWMACDefault(testCase)
    params = struct('tanhScale', 2);
    [sig, meta] = sigstrat.buildSignal('EWMAC', params, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    verifyEqual(testCase, numel(sig), testCase.TestData.T);
    valid = sig(isfinite(sig));
    verifyGreaterThan(testCase, numel(valid), 0);
    verifyGreaterThanOrEqual(testCase, min(valid), -1);
    verifyLessThanOrEqual(testCase, max(valid), 1);
    verifySubstring(testCase, meta.name, 'EWMAC_16_64');
end

%% Test 6: EWMAC different spans produce different signals
function testEWMACSpans(testCase)
    params1 = struct('tanhScale', 2, 'fastSpan', 8, 'slowSpan', 32);
    params2 = struct('tanhScale', 2, 'fastSpan', 32, 'slowSpan', 128);
    [sig1, meta1] = sigstrat.buildSignal('EWMAC', params1, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    [sig2, meta2] = sigstrat.buildSignal('EWMAC', params2, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    both = isfinite(sig1) & isfinite(sig2);
    verifyFalse(testCase, all(sig1(both) == sig2(both)), ...
        'Different span pairs should give different signals');
    verifySubstring(testCase, meta1.name, '8_32');
    verifySubstring(testCase, meta2.name, '32_128');
end

%% Test 7: Ensemble equal-weight produces valid signal
function testEnsembleEW(testCase)
    params = struct('tanhScale', 2, 'lookbacks', [21 63 126 252], 'method', 'equal');
    [sig, meta] = sigstrat.buildSignal('Ensemble', params, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    verifyEqual(testCase, numel(sig), testCase.TestData.T);
    valid = sig(isfinite(sig));
    verifyGreaterThan(testCase, numel(valid), 0);
    verifyGreaterThanOrEqual(testCase, min(valid), -1);
    verifyLessThanOrEqual(testCase, max(valid), 1);
    verifySubstring(testCase, meta.name, 'EW');
end

%% Test 8: Ensemble risk-parity differs from equal-weight
function testEnsembleRP(testCase)
    params_ew = struct('tanhScale', 2, 'lookbacks', [21 63 126 252], 'method', 'equal');
    params_rp = struct('tanhScale', 2, 'lookbacks', [21 63 126 252], 'method', 'riskparity');
    [sig_ew, ~] = sigstrat.buildSignal('Ensemble', params_ew, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    [sig_rp, meta_rp] = sigstrat.buildSignal('Ensemble', params_rp, ...
        testCase.TestData.mkt, testCase.TestData.macro);

    both = isfinite(sig_ew) & isfinite(sig_rp);
    verifyFalse(testCase, all(sig_ew(both) == sig_rp(both)), ...
        'EW and RP should produce different signals');
    verifySubstring(testCase, meta_rp.name, 'RP');
end

%% Test 9: Vol floor prevents extreme values
function testVolFloor(testCase)
    params = struct('tanhScale', 2, 'volFloor', 0.02);
    [sig, ~] = sigstrat.buildSignal('Momentum', params, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    valid = sig(isfinite(sig));
    verifyGreaterThan(testCase, numel(valid), 0);
    verifyGreaterThanOrEqual(testCase, min(valid), -1);
    verifyLessThanOrEqual(testCase, max(valid), 1);
end

%% Test 10: generateExtendedSignals still produces Tx12
function testExtendedSignals(testCase)
    % Add macro columns needed by all 12 signals
    T = testCase.TestData.T;
    macro = testCase.TestData.macro;
    macro.YieldSlope = 1.5 + 0.5*randn(T,1);
    macro.GDP_YoY = 2 + 0.5*randn(T,1);
    macro.RetailSales_YoY = 3 + randn(T,1);
    macro.IndProd_YoY = 1 + 0.8*randn(T,1);

    [signalData, signalNames] = sigstrat.generateExtendedSignals(macro, testCase.TestData.mkt);

    verifyEqual(testCase, size(signalData, 1), T);
    verifyEqual(testCase, size(signalData, 2), 12);
    verifyEqual(testCase, numel(signalNames), 12);

    % All valid values should be in [-1, 1]
    valid = signalData(isfinite(signalData));
    verifyGreaterThanOrEqual(testCase, min(valid), -1);
    verifyLessThanOrEqual(testCase, max(valid), 1);
end

%% Test 11: Backward compat — MacroZ unchanged
function testMacroZBackwardCompat(testCase)
    params = struct('tanhScale', 2, 'variable', 'VIX', 'negate', true);
    [sig, meta] = sigstrat.buildSignal('MacroZ', params, ...
        testCase.TestData.mkt, testCase.TestData.macro);
    valid = sig(isfinite(sig));
    verifyGreaterThan(testCase, numel(valid), 0);
    verifySubstring(testCase, meta.name, 'VIX');
end

%% Test 12: EWMAC with all activation types
function testEWMACActivations(testCase)
    activations = {'tanh', 'sigmoid', 'revertSigmoid'};
    for i = 1:numel(activations)
        params = struct('tanhScale', 2, 'activation', activations{i});
        [sig, ~] = sigstrat.buildSignal('EWMAC', params, ...
            testCase.TestData.mkt, testCase.TestData.macro);
        valid = sig(isfinite(sig));
        verifyGreaterThan(testCase, numel(valid), 0);
        verifyGreaterThanOrEqual(testCase, min(valid), -1);
        verifyLessThanOrEqual(testCase, max(valid), 1);
    end
end
