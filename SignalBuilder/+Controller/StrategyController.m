classdef StrategyController < Controller.BaseController
% StrategyController  Orchestrates signal computation, strategy backtest,
%                     and chart/summary rendering for one ticker.
%
%   This is the primary application controller.  It owns:
%       - A DataController (for market data)
%       - A Signal model (computed from MarketData)
%       - A Strategy model (backtested against signals)
%       - A ChartView and a StrategyView
%
%   Usage:
%       sc = Controller.StrategyController('SPY', 'data/SPY.csv');
%       sc.init();
%       sc.run();

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        Ticker      (1,1) string = ""
        FilePath    (1,1) string = ""

        % Owned model handles
        DataCtrl    Controller.DataController
        Signal      Model.Signal
        Strategy    Model.Strategy

        % Owned view handles
        ChartView    View.ChartView
        StrategyView View.StrategyView
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = StrategyController(ticker, filePath)
        % StrategyController  Constructor.
        %
        %   sc = Controller.StrategyController('SPY', 'data/SPY.csv')
        %
        %   Call init() then run() to execute the full pipeline.
            arguments
                ticker   (1,1) string
                filePath (1,1) string = ""
            end
            obj = obj@Controller.BaseController('StrategyController:' + upper(ticker));
            obj.Ticker   = upper(ticker);
            obj.FilePath = filePath;
        end

        % -------------------------------------------------------------- %
        function init(obj)
        % init  Instantiate all models and views, wire event listeners.
        %
        %   Must be called once before run().
            % --- Data layer ---
            obj.DataCtrl = Controller.DataController();
            obj.DataCtrl.init();

            % --- Views ---
            obj.ChartView    = View.ChartView(obj.Ticker + " Price & Signals");
            obj.StrategyView = View.StrategyView(obj.Ticker + " Strategy Summary");

            obj.logInfo('Initialised for ticker %s.', obj.Ticker);
        end

        % -------------------------------------------------------------- %
        function run(obj)
        % run  Execute the full pipeline: load → signals → backtest → render.
        %
        %   Uses the default MA-crossover strategy as an illustrative example.
        %   Override configureSigals() / configureStrategy() to customise.
            obj.requireInit();

            % 1. Load price data
            obj.loadData();

            % 2. Build Signal model and add indicators
            md           = obj.DataCtrl.getMarketData(obj.Ticker);
            obj.Signal   = Model.Signal(md);
            obj.configureSignals();

            % 3. Build Strategy model and run backtest
            obj.Strategy = Model.Strategy(obj.Ticker + '_Default', obj.Signal);
            obj.configureStrategy();
            obj.Strategy.run();

            % 4. Render views
            obj.renderCharts();

            obj.logInfo('Pipeline complete. Metrics:');
            disp(obj.Strategy);
        end

        % -------------------------------------------------------------- %
        function setFilePath(obj, filePath)
        % setFilePath  Update the CSV file path before calling run().
            obj.FilePath = filePath;
        end

        % -------------------------------------------------------------- %
        function showCharts(obj)
        % showCharts  Bring both chart windows to the front.
            obj.ChartView.show();
            obj.StrategyView.show();
        end

        % -------------------------------------------------------------- %
        function shutdown(obj)
        % shutdown  Close views and release all listeners.
            if ~isempty(obj.ChartView) && isvalid(obj.ChartView)
                obj.ChartView.close();
            end
            if ~isempty(obj.StrategyView) && isvalid(obj.StrategyView)
                obj.StrategyView.close();
            end
            shutdown@Controller.BaseController(obj);
            obj.logInfo('Shut down.');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function loadData(obj)
        % loadData  Load data from FilePath, or generate synthetic data if empty.
            if obj.FilePath == ""
                obj.logWarn('No file path set — using synthetic data for demo.');
                tt = obj.makeSyntheticData();
                obj.DataCtrl.loadTickerFromTimetable(obj.Ticker, tt, 'synthetic');
            else
                obj.DataCtrl.loadTicker(obj.Ticker, obj.FilePath);
            end
        end

        function configureSignals(obj)
        % configureSignals  Add default indicators to the Signal model.
        %   Override this method in a subclass to customise indicators.
            obj.Signal.addSMA(20);
            obj.Signal.addSMA(50);
            obj.Signal.addEMA(12);
            obj.Signal.addEMA(26);
            obj.Signal.addRSI(14);
            obj.Signal.addCrossoverSignal('SMA_20', 'SMA_50');
        end

        function configureStrategy(obj)
        % configureStrategy  Define default entry/exit rules.
        %   Override this method in a subclass to customise rules.
            obj.Strategy.setEntryRule('SMA_20_X_SMA_50', 1);
            obj.Strategy.setExitRule('SMA_20_X_SMA_50', -1);
        end

        function renderCharts(obj)
        % renderCharts  Push model data into views and render.
            md = obj.DataCtrl.getMarketData(obj.Ticker);

            % Price + signals chart
            obj.ChartView.setPriceData(md.getPrices());
            obj.ChartView.setSignalData( ...
                obj.Signal.getSignals(["SMA_20","SMA_50"]));
            obj.ChartView.setEquityData(obj.Strategy.BacktestResults);
            obj.ChartView.render();
            obj.ChartView.show();

            % Strategy summary
            obj.StrategyView.setResults( ...
                obj.Strategy.BacktestResults, ...
                obj.Strategy.Metrics, ...
                obj.Strategy.StrategyName);
            obj.StrategyView.render();
            obj.StrategyView.show();
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function requireInit(obj)
            if isempty(obj.DataCtrl) || ~isvalid(obj.DataCtrl)
                error('SignalBuilder:StrategyController:notInitialised', ...
                    'Call init() before run().');
            end
        end

        function tt = makeSyntheticData(obj)
        % makeSyntheticData  Create 5 years of synthetic daily OHLCV data.
            rng(42);
            nDays  = 252 * 5;
            dates  = datetime('2019-01-02', 'TimeZone', 'America/New_York') + ...
                     caldays(0 : nDays - 1);
            % Business days only (approx)
            dates  = dates(weekday(dates) >= 2 & weekday(dates) <= 6);
            n      = numel(dates);
            ret    = 0.0003 + 0.015 * randn(n, 1);
            close  = 100 * cumprod(1 + ret);
            noise  = 0.005 * close;
            open   = close .* (1 + 0.002 * randn(n,1));
            high   = close + abs(noise .* randn(n,1));
            low    = close - abs(noise .* randn(n,1));
            vol    = round(1e6 * (1 + 0.5 * abs(randn(n,1))));
            tt = timetable(dates(:), open, high, low, close, vol, ...
                'VariableNames', {'Open','High','Low','Close','Volume'});
            tt.Properties.DimensionNames{1} = 'Time';
            obj.logInfo('Synthetic data created: %d bars for %s.', n, obj.Ticker);
        end
    end
end
