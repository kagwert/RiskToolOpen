classdef DataController < Controller.BaseController
% DataController  Manages loading and refreshing MarketData models.
%
%   Owns one or more MarketData handle objects, coordinates file loading,
%   and notifies dependents (e.g. StrategyController) via events.
%
%   Usage:
%       dc = Controller.DataController();
%       dc.init();
%       dc.loadTicker('AAPL', 'data/AAPL.csv');
%       md = dc.getMarketData('AAPL');

    % ------------------------------------------------------------------ %
    events
        % Fired when any MarketData model is updated.
        DataLoaded
    end

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Map: ticker (string) -> Model.MarketData handle.
        DataStore containers.Map
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = DataController()
        % DataController  Constructor.
            obj = obj@Controller.BaseController('DataController');
            obj.DataStore = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        % -------------------------------------------------------------- %
        function init(obj)
        % init  Prepare the controller (nothing to wire at construction).
            obj.logInfo('DataController ready.');
        end

        % -------------------------------------------------------------- %
        function run(obj)
        % run  No-op for DataController — data loaded on demand.
            obj.logInfo('DataController running (awaiting loadTicker calls).');
        end

        % -------------------------------------------------------------- %
        function loadTicker(obj, ticker, filePath)
        % loadTicker  Load OHLCV data from a CSV file for a given ticker.
        %
        %   dc.loadTicker('SPY', 'data/SPY_daily.csv')
            arguments
                obj
                ticker   (1,1) string
                filePath (1,1) string
            end
            ticker = upper(ticker);
            if ~isKey(obj.DataStore, char(ticker))
                md = Model.MarketData(ticker);
                obj.DataStore(char(ticker)) = md;
                obj.addManagedListener(md, 'Changed', ...
                    @(~,~) obj.onDataChanged(ticker));
            end
            md = obj.DataStore(char(ticker));
            obj.logInfo('Loading %s from %s ...', ticker, filePath);
            md.loadFromFile(filePath);
            obj.logInfo('%s loaded: %d bars, %s to %s.', ...
                ticker, md.NumBars, ...
                datestr(md.DateRange(1), 'yyyy-mm-dd'), ...
                datestr(md.DateRange(2), 'yyyy-mm-dd'));
            notify(obj, 'DataLoaded');
        end

        % -------------------------------------------------------------- %
        function loadTickerFromTimetable(obj, ticker, tt, source)
        % loadTickerFromTimetable  Load data directly from a timetable.
        %
        %   dc.loadTickerFromTimetable('SPY', myTT, 'Bloomberg')
            arguments
                obj
                ticker (1,1) string
                tt     timetable
                source (1,1) string = "manual"
            end
            ticker = upper(ticker);
            if ~isKey(obj.DataStore, char(ticker))
                md = Model.MarketData(ticker);
                obj.DataStore(char(ticker)) = md;
                obj.addManagedListener(md, 'Changed', ...
                    @(~,~) obj.onDataChanged(ticker));
            end
            md = obj.DataStore(char(ticker));
            md.loadFromTimetable(tt, source);
            notify(obj, 'DataLoaded');
        end

        % -------------------------------------------------------------- %
        function md = getMarketData(obj, ticker)
        % getMarketData  Retrieve the MarketData handle for a ticker.
        %
        %   md = dc.getMarketData('AAPL')
            arguments
                obj
                ticker (1,1) string
            end
            ticker = upper(ticker);
            if ~isKey(obj.DataStore, char(ticker))
                error('SignalBuilder:DataController:notFound', ...
                    'No data loaded for ticker "%s".', ticker);
            end
            md = obj.DataStore(char(ticker));
        end

        % -------------------------------------------------------------- %
        function tickers = listTickers(obj)
        % listTickers  Return array of loaded ticker strings.
            tickers = string(keys(obj.DataStore));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function onDataChanged(obj, ticker)
            obj.logInfo('MarketData changed: %s', ticker);
        end
    end
end
