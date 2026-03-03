classdef MarketData < Model.BaseModel
% MarketData  Handle class that owns raw OHLCV price data.
%
%   Stores market data as a timetable with columns:
%       Open, High, Low, Close, Volume
%   Row times are datetime values with timezone 'America/New_York'.
%
%   Usage:
%       md = Model.MarketData('AAPL');
%       md.loadFromFile('AAPL_daily.csv');
%       tt = md.getPrices('2020-01-01', '2023-12-31');

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Ticker symbol.
        Ticker (1,1) string = ""

        % Primary timetable: columns Open High Low Close Volume.
        % RowTimes are datetime with TimeZone = 'America/New_York'.
        Prices timetable = timetable.empty

        % Metadata captured at load time.
        Source    (1,1) string   = ""
        LoadedAt  (1,1) datetime = NaT
    end

    properties (Dependent)
        % Number of rows in the price timetable.
        NumBars (1,1) double
        % Date range [startDate, endDate] as datetime row vector.
        DateRange (1,2) datetime
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = MarketData(ticker)
        % MarketData  Constructor.
        %   obj = Model.MarketData('AAPL')
            arguments
                ticker (1,1) string = "UNKNOWN"
            end
            obj = obj@Model.BaseModel("MarketData:" + ticker);
            obj.Ticker = upper(ticker);
        end

        % -------------------------------------------------------------- %
        function loadFromFile(obj, filePath)
        % loadFromFile  Import OHLCV data from a CSV file.
        %
        %   Expected CSV columns (case-insensitive):
        %       Date, Open, High, Low, Close, Volume
        %
        %   obj.loadFromFile('data/AAPL_daily.csv')
            arguments
                obj
                filePath (1,1) string
            end
            if ~isfile(filePath)
                error('SignalBuilder:MarketData:fileNotFound', ...
                    'File not found: %s', filePath);
            end
            try
                raw = readtimetable(filePath, ...
                    'RowTimes', 'Date', ...
                    'TextType', 'string');
            catch ME
                error('SignalBuilder:MarketData:readError', ...
                    'Failed to read %s: %s', filePath, ME.message);
            end
            obj.setPrices(raw, filePath);
        end

        % -------------------------------------------------------------- %
        function loadFromTimetable(obj, tt, source)
        % loadFromTimetable  Assign an existing timetable as price data.
        %
        %   obj.loadFromTimetable(myTimetable, 'Bloomberg')
            arguments
                obj
                tt timetable
                source (1,1) string = "manual"
            end
            obj.setPrices(tt, source);
        end

        % -------------------------------------------------------------- %
        function tt = getPrices(obj, startDate, endDate)
        % getPrices  Return the Prices timetable, optionally date-filtered.
        %
        %   tt = obj.getPrices()                       % all rows
        %   tt = obj.getPrices('2022-01-01','2023-12-31')
            arguments
                obj
                startDate = []
                endDate   = []
            end
            if isempty(obj.Prices)
                error('SignalBuilder:MarketData:noData', ...
                    'No price data loaded for %s.', obj.Ticker);
            end
            tt = obj.Prices;
            if ~isempty(startDate)
                t0 = datetime(startDate, 'TimeZone', 'America/New_York');
                tt = tt(tt.Time >= t0, :);
            end
            if ~isempty(endDate)
                t1 = datetime(endDate, 'TimeZone', 'America/New_York');
                tt = tt(tt.Time <= t1, :);
            end
        end

        % -------------------------------------------------------------- %
        function tt = getReturns(obj, method)
        % getReturns  Compute and return simple or log returns timetable.
        %
        %   tt = obj.getReturns('simple')   % default
        %   tt = obj.getReturns('log')
            arguments
                obj
                method (1,1) string {mustBeMember(method, ...
                    ["simple","log"])} = "simple"
            end
            obj.requireData();
            close = obj.Prices.Close;
            if method == "simple"
                ret = [NaN; diff(close) ./ close(1:end-1)];
            else
                ret = [NaN; diff(log(close))];
            end
            tt = timetable(obj.Prices.Time, ret, ...
                'VariableNames', {'Return'});
            tt.Properties.Description = obj.Ticker + " " + method + " returns";
        end

        % -------------------------------------------------------------- %
        % Dependent getters
        function n = get.NumBars(obj)
            n = height(obj.Prices);
        end

        function dr = get.DateRange(obj)
            if isempty(obj.Prices)
                dr = [NaT NaT];
            else
                dr = [obj.Prices.Time(1), obj.Prices.Time(end)];
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function setPrices(obj, tt, source)
            requiredVars = ["Open","High","Low","Close","Volume"];
            % Case-insensitive column normalisation
            tt.Properties.VariableNames = ...
                cellfun(@(v) obj.normaliseColName(v), ...
                tt.Properties.VariableNames, 'UniformOutput', false);
            Model.BaseModel.validateTimetable(tt, requiredVars);
            % Enforce timezone
            tt.Properties.DimensionNames{1} = 'Time';
            if ~strcmp(tt.Properties.RowTimes.TimeZone, 'America/New_York')
                tt.Properties.RowTimes.TimeZone = 'America/New_York';
            end
            tt = sortrows(tt);
            obj.Prices   = tt;
            obj.Source   = string(source);
            obj.LoadedAt = datetime('now', 'TimeZone', 'local');
            obj.notifyChanged();
        end

        function requireData(obj)
            if isempty(obj.Prices)
                error('SignalBuilder:MarketData:noData', ...
                    'No price data loaded for %s.', obj.Ticker);
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)
        function name = normaliseColName(name)
            % containers.Map used for R2021b compatibility (dictionary R2022a+)
            map = containers.Map( ...
                {'date','open','high','low','close','volume','adj close','adj_close'}, ...
                {'Time','Open','High','Low','Close','Volume','Close','Close'});
            key = lower(strtrim(char(name)));
            if isKey(map, key)
                name = map(key);
            else
                % Title-case unknown columns
                name = [upper(name(1)), name(2:end)];
            end
        end
    end
end
