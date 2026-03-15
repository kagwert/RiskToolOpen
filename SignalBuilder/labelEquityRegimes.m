function labels = labelEquityRegimes(equityPrices, monthGrid, opts)
% labelEquityRegimes  Assign Neutral / MildUW / SevereUW labels using
%                     forward-looking equity return and realised volatility.
%
%   labels = labelEquityRegimes(equityPrices, monthGrid)
%   labels = labelEquityRegimes(equityPrices, monthGrid, SevereVolThresh=0.30)
%
%   For each month-end date in monthGrid, computes the forward 3-month
%   simple cumulative return and forward 3-month annualised realised
%   volatility from daily equity prices.  Labels are assigned as:
%
%       SevereUW (2):  fwd_ret < SevereRetThresh  AND
%                      fwd_vol_ann > SevereVolThresh
%                      → typically recessions / bear markets
%
%       MildUW   (1):  fwd_ret < MildRetThresh  AND NOT SevereUW
%                      → negative expected return, manageable vol
%
%       Neutral  (0):  all other periods
%
%   IMPORTANT: The final LookforwardDays trading days of the sample will
%   have NaN labels because forward data is unavailable.  Exclude NaN rows
%   before training any model.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   equityPrices       timetable  – daily prices with a 'Close' column
%                                   (e.g. from Model.MarketData.Prices)
%   monthGrid          datetime   – monthly end-of-month dates (no timezone)
%                                   as produced by buildSignals()
%
%   LookforwardDays    (1,1) int  – forward window in trading days
%                                   [default 63 ≈ 3 calendar months]
%   SevereRetThresh    (1,1) dbl  – 3m cumulative return threshold for Severe
%                                   [default 0 — any negative return]
%   SevereVolThresh    (1,1) dbl  – 3m forward annualised vol threshold for Severe
%                                   [default 0.30 — 30%]
%   MildRetThresh      (1,1) dbl  – 3m cumulative return threshold for Mild
%                                   (must be ≥ SevereRetThresh)
%                                   [default 0 — any negative return]
%
% -------------------------------------------------------------------------
%  OUTPUT COLUMNS
% -------------------------------------------------------------------------
%   FwdReturn3m  – simple 3-month forward cumulative return (decimal)
%   FwdVol3m     – forward 3-month annualised realised vol (decimal)
%   Label        – 0 (Neutral), 1 (MildUW), 2 (SevereUW), NaN (no fwd data)
%   LabelStr     – 'Neutral' | 'MildUW' | 'SevereUW' | 'NaN'
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager(); dm.init();
%   tt_spy = dm.fetch_stooq('SPY', '1994-01-01', '');
%   md = Model.MarketData('SPY');
%   md.loadFromTimetable(tt_spy, 'Stooq');
%   features = buildSignals(dm);
%   labels   = labelEquityRegimes(md.Prices, features.Time);
%   disp(table(labels.Time, labels.LabelStr, labels.FwdReturn3m, labels.FwdVol3m, ...
%       'VariableNames', {'Month','Regime','Fwd3mRet','Fwd3mVol'}))

    arguments
        equityPrices                  timetable
        monthGrid                     (:,1) datetime
        opts.LookforwardDays          (1,1) double {mustBePositive, mustBeInteger} = 63
        opts.SevereRetThresh          (1,1) double = 0
        opts.SevereVolThresh          (1,1) double {mustBePositive}               = 0.30
        opts.MildRetThresh            (1,1) double = 0
    end

    if ~ismember('Close', equityPrices.Properties.VariableNames)
        error('SignalBuilder:labelEquityRegimes:missingColumn', ...
            'equityPrices must contain a ''Close'' column.');
    end
    if opts.MildRetThresh < opts.SevereRetThresh
        error('SignalBuilder:labelEquityRegimes:badParam', ...
            'MildRetThresh (%.3f) must be >= SevereRetThresh (%.3f).', ...
            opts.MildRetThresh, opts.SevereRetThresh);
    end

    close    = equityPrices.Close;
    dailyT   = equityPrices.Time;
    % Daily log return (used for vol; first element is NaN by convention)
    dailyRet = [NaN; diff(log(close))];

    n       = numel(monthGrid);
    fwdRet  = nan(n, 1);
    fwdVol  = nan(n, 1);
    nFwdNaN = 0;

    for k = 1 : n
        % Anchor: last trading day on or before this month-end
        % Year+month comparison avoids timezone mismatch between
        % monthly grid (no TZ) and dailyT (may have TZ)
        anchorYM  = year(monthGrid(k)) * 100 + month(monthGrid(k));
        dailyYM   = year(dailyT) * 100 + month(dailyT);
        dayInMonth = find(dailyYM == anchorYM, 1, 'last');

        if isempty(dayInMonth)
            nFwdNaN = nFwdNaN + 1;
            continue;
        end

        idx0 = dayInMonth;
        idx1 = idx0 + opts.LookforwardDays;

        if idx1 > numel(close)
            nFwdNaN = nFwdNaN + 1;
            continue;   % insufficient future data
        end

        % 3-month forward simple cumulative return
        fwdRet(k) = (close(idx1) - close(idx0)) / close(idx0);

        % 3-month forward annualised realised volatility (from daily log rets)
        window    = dailyRet(idx0+1 : idx1);
        fwdVol(k) = std(window, 'omitnan') * sqrt(252);
    end

    % ------------------------------------------------------------------ %
    % Assign labels (priority order: Severe overrides Mild)
    % ------------------------------------------------------------------ %
    label = nan(n, 1);
    hasData = ~isnan(fwdRet) & ~isnan(fwdVol);

    label(hasData) = 0;   % Neutral (default for labelled periods)

    isMild   = hasData & fwdRet < opts.MildRetThresh;
    isSevere = hasData & fwdRet < opts.SevereRetThresh & fwdVol > opts.SevereVolThresh;

    label(isMild)   = 1;   % Mild overrides Neutral
    label(isSevere) = 2;   % Severe overrides Mild

    % String labels for display
    labelMap = {'Neutral'; 'MildUW'; 'SevereUW'};
    labelStr = strings(n, 1);
    for k = 1 : n
        if isnan(label(k))
            labelStr(k) = "NaN";
        else
            labelStr(k) = labelMap{label(k) + 1};
        end
    end

    % ------------------------------------------------------------------ %
    % Pack into timetable
    % ------------------------------------------------------------------ %
    labels = timetable(monthGrid, fwdRet, fwdVol, label, labelStr, ...
        'VariableNames', {'FwdReturn3m','FwdVol3m','Label','LabelStr'});
    labels.Properties.DimensionNames{1} = 'Time';
    labels.Properties.Description = sprintf( ...
        ['Equity regime labels | Severe: 3mRet<%.0f%% & Vol>%.0f%%, ' ...
         'Mild: 3mRet<%.0f%%'], ...
        opts.SevereRetThresh*100, opts.SevereVolThresh*100, ...
        opts.MildRetThresh*100);
    labels.Properties.VariableUnits = {'','','',''};

    % ------------------------------------------------------------------ %
    % Summary
    % ------------------------------------------------------------------ %
    total    = sum(hasData);
    nNeutral = sum(label == 0, 'omitnan');
    nMild    = sum(label == 1, 'omitnan');
    nSevere  = sum(label == 2, 'omitnan');

    fprintf('\n[labelEquityRegimes] Label summary (%d months labelled, %d NaN):\n', ...
        total, nFwdNaN);
    fprintf('  Neutral  : %3d months (%4.1f%%)\n', nNeutral, 100*nNeutral/total);
    fprintf('  MildUW   : %3d months (%4.1f%%)\n', nMild,    100*nMild/total);
    fprintf('  SevereUW : %3d months (%4.1f%%)\n', nSevere,  100*nSevere/total);
    fprintf('  Thresholds: SevereRet<%.0f%%, SevereVol>%.0f%%, MildRet<%.0f%%\n\n', ...
        opts.SevereRetThresh*100, opts.SevereVolThresh*100, opts.MildRetThresh*100);
end
