function mkt = downloadMarketData(startDate, endDate)
%SIGSTRAT.DOWNLOADMARKETDATA Download S&P 500 + T-Bill data from Stooq.
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

    %% Download S&P 500 index from Stooq
    fprintf('Downloading S&P 500 (^spx) from Stooq...\n');
    spxTbl = downloadStooqSeries('^spx', startDate, endDate);
    if isempty(spxTbl) || height(spxTbl) < 10
        % Fallback: try SPY ETF
        fprintf('  ^spx failed, trying spy.us...\n');
        spxTbl = downloadStooqSeries('spy.us', startDate, endDate);
    end
    if isempty(spxTbl) || height(spxTbl) < 10
        error('sigstrat:downloadMarketData', 'Could not download S&P 500 data.');
    end

    %% Download T-Bill proxy
    fprintf('Downloading T-Bill proxy (bil.us) from Stooq...\n');
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

%% ---- Stooq single-series download ----
function T = downloadStooqSeries(ticker, startDate, endDate)
    url = sprintf('https://stooq.com/q/d/l/?s=%s&d1=%s&d2=%s&i=d', ticker, startDate, endDate);
    tmpFile = [tempname '.csv'];
    cleanUp = onCleanup(@() deleteIfExists(tmpFile)); %#ok<NASGU>
    try
        websave(tmpFile, url);
    catch
        T = table(); return;
    end
    raw = readtable(tmpFile, 'TextType', 'string');
    if isempty(raw) || height(raw) < 2
        T = table(); return;
    end
    if ~ismember('Date', raw.Properties.VariableNames) || ~ismember('Close', raw.Properties.VariableNames)
        T = table(); return;
    end
    raw.Date = datetime(raw.Date);
    T = table(raw.Date, raw.Close, 'VariableNames', {'Date','Close'});
    bad = isnan(T.Close) | T.Close <= 0;
    T = T(~bad, :);
    T = sortrows(T, 'Date');
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

%% ---- Download single FRED series ----
function T = downloadFREDSeries(seriesID, startDate, endDate)
    url = sprintf('https://fred.stlouisfed.org/graph/fredgraph.csv?bgcolor=%%23e1e9f0&fo=open+sans&id=%s&cosd=%s&coed=%s', ...
        seriesID, startDate, endDate);
    tmpFile = [tempname '.csv'];
    cleanUp = onCleanup(@() deleteIfExists(tmpFile)); %#ok<NASGU>
    try
        websave(tmpFile, url);
    catch
        T = table(); return;
    end

    opts = detectImportOptions(tmpFile);
    vnames = opts.VariableNames;
    valIdx = find(~strcmpi(vnames, 'observation_date') & ~strcmpi(vnames, 'DATE'), 1);
    if ~isempty(valIdx)
        opts = setvartype(opts, vnames{valIdx}, 'string');
    end
    raw = readtable(tmpFile, opts);

    if isempty(raw) || height(raw) < 1
        T = table(); return;
    end

    if ismember('observation_date', raw.Properties.VariableNames)
        dt = datetime(raw.observation_date);
    elseif ismember('DATE', raw.Properties.VariableNames)
        dt = datetime(raw.DATE);
    else
        dt = datetime(raw{:,1});
    end

    vn = raw.Properties.VariableNames;
    valColIdx = ~strcmpi(vn, 'observation_date') & ~strcmpi(vn, 'DATE');
    valColName = vn{find(valColIdx, 1)};
    valRaw = raw.(valColName);
    if isstring(valRaw) || iscell(valRaw)
        valNum = str2double(valRaw);
    else
        valNum = double(valRaw);
    end

    good = isfinite(valNum) & ~isnat(dt);
    T = table(dt(good), valNum(good), 'VariableNames', {'Date','Value'});
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

function deleteIfExists(f)
    if exist(f, 'file'), delete(f); end
end
