classdef TestMarketData < matlab.unittest.TestCase
% TestMarketData  Unit tests for Model.MarketData.
%
%   Tests cover: construction, timetable loading, timezone enforcement,
%   date filtering, simple and log return mathematics, and error paths.
%
%   Run:  results = runtests('+Tests/TestMarketData.m'); table(results)

    % ------------------------------------------------------------------ %
    methods (Test)

        %% --- Construction and basic properties ---

        function testNumBarsEmptyModel(tc)
            % A freshly constructed MarketData has no bars loaded.
            md = Model.MarketData('EMPTY');
            tc.verifyEqual(md.NumBars, 0);
        end

        function testTickerIsUpperCased(tc)
            md = Model.MarketData('aapl');
            tc.verifyEqual(md.Ticker, "AAPL");
        end

        function testDateRangeEmptyReturnsNaT(tc)
            md = Model.MarketData('X');
            dr = md.DateRange;
            tc.verifyTrue(isnat(dr(1)));
            tc.verifyTrue(isnat(dr(2)));
        end

        %% --- Loading from timetable ---

        function testLoadFromTimetable_NumBars(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            tc.verifyEqual(md.NumBars, 3);
        end

        function testLoadFromTimetable_TickerPreserved(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110], 'FOO');
            tc.verifyEqual(md.Ticker, "FOO");
        end

        function testLoadFromTimetable_HasRequiredColumns(tc)
            md   = Tests.TestMarketData.makeMarketData([100; 110]);
            tt   = md.getPrices();
            vars = string(tt.Properties.VariableNames);
            tc.verifyTrue(all(ismember( ...
                ["Open","High","Low","Close","Volume"], vars)));
        end

        function testLoadFromTimetable_TimezoneIsNewYork(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110]);
            tt = md.getPrices();
            tc.verifyEqual(tt.Properties.RowTimes.TimeZone, ...
                'America/New_York');
        end

        function testLoadFromTimetable_RowsAreSorted(tc)
            % Even if inserted in reverse the result must be ascending.
            n  = 5;
            t  = datetime('2020-01-05','TimeZone','America/New_York') ...
                 - caldays(0:n-1)';   % reverse order
            p  = (100:5:120)';
            tt = timetable(t, p, p, p, p, ones(n,1)*1e6, ...
                'VariableNames', {'Open','High','Low','Close','Volume'});
            md = Model.MarketData('SORT');
            md.loadFromTimetable(tt, 'test');
            times = md.Prices.Time;
            tc.verifyTrue(all(diff(times) > 0));
        end

        %% --- DateRange ---

        function testDateRangeLength(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            dr = md.DateRange;
            tc.verifyEqual(numel(dr), 2);
        end

        function testDateRangeStartBeforeEnd(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            dr = md.DateRange;
            tc.verifyLessThan(dr(1), dr(2));
        end

        %% --- getPrices ---

        function testGetPricesReturnsAllRows(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            tt = md.getPrices();
            tc.verifyEqual(height(tt), 3);
        end

        function testGetPricesStartDateFilter(tc)
            % Base: 3 bars on Jan 1-3. Filter from Jan 2 → expect 2 bars.
            md  = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            t0  = md.DateRange(1) + caldays(1);
            tt  = md.getPrices(datestr(t0, 'yyyy-mm-dd'));
            tc.verifyEqual(height(tt), 2);
        end

        function testGetPricesEndDateFilter(tc)
            md  = Tests.TestMarketData.makeMarketData([100; 110; 120]);
            t1  = md.DateRange(2) - caldays(1);
            tt  = md.getPrices([], datestr(t1, 'yyyy-mm-dd'));
            tc.verifyEqual(height(tt), 2);
        end

        %% --- Simple returns mathematics ---

        function testSimpleReturns_FirstIsNaN(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110]);
            tt = md.getReturns('simple');
            tc.verifyTrue(isnan(tt.Return(1)));
        end

        function testSimpleReturns_Formula(tc)
            % r_t = (P_t - P_{t-1}) / P_{t-1}
            md       = Tests.TestMarketData.makeMarketData([100; 110; 121]);
            tt       = md.getReturns('simple');
            expected = [(110-100)/100; (121-110)/110];
            tc.verifyEqual(tt.Return(2:end), expected, 'AbsTol', 1e-14);
        end

        function testSimpleReturns_KnownValue(tc)
            % 10 % single-step gain
            md = Tests.TestMarketData.makeMarketData([100; 110]);
            tt = md.getReturns('simple');
            tc.verifyEqual(tt.Return(2), 0.1, 'AbsTol', 1e-14);
        end

        function testSimpleReturns_Length(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110; 120; 130]);
            tt = md.getReturns('simple');
            tc.verifyEqual(height(tt), md.NumBars);
        end

        %% --- Log returns mathematics ---

        function testLogReturns_FirstIsNaN(tc)
            md = Tests.TestMarketData.makeMarketData([100; 110]);
            tt = md.getReturns('log');
            tc.verifyTrue(isnan(tt.Return(1)));
        end

        function testLogReturns_Formula(tc)
            % r_t = log(P_t / P_{t-1})
            md       = Tests.TestMarketData.makeMarketData([100; 110; 121]);
            tt       = md.getReturns('log');
            expected = [log(110/100); log(121/110)];
            tc.verifyEqual(tt.Return(2:end), expected, 'AbsTol', 1e-14);
        end

        function testLogLessThanSimpleForPositiveReturn(tc)
            % log(1+r) < r for r > 0  (Jensen's inequality)
            md     = Tests.TestMarketData.makeMarketData([100; 200]);
            simple = md.getReturns('simple');
            lg     = md.getReturns('log');
            tc.verifyGreaterThan(simple.Return(2), lg.Return(2));
        end

        function testLogEqualsSimpleForInfinitesimalReturn(tc)
            % For very small returns log(1+r) ≈ r
            md     = Tests.TestMarketData.makeMarketData([100; 100.001]);
            simple = md.getReturns('simple');
            lg     = md.getReturns('log');
            tc.verifyEqual(simple.Return(2), lg.Return(2), 'AbsTol', 1e-7);
        end

        %% --- Error paths ---

        function testFileNotFoundError(tc)
            md = Model.MarketData('X');
            tc.verifyError( ...
                @() md.loadFromFile('no_such_file_xyz.csv'), ...
                'SignalBuilder:MarketData:fileNotFound');
        end

        function testGetPricesNoDataError(tc)
            md = Model.MarketData('EMPTY');
            tc.verifyError(@() md.getPrices(), ...
                'SignalBuilder:MarketData:noData');
        end

        function testGetReturnsNoDataError(tc)
            md = Model.MarketData('EMPTY');
            tc.verifyError(@() md.getReturns(), ...
                'SignalBuilder:MarketData:noData');
        end

        function testLoadFromTimetableMissingColumnError(tc)
            % Supply a timetable without 'Volume' — should throw.
            t  = datetime('2020-01-01','TimeZone','America/New_York');
            tt = timetable(t, 100, 105, 95, 102, ...
                'VariableNames', {'Open','High','Low','Close'});
            md = Model.MarketData('NOCOL');
            tc.verifyError( ...
                @() md.loadFromTimetable(tt), ...
                'SignalBuilder:BaseModel:missingColumns');
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

    end
end
