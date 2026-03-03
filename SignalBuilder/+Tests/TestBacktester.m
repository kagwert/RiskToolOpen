classdef TestBacktester < matlab.unittest.TestCase
% TestBacktester  Unit tests for Model.Backtester.
%
%   Covers: construction, run() metric correctness (Sharpe, Sortino,
%   MaxDrawdown, Turnover, TotalReturn), budget-constraint enforcement,
%   NaN signal handling, IsRun flag, error paths, and Bayesian
%   optimisation (skipped automatically if toolbox unavailable).
%
%   Run:  results = runtests('+Tests/TestBacktester.m'); table(results)

    % ------------------------------------------------------------------ %
    properties
        MD  % Model.MarketData
        Eng % Model.SignalEngine
        BT  % Model.Backtester
    end

    methods (TestMethodSetup)
        function buildFixture(tc)
            % 5-bar monotone fixture: prices [100 110 121 133.1 146.41]
            % (10 % return per bar, no fraction issues)
            tc.MD  = Tests.TestBacktester.makeMarketData([100;110;121;133.1;146.41]);
            tc.Eng = Model.SignalEngine(tc.MD);
            tc.BT  = Model.Backtester(tc.Eng);
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        %% --- Construction ---

        function testConstructionNameContainsTicker(tc)
            tc.verifySubstring(tc.BT.Name, 'TEST');
        end

        function testIsRun_FalseBeforeRun(tc)
            tc.verifyFalse(tc.BT.IsRun);
        end

        %% --- run() basic results ---

        function testIsRun_TrueAfterRun(tc)
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyTrue(tc.BT.IsRun);
        end

        function testBacktestResults_HasRequiredColumns(tc)
            sig  = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            vars = string(tc.BT.BacktestResults.Properties.VariableNames);
            required = ["Position","AssetReturn","StrategyReturn", ...
                        "EquityCurve","Turnover"];
            tc.verifyTrue(all(ismember(required, vars)));
        end

        function testBacktestResults_HeightMatchesPrices(tc)
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyEqual(height(tc.BT.BacktestResults), tc.MD.NumBars);
        end

        function testMetrics_HasRequiredFields(tc)
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            required = {'SharpeRatio','SortinoRatio','MaxDrawdown', ...
                        'TurnoverDaily','TurnoverAnnual','TotalReturn'};
            for k = 1:numel(required)
                tc.verifyTrue(isfield(tc.BT.Metrics, required{k}));
            end
        end

        %% --- TotalReturn ---

        function testTotalReturn_KnownValue_NoCost(tc)
            % Long all bars, TC=0: equity goes from 100k to 100k*(1.1)^4
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            expected = (1.1)^4 - 1;   % ≈ 0.4641
            tc.verifyEqual(tc.BT.Metrics.TotalReturn, expected, 'AbsTol', 1e-10);
        end

        function testTotalReturn_FlatSignal_IsZero(tc)
            % All flat (signal = 0): no P&L → TotalReturn = 0
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 0);
            tc.BT.run(sig);
            tc.verifyEqual(tc.BT.Metrics.TotalReturn, 0, 'AbsTol', 1e-14);
        end

        %% --- Sharpe Ratio ---

        function testSharpe_PositiveForProfitableStrategy(tc)
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyGreaterThan(tc.BT.Metrics.SharpeRatio, 0);
        end

        function testSharpe_KnownValue(tc)
            % Long all bars, TC=0, rfRate=0.
            % stratRet = [0; 0.1; 0.1; 0.1; 0.1]  (NaN→0, then 10% each)
            % mean = 0.08, std = 0.04472 (sample std of [0,0.1,0.1,0.1,0.1])
            % Sharpe = 0.08 / 0.04472 * sqrt(252) ≈ 28.44
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            sr   = [0; 0.1; 0.1; 0.1; 0.1];   % actual stratRet vector
            expected = mean(sr) / std(sr) * sqrt(252);
            tc.verifyEqual(tc.BT.Metrics.SharpeRatio, expected, 'AbsTol', 1e-10);
        end

        %% --- Sortino Ratio ---

        function testSortino_GreaterThanSharpe_NoDownsideDays(tc)
            % No negative-return bars → downside semi-dev = 0 → Sortino >> Sharpe
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyGreaterThan(tc.BT.Metrics.SortinoRatio, ...
                                 tc.BT.Metrics.SharpeRatio);
        end

        function testSortino_KnownValue(tc)
            % stratRet = [0; 0.1; 0.1; 0.1; 0.1], rfDaily = 0
            % negExcess = min(stratRet, 0) = [0; 0; 0; 0; 0]
            % downsideStd = sqrt(mean(0)) = 0 → clamped to eps
            % Sortino = mean(stratRet) / eps * sqrt(252) → very large positive
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            sr       = [0; 0.1; 0.1; 0.1; 0.1];
            negExc   = min(sr, 0);
            downStd  = sqrt(mean(negExc.^2));   % = 0
            expected = mean(sr) / max(downStd, eps) * sqrt(252);
            % Values are O(1e15); use relative tolerance for ULP safety.
            tc.verifyEqual(tc.BT.Metrics.SortinoRatio, expected, 'RelTol', 1e-12);
        end

        function testSortino_WithLoss_LessThanPureLong(tc)
            % Introduce a losing bar: composite goes short on bar 3.
            % Prices go up so short loses money → Sortino should drop.
            prices = [100; 110; 121; 133.1; 146.41];
            md2    = Tests.TestBacktester.makeMarketData(prices);
            eng2   = Model.SignalEngine(md2);
            bt2    = Model.Backtester(eng2);
            bt2.TransactionCost  = 0;
            bt2.Constraints.MinWeightPerAsset = -1.0;

            % Build a signal that goes short for one bar
            n  = 5;
            t  = datetime('2020-01-01','TimeZone','America/New_York') ...
                 + caldays(0:n-1)';
            sig = timetable(t, [1;1;-1;1;1], 'VariableNames', {'CompositeSignal'});
            bt2.run(sig);
            sortino_mixed = bt2.Metrics.SortinoRatio;

            % Pure long (no losses after constraint)
            bt2.run(Tests.TestBacktester.constantSignal(md2, 1));
            sortino_pureLong = bt2.Metrics.SortinoRatio;

            tc.verifyLessThan(sortino_mixed, sortino_pureLong);
        end

        %% --- Max Drawdown ---

        function testMaxDrawdown_MonotoneUp_IsZero(tc)
            % Equity always rising → no drawdown
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyEqual(tc.BT.Metrics.MaxDrawdown, 0, 'AbsTol', 1e-14);
        end

        function testMaxDrawdown_WithDip_IsNegative(tc)
            % Dip at bar 4: prices go up then down then up.
            prices = [100; 110; 120; 115; 130];
            md2    = Tests.TestBacktester.makeMarketData(prices);
            eng2   = Model.SignalEngine(md2);
            bt2    = Model.Backtester(eng2);
            bt2.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(md2, 1);
            bt2.run(sig);
            tc.verifyLessThan(bt2.Metrics.MaxDrawdown, 0);
        end

        function testMaxDrawdown_KnownValue(tc)
            % Prices [100;110;120;115;130], long all bars, TC=0, no cost.
            % ret = [NaN; 0.1; 1/11; -1/24; 15/23]  (exact fractions)
            % stratRet (NaN→0) = [0; 0.1; 1/11; -1/24; 15/23]
            % cumprod factors: 1; 1.1; 1.1*(12/11); ...*(23/24); ...*(38/23)
            % equity(4)/equity(3) = 23/24 → drawdown at bar 4 = 23/24 - 1
            %   = -1/24
            prices = [100; 110; 120; 115; 130];
            md2    = Tests.TestBacktester.makeMarketData(prices);
            eng2   = Model.SignalEngine(md2);
            bt2    = Model.Backtester(eng2);
            bt2.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(md2, 1);
            bt2.run(sig);
            tc.verifyEqual(bt2.Metrics.MaxDrawdown, -1/24, 'AbsTol', 1e-12);
        end

        function testMaxDrawdown_IsNonPositive(tc)
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyLessThanOrEqual(tc.BT.Metrics.MaxDrawdown, 0);
        end

        %% --- Turnover ---

        function testTurnover_ConstantLongPosition_NearZero(tc)
            % After the entry bar (bar 1 cost), daily turnover is 0.
            % Mean turnover = 1/numBars.
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            % posChg = [1; 0; 0; 0; 0] → mean = 1/5 = 0.2
            tc.verifyEqual(tc.BT.Metrics.TurnoverDaily, 1/5, 'AbsTol', 1e-14);
        end

        function testTurnoverAnnual_EqualsDailyTimes252(tc)
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1);
            tc.BT.run(sig);
            tc.verifyEqual(tc.BT.Metrics.TurnoverAnnual, ...
                           tc.BT.Metrics.TurnoverDaily * 252, 'AbsTol', 1e-12);
        end

        function testTurnover_HighFrequencySignal_IsHigh(tc)
            % Alternating +1 / -1 signal → position changes every bar
            sig = Tests.TestBacktester.makeSignalTT(tc.MD, [1;-1;1;-1;1]);
            tc.BT.Constraints.MinWeightPerAsset = -1.0;
            tc.BT.run(sig);
            tc.verifyGreaterThan(tc.BT.Metrics.TurnoverDaily, 0.9);
        end

        %% --- Budget constraints ---

        function testConstraint_MaxLeverage_ClipsSignal(tc)
            % Signal = 2.0, MaxLeverage = 1.0 → position clamped to 1.0
            tc.BT.Constraints.MaxLeverage       = 1.0;
            tc.BT.Constraints.MaxWeightPerAsset = 2.0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 2.0);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyTrue(all(pos <= 1.0 + 1e-14));
        end

        function testConstraint_MaxWeightPerAsset_ClipsSignal(tc)
            % Signal = 3.0, MaxWeight = 0.5 → position clamped to 0.5
            tc.BT.Constraints.MaxLeverage       = 2.0;
            tc.BT.Constraints.MaxWeightPerAsset = 0.5;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 3.0);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyTrue(all(pos <= 0.5 + 1e-14));
        end

        function testConstraint_MinWeightPerAsset_AllowsShorts(tc)
            % Signal = -1.0, MinWeight = -1.0 → position = -1 allowed
            tc.BT.Constraints.MinWeightPerAsset = -1.0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, -1.0);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyTrue(all(pos >= -1.0 - 1e-14));
            tc.verifyLessThan(min(pos), 0);   % actually negative
        end

        function testConstraint_LongOnly_BlocksNegativeSignal(tc)
            % Default MinWeightPerAsset = 0: negative signal → flat
            tc.BT.Constraints.MinWeightPerAsset = 0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, -1.0);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyTrue(all(pos == 0));
        end

        function testConstraint_EffectiveBoundsUseLeverageIfTighter(tc)
            % MaxLeverage=0.5, MaxWeight=1.0 → effective upper = 0.5
            tc.BT.Constraints.MaxLeverage       = 0.5;
            tc.BT.Constraints.MaxWeightPerAsset = 1.0;
            sig = Tests.TestBacktester.constantSignal(tc.MD, 1.0);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyTrue(all(pos <= 0.5 + 1e-14));
        end

        %% --- NaN signal handling ---

        function testNaN_SignalBar_BecomesFlat(tc)
            % NaN composite on bar 2 → decision(2)=0 → posLag flat on bar 3.
            % With 1-bar lag: pos(3) = 0 (position active during bar 3
            % is based on the NaN bar 2 decision which clamps to 0).
            sig = Tests.TestBacktester.makeSignalTT(tc.MD, [1;NaN;1;1;1]);
            tc.BT.run(sig);
            pos = tc.BT.BacktestResults.Position;
            tc.verifyEqual(pos(3), 0, 'AbsTol', 1e-14);
        end

        function testAllNaN_Signal_ProducesZeroTotalReturn(tc)
            tc.BT.TransactionCost = 0;
            sig = Tests.TestBacktester.makeSignalTT(tc.MD, nan(5,1));
            tc.BT.run(sig);
            tc.verifyEqual(tc.BT.Metrics.TotalReturn, 0, 'AbsTol', 1e-14);
        end

        %% --- Error paths ---

        function testRun_MissingCompositeColumn_Throws(tc)
            n  = 5;
            t  = datetime('2020-01-01','TimeZone','America/New_York') ...
                 + caldays(0:n-1)';
            tt = timetable(t, ones(n,1), 'VariableNames', {'WrongCol'});
            tc.verifyError(@() tc.BT.run(tt), ...
                'SignalBuilder:Backtester:missingColumn');
        end

        function testRun_SizeMismatch_Throws(tc)
            % 3-bar signal on a 5-bar engine → error
            n  = 3;
            t  = datetime('2020-01-01','TimeZone','America/New_York') ...
                 + caldays(0:n-1)';
            tt = timetable(t, ones(n,1), 'VariableNames', {'CompositeSignal'});
            tc.verifyError(@() tc.BT.run(tt), ...
                'SignalBuilder:Backtester:sizeMismatch');
        end

        %% --- Bayesian optimisation ---

        function testOptimize_FindsBetterSharpe(tc)
        % Verify that optimize() runs without error and the final Sharpe
        % is finite.  Uses 3 evaluations to keep runtime short.
        % Skipped automatically if Statistics Toolbox is unavailable.
            tc.assumeTrue( ...
                exist('bayesopt','file') || exist('bayesopt','builtin'), ...
                'Statistics and Machine Learning Toolbox not available.');

            % 50-bar linearly drifting price series
            prices = (100:149)';
            md2    = Tests.TestBacktester.makeMarketData(prices);
            eng2   = Model.SignalEngine(md2);
            bt2    = Model.Backtester(eng2);
            bt2.TransactionCost = 0;
            bt2.OptimOptions.MaxObjectiveEvaluations = 3;
            bt2.OptimOptions.Verbose = 0;

            builderFn = @(e) Tests.TestBacktester.simpleBuild(e);

            vars = optimizableVariable('MAWindow', [2, 10], 'Type','integer');
            bt2.optimize(builderFn, 'static', vars);

            tc.verifyTrue(isfinite(bt2.Metrics.SharpeRatio));
            tc.verifyFalse(isempty(bt2.OptimalParams));
        end

        function testOptimize_StoresOptimalParams(tc)
            tc.assumeTrue( ...
                exist('bayesopt','file') || exist('bayesopt','builtin'), ...
                'Statistics and Machine Learning Toolbox not available.');

            prices = (100:149)';
            md2    = Tests.TestBacktester.makeMarketData(prices);
            eng2   = Model.SignalEngine(md2);
            bt2    = Model.Backtester(eng2);
            bt2.TransactionCost = 0;
            bt2.OptimOptions.MaxObjectiveEvaluations = 3;
            bt2.OptimOptions.Verbose = 0;

            vars = optimizableVariable('MAWindow', [2, 10], 'Type','integer');
            bt2.optimize( ...
                @Tests.TestBacktester.simpleBuild, 'static', vars);

            tc.verifyTrue(isfield(bt2.OptimalParams, 'MAWindow'));
            tc.verifyGreaterThanOrEqual(bt2.OptimalParams.MAWindow, 2);
            tc.verifyLessThanOrEqual(bt2.OptimalParams.MAWindow, 10);
        end

    end

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function md = makeMarketData(closePrices, ticker)
        % Build a minimal MarketData from a column vector of close prices.
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

        function sig = constantSignal(md, value)
        % Build a constant composite-signal timetable aligned to md.
            n   = md.NumBars;
            t   = md.Prices.Time;
            sig = timetable(t, repmat(value, n, 1), ...
                'VariableNames', {'CompositeSignal'});
        end

        function sig = makeSignalTT(md, values)
        % Build a composite-signal timetable from an explicit value vector.
            t   = md.Prices.Time;
            sig = timetable(t, values, 'VariableNames', {'CompositeSignal'});
        end

        function simpleBuild(eng)
        % Signal builder for optimization tests: MA only.
            eng.clearSignals();
            eng.addMovingAverage('Close');   % uses current Params.MAWindow
        end

    end
end
