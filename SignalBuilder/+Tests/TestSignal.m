classdef TestSignal < matlab.unittest.TestCase
% TestSignal  Unit tests for Model.Signal indicator mathematics.
%
%   Covers SMA, EMA, RSI, and crossover logic with analytically-verified
%   expected values derived by hand.
%
%   Run:  results = runtests('+Tests/TestSignal.m'); table(results)

    % ------------------------------------------------------------------ %
    %  Shared fixture: linear prices [10..14], 5 bars
    % ------------------------------------------------------------------ %
    properties
        MD  % Model.MarketData handle
        Sig % Model.Signal handle
    end

    methods (TestMethodSetup)
        function buildLinearFixture(tc)
            % Clean linear prices used by most SMA/EMA/crossover tests.
            tc.MD  = Tests.TestSignal.makeMarketData((10:14)');
            tc.Sig = Model.Signal(tc.MD);
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        %% === SMA ===

        function testSMAColumnIsAdded(tc)
            tc.Sig.addSMA(3);
            tc.verifyTrue(ismember('SMA_3', tc.Sig.SignalNames));
        end

        function testSMALengthMatchesNumBars(tc)
            tc.Sig.addSMA(3);
            tc.verifyEqual(height(tc.Sig.SignalTable), tc.MD.NumBars);
        end

        function testSMALeadingNaNCount(tc)
            % A period-p SMA should have exactly p-1 leading NaN values.
            tc.Sig.addSMA(3);
            sma = tc.Sig.SignalTable.SMA_3;
            tc.verifyTrue(isnan(sma(1)));
            tc.verifyTrue(isnan(sma(2)));
            tc.verifyFalse(isnan(sma(3)));
        end

        function testSMAKnownValues_LinearPrices(tc)
            % prices=[10;11;12;13;14], period=3:
            %   SMA_3 = [NaN; NaN; 11; 12; 13]
            tc.Sig.addSMA(3);
            sma = tc.Sig.SignalTable.SMA_3;
            tc.verifyEqual(sma(3), 11.0, 'AbsTol', 1e-12);
            tc.verifyEqual(sma(4), 12.0, 'AbsTol', 1e-12);
            tc.verifyEqual(sma(5), 13.0, 'AbsTol', 1e-12);
        end

        function testSMAPeriod1EqualsClose(tc)
            % SMA with window=1 must equal the close series exactly.
            tc.Sig.addSMA(1);
            sma   = tc.Sig.SignalTable.SMA_1;
            close = tc.MD.Prices.Close;
            tc.verifyEqual(sma, close, 'AbsTol', 1e-14);
        end

        function testSMAUpsertOverwritesPreviousColumn(tc)
            % Adding SMA with same period twice should not duplicate column.
            tc.Sig.addSMA(2);
            tc.Sig.addSMA(2);
            count = sum(strcmp(tc.Sig.SignalTable.Properties.VariableNames, ...
                'SMA_2'));
            tc.verifyEqual(count, 1);
        end

        function testSMANaNOnlyWhenWindowInsufficient(tc)
            % For n=5, period=5: only one non-NaN value (the last row).
            tc.Sig.addSMA(5);
            sma = tc.Sig.SignalTable.SMA_5;
            tc.verifyEqual(sum(isnan(sma)), 4);
            tc.verifyEqual(sma(5), mean(10:14), 'AbsTol', 1e-12);
        end

        %% === EMA ===

        function testEMAColumnIsAdded(tc)
            tc.Sig.addEMA(3);
            tc.verifyTrue(ismember('EMA_3', tc.Sig.SignalNames));
        end

        function testEMALengthMatchesNumBars(tc)
            tc.Sig.addEMA(3);
            tc.verifyEqual(height(tc.Sig.SignalTable), tc.MD.NumBars);
        end

        function testEMALeadingNaNCount(tc)
            tc.Sig.addEMA(3);
            ema = tc.Sig.SignalTable.EMA_3;
            tc.verifyTrue(isnan(ema(1)));
            tc.verifyTrue(isnan(ema(2)));
            tc.verifyFalse(isnan(ema(3)));
        end

        function testEMASeedEqualsInitialSMA(tc)
            % The seed at index `period` = mean(close(1:period)).
            period = 3;
            tc.Sig.addEMA(period);
            ema   = tc.Sig.SignalTable.EMA_3;
            close = tc.MD.Prices.Close;
            tc.verifyEqual(ema(period), mean(close(1:period)), 'AbsTol', 1e-12);
        end

        function testEMAKnownValues_NonLinearPrices(tc)
            % prices=[10;11;12;15;16], period=3, k = 2/(3+1) = 0.5
            %   seed: EMA(3) = mean([10;11;12]) = 11
            %   EMA(4) = 15*0.5 + 11*0.5   = 13
            %   EMA(5) = 16*0.5 + 13*0.5   = 14.5
            md  = Tests.TestSignal.makeMarketData([10; 11; 12; 15; 16]);
            sig = Model.Signal(md);
            sig.addEMA(3);
            ema = sig.SignalTable.EMA_3;
            tc.verifyEqual(ema(3), 11.0,  'AbsTol', 1e-12);
            tc.verifyEqual(ema(4), 13.0,  'AbsTol', 1e-12);
            tc.verifyEqual(ema(5), 14.5,  'AbsTol', 1e-12);
        end

        function testEMASmootherThanSMA_OnSpike(tc)
            % A spike in prices should be damped more by EMA than SMA.
            prices = [10; 10; 10; 50; 10; 10; 10];
            md     = Tests.TestSignal.makeMarketData(prices);
            sig    = Model.Signal(md);
            sig.addSMA(3);
            sig.addEMA(3);
            ema = sig.SignalTable.EMA_3;
            sma = sig.SignalTable.SMA_3;
            % At bar 6, EMA recovers faster (smaller) than SMA from the spike
            tc.verifyLessThan(abs(ema(6) - 10), abs(sma(6) - 10));
        end

        %% === RSI ===

        function testRSIColumnIsAdded(tc)
            md  = Tests.TestSignal.makeMarketData((10:14)');
            sig = Model.Signal(md);
            sig.addRSI(2);
            tc.verifyTrue(ismember('RSI_2', sig.SignalNames));
        end

        function testRSILengthMatchesNumBars(tc)
            md  = Tests.TestSignal.makeMarketData((1:20)');
            sig = Model.Signal(md);
            sig.addRSI(14);
            tc.verifyEqual(height(sig.SignalTable), md.NumBars);
        end

        function testRSIAllUp_Approaches100(tc)
            % Prices=10..14, period=2.  All gains, no losses → RSI → 100.
            %   delta=[1;1;1;1], avgGain=1, avgLoss→0
            %   RS=1/eps≈inf, RSI=100-100/(1+inf)≈100
            md  = Tests.TestSignal.makeMarketData((10:14)');
            sig = Model.Signal(md);
            sig.addRSI(2);
            rsi    = sig.SignalTable.RSI_2;
            nonNaN = rsi(~isnan(rsi));
            tc.verifyGreaterThan(min(nonNaN), 99.0);
        end

        function testRSIAllDown_Approaches0(tc)
            % Prices=14..10, period=2.  All losses, no gains → RSI → 0.
            %   avgGain=0, RS=0/avgLoss=0, RSI=100-100=0
            md  = Tests.TestSignal.makeMarketData((14:-1:10)');
            sig = Model.Signal(md);
            sig.addRSI(2);
            rsi    = sig.SignalTable.RSI_2;
            nonNaN = rsi(~isnan(rsi));
            tc.verifyLessThan(max(nonNaN), 1.0);
        end

        function testRSIBounded_Between0And100(tc)
            % RSI must lie in [0, 100] for any non-negative price series.
            rng(42);
            prices = max(100 + cumsum(randn(60, 1)), 1);
            md     = Tests.TestSignal.makeMarketData(prices);
            sig    = Model.Signal(md);
            sig.addRSI(14);
            rsi    = sig.SignalTable.RSI_14;
            nonNaN = rsi(~isnan(rsi));
            tc.verifyGreaterThanOrEqual(min(nonNaN), 0,   'RSI < 0');
            tc.verifyLessThanOrEqual(max(nonNaN),    100, 'RSI > 100');
        end

        function testRSILeadingNaNCount(tc)
            % With period=p and n=p+2 bars, the loop runs for i=p+1 only,
            % producing one non-NaN value at index p+2.  First p+1 are NaN.
            period = 4;
            n      = period + 2;   % 6 bars
            prices = (1:n)';
            md     = Tests.TestSignal.makeMarketData(prices);
            sig    = Model.Signal(md);
            sig.addRSI(period);
            rsi = sig.SignalTable.(sprintf('RSI_%d', period));
            tc.verifyEqual(sum(isnan(rsi)), period + 1);
        end

        function testRSIAlternatingGainsLosses_Near50(tc)
            % Equal-magnitude alternating ups and downs → RSI ≈ 50.
            % Build using: prices that go up/down symmetrically.
            n = 30;
            prices = zeros(n, 1);
            prices(1) = 100;
            for k = 2:n
                prices(k) = prices(k-1) + (-1)^k;
            end
            md  = Tests.TestSignal.makeMarketData(prices);
            sig = Model.Signal(md);
            sig.addRSI(14);
            rsi    = sig.SignalTable.RSI_14;
            nonNaN = rsi(~isnan(rsi));
            % Smoothed EMA of equal gains/losses → RS ≈ 1 → RSI ≈ 50
            tc.verifyEqual(mean(nonNaN), 50, 'AbsTol', 5);
        end

        %% === Crossover signal ===

        function testCrossover_FastAboveSlow_Returns1(tc)
            % SMA_1 (= close) always above SMA_5 for ascending prices.
            % Last bar: both non-NaN, fast>slow → crossover=+1.
            tc.Sig.addSMA(1);
            tc.Sig.addSMA(5);
            tc.Sig.addCrossoverSignal('SMA_1', 'SMA_5');
            cross = tc.Sig.SignalTable.SMA_1_X_SMA_5;
            tc.verifyEqual(cross(5), 1);
        end

        function testCrossover_FastBelowSlow_ReturnsMinus1(tc)
            % Descending prices: SMA_1 < SMA_5 → crossover = -1.
            md  = Tests.TestSignal.makeMarketData((14:-1:10)');
            sig = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(5);
            sig.addCrossoverSignal('SMA_1', 'SMA_5');
            cross = sig.SignalTable.SMA_1_X_SMA_5;
            tc.verifyEqual(cross(5), -1);
        end

        function testCrossover_NaNRow_Returns0(tc)
            % Rows where either MA is NaN must produce 0.
            tc.Sig.addSMA(1);
            tc.Sig.addSMA(5);   % NaN for rows 1-4
            tc.Sig.addCrossoverSignal('SMA_1', 'SMA_5');
            cross = tc.Sig.SignalTable.SMA_1_X_SMA_5;
            tc.verifyEqual(cross(1), 0);
            tc.verifyEqual(cross(2), 0);
            tc.verifyEqual(cross(3), 0);
            tc.verifyEqual(cross(4), 0);
        end

        function testCrossover_KnownValues_UpThenDown(tc)
            % prices=[10;11;12;11;10], SMA_1 vs SMA_3
            %   SMA_1 = [10;11;12;11;10]
            %   SMA_3 = [NaN;NaN;11;11.33;11]
            %   Row 3: 12 > 11        → cross = +1
            %   Row 4: 11 < 11.33     → cross = -1
            %   Row 5: 10 < 11        → cross = -1
            md  = Tests.TestSignal.makeMarketData([10; 11; 12; 11; 10]);
            sig = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(3);
            sig.addCrossoverSignal('SMA_1', 'SMA_3');
            cross = sig.SignalTable.SMA_1_X_SMA_3;
            tc.verifyEqual(cross(3),  1);
            tc.verifyEqual(cross(4), -1);
            tc.verifyEqual(cross(5), -1);
        end

        function testCrossover_EqualValues_Returns0(tc)
            % When fast == slow, crossover must be 0 (no strict inequality).
            prices = ones(5,1) * 10;          % flat price
            md     = Tests.TestSignal.makeMarketData(prices);
            sig    = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(3);
            sig.addCrossoverSignal('SMA_1', 'SMA_3');
            cross = sig.SignalTable.SMA_1_X_SMA_3;
            % Row 3-5: SMA_1=10, SMA_3=10 → 0
            tc.verifyEqual(cross(3), 0);
            tc.verifyEqual(cross(4), 0);
            tc.verifyEqual(cross(5), 0);
        end

        function testCrossover_OutputValuesOnlyPlusOneMinus1OrZero(tc)
            % All crossover values must be in {-1, 0, +1}.
            rng(7);
            prices = max(100 + cumsum(randn(40,1)), 1);
            md     = Tests.TestSignal.makeMarketData(prices);
            sig    = Model.Signal(md);
            sig.addSMA(5);
            sig.addSMA(10);
            sig.addCrossoverSignal('SMA_5', 'SMA_10');
            cross = sig.SignalTable.SMA_5_X_SMA_10;
            allowedValues = [-1; 0; 1];
            tc.verifyTrue(all(ismember(cross, allowedValues)));
        end

        function testCrossover_MissingColumnError(tc)
            tc.verifyError( ...
                @() tc.Sig.addCrossoverSignal('DoesNotExist', 'AlsoMissing'), ...
                'SignalBuilder:Signal:missingColumn');
        end

        %% === getSignals ===

        function testGetSignals_AllColumns(tc)
            tc.Sig.addSMA(1);
            tc.Sig.addSMA(3);
            tt = tc.Sig.getSignals();
            tc.verifyEqual(width(tt), 2);
        end

        function testGetSignals_Subset(tc)
            tc.Sig.addSMA(1);
            tc.Sig.addSMA(3);
            tt = tc.Sig.getSignals("SMA_1");
            tc.verifyEqual(width(tt), 1);
            tc.verifyEqual(string(tt.Properties.VariableNames{1}), "SMA_1");
        end

        function testGetSignals_MissingColumnError(tc)
            tc.verifyError( ...
                @() tc.Sig.getSignals("NonExistent"), ...
                'SignalBuilder:Signal:missingColumn');
        end

        %% === Observer: signal resets on data reload ===

        function testSignalsClearedOnDataReload(tc)
            tc.Sig.addSMA(3);
            % Confirm column exists
            tc.verifyFalse(isempty(tc.Sig.SignalTable.Properties.VariableNames));
            % Reload data into the same MarketData handle
            tc.MD.loadFromTimetable(tc.MD.Prices, 'reload');
            % Signal should have been reset by the Changed listener
            tc.verifyTrue(isempty(tc.Sig.SignalTable.Properties.VariableNames));
        end

        function testChangedEventFiredOnSMAAdd(tc)
            fired = false;
            addlistener(tc.Sig, 'Changed', @(~,~) setFired());
            tc.Sig.addSMA(3);
            tc.verifyTrue(fired, 'Expected Changed event after addSMA');

            function setFired()
                fired = true;
            end
        end

    end

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function md = makeMarketData(closePrices, ticker)
        % Build a minimal MarketData from a close-price column vector.
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
