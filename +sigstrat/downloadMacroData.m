function macro = downloadMacroData(targetDates)
%SIGSTRAT.DOWNLOADMACRODATA Download FRED macro series and compute derived measures.
%   macro = sigstrat.downloadMacroData(targetDates)
%
% Inputs:
%   targetDates - Tx1 datetime vector to align measures to
%
% Returns:
%   macro - table with Date + 14 derived columns (same as gaa.downloadFRED)

    if ~isdatetime(targetDates)
        error('sigstrat:downloadMacroData', 'targetDates must be datetime array.');
    end

    % Try calling gaa.downloadFRED with a minimal config struct
    try
        cfg = buildMinimalCfg(targetDates);
        macro = gaa.downloadFRED(cfg, targetDates);
        fprintf('Macro data loaded via gaa.downloadFRED.\n');
        return;
    catch
        fprintf('gaa.downloadFRED unavailable; using embedded FRED download.\n');
    end

    %% Embedded FRED pipeline (mirrors gaa.downloadFRED)
    fredSeriesIDs   = {'A191RL1Q225SBEA','CPIAUCSL','DTWEXBGS','VIXCLS','DFF','DGS10','DGS2', ...
                       'BAMLH0A0HYM2','BAMLC0A4CBBB','PAYEMS','RSAFS','DCOILWTICO'};
    fredSeriesNames = {'GDP_pct','CPI_level','DXY_level','VIX','FedFunds','TenYr','TwoYr', ...
                       'HY_Spread','IG_Spread','NFP_level','RetailSales_level','WTI_level'};

    % Extra lookback for derived columns
    startDt = targetDates(1) - calmonths(15);
    endDt   = targetDates(end);
    d1 = datestr(startDt, 'yyyy-mm-dd'); %#ok<DATST>
    d2 = datestr(endDt, 'yyyy-mm-dd');   %#ok<DATST>

    rawData = cell(1, numel(fredSeriesIDs));
    failed = {};
    for i = 1:numel(fredSeriesIDs)
        fprintf('Downloading FRED %s (%d/%d)...\n', fredSeriesIDs{i}, i, numel(fredSeriesIDs));
        ok = false;
        for attempt = 1:2
            try
                rawData{i} = downloadFREDSeries(fredSeriesIDs{i}, d1, d2);
                if ~isempty(rawData{i}) && height(rawData{i}) >= 2
                    ok = true; break;
                end
            catch
            end
            if attempt == 1, pause(1); end
        end
        if ~ok
            failed{end+1} = fredSeriesIDs{i}; %#ok<AGROW>
            rawData{i} = table();
        end
    end

    N = numel(targetDates);
    macro = table(targetDates(:), 'VariableNames', {'Date'});

    % Forward-fill each series to target dates
    for i = 1:numel(fredSeriesIDs)
        if isempty(rawData{i}) || height(rawData{i}) < 2
            macro.(fredSeriesNames{i}) = NaN(N, 1);
            continue;
        end
        srcDates = rawData{i}.Date;
        srcVals  = rawData{i}.Value;
        macro.(fredSeriesNames{i}) = forwardFill(srcDates, srcVals, targetDates);
    end

    %% Compute derived columns

    % GDP_YoY: already annualized % change from FRED, convert to decimal
    macro.GDP_YoY = macro.GDP_pct / 100;

    % CPI_YoY: year-over-year change from CPI level
    cpiLag = min(252, N-1);
    macro.CPI_YoY = NaN(N, 1);
    if cpiLag > 0
        macro.CPI_YoY(cpiLag+1:end) = macro.CPI_level(cpiLag+1:end) ./ macro.CPI_level(1:end-cpiLag) - 1;
    end

    % CPI_MoM: month-over-month change (~21 trading days)
    cpiMoMLag = min(21, N-1);
    macro.CPI_MoM = NaN(N, 1);
    if cpiMoMLag > 0
        macro.CPI_MoM(cpiMoMLag+1:end) = macro.CPI_level(cpiMoMLag+1:end) ./ macro.CPI_level(1:end-cpiMoMLag) - 1;
    end

    % DXY_3m_return: 3-month (~63 trading days) return
    dxyLag = min(63, N-1);
    macro.DXY_3m_return = NaN(N, 1);
    if dxyLag > 0
        macro.DXY_3m_return(dxyLag+1:end) = macro.DXY_level(dxyLag+1:end) ./ macro.DXY_level(1:end-dxyLag) - 1;
    end

    % NFP_MoM: month-over-month change in Nonfarm Payrolls
    nfpLag = min(21, N-1);
    macro.NFP_MoM = NaN(N, 1);
    if nfpLag > 0
        macro.NFP_MoM(nfpLag+1:end) = macro.NFP_level(nfpLag+1:end) - macro.NFP_level(1:end-nfpLag);
    end

    % RetailSales_YoY
    rsLag = min(252, N-1);
    macro.RetailSales_YoY = NaN(N, 1);
    if rsLag > 0
        macro.RetailSales_YoY(rsLag+1:end) = macro.RetailSales_level(rsLag+1:end) ./ macro.RetailSales_level(1:end-rsLag) - 1;
    end

    % Yield curve slope: 10Y - 2Y (in decimal)
    macro.YieldSlope = (macro.TenYr - macro.TwoYr) / 100;

    % Oil 3-month return
    oilLag = min(63, N-1);
    macro.Oil_3m_return = NaN(N, 1);
    if oilLag > 0
        macro.Oil_3m_return(oilLag+1:end) = macro.WTI_level(oilLag+1:end) ./ macro.WTI_level(1:end-oilLag) - 1;
    end

    % Convert rate series from percent to decimal
    macro.FedFunds  = macro.FedFunds / 100;
    macro.TenYr     = macro.TenYr / 100;
    macro.TwoYr     = macro.TwoYr / 100;
    macro.HY_Spread = macro.HY_Spread / 100;
    macro.IG_Spread = macro.IG_Spread / 100;

    % Remove intermediate columns
    macro = removevars(macro, {'GDP_pct','CPI_level','DXY_level','NFP_level','RetailSales_level','WTI_level'});

    fprintf('FRED measures: %d rows, %d columns.', height(macro), width(macro)-1);
    if ~isempty(failed)
        fprintf(' Failed: %s.', strjoin(failed, ', '));
    end
    fprintf('\n');
end

%% ---- Build minimal config for gaa.downloadFRED ----
function cfg = buildMinimalCfg(targetDates) %#ok<INUSD>
    cfg.fredSeriesIDs   = {'A191RL1Q225SBEA','CPIAUCSL','DTWEXBGS','VIXCLS','DFF','DGS10','DGS2', ...
                           'BAMLH0A0HYM2','BAMLC0A4CBBB','PAYEMS','RSAFS','DCOILWTICO'};
    cfg.fredSeriesNames = {'GDP_pct','CPI_level','DXY_level','VIX','FedFunds','TenYr','TwoYr', ...
                           'HY_Spread','IG_Spread','NFP_level','RetailSales_level','WTI_level'};
end

%% ---- Download single FRED series ----
function T = downloadFREDSeries(seriesID, startDate, endDate)
    url = sprintf('https://fred.stlouisfed.org/graph/fredgraph.csv?bgcolor=%%23e1e9f0&fo=open+sans&id=%s&cosd=%s&coed=%s', ...
        seriesID, startDate, endDate);
    tmpFile = [tempname '.csv'];
    cleanUp = onCleanup(@() deleteIfExists(tmpFile)); %#ok<NASGU>
    websave(tmpFile, url);

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
