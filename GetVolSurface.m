function iv = GetVolSurface(T, K, options)
% GetVolSurface Download SPY options, calibrate SVI vol surface, query (T,K)
%   iv = GetVolSurface(T, K) returns annualized implied volatility for
%   time-to-expiry T (years) and strike K (absolute).
%
%   iv = GetVolSurface(T, K, Type="moneyness") treats K as K/S ratio.
%   iv = GetVolSurface(T, K, Refresh=true) forces re-download.
%   iv = GetVolSurface(T, K, Plot=true) shows 3D volatility surface.
%
%   Uses SVI (Stochastic Volatility Inspired) parameterization with
%   linear total-variance interpolation across expiries.

    arguments
        T (:,1) double {mustBeReal}
        K (:,1) double {mustBePositive}
        options.Type (1,1) string {mustBeMember(options.Type, ["strike", "moneyness"])} = "strike"
        options.Refresh (1,1) logical = false
        options.Plot (1,1) logical = false
    end

    if any(T < 0)
        error("GetVolSurface:InvalidInput", "T must be non-negative.");
    end
    if numel(T) ~= numel(K)
        error("GetVolSurface:SizeMismatch", "T and K must have the same number of elements.");
    end

    persistent cachedSurface

    surface = loadSurface(cachedSurface, options.Refresh);

    if isempty(surface)
        surface = buildSurface();
        cachedSurface = surface;
        saveSurfaceToFile(surface);
    end

    if options.Type == "moneyness"
        K = K * surface.spotPrice;
    end

    iv = interpolateSurface(T, K, surface);

    if options.Plot
        plotVolSurface(surface);
    end
end

%% --- Surface Construction ---

function surface = loadSurface(cachedSurface, forceRefresh)
% loadSurface Load surface from persistent cache or disk, check staleness
    surface = [];
    maxAgeHours = 24;

    if ~forceRefresh && ~isempty(cachedSurface)
        ageHours = (now() - cachedSurface.timestamp) * 24;
        if ageHours < maxAgeHours
            surface = cachedSurface;
            return;
        end
    end

    cacheFile = fullfile(fileparts(mfilename("fullpath")), "VolSurfaceCache.mat");
    if ~forceRefresh && isfile(cacheFile)
        data = load(cacheFile, "surface");
        if isfield(data, "surface")
            ageHours = (now() - data.surface.timestamp) * 24;
            if ageHours < maxAgeHours
                surface = data.surface;
            end
        end
    end
end

function saveSurfaceToFile(surface)
% saveSurfaceToFile Persist surface to disk
    cacheFile = fullfile(fileparts(mfilename("fullpath")), "VolSurfaceCache.mat");
    save(cacheFile, "surface");
end

function surface = buildSurface()
% buildSurface Download data from Yahoo and calibrate SVI surface
    ticker = "SPY";
    r = getRiskFreeRate();
    q = 0.013;

    fprintf("GetVolSurface: Authenticating with Yahoo Finance...\n");
    [cookie, crumb] = getYahooAuth();

    fprintf("GetVolSurface: Downloading options chains for %s...\n", ticker);
    [rawOptions, expiryDates, spotPrice] = downloadAllExpiries(ticker, cookie, crumb);

    fprintf("GetVolSurface: Building and calibrating SVI slices (S=%.2f)...\n", spotPrice);
    slices = buildSlices(rawOptions, expiryDates, spotPrice, r, q);

    if numel(slices) < 3
        error("GetVolSurface:InsufficientData", ...
            "Only %d valid expiry slices found. Need at least 3.", numel(slices));
    end

    surface.ticker = ticker;
    surface.timestamp = now();
    surface.spotPrice = spotPrice;
    surface.riskFreeRate = r;
    surface.divYield = q;
    surface.slices = slices;
    fprintf("GetVolSurface: Surface ready with %d expiry slices.\n", numel(slices));
end

function r = getRiskFreeRate()
% getRiskFreeRate Return risk-free rate estimate
    r = 0.045;
end

%% --- Yahoo Finance Data Pipeline ---

