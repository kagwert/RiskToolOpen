function mkt = downloadMarketData(startDate, endDate)
%SIGSTRAT.DOWNLOADMARKETDATA Download S&P 500 + T-Bill data from Yahoo Finance.
%   mkt = sigstrat.downloadMarketData(startDate, endDate)
%
% Inputs:
%   startDate - char, 'YYYYMMDD' format (default '19900101')
%   endDate   - char, 'YYYYMMDD' format (default today)
%
% Returns:
%   mkt.dates    - Tx1 datetime (price dates, aligned)
%   mkt.retDates - (T-1)x1 datetime (return dates)
%   mkt.spxRet   - (T-1)x1 daily log returns of S&P 500
%   mkt.cashRet  - (T-1)x1 daily returns (T-Bill proxy)
%   mkt.spxPrice - Tx1 S&P 500 price level

    if nargin < 1 || isempty(startDate), startDate = '19900101'; end
    if nargin < 2 || isempty(endDate),   endDate = datestr(datetime('today'),'yyyymmdd'); end %#ok<DATST>

    cacheDir = fullfile(tempdir, 'sigstrat_cache');
    if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end
    cacheFile = fullfile(cacheDir, sprintf('mktdata_%s_%s.mat', startDate, endDate));

    % Check cache (24h validity)
    if exist(cacheFile, 'file')
        info = dir(cacheFile);
        ageHours = (now - info.datenum) * 24; %#ok<TNOW1>
        if ageHours < 24
            tmp = load(cacheFile, 'mkt');
            mkt = tmp.mkt;
            fprintf('Loaded cached market data (%.1f hours old).\n', ageHours);
            return;
        end
    end

    %% Download S&P 500 index from Yahoo Finance
    fprintf('Downloading S&P 500 (^GSPC) from Yahoo Finance...\n');
    spxTbl = downloadStooqSeries('^spx', startDate, endDate);
    if isempty(spxTbl) || height(spxTbl) < 10
        % Fallback: try SPY ETF
        fprintf('  ^GSPC failed, trying SPY ETF...\n');
        spxTbl = downloadStooqSeries('spy.us', startDate, endDate);
    end
    if isempty(spxTbl) || height(spxTbl) < 10
        error('sigstrat:downloadMarketData', 'Could not download S&P 500 data.');
    end

    %% Download T-Bill proxy
    fprintf('Downloading T-Bill proxy (BIL) from Yahoo Finance...\n');
    cashTbl = downloadStooqSeries('bil.us', startDate, endDate);
    hasCashETF = ~isempty(cashTbl) && height(cashTbl) >= 10;

    %% Intersect dates for cash ETF period
    if hasCashETF
        commonDates = intersect(spxTbl.Date, cashTbl.Date);
        commonDates = sort(commonDates);
        [~, iSpx]  = ismember(commonDates, spxTbl.Date);
        [~, iCash] = ismember(commonDates, cashTbl.Date);
        spxP  = spxTbl.Close(iSpx);
        cashP = cashTbl.Close(iCash);

        % Log returns
        spxRet  = diff(log(spxP));
        cashRet = diff(log(cashP));
        retDates = commonDates(2:end);
        allDates = commonDates;
    else
        % Use all SPX dates; synthesize cash returns from FRED Fed Funds
        fprintf('  bil.us unavailable; synthesizing cash returns from FRED Fed Funds...\n');
        cashRet = synthesizeCashFromFRED(spxTbl.Date, startDate, endDate);
        allDates = spxTbl.Date;
        spxP = spxTbl.Close;
        spxRet = diff(log(spxP));
        retDates = allDates(2:end);

        % Align lengths
        nRet = min(numel(spxRet), numel(cashRet));
        spxRet   = spxRet(end-nRet+1:end);
        cashRet  = cashRet(end-nRet+1:end);
        retDates = retDates(end-nRet+1:end);
        allDates = allDates(end-nRet:end);
        spxP     = spxP(end-nRet:end);
    end

    % Remove bad rows
    bad = ~isfinite(spxRet) | ~isfinite(cashRet);
    spxRet(bad)   = 0;
    cashRet(bad)  = 0;

    mkt.dates    = allDates;
    mkt.retDates = retDates;
    mkt.spxRet   = spxRet;
    mkt.cashRet  = cashRet;
    mkt.spxPrice = spxP;

    fprintf('Market data: %d return days (%s to %s).\n', ...
        numel(retDates), datestr(retDates(1),'yyyy-mm-dd'), datestr(retDates(end),'yyyy-mm-dd')); %#ok<DATST>

    % Save cache
    save(cacheFile, 'mkt');
end

