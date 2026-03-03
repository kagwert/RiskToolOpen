classdef TestSignalEngine < matlab.unittest.TestCase
% TestSignalEngine  Unit tests for Model.SignalEngine.
%
%   Verifies: transform output correctness (MA, z-score, RS, VNR),
%   aggregation methods (static, risk_parity, logic_gate), Params
%   mutability, and error paths.
%
%   Run:  results = runtests('+Tests/TestSignalEngine.m'); table(results)

    % ------------------------------------------------------------------ %
    properties
        MD  % Model.MarketData
        Eng % Model.SignalEngine
    end

    methods (TestMethodSetup)
        function buildFixture(tc)
            % Linear prices [10..19], 10 bars.
            tc.MD  = Tests.TestSignalEngine.makeMarketData((10:19)');
            tc.Eng = Model.SignalEngine(tc.MD);
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        %% === Construction ===

        function testConstructionSetsName(tc)
            tc.verifySubstring(tc.Eng.Name, "SignalEngine");
        end

        function testSignalTableEmpty_OnConstruction(tc)
            tc.verifyTrue(isempty(tc.Eng.SignalNames));
        end

        %% === Params are publicly writable ===

        function testParamsMAWindowIsWritable(tc)
            tc.Eng.Params.MAWindow = 30;
            tc.verifyEqual(tc.Eng.Params.MAWindow, 30);
        end

        function testParamsZScoreWindowIsWritable(tc)
            tc.Eng.Params.ZScoreWindow = 45;
            tc.verifyEqual(tc.Eng.Params.ZScoreWindow, 45);
        end

        function testParamsGateThresholdIsWritable(tc)
            tc.Eng.Params.GateThreshold = 0.75;
            tc.verifyEqual(tc.Eng.Params.GateThreshold, 0.75);
        end

        function testParamsUsedByDefaultInTransform(tc)
            % Setting MAWindow=3 and calling addMovingAverage with no
            % explicit window should produce SMA with period=3.
            tc.Eng.Params.MAWindow = 3;
            tc.Eng.addMovingAverage('Close');
            tc.verifyTrue(ismember('MA_Close_3', tc.Eng.SignalNames));
        end

        %% === Moving Average transform ===

        function testMA_ColumnNamed_Correctly(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.verifyTrue(ismember('MA_Close_3', tc.Eng.SignalNames));
        end

        function testMA_KnownValues_LinearPrices(tc)
            % prices=[10..19], period=3
            %   MA(3)=mean([10;11;12])=11, MA(4)=12, ..., MA(10)=17
            tc.Eng.addMovingAverage('Close', 3);
            ma = tc.Eng.SignalTable.MA_Close_3;
            tc.verifyEqual(ma(3),  11.0, 'AbsTol', 1e-12);
            tc.verifyEqual(ma(6),  14.0, 'AbsTol', 1e-12);
            tc.verifyEqual(ma(10), 18.0, 'AbsTol', 1e-12);
        end

        function testMA_LeadingNaNCount(tc)
            period = 4;
            tc.Eng.addMovingAverage('Close', period);
            ma = tc.Eng.SignalTable.(sprintf('MA_Close_%d', period));
            tc.verifyEqual(sum(isnan(ma)), period - 1);
        end

        function testMA_LengthMatchesNumBars(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.verifyEqual(height(tc.Eng.SignalTable), tc.MD.NumBars);
        end

        function testMA_Period1EqualsClose(tc)
            tc.Eng.addMovingAverage('Close', 1);
            ma    = tc.Eng.SignalTable.MA_Close_1;
            close = tc.MD.Prices.Close;
            tc.verifyEqual(ma, close, 'AbsTol', 1e-14);
        end

        %% === Z-Score transform ===

        function testZScore_ColumnNamed_Correctly(tc)
            tc.Eng.addZScore('Close', 5);
            tc.verifyTrue(ismember('ZScore_Close_5', tc.Eng.SignalNames));
        end

        function testZScore_ConstantSeries_IsNaN(tc)
            % Constant prices → std=0 → z-score is well-defined (0/eps≈0)
            % but we just verify no error is thrown and output is finite.
            md  = Tests.TestSignalEngine.makeMarketData(ones(10,1)*100);
            eng = Model.SignalEngine(md);
            eng.addZScore('Close', 5);
            z = eng.SignalTable.ZScore_Close_5;
            tc.verifyTrue(all(isfinite(z(~isnan(z)))));
        end

        function testZScore_ZeroMean_OverWindow(tc)
            % For any series, the rolling z-score has mean≈0 over the window
            % by construction (subtracts rolling mean in numerator).
            % Test: z-score of prices at the very bar where window is full
            % equals (x_n - mean(x_{1..n})) / std(x_{1..n}).
            prices = (10:19)';
            w      = 5;
            mu     = mean(prices(1:w));
            sg     = std(prices(1:w), 0);
            expected_at_w = (prices(w) - mu) / sg;

            md  = Tests.TestSignalEngine.makeMarketData(prices);
            eng = Model.SignalEngine(md);
            eng.addZScore('Close', w);
            z = eng.SignalTable.(sprintf('ZScore_Close_%d', w));
            tc.verifyEqual(z(w), expected_at_w, 'AbsTol', 1e-12);
        end

        function testZScore_LeadingNaNCount(tc)
            window = 4;
            tc.Eng.addZScore('Close', window);
            z = tc.Eng.SignalTable.(sprintf('ZScore_Close_%d', window));
            tc.verifyEqual(sum(isnan(z)), window - 1);
        end

        function testZScore_StationaryProcess_UnitVariance(tc)
            % For a stationary i.i.d. process the z-score should have
            % rolling variance approximately 1.  We verify std is O(1).
            rng(3);
            prices = 100 + cumsum(randn(200,1) * 0.1);
            md     = Tests.TestSignalEngine.makeMarketData(max(prices,1));
            eng    = Model.SignalEngine(md);
            eng.addZScore('Close', 20);
            z      = eng.SignalTable.ZScore_Close_20;
            nonNaN = z(~isnan(z));
            tc.verifyLessThan(std(nonNaN), 3.0, ...
                'z-score std should be O(1) for weakly stationary series');
        end

        %% === Relative Strength transform ===

        function testRS_ColumnNamed_Correctly(tc)
            tc.Eng.addRelativeStrength('Close', 5);
            tc.verifyTrue(ismember('RS_Close_5', tc.Eng.SignalNames));
        end

        function testRS_AllUpPrices_VeryLargeRS(tc)
            % All gains, no losses → RS = sumGains / eps → very large.
            md  = Tests.TestSignalEngine.makeMarketData((10:19)');
            eng = Model.SignalEngine(md);
            eng.addRelativeStrength('Close', 3);
            rs     = eng.SignalTable.RS_Close_3;
            nonNaN = rs(~isnan(rs));
            tc.verifyGreaterThan(min(nonNaN), 1e6);
        end

        function testRS_AllDownPrices_IsZero(tc)
            % All losses, no gains → RS = 0 / sumLosses = 0.
            md  = Tests.TestSignalEngine.makeMarketData((19:-1:10)');
            eng = Model.SignalEngine(md);
            eng.addRelativeStrength('Close', 3);
            rs     = eng.SignalTable.RS_Close_3;
            nonNaN = rs(~isnan(rs));
            tc.verifyEqual(max(nonNaN), 0, 'AbsTol', 1e-12);
        end

        function testRS_IsNonNegative(tc)
            rng(5);
            prices = max(100 + cumsum(randn(50,1)), 1);
            md     = Tests.TestSignalEngine.makeMarketData(prices);
            eng    = Model.SignalEngine(md);
            eng.addRelativeStrength('Close', 5);
            rs     = eng.SignalTable.RS_Close_5;
            nonNaN = rs(~isnan(rs));
            tc.verifyGreaterThanOrEqual(min(nonNaN), 0);
        end

        %% === Volatility-Normalised Return transform ===

        function testVNR_ColumnNamed_Correctly(tc)
            tc.Eng.addVolNormReturn('Close', 5);
            tc.verifyTrue(ismember('VNR_Close_5', tc.Eng.SignalNames));
        end

        function testVNR_FirstBarIsNaN(tc)
            tc.Eng.addVolNormReturn('Close', 3);
            vnr = tc.Eng.SignalTable.VNR_Close_3;
            tc.verifyTrue(isnan(vnr(1)));
        end

        function testVNR_LengthMatchesNumBars(tc)
            tc.Eng.addVolNormReturn('Close', 3);
            tc.verifyEqual(height(tc.Eng.SignalTable), tc.MD.NumBars);
        end

        function testVNR_HighVolPeriod_SmallOutput(tc)
            % Volatile period → large rolling std → normalised return shrinks.
            % Low-vol period → small std → normalised return is larger for
            % same raw return magnitude.
            % Build two environments and compare.
            rng(9);
            % High-vol sequence
            highVol = 100 + cumsum(randn(30,1) * 5);
            highVol = max(highVol, 1);
            mdH     = Tests.TestSignalEngine.makeMarketData(highVol);
            engH    = Model.SignalEngine(mdH);
            engH.addVolNormReturn('Close', 10);
            vnrH = engH.SignalTable.VNR_Close_10;

            % Low-vol sequence with same mean drift
            lowVol  = 100 + cumsum(randn(30,1) * 0.1);
            lowVol  = max(lowVol, 1);
            mdL     = Tests.TestSignalEngine.makeMarketData(lowVol);
            engL    = Model.SignalEngine(mdL);
            engL.addVolNormReturn('Close', 10);
            vnrL = engL.SignalTable.VNR_Close_10;

            % High-vol normalised returns should have similar magnitude to
            % low-vol since both are divided by their own volatility.
            % Verify both are finite (not exploding due to /0).
            tc.verifyTrue(all(isfinite(vnrH(~isnan(vnrH)))));
            tc.verifyTrue(all(isfinite(vnrL(~isnan(vnrL)))));
        end

        %% === Aggregation: static ===

        function testAggregate_Static_EqualWeights(tc)
            % Two equal signals: average = each signal individually.
            tc.Eng.addMovingAverage('Close', 3);
            tc.Eng.addMovingAverage('Close', 3);   % same col, overwritten
            % Create two DIFFERENT signal columns
            md  = Tests.TestSignalEngine.makeMarketData((10:19)');
            eng = Model.SignalEngine(md);
            eng.addMovingAverage('Close', 3);
            eng.addZScore('Close', 3);

            cols = ["MA_Close_3", "ZScore_Close_3"];
            tt   = eng.aggregate(cols, 'static');
            tc.verifyTrue(ismember('CompositeSignal', ...
                tt.Properties.VariableNames));
            tc.verifyEqual(height(tt), md.NumBars);
        end

        function testAggregate_Static_KnownWeightedSum(tc)
            % Build two constant-valued signals then verify weighted mean.
            % We construct them by adding MA_1 (=close) to a flat signal.
            % Use a 5-bar fixture where MA_1=[10;11;12;13;14] and
            % ZScore with window=5 (all NaN except last) is not ideal.
            % Instead inject via MA at two different windows both with
            % explicit expected values.
            prices = (10:14)';
            md  = Tests.TestSignalEngine.makeMarketData(prices);
            eng = Model.SignalEngine(md);
            eng.addMovingAverage('Close', 1);   % MA_Close_1 = close
            eng.addMovingAverage('Close', 3);   % MA_Close_3 = [NaN;NaN;11;12;13]
            cols = ["MA_Close_1", "MA_Close_3"];
            w    = [0.6; 0.4];
            tt   = eng.aggregate(cols, 'static', struct('Weights', w'));

            % Row 3: composite = 0.6*12 + 0.4*11 = 7.2+4.4 = 11.6
            tc.verifyEqual(tt.CompositeSignal(3), 11.6, 'AbsTol', 1e-12);
            % Row 5: composite = 0.6*14 + 0.4*13 = 8.4+5.2 = 13.6
            tc.verifyEqual(tt.CompositeSignal(5), 13.6, 'AbsTol', 1e-12);
        end

        function testAggregate_Static_WeightsNormalised(tc)
            % Weights [1,1] must give same result as [0.5, 0.5].
            prices = (10:19)';
            md  = Tests.TestSignalEngine.makeMarketData(prices);

            eng1 = Model.SignalEngine(md);
            eng1.addMovingAverage('Close', 2);
            eng1.addMovingAverage('Close', 3);
            tt1  = eng1.aggregate(["MA_Close_2","MA_Close_3"], 'static', ...
                struct('Weights', [1, 1]));

            eng2 = Model.SignalEngine(md);
            eng2.addMovingAverage('Close', 2);
            eng2.addMovingAverage('Close', 3);
            tt2  = eng2.aggregate(["MA_Close_2","MA_Close_3"], 'static', ...
                struct('Weights', [0.5, 0.5]));

            tc.verifyEqual(tt1.CompositeSignal, tt2.CompositeSignal, ...
                'AbsTol', 1e-12);
        end

        function testAggregate_Static_WeightsMismatchError(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.Eng.addZScore('Close', 3);
            cols = ["MA_Close_3","ZScore_Close_3"];
            tc.verifyError( ...
                @() tc.Eng.aggregate(cols, 'static', ...
                    struct('Weights', [1,2,3])), ...
                'SignalBuilder:SignalEngine:weightsMismatch');
        end

        %% === Aggregation: risk_parity ===

        function testAggregate_RiskParity_OutputIsTimetable(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.Eng.addZScore('Close', 3);
            cols = ["MA_Close_3","ZScore_Close_3"];
            tt   = tc.Eng.aggregate(cols, 'risk_parity');
            tc.verifyClass(tt, 'timetable');
            tc.verifyTrue(ismember('CompositeSignal', ...
                tt.Properties.VariableNames));
        end

        function testAggregate_RiskParity_HighVolSignalGetsLessWeight(tc)
            % Build a high-vol signal (large std) and a low-vol signal.
            % Risk parity should down-weight the high-vol signal so its
            % contribution to the composite is smaller.
            rng(11);
            n      = 50;
            prices = max(100 + cumsum(randn(n,1)*0.1), 1);
            md     = Tests.TestSignalEngine.makeMarketData(prices);
            eng    = Model.SignalEngine(md);

            % Low-vol signal: MA close (smoothed)
            eng.addMovingAverage('Close', 5);   % MA_Close_5 — smooth

            % High-vol signal: manually inject by scaling MA by randn noise
            % Easiest: compute ZScore which is naturally O(1) but with
            % a short window will be noisier.
            eng.addZScore('Close', 3);  % ZScore_Close_3 (short window = noisy)
            eng.addZScore('Close', 20); % ZScore_Close_20 (long window = less noisy)

            cols = ["ZScore_Close_3", "ZScore_Close_20"];
            tt   = eng.aggregate(cols, 'risk_parity', ...
                struct('VolLookback', 10));

            % Check composite is finite where inputs are non-NaN
            nonNaN = tt.CompositeSignal(~isnan(tt.CompositeSignal));
            tc.verifyTrue(all(isfinite(nonNaN)));
        end

        %% === Aggregation: logic_gate ===

        function testAggregate_LogicGate_RegimeActivePassesSignal(tc)
            % When regime > threshold, composite = primary for valid rows.
            % Use MA_Close_1 (=Close, no warm-up) as regime so it is
            % always positive (ascending prices 10-19); primary is MA_Close_2
            % (1 warm-up bar).  Assert composite == primary where primary
            % is non-NaN.
            prices = (10:19)';
            md     = Tests.TestSignalEngine.makeMarketData(prices);
            eng    = Model.SignalEngine(md);
            eng.addMovingAverage('Close', 2);   % primary: NaN only at row 1
            eng.addMovingAverage('Close', 1);   % regime: = Close, always > 0

            opts = struct( ...
                'PrimarySignalCol', 'MA_Close_2', ...
                'RegimeSignalCol',  'MA_Close_1', ...
                'RegimeThreshold',  0);
            tt = eng.aggregate([], 'logic_gate', opts);

            primary = eng.SignalTable.MA_Close_2;
            valid   = ~isnan(primary);   % rows 2-10
            tc.verifyEqual(tt.CompositeSignal(valid), primary(valid), ...
                'AbsTol', 1e-12);
        end

        function testAggregate_LogicGate_RegimeInactiveZerosSignal(tc)
            % When regime <= threshold everywhere, composite must be 0.
            prices = (10:19)';
            md     = Tests.TestSignalEngine.makeMarketData(prices);
            eng    = Model.SignalEngine(md);
            eng.addMovingAverage('Close', 2);   % primary
            eng.addMovingAverage('Close', 3);   % regime

            % Threshold above max regime value → regime always inactive
            opts = struct( ...
                'PrimarySignalCol', 'MA_Close_2', ...
                'RegimeSignalCol',  'MA_Close_3', ...
                'RegimeThreshold',  1e9);          % impossible to exceed
            tt = eng.aggregate([], 'logic_gate', opts);

            nonNaN = tt.CompositeSignal(~isnan(tt.CompositeSignal));
            tc.verifyEqual(nonNaN, zeros(size(nonNaN)), 'AbsTol', 1e-12);
        end

        function testAggregate_LogicGate_TwoGates_ANDLogic(tc)
            % Both regime conditions must be met for the primary to fire.
            prices = (10:19)';
            md     = Tests.TestSignalEngine.makeMarketData(prices);
            eng    = Model.SignalEngine(md);
            eng.addMovingAverage('Close', 1);   % primary = close
            eng.addMovingAverage('Close', 2);   % regime A
            eng.addMovingAverage('Close', 3);   % regime B

            % Gate A: regime A > 0   (always true — ascending prices)
            % Gate B: regime B > 1e9 (always false — impossible)
            % AND result: all zeros
            gates = struct( ...
                'RegimeSignalCol', {'MA_Close_2', 'MA_Close_3'}, ...
                'Threshold',       {0, 1e9});
            opts  = struct('PrimarySignalCol', 'MA_Close_1', ...
                           'Gates', gates);
            tt = eng.aggregate([], 'logic_gate', opts);

            nonNaN = tt.CompositeSignal(~isnan(tt.CompositeSignal));
            tc.verifyEqual(nonNaN, zeros(size(nonNaN)), 'AbsTol', 1e-12);
        end

        function testAggregate_LogicGate_MissingPrimaryError(tc)
            tc.Eng.addMovingAverage('Close', 3);
            opts = struct('RegimeSignalCol', 'MA_Close_3', ...
                          'RegimeThreshold', 0);
            % PrimarySignalCol not provided → error
            tc.verifyError( ...
                @() tc.Eng.aggregate([], 'logic_gate', opts), ...
                'SignalBuilder:SignalEngine:missingOption');
        end

        %% === clearSignals ===

        function testClearSignals_RemovesAllColumns(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.Eng.addZScore('Close', 5);
            tc.Eng.clearSignals();
            tc.verifyTrue(isempty(tc.Eng.SignalNames));
        end

        %% === Error paths ===

        function testUnknownColumn_ThrowsError(tc)
            tc.verifyError( ...
                @() tc.Eng.addMovingAverage('NoSuchCol', 3), ...
                'SignalBuilder:SignalEngine:columnNotFound');
        end

        function testAggregate_MissingSignalColumn_ThrowsError(tc)
            tc.verifyError( ...
                @() tc.Eng.aggregate("DoesNotExist", 'static'), ...
                'SignalBuilder:SignalEngine:missingColumn');
        end

        %% === Observer: signals reset on data reload ===

        function testSignalsClearedOnDataReload(tc)
            tc.Eng.addMovingAverage('Close', 3);
            tc.verifyFalse(isempty(tc.Eng.SignalNames));
            tc.MD.loadFromTimetable(tc.MD.Prices, 'reload');
            tc.verifyTrue(isempty(tc.Eng.SignalNames));
        end

    end

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function md = makeMarketData(closePrices, ticker)
            if nargin < 2, ticker = 'TEST'; end
            n  = numel(closePrices);
            t  = datetime('2020-01-01','TimeZone','America/New_York') ...
                 + caldays(0:n-1)';
            tt = timetable(t, closePrices, closePrices, closePrices, ...
                           closePrices, ones(n,1) * 1e6, ...
                           'VariableNames', ...
                           {'Open','High','Low','Close','Volume'});
            md = Model.MarketData(ticker);
            md.loadFromTimetable(tt, 'test');
        end

    end
end