function [cookie, crumb] = getYahooAuth()
% getYahooAuth Obtain Yahoo Finance session cookie and crumb token
    GET = matlab.net.http.RequestMethod.GET;

    try
        req1 = matlab.net.http.RequestMessage(GET);
        uri1 = matlab.net.URI("https://fc.yahoo.com");
        [resp1, ~, ~] = req1.send(uri1);

        cookieStr = "";
        for i = 1:numel(resp1.Header)
            if strcmpi(resp1.Header(i).Name, "Set-Cookie")
                val = string(resp1.Header(i).Value);
                parts = split(val, ";");
                if cookieStr == ""
                    cookieStr = parts(1);
                else
                    cookieStr = cookieStr + "; " + parts(1);
                end
            end
        end

        if cookieStr == ""
            error("GetVolSurface:AuthFailed", "No cookies received from Yahoo.");
        end

        headers = [matlab.net.http.HeaderField("Cookie", cookieStr), ...
                   matlab.net.http.HeaderField("User-Agent", "Mozilla/5.0")];
        req2 = matlab.net.http.RequestMessage(GET, headers);
        uri2 = matlab.net.URI("https://query2.finance.yahoo.com/v1/test/getcrumb");
        [resp2, ~, ~] = req2.send(uri2);

        crumb = string(resp2.Body.Data);
        if strlength(crumb) < 5 || strlength(crumb) > 50
            error("GetVolSurface:AuthFailed", "Invalid crumb received.");
        end
        cookie = cookieStr;
    catch ex
        error("GetVolSurface:AuthFailed", ...
            "Yahoo Finance authentication failed: %s\n" + ...
            "Check your network connection or firewall settings.", ex.message);
    end
end

function [rawOptions, expiryDates, spotPrice] = downloadAllExpiries(ticker, cookie, crumb)
% downloadAllExpiries Fetch all options chains from Yahoo Finance
    GET = matlab.net.http.RequestMethod.GET;
    headers = [matlab.net.http.HeaderField("Cookie", cookie), ...
               matlab.net.http.HeaderField("User-Agent", "Mozilla/5.0")];
    baseUrl = sprintf("https://query2.finance.yahoo.com/v7/finance/options/%s?crumb=%s", ...
        ticker, crumb);

    req = matlab.net.http.RequestMessage(GET, headers);
    [resp, ~, ~] = req.send(matlab.net.URI(baseUrl));
    data = resp.Body.Data;

    if ~isfield(data, "optionChain") || ~isfield(data.optionChain, "result")
        error("GetVolSurface:DownloadFailed", "Unexpected Yahoo API response structure.");
    end

    result = data.optionChain.result;
    if iscell(result)
        result = result{1};
    end

    spotPrice = result.quote.regularMarketPrice;
    expiryTimestamps = result.expirationDates;
    if iscell(expiryTimestamps)
        expiryTimestamps = cell2mat(expiryTimestamps);
    end

    nExpiries = numel(expiryTimestamps);
    rawOptions = cell(nExpiries, 1);
    expiryDates = NaT(nExpiries, 1);

    for i = 1:nExpiries
        ts = expiryTimestamps(i);
        expiryDates(i) = datetime(ts, "ConvertFrom", "posixtime");

        if i == 1 && isfield(result, "options") && ~isempty(result.options)
            opts = result.options;
            if iscell(opts)
                opts = opts{1};
            end
            rawOptions{i} = opts;
        else
            url = sprintf("%s&date=%d", baseUrl, ts);
            try
                pause(0.3);
                reqI = matlab.net.http.RequestMessage(GET, headers);
                [respI, ~, ~] = reqI.send(matlab.net.URI(url));
                dataI = respI.Body.Data;
                resI = dataI.optionChain.result;
                if iscell(resI)
                    resI = resI{1};
                end
                opts = resI.options;
                if iscell(opts)
                    opts = opts{1};
                end
                rawOptions{i} = opts;
            catch ex
                warning("GetVolSurface:ExpiryFailed", ...
                    "Failed to download expiry %s: %s", string(expiryDates(i)), ex.message);
                rawOptions{i} = [];
            end
        end

        if mod(i, 10) == 0
            fprintf("  ... downloaded %d/%d expiries\n", i, nExpiries);
        end
    end
end

%% --- Surface Calibration ---