%% ---- Yahoo Finance single-series download (replaces Stooq) ----
function T = downloadStooqSeries(ticker, startDate, endDate)
    % Stooq returns a JS challenge page to non-browser requests — use Yahoo Finance JSON API
    yfTicker = stooqToYahoo(ticker);

    try
        d1_dt = datetime(startDate, 'InputFormat', 'yyyyMMdd', 'TimeZone', 'UTC');
        d2_dt = datetime(endDate,   'InputFormat', 'yyyyMMdd', 'TimeZone', 'UTC');
    catch
        d1_dt = datetime(startDate, 'InputFormat', 'yyyyMMdd');
        d2_dt = datetime(endDate,   'InputFormat', 'yyyyMMdd');
    end
    p1 = num2str(floor(posixtime(d1_dt)));
    p2 = num2str(floor(posixtime(d2_dt)));

    url = sprintf( ...
        'https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&period1=%s&period2=%s&events=history', ...
        yfTicker, p1, p2);
    opts = weboptions( ...
        'HeaderFields', {'User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}, ...
        'Timeout', 30);

    try
        resp = webread(url, opts);
    catch
        url2 = strrep(url, 'query1.', 'query2.');
        try
            resp = webread(url2, opts);
        catch
            T = table(); return;
        end
    end

    try
        result = resp.chart.result;
        rawTS  = result.timestamp;
        rawQ   = result.indicators.quote;
        if iscell(rawTS), rawTS = cell2mat(rawTS); end
        closes = rawQ.close;
        if iscell(closes), closes = cell2mat(closes); end
        dt = datetime(rawTS, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
        dt.TimeZone = '';
        dt = dateshift(dt, 'start', 'day');
        T = table(dt(:), closes(:), 'VariableNames', {'Date','Close'});
        bad = isnan(T.Close) | T.Close <= 0;
        T = T(~bad, :);
        T = sortrows(T, 'Date');
    catch
        T = table();
    end
end

%% ---- Map Stooq-style tickers to Yahoo Finance tickers ----
function yfTicker = stooqToYahoo(stooqTicker)
    t = lower(strtrim(stooqTicker));
    switch t
        case {'^spx', 'spx'},  yfTicker = '^GSPC';
        case {'^ndx', 'ndx'},  yfTicker = '^NDX';
        case {'^dji', 'dji'},  yfTicker = '^DJI';
        case {'^vix', 'vix'},  yfTicker = '^VIX';
        otherwise
            if startsWith(t, '^')
                yfTicker = ['^' upper(t(2:end))];
            else
                dotPos = strfind(t, '.');
                if ~isempty(dotPos)
                    yfTicker = upper(t(1:dotPos(1)-1));
                else
                    yfTicker = upper(t);
                end
            end
    end
end

%% ---- Synthesize cash from FRED Fed Funds ----
function cashRet = synthesizeCashFromFRED(targetDates, startDate, endDate)
    d1 = [startDate(1:4) '-' startDate(5:6) '-' startDate(7:8)];
    d2 = [endDate(1:4) '-' endDate(5:6) '-' endDate(7:8)];

    T = downloadFREDSeries('DFF', d1, d2);
    if isempty(T) || height(T) < 10
        % Fallback: constant 3% annual rate
        fprintf('  FRED Fed Funds unavailable; using constant 3%% rate.\n');
        cashRet = ones(numel(targetDates)-1, 1) * (0.03 / 252);
        return;
    end

    % Forward-fill to target dates
    aligned = forwardFill(T.Date, T.Value, targetDates);

    % Convert annualized % rate to daily return
    dailyRate = aligned / 100 / 252;
    cashRet = dailyRate(2:end);
    cashRet(~isfinite(cashRet)) = 0;
end

%% ---- Download single FRED series (REST API) ----
function T = downloadFREDSeries(seriesID, startDate, endDate)
    % Uses FRED REST API — not the CDN-gated fredgraph.csv endpoint.
    % Set env var FRED_API_KEY (free key from fred.stlouisfed.org/docs/api/api_key.html).
    apiKey = strtrim(getenv('FRED_API_KEY'));
    if isempty(apiKey)
        fprintf('  [SKIP] FRED %s — FRED_API_KEY env var not set; using constant cash rate fallback.\n', seriesID);
        T = table(); return;
    end
    T = callFredRestApi(apiKey, seriesID, startDate, endDate);
end

%% ---- FRED REST API call ----
function T = callFredRestApi(apiKey, seriesID, startDate, endDate)
    url = sprintf( ...
        'https://api.stlouisfed.org/fred/series/observations?series_id=%s&observation_start=%s&observation_end=%s&api_key=%s&file_type=json&units=lin', ...
        seriesID, startDate, endDate, apiKey);
    opts = weboptions('Timeout', 30, 'ContentType', 'json');
    try
        resp = webread(url, opts);
    catch
        T = table(); return;
    end
    if ~isfield(resp, 'observations') || isempty(resp.observations)
        T = table(); return;
    end
    obs   = resp.observations;
    dates = datetime({obs.date}, 'InputFormat', 'yyyy-MM-dd')';
    vals  = str2double({obs.value})';  % FRED uses '.' for missing; str2double → NaN
    good  = isfinite(vals) & ~isnat(dates);
    T = table(dates(good), vals(good), 'VariableNames', {'Date','Value'});
    T = sortrows(T, 'Date');
end

%% ---- Forward-fill alignment ----
function aligned = forwardFill(srcDates, srcVals, targetDates)
    N = numel(targetDates);
    aligned = NaN(N, 1);
    srcDates = srcDates(:);
    srcVals  = srcVals(:);
    [srcDates, si] = sort(srcDates);
    srcVals = srcVals(si);
    j = 1;
    lastVal = NaN;
    for i = 1:N
        while j <= numel(srcDates) && srcDates(j) <= targetDates(i)
            lastVal = srcVals(j);
            j = j + 1;
        end
        aligned(i) = lastVal;
    end
end

