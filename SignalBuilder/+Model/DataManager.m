classdef DataManager < Model.BaseModel
% DataManager  Handle class for multi-source data acquisition and caching.
%
%   Manages fetching, caching, and standardising time-series data from:
%       - FRED          (Federal Reserve Economic Data) via webread + free key
%       - Alpha Vantage daily-adjusted OHLCV             via REST API + free key
%       - Stooq         daily OHLCV                      via CSV  (no key needed)
%       - Yahoo Finance                                   via unofficial JSON API
%       - Bloomberg                                       via blp() (placeholder)
%
%   Persistence layer:
%       - SQLite database  (cache/metadata.db)   for series registry
%       - .mat files       (cache/mat/<id>.mat)  for bulk timetable storage
%
%   All returned timetables are synchronised, timezone-aware, and have
%   missing values handled via interpolation or forward-fill.
%
%   Usage:
%       dm = Model.DataManager();
%       dm.init();
%
%       % Fetch (or load from cache) a FRED series
%       tt = dm.fetch_fred('DGS10');           % 10-yr Treasury yield
%
%       % Fetch Yahoo equity prices
%       tt = dm.fetch_yahoo('AAPL');
%
%       % Fetch Bloomberg (requires Datafeed Toolbox + active session)
%       tt = dm.fetch_bloomberg('SPX Index', 'PX_LAST');
%
%       % Incremental refresh — only downloads the delta
%       dm.update_data('DGS10');
%
%       % Return a synchronised multi-series timetable
%       tt = dm.getSynchronised({'DGS10','AAPL'}, 'last');

    % ------------------------------------------------------------------ %
    %  Constants
    % ------------------------------------------------------------------ %
    properties (Constant, Access = private)
        % FRED base URL
        FRED_BASE_URL  = 'https://api.stlouisfed.org/fred/series/observations'
        % Yahoo Finance JSON base URL
        YAHOO_BASE_URL = 'https://query1.finance.yahoo.com/v8/finance/chart/'
        % Alpha Vantage REST base URL
        ALPHAVANTAGE_BASE_URL = 'https://www.alphavantage.co/query'
        % Stooq CSV download base URL
        STOOQ_BASE_URL = 'https://stooq.com/q/d/l/'
        % Default local cache directory (relative to project root)
        DEFAULT_CACHE_DIR = 'cache'
        % SQLite DB file name inside cache dir
        DB_FILE        = 'metadata.db'
        % Subdirectory for .mat files
        MAT_SUBDIR     = 'mat'
    end

    % ------------------------------------------------------------------ %
    %  Properties
    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Absolute path to the cache root directory.
        CacheDir  (1,1) string

        % Absolute path to the SQLite metadata database.
        DbPath    (1,1) string

        % sqlite connection object (set in init()).
        Db        % sqlite | []

        % Registry: seriesId -> struct with LastDate, Source, MatPath.
        % Populated from DB at init; kept in-memory for fast lookup.
        Registry  containers.Map
    end

    properties
        % FRED API key.  Set here or export env var FRED_API_KEY.
        FredApiKey  (1,1) string = "8bf43d6978221c9897d819ded36bab05"

        % Alpha Vantage API key.  Free key from:
        %   https://www.alphavantage.co/support/#api-key
        % Set here or export env var ALPHAVANTAGE_API_KEY.
        AlphaVantageApiKey  (1,1) string = ""

        % Missing value fill method: 'linear' | 'previous' | 'next' | 'none'.
        FillMethod  (1,1) string ...
            {mustBeMember(FillMethod, ["linear","previous","next","none"])} ...
            = "previous"

        % Request timeout in seconds for webread calls.
        TimeoutSec  (1,1) double {mustBePositive} = 30

        % Whether to print progress messages.
        Verbose     (1,1) logical = true
    end

    % ------------------------------------------------------------------ %
    %  Lifecycle
    % ------------------------------------------------------------------ %
    methods
        function obj = DataManager(cacheDir)
        % DataManager  Constructor.
        %
        %   dm = Model.DataManager()               % uses './cache'
        %   dm = Model.DataManager('/my/cache')    % custom path
            arguments
                cacheDir (1,1) string = ""
            end
            obj = obj@Model.BaseModel("DataManager");

            if cacheDir == ""
                % Resolve relative to the directory of this file
                here = fileparts(mfilename('fullpath'));
                cacheDir = fullfile(fileparts(here), ...
                    Model.DataManager.DEFAULT_CACHE_DIR);
            end
            obj.CacheDir = cacheDir;
            obj.DbPath   = fullfile(cacheDir, Model.DataManager.DB_FILE);
            obj.Registry = containers.Map('KeyType','char','ValueType','any');
        end

        % -------------------------------------------------------------- %
        function init(obj)
        % init  Create cache directories and open/initialise the SQLite DB.
        %
        %   Must be called before any fetch or update method.
            obj.ensureDirs();
            obj.openDb();
            obj.loadRegistry();
            obj.resolveFredKey();
            obj.resolveAvKey();
            obj.log('DataManager ready. Cache: %s', obj.CacheDir);
        end

        % -------------------------------------------------------------- %
        function delete(obj)
        % delete  Destructor — close DB connection.
            obj.closeDb();
        end
    end

    % ------------------------------------------------------------------ %
    %  Public fetch methods
    % ------------------------------------------------------------------ %
    methods
        function tt = fetch_fred(obj, seriesId, startDate, endDate)
        % fetch_fred  Fetch a FRED series, using cache when available.
        %
        %   tt = dm.fetch_fred('DGS10')
        %   tt = dm.fetch_fred('CPIAUCSL', '2010-01-01', '2023-12-31')
        %
        %   Returns a timetable with column matching seriesId.
        %   RowTimes are datetime with TimeZone 'UTC'.
            arguments
                obj
                seriesId  (1,1) string
                startDate (1,1) string = ""
                endDate   (1,1) string = ""
            end
            obj.requireInit();
            cacheKey = "FRED_" + upper(seriesId);

            % Check cache freshness
            [cached, lastDate] = obj.loadFromCache(cacheKey);
            if ~isempty(cached) && isempty(startDate)
                obj.log('Cache hit for %s (last: %s)', seriesId, ...
                    datestr(lastDate, 'yyyy-mm-dd'));
                tt = obj.standardise(cached, cacheKey);
                return;
            end

            % Determine effective start date for API call
            if ~isempty(cached) && isempty(startDate)
                apiStart = datestr(lastDate + caldays(1), 'yyyy-mm-dd');
            elseif startDate ~= ""
                apiStart = char(startDate);
            else
                apiStart = '1900-01-01';
            end
            apiEnd = obj.resolveEndDate(endDate);

            obj.log('Fetching FRED:%s [%s -> %s]', seriesId, apiStart, apiEnd);
            raw = obj.callFredApi(seriesId, apiStart, apiEnd);

            if isempty(raw)
                if ~isempty(cached)
                    tt = obj.standardise(cached, cacheKey);
                    return;
                end
                error('SignalBuilder:DataManager:noData', ...
                    'FRED returned no data for series "%s".', seriesId);
            end

            % Merge with cache and persist
            merged = obj.mergeAndPersist(cached, raw, cacheKey, 'FRED');
            tt = obj.standardise(merged, cacheKey);
        end

        % -------------------------------------------------------------- %
        function tt = fetch_yahoo(obj, ticker, startDate, endDate)
        % fetch_yahoo  Fetch daily OHLCV from Yahoo Finance (unofficial API).
        %
        %   tt = dm.fetch_yahoo('AAPL')
        %   tt = dm.fetch_yahoo('SPY', '2015-01-01', '2023-12-31')
        %
        %   Returns a timetable with columns Open High Low Close Volume
        %   (timezone 'America/New_York').
            arguments
                obj
                ticker    (1,1) string
                startDate (1,1) string = ""
                endDate   (1,1) string = ""
            end
            obj.requireInit();
            cacheKey = "YF_" + upper(ticker);

            [cached, lastDate] = obj.loadFromCache(cacheKey);
            if ~isempty(cached) && startDate == ""
                obj.log('Cache hit for %s (last: %s)', ticker, ...
                    datestr(lastDate, 'yyyy-mm-dd'));
                tt = obj.standardise(cached, cacheKey);
                return;
            end

            if ~isempty(cached) && startDate == ""
                t1Unix = posixtime(lastDate + caldays(1));
            elseif startDate ~= ""
                t1Unix = posixtime(datetime(startDate, 'TimeZone','UTC'));
            else
                t1Unix = posixtime(datetime('1970-01-02','TimeZone','UTC'));
            end
            t2Unix = posixtime(datetime(obj.resolveEndDate(endDate), ...
                'TimeZone','UTC'));

            obj.log('Fetching Yahoo:%s [period1=%d period2=%d]', ...
                ticker, t1Unix, t2Unix);
            raw = obj.callYahooApi(ticker, t1Unix, t2Unix);

            if isempty(raw)
                if ~isempty(cached)
                    tt = obj.standardise(cached, cacheKey);
                    return;
                end
                error('SignalBuilder:DataManager:noData', ...
                    'Yahoo returned no data for ticker "%s".', ticker);
            end

            merged = obj.mergeAndPersist(cached, raw, cacheKey, 'Yahoo');
            tt = obj.standardise(merged, cacheKey);
        end

        % -------------------------------------------------------------- %
        function tt = fetch_bloomberg(obj, security, field, startDate, endDate)
        % fetch_bloomberg  Fetch data from Bloomberg (requires Datafeed Toolbox).
        %
        %   tt = dm.fetch_bloomberg('SPX Index', 'PX_LAST')
        %   tt = dm.fetch_bloomberg('AAPL US Equity', 'PX_LAST', ...
        %                           '2020-01-01', '2023-12-31')
        %
        %   PLACEHOLDER: Replace the blp() call body with your connection
        %   setup if you have an active Bloomberg terminal session.
            arguments
                obj
                security  (1,1) string
                field     (1,1) string = "PX_LAST"
                startDate (1,1) string = ""
                endDate   (1,1) string = ""
            end
            obj.requireInit();

            % --- Bloomberg connection (placeholder) -------------------
            if ~obj.isToolboxAvailable('Datafeed Toolbox')
                error('SignalBuilder:DataManager:noToolbox', ...
                    ['Datafeed Toolbox is required for Bloomberg access. ' ...
                    'Use fetch_fred() or fetch_yahoo() instead.']);
            end

            cacheKey = "BBG_" + upper(strrep(security,' ','_')) + "_" + field;
            [cached, lastDate] = obj.loadFromCache(cacheKey);

            if startDate == "" && ~isempty(cached)
                apiStart = datestr(lastDate + caldays(1), 'mm/dd/yyyy');
            elseif startDate ~= ""
                apiStart = datestr(datetime(startDate), 'mm/dd/yyyy');
            else
                apiStart = '01/01/2000';
            end
            apiEnd = datestr(datetime(obj.resolveEndDate(endDate)), 'mm/dd/yyyy');

            obj.log('Fetching Bloomberg:%s field=%s [%s -> %s]', ...
                security, field, apiStart, apiEnd);

            try
                % ---- Replace this block with your blp session setup ----
                % c    = blp();                         % open connection
                % raw  = history(c, security, field, apiStart, apiEnd);
                % close(c);
                % tt_raw = timetable(datetime(raw(:,1),'ConvertFrom','datenum',...
                %              'TimeZone','UTC'), raw(:,2), ...
                %              'VariableNames', {field});
                % --------------------------------------------------------
                error('SignalBuilder:DataManager:bbgPlaceholder', ...
                    'Bloomberg fetch is a placeholder. ' + ...
                    'Wire your blp() session in DataManager.fetch_bloomberg().');
            catch ME
                rethrow(ME);
            end

            % merged = obj.mergeAndPersist(cached, tt_raw, cacheKey, 'Bloomberg');
            % tt = obj.standardise(merged, cacheKey);
            tt = timetable.empty;   % reached only when above block is wired
        end

        % -------------------------------------------------------------- %
        function tt = fetch_alphavantage(obj, ticker, startDate, endDate)
        % fetch_alphavantage  Fetch daily adjusted OHLCV from Alpha Vantage.
        %
        %   tt = dm.fetch_alphavantage('SPY')
        %   tt = dm.fetch_alphavantage('AAPL', '2015-01-01', '2024-01-01')
        %
        %   Returns a timetable with columns Open High Low Close Volume
        %   (timezone 'America/New_York', split/dividend-adjusted Close).
        %
        %   Free API key: https://www.alphavantage.co/support/#api-key
        %   Set dm.AlphaVantageApiKey or env var ALPHAVANTAGE_API_KEY.
            arguments
                obj
                ticker    (1,1) string
                startDate (1,1) string = ""
                endDate   (1,1) string = ""
            end
            obj.requireInit();
            cacheKey = "AV_" + upper(ticker);

            [cached, lastDate] = obj.loadFromCache(cacheKey);
            if ~isempty(cached) && startDate == ""
                obj.log('Cache hit for AV:%s (last: %s)', ticker, ...
                    datestr(lastDate, 'yyyy-mm-dd'));
                tt = obj.standardise(cached, cacheKey);
                return;
            end

            obj.log('Fetching AlphaVantage:%s [outputsize=compact, ~100 bars]', ticker);
            raw = obj.callAlphaVantageApi(ticker, char(startDate), ...
                obj.resolveEndDate(endDate));

            if isempty(raw)
                if ~isempty(cached)
                    tt = obj.standardise(cached, cacheKey);
                    return;
                end
                error('SignalBuilder:DataManager:noData', ...
                    'Alpha Vantage returned no data for ticker "%s".', ticker);
            end

            merged = obj.mergeAndPersist(cached, raw, cacheKey, 'AlphaVantage');
            tt = obj.standardise(merged, cacheKey);
        end

        % -------------------------------------------------------------- %
        function tt = fetch_stooq(obj, ticker, startDate, endDate)
        % fetch_stooq  Fetch daily OHLCV from Stooq (no API key required).
        %
        %   tt = dm.fetch_stooq('SPY')
        %   tt = dm.fetch_stooq('AAPL', '2000-01-01', '2024-01-01')
        %
        %   For US equities/ETFs the .US suffix is appended automatically
        %   ('SPY' → 'SPY.US').  Pass 'SPY.US' explicitly to override.
        %   Major indices: '^SPX' (S&P 500), '^NDX' (NASDAQ 100), '^DJI'.
        %
        %   Returns a timetable with columns Open High Low Close Volume
        %   (timezone 'America/New_York').
            arguments
                obj
                ticker    (1,1) string
                startDate (1,1) string = ""
                endDate   (1,1) string = ""
            end
            obj.requireInit();
            cacheKey = "STOOQ_" + upper(ticker);

            [cached, lastDate] = obj.loadFromCache(cacheKey);
            if ~isempty(cached) && startDate == ""
                obj.log('Cache hit for Stooq:%s (last: %s)', ticker, ...
                    datestr(lastDate, 'yyyy-mm-dd'));
                tt = obj.standardise(cached, cacheKey);
                return;
            end

            if ~isempty(cached)
                d1 = datestr(lastDate + caldays(1), 'yyyymmdd');
            elseif startDate ~= ""
                d1 = strrep(char(startDate), '-', '');
            else
                d1 = '19900101';
            end
            d2 = strrep(obj.resolveEndDate(endDate), '-', '');

            obj.log('Fetching Stooq:%s [%s to %s]', ticker, d1, d2);
            raw = obj.callStooqApi(ticker, d1, d2);

            if isempty(raw)
                if ~isempty(cached)
                    tt = obj.standardise(cached, cacheKey);
                    return;
                end
                error('SignalBuilder:DataManager:noData', ...
                    ['Stooq returned no data for ticker "%s". ' ...
                    'Check the ticker format (e.g. SPY or SPY.US).'], ticker);
            end

            merged = obj.mergeAndPersist(cached, raw, cacheKey, 'Stooq');
            tt = obj.standardise(merged, cacheKey);
        end

        % -------------------------------------------------------------- %
        function update_data(obj, seriesId)
        % update_data  Incremental refresh — only fetches data after last cache date.
        %
        %   Determines the data source from the registry and calls the
        %   appropriate fetch method with the cached last-date as startDate.
        %
        %   dm.update_data('DGS10')
        %   dm.update_data('AAPL')
            arguments
                obj
                seriesId (1,1) string
            end
            obj.requireInit();

            % Search registry for a matching cache key
            fredKey   = "FRED_"  + upper(seriesId);
            yahooKey  = "YF_"    + upper(seriesId);
            avKey     = "AV_"    + upper(seriesId);
            stooqKey  = "STOOQ_" + upper(seriesId);

            if isKey(obj.Registry, char(fredKey))
                rec = obj.Registry(char(fredKey));
                obj.log('Updating FRED:%s (last: %s)', seriesId, ...
                    datestr(rec.LastDate, 'yyyy-mm-dd'));
                obj.fetch_fred(seriesId, ...
                    datestr(rec.LastDate + caldays(1), 'yyyy-mm-dd'));

            elseif isKey(obj.Registry, char(yahooKey))
                rec = obj.Registry(char(yahooKey));
                obj.log('Updating Yahoo:%s (last: %s)', seriesId, ...
                    datestr(rec.LastDate, 'yyyy-mm-dd'));
                obj.fetch_yahoo(seriesId, ...
                    datestr(rec.LastDate + caldays(1), 'yyyy-mm-dd'));

            elseif isKey(obj.Registry, char(avKey))
                rec = obj.Registry(char(avKey));
                obj.log('Updating AlphaVantage:%s (last: %s)', seriesId, ...
                    datestr(rec.LastDate, 'yyyy-mm-dd'));
                obj.fetch_alphavantage(seriesId);   % always full pull; cache merges

            elseif isKey(obj.Registry, char(stooqKey))
                rec = obj.Registry(char(stooqKey));
                obj.log('Updating Stooq:%s (last: %s)', seriesId, ...
                    datestr(rec.LastDate, 'yyyy-mm-dd'));
                obj.fetch_stooq(seriesId, ...
                    datestr(rec.LastDate + caldays(1), 'yyyy-mm-dd'));

            else
                error('SignalBuilder:DataManager:unknownSeries', ...
                    'Series "%s" not in cache. Fetch it first.', seriesId);
            end
        end

        % -------------------------------------------------------------- %
        function tt = getSynchronised(obj, seriesIds, fillMethod)
        % getSynchronised  Return a multi-series synchronised timetable.
        %
        %   Loads each series from cache (must be fetched first) and
        %   synchronises on a union of all row times.
        %
        %   tt = dm.getSynchronised({'DGS10','AAPL'})
        %   tt = dm.getSynchronised({'DGS10','CPIAUCSL'}, 'linear')
            arguments
                obj
                seriesIds (1,:) cell
                fillMethod (1,1) string ...
                    {mustBeMember(fillMethod, ...
                    ["linear","previous","next","none","last"])} = "previous"
            end
            obj.requireInit();
            if fillMethod == "last"
                fillMethod = "previous";   % alias
            end

            ttList = cell(numel(seriesIds), 1);
            for k = 1 : numel(seriesIds)
                id  = string(seriesIds{k});
                key = obj.resolveKey(id);
                [tt_k, ~] = obj.loadFromCache(key);
                if isempty(tt_k)
                    error('SignalBuilder:DataManager:notCached', ...
                        'Series "%s" not in cache. Fetch it first.', id);
                end
                ttList{k} = tt_k;
            end

            % Synchronise on union of all row times
            result = ttList{1};
            for k = 2 : numel(ttList)
                result = synchronize(result, ttList{k}, ...
                    'union', 'fillwithconstant', NaN);
            end

            if fillMethod ~= "none"
                result = fillmissing(result, char(fillMethod));
            end
            tt = result;
        end

        % -------------------------------------------------------------- %
        function list = listCachedSeries(obj)
        % listCachedSeries  Return a table of all cached series metadata.
            obj.requireInit();
            keys_   = string(keys(obj.Registry));
            if isempty(keys_)
                list = table();
                return;
            end
            sources   = strings(numel(keys_), 1);
            lastDates = NaT(numel(keys_), 1);
            matPaths  = strings(numel(keys_), 1);
            for k = 1 : numel(keys_)
                rec = obj.Registry(char(keys_(k)));
                sources(k)   = rec.Source;
                lastDates(k) = rec.LastDate;
                matPaths(k)  = rec.MatPath;
            end
            list = table(keys_(:), sources, lastDates, matPaths, ...
                'VariableNames', {'CacheKey','Source','LastDate','MatPath'});
        end
    end

    % ------------------------------------------------------------------ %
    %  Private — API callers
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function tt = callFredApi(obj, seriesId, startDate, endDate)
        % callFredApi  HTTP GET to FRED observations endpoint.
        %
        %   NOTE: webread does not accept a params struct in R2021b;
        %   query parameters are embedded directly in the URL string.
            if obj.FredApiKey == ""
                error('SignalBuilder:DataManager:noApiKey', ...
                    ['FRED API key not set. Provide one via:\n' ...
                    '  dm.FredApiKey = ''your_key'';\n' ...
                    'Or set env var FRED_API_KEY before launching MATLAB.']);
            end
            opts = weboptions( ...
                'Timeout', obj.TimeoutSec, ...
                'ContentType', 'json');
            queryStr = sprintf( ...
                '?series_id=%s&observation_start=%s&observation_end=%s&api_key=%s&file_type=json&units=lin', ...
                char(seriesId), startDate, endDate, char(obj.FredApiKey));
            fullUrl = [char(Model.DataManager.FRED_BASE_URL) queryStr];
            try
                resp = webread(fullUrl, opts);
            catch ME
                error('SignalBuilder:DataManager:fredHttpError', ...
                    'FRED request failed: %s', ME.message);
            end
            if ~isfield(resp, 'observations') || isempty(resp.observations)
                tt = timetable.empty;
                return;
            end
            obs   = resp.observations;
            dates = datetime({obs.date}, 'InputFormat', 'yyyy-MM-dd', ...
                'TimeZone', 'UTC')';
            vals  = str2double({obs.value})';
            % FRED uses '.' for missing
            vals(strcmp({obs.value}, '.')) = NaN;
            colName = matlab.lang.makeValidName(char(seriesId));
            tt = timetable(dates, vals, 'VariableNames', {colName});
            tt.Properties.DimensionNames{1} = 'Time';
        end

        % -------------------------------------------------------------- %
        function tt = callYahooApi(obj, ticker, t1Unix, t2Unix)
        % callYahooApi  HTTP GET to Yahoo Finance v8/chart endpoint.
            url  = Model.DataManager.YAHOO_BASE_URL + upper(ticker);
            opts = weboptions( ...
                'Timeout',     obj.TimeoutSec, ...
                'ContentType', 'json', ...
                'HeaderFields', {'User-Agent', ...
                    'Mozilla/5.0 (compatible; MATLAB DataManager)'});
            params = struct( ...
                'period1',  t1Unix, ...
                'period2',  t2Unix, ...
                'interval', '1d', ...
                'events',   'history');
            try
                resp = webread(char(url), params, opts);
            catch ME
                error('SignalBuilder:DataManager:yahooHttpError', ...
                    'Yahoo Finance request failed: %s', ME.message);
            end
            try
                result    = resp.chart.result{1};
                timestamps = result.timestamp;
                q         = result.indicators.quote{1};
                dates = datetime(timestamps, 'ConvertFrom', 'posixtime', ...
                    'TimeZone', 'America/New_York')';
                open   = q.open(:);
                high   = q.high(:);
                low    = q.low(:);
                close  = q.close(:);
                volume = double(q.volume(:));
                tt = timetable(dates, open, high, low, close, volume, ...
                    'VariableNames', {'Open','High','Low','Close','Volume'});
            catch ME
                error('SignalBuilder:DataManager:yahooParseError', ...
                    'Failed to parse Yahoo response for %s: %s', ...
                    ticker, ME.message);
            end
        end
        % -------------------------------------------------------------- %
        function tt = callAlphaVantageApi(obj, ticker, startDate, endDate)
        % callAlphaVantageApi  HTTP GET to Alpha Vantage TIME_SERIES_DAILY_ADJUSTED.
        %   Always requests outputsize=full (~20 yr); caller filters by date.
        %
        %   NOTE: 'function' is a MATLAB reserved word and cannot be used as
        %   a struct field name for webread.  The URL query string is therefore
        %   constructed directly via sprintf instead of using a params struct.
            if obj.AlphaVantageApiKey == ""
                error('SignalBuilder:DataManager:noApiKey', ...
                    ['Alpha Vantage API key not set.\n' ...
                     'Get a free key at: ' ...
                     'https://www.alphavantage.co/support/#api-key\n' ...
                     'Then: dm.AlphaVantageApiKey = ''your_key''\n' ...
                     'Or set env var ALPHAVANTAGE_API_KEY before launching MATLAB.']);
            end
            % Build URL with query string directly — avoids 'function' keyword issue.
            % Free tier: TIME_SERIES_DAILY + outputsize=compact (last 100 bars).
            % Premium:   TIME_SERIES_DAILY + outputsize=full  (20+ years).
            % For full history on a free key, use fetch_stooq() instead.
            queryStr = sprintf( ...
                '?function=TIME_SERIES_DAILY&symbol=%s&outputsize=compact&datatype=csv&apikey=%s', ...
                char(upper(ticker)), char(obj.AlphaVantageApiKey));
            fullUrl = [char(Model.DataManager.ALPHAVANTAGE_BASE_URL) queryStr];
            opts = weboptions('Timeout', obj.TimeoutSec, 'ContentType', 'text');
            try
                csvText = webread(fullUrl, opts);
            catch ME
                error('SignalBuilder:DataManager:avHttpError', ...
                    'Alpha Vantage request failed: %s', ME.message);
            end
            % AV CSV header: timestamp,open,high,low,close,adjusted_close,volume,...
            tt = obj.parseCsvText(csvText, 'timestamp', ...
                {'open','high','low','close','volume'}, ...
                {'Open','High','Low','Close','Volume'}, ...
                startDate, endDate, 'America/New_York');
        end

        % -------------------------------------------------------------- %
        function tt = callStooqApi(obj, ticker, d1, d2)
        % callStooqApi  HTTP GET Stooq CSV download endpoint (no API key).
        %   d1, d2 are date strings in 'yyyymmdd' format.
        %
        %   NOTE: webread does not accept a params struct in R2021b;
        %   query parameters are embedded directly in the URL string.
            stooqTicker = Model.DataManager.formatStooqTicker(ticker);
            queryStr = sprintf('?s=%s&d1=%s&d2=%s&i=d', ...
                char(stooqTicker), d1, d2);
            fullUrl = [char(Model.DataManager.STOOQ_BASE_URL) queryStr];
            opts = weboptions('Timeout', obj.TimeoutSec, ...
                'ContentType', 'text', ...
                'HeaderFields', {'User-Agent', ...
                    'Mozilla/5.0 (compatible; MATLAB SignalBuilder)'});
            try
                csvText = webread(fullUrl, opts);
            catch ME
                error('SignalBuilder:DataManager:stooqHttpError', ...
                    'Stooq request failed: %s', ME.message);
            end
            % Stooq CSV header: Date,Open,High,Low,Close,Volume
            tt = obj.parseCsvText(csvText, 'Date', ...
                {'Open','High','Low','Close','Volume'}, ...
                {'Open','High','Low','Close','Volume'}, ...
                '', '', 'America/New_York');
        end

    end   % end private API callers

    % ------------------------------------------------------------------ %
    %  Public CSV utility — callable externally and by tests
    % ------------------------------------------------------------------ %
    methods
        function tt = parseCsvText(~, csvText, dateColName, ...
                                   srcCols, outCols, startDate, endDate, tz)
        % parseCsvText  Parse a CSV text blob into a filtered OHLCV timetable.
        %
        %   Can be called directly to parse CSV data from custom sources:
        %
        %   dm = Model.DataManager(); dm.init();
        %   tt = dm.parseCsvText(csvText, 'Date', ...
        %           {'Open','High','Low','Close','Volume'}, ...
        %           {'Open','High','Low','Close','Volume'}, ...
        %           '2020-01-01', '2024-01-01', 'America/New_York');
        %   dateColName   name of the date/timestamp column (case-insensitive)
        %   srcCols       source column names to extract (cell of chars)
        %   outCols       desired output column names (cell of chars)
        %   startDate/endDate  'yyyy-MM-dd' filter strings, or '' for none
        %   tz            IANA timezone string
            tt = timetable.empty;

            % Guard: API error responses from Alpha Vantage arrive as JSON
            trimmed = strtrim(csvText);
            if startsWith(trimmed, '{') || startsWith(trimmed, '[')
                error('SignalBuilder:DataManager:apiError', ...
                    ['API returned a non-CSV error response ' ...
                    '(check API key or rate limit):\n%s'], ...
                    trimmed(1 : min(numel(trimmed), 300)));
            end

            % Write text to a temp file and read as table
            tmpFile = [tempname, '.csv'];
            fid = fopen(tmpFile, 'wt');
            if fid < 0
                error('SignalBuilder:DataManager:tmpFileError', ...
                    'Cannot open temp file for CSV parsing.');
            end
            fprintf(fid, '%s', csvText);
            fclose(fid);

            try
                raw = readtable(tmpFile, 'Delimiter', ',', ...
                    'ReadVariableNames', true, ...
                    'VariableNamingRule', 'preserve');
                delete(tmpFile);
            catch ME
                if isfile(tmpFile); delete(tmpFile); end
                error('SignalBuilder:DataManager:csvParseError', ...
                    'Failed to parse CSV response: %s', ME.message);
            end

            if height(raw) == 0; return; end

            % Find date column (case-insensitive match)
            varNames = raw.Properties.VariableNames;
            dateIdx  = find(strcmpi(varNames, dateColName), 1);
            if isempty(dateIdx)
                error('SignalBuilder:DataManager:csvParseError', ...
                    'Date column "%s" not found. Available: %s', ...
                    dateColName, strjoin(varNames, ', '));
            end
            rawDates = raw{:, dateIdx};
            if iscell(rawDates)
                t = datetime(rawDates, 'InputFormat', 'yyyy-MM-dd', ...
                    'TimeZone', tz);
            elseif isdatetime(rawDates)
                t = rawDates;
                if isempty(t.TimeZone), t.TimeZone = tz; end
            else
                error('SignalBuilder:DataManager:csvParseError', ...
                    'Unexpected type for date column "%s": %s.', ...
                    dateColName, class(rawDates));
            end

            % Extract each output column (fill NaN when column is absent)
            nOut    = numel(outCols);
            colData = cell(nOut, 1);
            for k = 1 : nOut
                colIdx = find(strcmpi(varNames, srcCols{k}), 1);
                if isempty(colIdx)
                    colData{k} = NaN(height(raw), 1);
                else
                    col = raw{:, colIdx};
                    if iscell(col)
                        colData{k} = str2double(col);
                    else
                        colData{k} = double(col);
                    end
                end
            end

            tt = timetable(t, colData{:}, 'VariableNames', outCols);
            tt.Properties.DimensionNames{1} = 'Time';
            tt = sortrows(tt);   % APIs often return newest-first

            % Optional date-range filter
            if ~isempty(startDate) && ~strcmp(startDate, '')
                sd = datetime(startDate, 'InputFormat', 'yyyy-MM-dd', ...
                    'TimeZone', tz);
                tt = tt(tt.Time >= sd, :);
            end
            if ~isempty(endDate) && ~strcmp(endDate, '')
                ed = datetime(endDate, 'InputFormat', 'yyyy-MM-dd', ...
                    'TimeZone', tz);
                tt = tt(tt.Time <= ed, :);
            end

            % Drop bars with missing Close
            if ismember('Close', tt.Properties.VariableNames)
                tt = tt(~isnan(tt.Close), :);
            end
        end
    end   % end public CSV utility

    % ------------------------------------------------------------------ %
    %  Private — persistence helpers
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function ensureDirs(obj)
            dirs = {obj.CacheDir, ...
                    fullfile(obj.CacheDir, Model.DataManager.MAT_SUBDIR)};
            for k = 1 : numel(dirs)
                if ~isfolder(dirs{k})
                    mkdir(dirs{k});
                end
            end
        end

        function openDb(obj)
            try
                obj.Db = sqlite(obj.DbPath, 'connect');
            catch
                % First run — create fresh DB
                obj.Db = sqlite(obj.DbPath, 'create');
            end
            % R2021b sqlite uses exec() not execute()
            obj.Db.exec([ ...
                'CREATE TABLE IF NOT EXISTS series_registry (' ...
                '  cache_key TEXT PRIMARY KEY,' ...
                '  source    TEXT NOT NULL,' ...
                '  last_date TEXT NOT NULL,' ...
                '  mat_path  TEXT NOT NULL' ...
                ');']);
        end

        function closeDb(obj)
            if ~isempty(obj.Db) && isvalid(obj.Db)
                close(obj.Db);
            end
        end

        function loadRegistry(obj)
            rows = obj.Db.fetch('SELECT * FROM series_registry');
            if isempty(rows)
                return;
            end
            for k = 1 : size(rows, 1)
                key = rows{k,1};
                rec = struct( ...
                    'Source',   rows{k,2}, ...
                    'LastDate', datetime(rows{k,3}, 'InputFormat','yyyy-MM-dd',...
                                         'TimeZone','UTC'), ...
                    'MatPath',  rows{k,4});
                obj.Registry(char(key)) = rec;
            end
        end

        function [tt, lastDate] = loadFromCache(obj, cacheKey)
        % loadFromCache  Load timetable from .mat; return empty if missing.
            tt       = timetable.empty;
            lastDate = NaT;
            if ~isKey(obj.Registry, char(cacheKey))
                return;
            end
            rec = obj.Registry(char(cacheKey));
            if ~isfile(rec.MatPath)
                return;
            end
            try
                s  = load(rec.MatPath, 'tt');
                tt = s.tt;
                lastDate = rec.LastDate;
            catch
                tt = timetable.empty;
            end
        end

        function merged = mergeAndPersist(obj, cached, newData, cacheKey, source)
        % mergeAndPersist  Append new rows, remove duplicates, save to disk.
            if isempty(cached)
                merged = newData;
            else
                % Same source → same column schema; vertcat over non-overlapping
                % date ranges.  synchronize() renames duplicate columns and its
                % 'fillwithconstant' form has wrong-number-of-args in R2021b.
                merged = [cached; newData];
            end
            merged = sortrows(merged);
            % Deduplicate on row time
            [~, ia] = unique(merged.Time);
            merged = merged(ia, :);

            % Persist .mat
            matPath = fullfile(obj.CacheDir, Model.DataManager.MAT_SUBDIR, ...
                matlab.lang.makeValidName(char(cacheKey)) + ".mat");
            tt = merged;
            save(matPath, 'tt', '-v7.3');

            % Update SQLite registry
            lastDate = merged.Time(end);
            lastDateStr = datestr(lastDate, 'yyyy-mm-dd');
            matPathStr  = char(matPath);
            keyStr      = char(cacheKey);
            sourceStr   = char(source);
            % R2021b sqlite.exec() does not support parameterised queries;
            % embed values directly (single-quotes escaped for safety).
            escStr = @(s) strrep(char(s), '''', '''''');
            sql = sprintf([ ...
                'INSERT OR REPLACE INTO series_registry ' ...
                '(cache_key,source,last_date,mat_path) ' ...
                'VALUES (''%s'',''%s'',''%s'',''%s'');'], ...
                escStr(keyStr), escStr(sourceStr), ...
                escStr(lastDateStr), escStr(matPathStr));
            obj.Db.exec(sql);

            rec = struct('Source', source, 'LastDate', lastDate, ...
                'MatPath', matPath);
            obj.Registry(keyStr) = rec;
        end

        function tt = standardise(obj, tt, ~)
        % standardise  Fill missing values and validate structure.
            if isempty(tt) || obj.FillMethod == "none"
                return;
            end
            tt = fillmissing(tt, char(obj.FillMethod));
        end

        function resolveFredKey(obj)
            if obj.FredApiKey == ""
                envKey = getenv('FRED_API_KEY');
                if ~isempty(envKey)
                    obj.FredApiKey = string(envKey);
                    obj.log('FRED API key loaded from environment.');
                end
            end
        end

        function resolveAvKey(obj)
        % resolveAvKey  Read ALPHAVANTAGE_API_KEY env var if property unset.
            if obj.AlphaVantageApiKey == ""
                envKey = getenv('ALPHAVANTAGE_API_KEY');
                if ~isempty(envKey)
                    obj.AlphaVantageApiKey = string(envKey);
                    obj.log('Alpha Vantage API key loaded from environment.');
                end
            end
        end

        function d = resolveEndDate(~, endDate)
            if endDate == "" || isempty(endDate)
                d = datestr(datetime('today'), 'yyyy-mm-dd');
            else
                d = char(endDate);
            end
        end

        function key = resolveKey(obj, seriesId)
        % resolveKey  Find the registry key for a bare series/ticker ID.
            candidates = ["FRED_"  + upper(seriesId), ...
                          "YF_"    + upper(seriesId), ...
                          "AV_"    + upper(seriesId), ...
                          "STOOQ_" + upper(seriesId)];
            for k = 1 : numel(candidates)
                if isKey(obj.Registry, char(candidates(k)))
                    key = candidates(k);
                    return;
                end
            end
            % Return first candidate and let caller throw if not found
            key = candidates(1);
        end

        function requireInit(obj)
            if isempty(obj.Db)
                error('SignalBuilder:DataManager:notInitialised', ...
                    'Call dm.init() before using DataManager.');
            end
        end

        function log(obj, msg, varargin)
            if obj.Verbose
                fprintf('[DataManager] %s\n', sprintf(msg, varargin{:}));
            end
        end
    end

    % ------------------------------------------------------------------ %
    %  Public static helpers
    % ------------------------------------------------------------------ %
    methods (Static, Access = public)
        function t = formatStooqTicker(ticker)
        % formatStooqTicker  Normalise a ticker to Stooq's URL format.
        %
        %   Appends '.US' for US equities/ETFs when no dot is present.
        %   Index symbols starting with '^' are passed through unchanged.
        %
        %   Model.DataManager.formatStooqTicker('SPY')    → 'SPY.US'
        %   Model.DataManager.formatStooqTicker('SPY.US') → 'SPY.US'
        %   Model.DataManager.formatStooqTicker('^SPX')   → '^SPX'
            t = upper(char(ticker));
            if ~contains(t, '.') && ~startsWith(t, '^')
                t = [t '.US'];
            end
        end
    end

    % ------------------------------------------------------------------ %
    %  Private static helpers
    % ------------------------------------------------------------------ %
    methods (Static, Access = private)
        function tf = isToolboxAvailable(toolboxName)
            v = ver;
            tf = any(strcmp({v.Name}, toolboxName));
        end
    end
end