function slices = buildSlices(rawOptions, expiryDates, S, r, q)
% buildSlices Process each expiry and calibrate SVI parameters
    nExpiries = numel(rawOptions);
    sliceList = [];

    for i = 1:nExpiries
        if isempty(rawOptions{i})
            continue;
        end

        T_i = yearfrac(datetime("now"), expiryDates(i));
        if T_i < 1/365
            continue;
        end

        F_i = S * exp((r - q) * T_i);

        opts = rawOptions{i};
        calls = extractChain(opts, "calls", S, F_i, T_i);
        puts = extractChain(opts, "puts", S, F_i, T_i);

        if isempty(calls) && isempty(puts)
            continue;
        elseif isempty(calls)
            chain = puts(:);
        elseif isempty(puts)
            chain = calls(:);
        else
            chain = [calls(:); puts(:)];
        end
        if isempty(chain)
            continue;
        end

        chain = filterChain(chain);
        if numel(chain) < 5
            continue;
        end

        strikes = [chain.strike]';
        ivVals = [chain.iv]';
        weights = [chain.weight]';
        k = log(strikes / F_i);
        w = ivVals.^2 * T_i;

        [sviParams, fitRMSE] = calibrateSVI(k, w, weights);
        if isempty(sviParams)
            warning("GetVolSurface:SVIFailed", "SVI calibration failed for T=%.3f", T_i);
            continue;
        end

        slice.expiry = expiryDates(i);
        slice.T = T_i;
        slice.forward = F_i;
        slice.sviParams = sviParams;
        slice.fitRMSE = fitRMSE;
        slice.kRange = [min(k), max(k)];
        slice.nPoints = numel(chain);

        if isempty(sliceList)
            sliceList = slice;
        else
            sliceList(end + 1) = slice; %#ok<AGROW>
        end
    end

    [~, sortIdx] = sort([sliceList.T]);
    slices = sliceList(sortIdx);
end

function chain = extractChain(opts, fieldName, S, F, T)
% extractChain Extract and process calls or puts from Yahoo data
    chain = struct("strike", {}, "iv", {}, "weight", {});

    if ~isfield(opts, fieldName)
        return;
    end

    raw = opts.(fieldName);
    if iscell(raw)
        raw = cellToStructArray(raw);
    end

    if isempty(raw)
        return;
    end

    for j = 1:numel(raw)
        item = raw(j);

        if ~isfield(item, "strike") || ~isfield(item, "impliedVolatility")
            continue;
        end

        strike = double(item.strike);
        ivVal = double(item.impliedVolatility);

        bid = 0;
        ask = 0;
        oi = 0;
        if isfield(item, "bid"), bid = double(item.bid); end
        if isfield(item, "ask"), ask = double(item.ask); end
        if isfield(item, "openInterest"), oi = double(item.openInterest); end

        if bid <= 0 || ask <= 0
            continue;
        end
        if oi < 10
            continue;
        end

        spread = (ask - bid) / ((ask + bid) / 2);
        if spread > 0.5
            continue;
        end

        isCall = (fieldName == "calls");
        if isCall && strike < F
            continue;
        end
        if ~isCall && strike > F
            continue;
        end

        if ivVal <= 0 || ivVal > 5 || isnan(ivVal)
            ivVal = computeIVFallback(strike, bid, ask, S, T, F, isCall);
            if isnan(ivVal)
                continue;
            end
        end

        entry.strike = strike;
        entry.iv = ivVal;
        entry.weight = 1 / max(spread, 0.01);

        if isempty(chain)
            chain = entry;
        else
            chain(end + 1) = entry; %#ok<AGROW>
        end
    end
end

function ivFallback = computeIVFallback(strike, bid, ask, S, T, ~, isCall)
% computeIVFallback Use blsimpv as fallback for bad Yahoo IV values
    midPrice = (bid + ask) / 2;
    r = getRiskFreeRate();
    try
        if isCall
            ivFallback = blsimpv(S, strike, r, T, midPrice, [], [], [], "call");
        else
            ivFallback = blsimpv(S, strike, r, T, midPrice, [], [], [], "put");
        end
        if isempty(ivFallback) || ivFallback <= 0
            ivFallback = NaN;
        end
    catch
        ivFallback = NaN;
    end
end

function chain = filterChain(chain)
% filterChain Remove outlier IV values using median deviation
    ivVals = [chain.iv];
    medIV = median(ivVals);
    madIV = median(abs(ivVals - medIV));
    keep = abs(ivVals - medIV) < 5 * max(madIV, 0.01);
    chain = chain(keep);
end

%% --- SVI Calibration ---

