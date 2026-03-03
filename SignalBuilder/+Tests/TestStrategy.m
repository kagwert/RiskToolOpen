classdef TestStrategy < matlab.unittest.TestCase
% TestStrategy  Unit tests for Model.Strategy backtest mathematics.
%
%   All expected values are derived analytically by hand with zero
%   transaction cost and full position size so intermediate steps are
%   exact fractions.
%
%   Two canonical fixtures are used throughout (all with 1-bar lag):
%
%   MONOTONE  prices=[100;110;121], SMA_1/SMA_2 crossover
%     Signal:   cross=[0;+1;+1]
%     Position: decision=[0;1;1], posLag=[0;0;1]
%     Returns:  [NaN;0.1;0.1]  ret(3)=(121-110)/110=11/110=0.1
%     StratRet: [0;0;0.1]   (zero cost, posLag applied; bar 3 earns)
%     Equity:   [1e5; 1e5; 1.1e5]
%     TotalReturn = 0.1,  MaxDrawdown = 0,  WinRate = 1.0
%
%   DRAWDOWN   prices=[100;110;120;108;132], SMA_1/SMA_2 crossover
%     Signal:   cross=[0;+1;+1;-1;+1]
%     Position: decision=[0;1;1;0;1], posLag=[0;0;1;1;0]
%     Returns:  [NaN;0.1;1/11;-1/10;2/9]
%     StratRet: [0;0;1/11;-1/10;0]  (long bar 3-4, flat bar 5)
%     Equity:   [1e5;1e5;1e5*12/11;1e5*54/55;1e5*54/55]
%     MaxDrawdown = -1/10
%
%   Run:  results = runtests('+Tests/TestStrategy.m'); table(results)

    % ------------------------------------------------------------------ %
    methods (Test)

        %% --- Lifecycle and state ---

        function testIsStaleAfterConstruction(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            tc.verifyTrue(strat.IsStale);
        end

        function testIsStaleAfterRun_BecomesFalse(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyFalse(strat.IsStale);
        end

        function testIsStale_ResetWhenSignalChanges(tc)
            [md, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyFalse(strat.IsStale);
            % Touching the underlying data fires Signal.Changed →
            % Strategy.onSignalChanged → IsStale = true.
            md.loadFromTimetable(md.Prices, 'reload');
            tc.verifyTrue(strat.IsStale);
        end

        function testRunWithNoRulesThrows(tc)
            md  = Tests.TestStrategy.makeMarketData([100; 110; 121]);
            sig = Model.Signal(md);
            sig.addSMA(1);
            strat = Model.Strategy('NoRules', sig);
            tc.verifyError(@() strat.run(), ...
                'SignalBuilder:Strategy:noRules');
        end

        %% --- BacktestResults timetable structure ---

        function testBacktestResults_HasRequiredColumns(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            vars = string(strat.BacktestResults.Properties.VariableNames);
            expected = ["Position","AssetReturn","StrategyReturn", ...
                        "EquityCurve","Trade"];
            tc.verifyTrue(all(ismember(expected, vars)));
        end

        function testBacktestResults_HeightMatchesPriceRows(tc)
            [md, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyEqual(height(strat.BacktestResults), md.NumBars);
        end

        %% --- Position logic ---

        function testPositionLogic_EntersOnSignal(tc)
            % crossover = +1 at bar 2; with 1-bar lag the position is
            % active during bar 3 (posLag(3) = 1).
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            pos = strat.BacktestResults.Position;
            tc.verifyEqual(pos(1), 0, 'Position must start flat');
            tc.verifyEqual(pos(3), 1, 'Must be active the bar after +1 signal');
        end

        function testPositionLogic_HoldsWithoutExitSignal(tc)
            % Bar 3 crossover = +1 again (not -1) → position stays at 1.
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            pos = strat.BacktestResults.Position;
            tc.verifyEqual(pos(3), 1, 'Must hold when no exit signal');
        end

        function testPositionLogic_ExitsOnMinusOneSignal(tc)
            % 5-bar scenario with explicit entry, exit and re-entry.
            % prices=[100;110;90;110;120], SMA_1 vs SMA_2
            %   SMA_1=[100;110;90;110;120], SMA_2=[NaN;105;100;100;115]
            %   cross=[0;+1;-1;+1;+1]
            %   decision=[0;1;0;1;1], posLag=[0;0;1;0;1]
            md   = Tests.TestStrategy.makeMarketData([100; 110; 90; 110; 120]);
            sig  = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(2);
            sig.addCrossoverSignal('SMA_1', 'SMA_2');
            strat = Model.Strategy('ExitTest', sig);
            strat.TransactionCost = 0;
            strat.setEntryRule('SMA_1_X_SMA_2', 1);
            strat.setExitRule('SMA_1_X_SMA_2', -1);
            strat.run();
            pos = strat.BacktestResults.Position;
            tc.verifyEqual(pos(3), 1, 'Active bar after +1 entry');
            tc.verifyEqual(pos(4), 0, 'Flat bar after -1 exit');
            tc.verifyEqual(pos(5), 1, 'Active bar after +1 re-entry');
        end

        function testTradeColumn_BuyOnEntry(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            trades = strat.BacktestResults.Trade;
            tc.verifyEqual(trades(2), 1, 'Buy trade on entry bar');
        end

        function testTradeColumn_NoBuysOnHold(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            trades = strat.BacktestResults.Trade;
            tc.verifyEqual(trades(3), 0, 'No trade when holding');
        end

        %% --- Equity curve mathematics ---

        function testEquityCurve_ZeroCost_KnownValues(tc)
            % MONOTONE with 1-bar lag: posLag=[0;0;1], StratRet=[0;0;0.1]
            %   ret(3) = (121-110)/110 = 11/110 = 0.1
            %   equity = 1e5 * cumprod([1;1;1.1]) = [1e5; 1e5; 1.1e5]
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            eq = strat.BacktestResults.EquityCurve;
            tc.verifyEqual(eq(1), 1e5,   'AbsTol', 1e-8);
            tc.verifyEqual(eq(2), 1e5,   'AbsTol', 1e-8);
            tc.verifyEqual(eq(3), 1.1e5, 'AbsTol', 1e-8);
        end

        function testEquityCurve_StartsAtInitialCapital(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            eq = strat.BacktestResults.EquityCurve;
            tc.verifyEqual(eq(1), strat.InitialCapital, 'AbsTol', 1e-8);
        end

        function testEquityCurve_TransactionCostReducesReturn(tc)
            [md, sig, ~]  = Tests.TestStrategy.makeMonotoneStrategy();
            % With cost
            stratCost = Model.Strategy('WithCost', sig);
            stratCost.TransactionCost = 0.01;
            stratCost.setEntryRule('SMA_1_X_SMA_2', 1);
            stratCost.setExitRule('SMA_1_X_SMA_2', -1);
            stratCost.run();
            % Free strategy for same data
            sig0      = Model.Signal(md);
            sig0.addSMA(1); sig0.addSMA(2);
            sig0.addCrossoverSignal('SMA_1','SMA_2');
            stratFree = Model.Strategy('NoCost', sig0);
            stratFree.TransactionCost = 0;
            stratFree.setEntryRule('SMA_1_X_SMA_2', 1);
            stratFree.setExitRule('SMA_1_X_SMA_2', -1);
            stratFree.run();
            eqCost = stratCost.BacktestResults.EquityCurve;
            eqFree = stratFree.BacktestResults.EquityCurve;
            tc.verifyLessThan(eqCost(end), eqFree(end));
        end

        %% --- Metrics: TotalReturn ---

        function testTotalReturn_KnownValue(tc)
            % MONOTONE with 1-bar lag: equity 1e5 → 1.1e5 → TotalReturn = 0.1
            %   ret(3) = (121-110)/110 = 11/110 = 0.1; posLag(3)=1 earns it
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyEqual(strat.Metrics.TotalReturn, 0.1, 'AbsTol', 1e-12);
        end

        function testTotalReturn_Formula(tc)
            % Verify the formula: (equity_end - capital) / capital
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            eq       = strat.BacktestResults.EquityCurve;
            expected = (eq(end) - strat.InitialCapital) / strat.InitialCapital;
            tc.verifyEqual(strat.Metrics.TotalReturn, expected, 'AbsTol', 1e-14);
        end

        %% --- Metrics: MaxDrawdown ---

        function testMaxDrawdown_MonotoneUp_IsZero(tc)
            % MONOTONE: equity is strictly increasing → no drawdown.
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyEqual(strat.Metrics.MaxDrawdown, 0, 'AbsTol', 1e-12);
        end

        function testMaxDrawdown_KnownDip(tc)
            % DRAWDOWN scenario with 1-bar lag (analytically exact):
            %   posLag=[0;0;1;1;0], StratRet=[0;0;1/11;-1/10;0]
            %   equity=[1e5;1e5;1e5*12/11;1e5*54/55;1e5*54/55]
            %   cummax peaks at 1e5*12/11 from bar 3 onward
            %   dd at bar 4 = (54/55 - 12/11) / (12/11) = -1/10
            %   MaxDrawdown = -1/10
            strat = Tests.TestStrategy.makeDrawdownStrategy();
            strat.run();
            tc.verifyEqual(strat.Metrics.MaxDrawdown, -1/10, 'AbsTol', 1e-12);
        end

        function testMaxDrawdown_IsNonPositive(tc)
            % By definition drawdown <= 0 for any strategy.
            strat = Tests.TestStrategy.makeDrawdownStrategy();
            strat.run();
            tc.verifyLessThanOrEqual(strat.Metrics.MaxDrawdown, 0);
        end

        %% --- Metrics: WinRate ---

        function testWinRate_AllWinningBars(tc)
            % MONOTONE: StratRet=[0;0.1;0.1], posRet=[0.1;0.1], negRet=[]
            %   WinRate = 2/(2+0) = 1.0
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyEqual(strat.Metrics.WinRate, 1.0, 'AbsTol', 1e-14);
        end

        function testWinRate_BetweenZeroAndOne(tc)
            strat = Tests.TestStrategy.makeDrawdownStrategy();
            strat.run();
            tc.verifyGreaterThanOrEqual(strat.Metrics.WinRate, 0);
            tc.verifyLessThanOrEqual(strat.Metrics.WinRate, 1);
        end

        %% --- Metrics: SharpeRatio ---

        function testSharpeRatio_PositiveForProfitableStrategy(tc)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyGreaterThan(strat.Metrics.SharpeRatio, 0);
        end

        function testSharpeRatio_Formula(tc)
            % Sharpe = mean(stratRet) / std(stratRet) * sqrt(252)
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            sr  = strat.BacktestResults.StrategyReturn;
            expected = mean(sr,'omitnan') / ...
                       max(std(sr,'omitnan'), eps) * sqrt(252);
            tc.verifyEqual(strat.Metrics.SharpeRatio, expected, 'AbsTol', 1e-10);
        end

        %% --- Metrics: ProfitFactor ---

        function testProfitFactor_AllWins_IsLarge(tc)
            % With only gains, ProfitFactor = sum(gains)/eps → very large.
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyGreaterThan(strat.Metrics.ProfitFactor, 100);
        end

        function testProfitFactor_WithLoss_LessThanAllWin(tc)
            stratMono = Tests.TestStrategy.makeDrawdownStrategy();
            stratMono.run();
            [~, ~, stratUp] = Tests.TestStrategy.makeMonotoneStrategy();
            stratUp.run();
            tc.verifyLessThan( ...
                stratMono.Metrics.ProfitFactor, ...
                stratUp.Metrics.ProfitFactor);
        end

        %% --- AssetReturn column ---

        function testAssetReturn_FirstIsZero(tc)
            % Row 1 has NaN asset return; strategy replaces with 0.
            [~, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            tc.verifyEqual(strat.BacktestResults.StrategyReturn(1), 0, ...
                'AbsTol', 1e-14);
        end

        function testAssetReturn_Formula(tc)
            % AssetReturn_t = (Close_t - Close_{t-1}) / Close_{t-1}
            [md, ~, strat] = Tests.TestStrategy.makeMonotoneStrategy();
            strat.run();
            close    = md.Prices.Close;
            ar       = strat.BacktestResults.AssetReturn;
            expected = (close(2) - close(1)) / close(1);
            tc.verifyEqual(ar(2), expected, 'AbsTol', 1e-14);
        end

    end

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function [md, sig, strat] = makeMonotoneStrategy()
        % prices=[100;110;121], no cost, SMA_1 X SMA_2 crossover.
        %   cross=[0;+1;+1] → pos=[0;1;1]
        %   equity=[1e5;1.1e5;1.21e5]
            md   = Tests.TestStrategy.makeMarketData([100; 110; 121]);
            sig  = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(2);
            sig.addCrossoverSignal('SMA_1', 'SMA_2');
            strat = Model.Strategy('Monotone', sig);
            strat.TransactionCost = 0;
            strat.setEntryRule('SMA_1_X_SMA_2', 1);
            strat.setExitRule('SMA_1_X_SMA_2', -1);
        end

        function strat = makeDrawdownStrategy()
        % prices=[100;110;120;108;132], no cost, SMA_1 X SMA_2 crossover.
        %   SMA_1 = [100;110;120;108;132]
        %   SMA_2 = [NaN;105;115;114;120]
        %   cross = [0;+1;+1;-1;+1]
        %   decision=[0;1;1;0;1], posLag=[0;0;1;1;0]
        %   ret      = [NaN;0.1;1/11;-1/10;2/9]
        %   stratRet = [0;0;1/11;-1/10;0]   (zero cost)
        %   equity   = [1e5;1e5;1e5*12/11;1e5*54/55;1e5*54/55]
        %   MaxDrawdown = -1/10,  ProfitFactor = 10/11
            md   = Tests.TestStrategy.makeMarketData([100;110;120;108;132]);
            sig  = Model.Signal(md);
            sig.addSMA(1);
            sig.addSMA(2);
            sig.addCrossoverSignal('SMA_1', 'SMA_2');
            strat = Model.Strategy('Drawdown', sig);
            strat.TransactionCost = 0;
            strat.setEntryRule('SMA_1_X_SMA_2', 1);
            strat.setExitRule('SMA_1_X_SMA_2', -1);
        end

        function md = makeMarketData(closePrices)
            n  = numel(closePrices);
            t  = datetime('2020-01-01','TimeZone','America/New_York') ...
                 + caldays(0:n-1)';
            tt = timetable(t, closePrices, closePrices, closePrices, ...
                           closePrices, ones(n,1) * 1e6, ...
                           'VariableNames', ...
                           {'Open','High','Low','Close','Volume'});
            md = Model.MarketData('TEST');
            md.loadFromTimetable(tt, 'test');
        end

    end
end