function [params, rmse] = calibrateSVI(k, wMarket, weights)
% calibrateSVI Fit SVI parameters to market total variance slice
%   SVI: w(k) = a + b*(rho*(k-m) + sqrt((k-m)^2 + sigma^2))
%   params = [a, b, rho, m, sigma]
    params = [];
    rmse = Inf;

    wAtm = interp1(k, wMarket, 0, "linear", "extrap");
    wAtm = max(wAtm, 0.001);

    x0 = [wAtm, 0.1, -0.3, 0, 0.2];
    lb = [0.0001, 0.001, -0.99, min(k) - 0.5, 0.001];
    ub = [2.0, 5.0, 0.99, max(k) + 0.5, 5.0];

    wSqrt = sqrt(weights / max(weights));

    objFun = @(p) wSqrt .* (evalSVI(p, k) - wMarket);

    opts = optimoptions("lsqnonlin", "Display", "off", ...
        "MaxIterations", 500, "MaxFunctionEvaluations", 5000, ...
        "FunctionTolerance", 1e-12, "StepTolerance", 1e-10);

    try
        [pBest, resnorm] = lsqnonlin(objFun, x0, lb, ub, opts);
        rmse = sqrt(resnorm / numel(k));

        if rmse > 0.005
            [pBest, rmse] = multiStartSVI(objFun, lb, ub, opts, k, wMarket, pBest, rmse);
        end

        if pBest(1) + pBest(2) * pBest(5) * sqrt(1 - pBest(3)^2) < 0
            [pBest, rmse] = constrainedSVI(k, wMarket, wSqrt, pBest, lb, ub);
        end

        params = pBest;
    catch
        try
            [params, rmse] = constrainedSVI(k, wMarket, wSqrt, x0, lb, ub);
        catch
            params = [];
            rmse = Inf;
        end
    end
end

function [pBest, bestRMSE] = multiStartSVI(objFun, lb, ub, opts, k, wMarket, pBest, bestRMSE)
% multiStartSVI Try multiple starting points for SVI calibration
    rng("default");
    for trial = 1:3
        x0_rand = lb + (ub - lb) .* rand(1, 5);
        x0_rand(3) = -0.5 + rand() * 0.8;
        try
            [pTrial, resnorm] = lsqnonlin(objFun, x0_rand, lb, ub, opts);
            trialRMSE = sqrt(resnorm / numel(k));
            if trialRMSE < bestRMSE
                pBest = pTrial;
                bestRMSE = trialRMSE;
            end
        catch
            continue;
        end
    end

    if bestRMSE > 0.01
        wAtm = interp1(k, wMarket, 0, "linear", "extrap");
        coeffs = polyfit(k, wMarket, 2);
        x0_quad = [max(wAtm, 0.001), max(2*coeffs(1), 0.01), -0.2, -coeffs(2)/(2*coeffs(1) + eps), 0.1];
        x0_quad = max(min(x0_quad, ub), lb);
        try
            [pTrial, resnorm] = lsqnonlin(objFun, x0_quad, lb, ub, opts);
            trialRMSE = sqrt(resnorm / numel(k));
            if trialRMSE < bestRMSE
                pBest = pTrial;
                bestRMSE = trialRMSE;
            end
        catch
        end
    end
end

function [params, rmse] = constrainedSVI(k, wMarket, wSqrt, x0, lb, ub)
% constrainedSVI Use fmincon to enforce no-arb vertex constraint
    objFun2 = @(p) sum((wSqrt .* (evalSVI(p, k) - wMarket)).^2);

    nlcon = @(p) deal(-(p(1) + p(2)*p(5)*sqrt(1 - p(3)^2)), 0);

    fmOpts = optimoptions("fmincon", "Display", "off", ...
        "MaxIterations", 500, "MaxFunctionEvaluations", 5000);

    [params, fval] = fmincon(objFun2, x0, [], [], [], [], lb, ub, nlcon, fmOpts);
    rmse = sqrt(fval / numel(k));
end

function w = evalSVI(params, k)
% evalSVI Evaluate SVI total variance formula
%   w(k) = a + b*(rho*(k-m) + sqrt((k-m)^2 + sigma^2))
    a = params(1);
    b = params(2);
    rho = params(3);
    m = params(4);
    sigma = params(5);

    km = k - m;
    w = a + b * (rho * km + sqrt(km.^2 + sigma^2));
end

%% --- Interpolation ---

function iv = interpolateSurface(T, K, surface)
% interpolateSurface Query the calibrated SVI surface at (T, K) pairs
    slices = surface.slices;
    S = surface.spotPrice;
    r = surface.riskFreeRate;
    q = surface.divYield;
    Tslices = [slices.T];
    nQuery = numel(T);
    iv = zeros(nQuery, 1);

    for i = 1:nQuery
        Ti = T(i);
        Ki = K(i);

        Fi = S * exp((r - q) * max(Ti, 1/365));
        ki = log(Ki / Fi);

        if Ti <= Tslices(1)
            w = evalSVI(slices(1).sviParams, ki);
            w = max(w, 0);
            iv(i) = sqrt(w / Tslices(1));
        elseif Ti >= Tslices(end)
            wLast = evalSVI(slices(end).sviParams, ki);
            wLast = max(wLast, 0);
            growthRate = wLast / Tslices(end);
            w = growthRate * Ti;
            iv(i) = sqrt(w / Ti);
        else
            idxHi = find(Tslices >= Ti, 1, "first");
            idxLo = idxHi - 1;

            Tlo = Tslices(idxLo);
            Thi = Tslices(idxHi);
            alpha = (Ti - Tlo) / (Thi - Tlo);

            Flo = S * exp((r - q) * Tlo);
            Fhi = S * exp((r - q) * Thi);
            kLo = log(Ki / Flo);
            kHi = log(Ki / Fhi);

            wLo = evalSVI(slices(idxLo).sviParams, kLo);
            wHi = evalSVI(slices(idxHi).sviParams, kHi);
            wLo = max(wLo, 0);
            wHi = max(wHi, 0);

            w = (1 - alpha) * wLo + alpha * wHi;
            iv(i) = sqrt(w / Ti);
        end

        iv(i) = max(iv(i), 0.01);
        iv(i) = min(iv(i), 5.0);

        if isnan(iv(i))
            warning("GetVolSurface:NaNIV", "NaN IV at T=%.3f, K=%.1f. Setting to 1%%.", Ti, Ki);
            iv(i) = 0.01;
        end
    end
end

%% --- Visualization ---

function plotVolSurface(surface)
% plotVolSurface Render 3D vol surface and 2D smile slices
    slices = surface.slices;
    S = surface.spotPrice;

    Tvals = linspace(min([slices.T]), max([slices.T]), 40);
    moneyRange = linspace(0.85, 1.15, 50);
    [Tgrid, Mgrid] = meshgrid(Tvals, moneyRange);
    Kgrid = Mgrid * S;
    IVgrid = zeros(size(Tgrid));

    for row = 1:size(Tgrid, 1)
        for col = 1:size(Tgrid, 2)
            IVgrid(row, col) = interpolateSurface(Tgrid(row, col), Kgrid(row, col), surface);
        end
    end

    figure("Name", "SPY Implied Volatility Surface", "NumberTitle", "off");

    subplot(1, 2, 1);
    surf(Tgrid, Mgrid, IVgrid * 100, "EdgeAlpha", 0.3);
    xlabel("Time to Expiry (years)");
    ylabel("Moneyness (K/S)");
    zlabel("Implied Volatility (%)");
    title(sprintf("SPY Vol Surface (S=%.2f)", S));
    colorbar();
    view([-30, 25]);

    subplot(1, 2, 2);
    nShow = min(6, numel(slices));
    indices = round(linspace(1, numel(slices), nShow));
    colors = lines(nShow);
    hold("on");
    legendEntries = strings(nShow, 1);
    for j = 1:nShow
        idx = indices(j);
        sl = slices(idx);
        kPlot = linspace(sl.kRange(1), sl.kRange(2), 100);
        wPlot = evalSVI(sl.sviParams, kPlot);
        ivPlot = sqrt(max(wPlot, 0) / sl.T) * 100;
        plot(kPlot, ivPlot, "Color", colors(j, :), "LineWidth", 1.5);
        legendEntries(j) = sprintf("T=%.2f (%s)", sl.T, string(sl.expiry, "MMM-yy"));
    end
    hold("off");
    xlabel("Log-Moneyness ln(K/F)");
    ylabel("Implied Volatility (%)");
    title("Volatility Smiles (SVI Fits)");
    legend(legendEntries, "Location", "best");
    grid("on");
end

%% --- Utilities ---

function sArr = cellToStructArray(c)
% cellToStructArray Convert cell array of structs to struct array
    if ~iscell(c) || isempty(c)
        sArr = [];
        return;
    end

    c = homogenizeStructs(c);
    sArr = [c{:}];
    sArr = sArr(:);
end

function c = homogenizeStructs(c)
% homogenizeStructs Ensure all structs in cell array have same fields
    allFields = {};
    for i = 1:numel(c)
        if isstruct(c{i})
            allFields = union(allFields, fieldnames(c{i}));
        end
    end

    for i = 1:numel(c)
        if isstruct(c{i})
            for j = 1:numel(allFields)
                if ~isfield(c{i}, allFields{j})
                    c{i}.(allFields{j}) = NaN;
                end
            end
        end
    end
end
