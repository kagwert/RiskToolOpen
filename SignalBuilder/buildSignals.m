function features = buildSignals(dm, equityTicker, opts)
% buildSignals  Assemble macro and market signals into a monthly feature timetable.
%
%   features = buildSignals(dm)
%   features = buildSignals(dm, 'SPY', StartDate='1994-01-01', MAWindow=200)
%
%   Fetches four signals, resamples them to a common monthly end-of-month
%   grid, and returns a synchronised timetable:
%
%       PayrollsMom   – FRED PAYEMS momentum signal        (-1,+1)
%       YieldCurve    – FRED T10Y2Y slope signal           (-1,+1)
%       CreditSpread  – FRED BAMLH0A0HYM2 spread signal   (-1,+1)
%       EquityTrend   – equityTicker price vs MA signal    (-1,+1)
%       Composite     – equal-weighted mean (NaN-tolerant) (-1,+1)
%
%   All signals: positive ≈ risk-on, negative ≈ risk-off.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm             (1,1) Model.DataManager  – initialised DataManager
%   equityTicker   (1,1) string             – ticker for price trend signal
%                                             [default 'SPY']
%   StartDate      (1,1) string             – data fetch start 'yyyy-MM-dd'
%                                             [default '1994-01-01']
%   MAWindow       (1,1) int > 0            – moving-average window (days)
%                                             [default 200]
%   TrendScale     (1,1) double > 0         – tanh scale for equity trend
%                                             10 → 10% above MA ≈ signal 0.76
%                                             [default 10]
%   PayrollsPrefilterWindow  (1,1) int      – [default 3]
%   PayrollsSmoothHalfLife   (1,1) double   – [default 3]
%   YieldZScoreWindow        (1,1) int      – [default 60]
%   YieldSmoothHalfLife      (1,1) double   – [default 3]
%   CreditZScoreWindow       (1,1) int      – [default 60]
%   CreditSmoothHalfLife     (1,1) double   – [default 1]
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager(); dm.init();
%   features = buildSignals(dm);

    arguments
        dm                              (1,1) Model.DataManager
        equityTicker                    (1,1) string = "SPY"
        opts.StartDate                  (1,1) string = "1994-01-01"
        opts.MAWindow                   (1,1) double {mustBePositive, mustBeInteger} = 200
        opts.TrendScale                 (1,1) double {mustBePositive}               = 10
        opts.PayrollsPrefilterWindow    (1,1) double {mustBePositive, mustBeInteger} = 3
        opts.PayrollsSmoothHalfLife     (1,1) double {mustBePositive}               = 3
        opts.YieldZScoreWindow          (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.YieldSmoothHalfLife        (1,1) double {mustBePositive}               = 3
        opts.CreditZScoreWindow         (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.CreditSmoothHalfLife       (1,1) double {mustBePositive}               = 1
    end

    % ------------------------------------------------------------------ %
    % 1. Equity prices → trailing MA trend signal (daily)
    %    Priority: Yahoo Finance → Stooq → FRED SP500 proxy.
    %    FRED SP500 (series 'SP500', from 1928) is used as a last resort
    %    when Yahoo is rate-limited and Stooq returns < 5 years.
    % ------------------------------------------------------------------ %
    fprintf('[buildSignals] Fetching %s prices (Yahoo Finance)...\n', equityTicker);
    tt_eq = timetable.empty;
    try
        tt_eq = dm.fetch_yahoo(equityTicker, opts.StartDate, "");
    catch ME_yf
        fprintf('[buildSignals] Yahoo failed (%s), trying Stooq...\n', ME_yf.message);
    end
    if height(tt_eq) < 252 * 25
        try
            tt_stooq = dm.fetch_stooq(equityTicker, opts.StartDate, "");
            if height(tt_stooq) > height(tt_eq)
                tt_eq = tt_stooq;
            end
        catch
        end
    end
    if height(tt_eq) < 252 * 25
        % Stooq ETF data may not cover full requested history; ^SPX index
        % (available from 1928 on Stooq) provides the missing pre-history.
        fprintf('[buildSignals] Price history shorter than 25yr (%d bars), trying Stooq ^SPX...\n', height(tt_eq));
        tt_eq = buildSignals_fredSp500(dm, opts.StartDate);
    end
    if height(tt_eq) < 252 * 5
        warning('SignalBuilder:buildSignals:shortHistory', ...
            ['Only %d daily bars returned for %s (expected 5+ years). ' ...
             'Labels and signals will cover a very short period.'], ...
            height(tt_eq), equityTicker);
    end
    fprintf('[buildSignals] %s price history: %d bars (%s to %s)\n', ...
        equityTicker, height(tt_eq), ...
        datestr(tt_eq.Time(1), 'mmm-yyyy'), datestr(tt_eq.Time(end), 'mmm-yyyy'));

    md = Model.MarketData(equityTicker);
    md.loadFromTimetable(tt_eq, 'Yahoo');

    close  = md.Prices.Close;
    eqTime = md.Prices.Time;
    N      = opts.MAWindow;

    % Causal moving average (trailing [N-1, 0] window)
    ma      = movmean(close, [N-1, 0], 'omitnan');
    % tanh( scale × (price/MA − 1) ): 10% above MA → tanh(1) ≈ 0.76
    eqTrend = tanh(opts.TrendScale .* ((close ./ ma) - 1));
    eqTrend(1 : N-1) = NaN;   % warm-up NaN

    tt_eqTrend = timetable(eqTime, eqTrend, 'VariableNames', {'EquityTrend'});
    tt_eqTrend.Properties.DimensionNames{1} = 'Time';

    % ------------------------------------------------------------------ %
    % 2. Macro signals
    % ------------------------------------------------------------------ %
    fprintf('[buildSignals] Fetching payrolls signal...\n');
    tt_payrolls = Model.payrollsMomentum(dm, ...
        PrefilterWindow = opts.PayrollsPrefilterWindow, ...
        SmoothHalfLife  = opts.PayrollsSmoothHalfLife, ...
        StartDate       = opts.StartDate);

    fprintf('[buildSignals] Fetching yield curve signal...\n');
    tt_yield = Model.yieldCurveSlope(dm, ...
        ZScoreWindow   = opts.YieldZScoreWindow, ...
        SmoothHalfLife = opts.YieldSmoothHalfLife, ...
        StartDate      = opts.StartDate);

    fprintf('[buildSignals] Fetching credit spread signal...\n');
    tt_credit = Model.creditSpreadSignal(dm, ...
        ZScoreWindow   = opts.CreditZScoreWindow, ...
        SmoothHalfLife = opts.CreditSmoothHalfLife, ...
        StartDate      = opts.StartDate);

    % ------------------------------------------------------------------ %
    % 3. Build monthly end-of-month grid from common data range
    %    Use year×100+month integer key to avoid timezone comparison issues.
    %
    %    Grid is anchored to the FIRST AVAILABLE PRICE DATE (not the first
    %    valid MA date after warmup).  The MA warm-up period will produce
    %    NaN for EquityTrend in those months, which downstream code handles
    %    correctly (NaN signal → base allocation; excluded from tree training).
    % ------------------------------------------------------------------ %
    % Latest start date across all series (gives common valid range)
    ym_starts = [ year(eqTime(1))         * 100 + month(eqTime(1)), ...
                  year(tt_payrolls.Time(1)) * 100 + month(tt_payrolls.Time(1)), ...
                  year(tt_yield.Time(1))    * 100 + month(tt_yield.Time(1)), ...
                  year(tt_credit.Time(1))   * 100 + month(tt_credit.Time(1)) ];
    ym_ends   = [ year(eqTime(end))             * 100 + month(eqTime(end)), ...
                  year(tt_payrolls.Time(end))   * 100 + month(tt_payrolls.Time(end)), ...
                  year(tt_yield.Time(end))      * 100 + month(tt_yield.Time(end)), ...
                  year(tt_credit.Time(end))     * 100 + month(tt_credit.Time(end)) ];

    ym0 = max(ym_starts);
    ym1 = min(ym_ends);

    y0 = floor(ym0 / 100);  m0 = mod(ym0, 100);
    y1 = floor(ym1 / 100);  m1 = mod(ym1, 100);

    % Monthly end-of-month grid (no timezone — avoids synchronize conflicts)
    monthStarts = (datetime(y0, m0, 1) : calmonths(1) : datetime(y1, m1, 1))';
    monthGrid   = dateshift(monthStarts, 'end', 'month');

    fprintf('[buildSignals] Monthly grid: %s to %s (%d months)\n', ...
        datestr(monthGrid(1), 'mmm-yyyy'), ...
        datestr(monthGrid(end), 'mmm-yyyy'), numel(monthGrid));

    % ------------------------------------------------------------------ %
    % 4. Resample each series to monthly (last non-NaN obs per month)
    %    Year×100+month comparison is timezone-agnostic.
    % ------------------------------------------------------------------ %
    vPayrolls = buildSignals_resampleMonthly(tt_payrolls.Time, tt_payrolls.Signal,      monthGrid);
    vYield    = buildSignals_resampleMonthly(tt_yield.Time,    tt_yield.Signal,          monthGrid);
    vCredit   = buildSignals_resampleMonthly(tt_credit.Time,   tt_credit.Signal,         monthGrid);
    vEqTrend  = buildSignals_resampleMonthly(tt_eqTrend.Time,  tt_eqTrend.EquityTrend,  monthGrid);

    % ------------------------------------------------------------------ %
    % 5. Assemble feature timetable
    % ------------------------------------------------------------------ %
    features = timetable(monthGrid, vPayrolls, vYield, vCredit, vEqTrend, ...
        'VariableNames', {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend'});
    features.Properties.DimensionNames{1} = 'Time';

    % Equal-weighted composite (NaN-tolerant: divide by count of valid signals)
    mat    = [vPayrolls, vYield, vCredit, vEqTrend];
    nValid = sum(~isnan(mat), 2);
    comp   = sum(mat, 2, 'omitnan') ./ max(nValid, 1);
    comp(nValid == 0) = NaN;
    features.Composite = comp;

    features.Properties.Description = sprintf( ...
        'Monthly signals | equity=%s, MA=%dd, start=%s', ...
        equityTicker, N, opts.StartDate);
    features.Properties.VariableDescriptions = { ...
        'PAYEMS payrolls momentum (-1=weak, +1=strong)', ...
        'T10Y2Y yield curve slope (-1=inverted, +1=steep)', ...
        'BAMLH0A0HYM2 HY spread (-1=wide/stress, +1=tight/calm)', ...
        sprintf('%s vs %d-day MA (-1=below, +1=above)', equityTicker, N), ...
        'Equal-weighted composite of all four signals'};

    fprintf('[buildSignals] Done: %d months × %d signal columns.\n', ...
        height(features), width(features));
end

% =========================================================================
% Local helper: fetch FRED SP500 daily close and wrap as OHLCV timetable.
%   Used when Yahoo Finance is rate-limited and Stooq returns < 5 years.
%   FRED 'SP500' series: daily S&P 500 close from 1928 (no API cost).
%   Calendar dates are extracted from UTC timestamps without conversion.
% =========================================================================
function tt = buildSignals_fredSp500(dm, startDate)
% Fall back to Stooq ^SPX (S&P 500 index, available from 1928).
% Note: FRED 'SP500' series only starts 2016-01-04; Stooq ^SPX covers
% the full history needed for a 30-year backtest.
    try
        tt = dm.fetch_stooq('^SPX', startDate, "");
        fprintf('[buildSignals] Stooq ^SPX fallback: %d bars (%s to %s)\n', ...
            height(tt), datestr(tt.Time(1), 'mmm-yyyy'), datestr(tt.Time(end), 'mmm-yyyy'));
    catch ME_spx
        error('SignalBuilder:buildSignals:noEquityData', ...
            ['Could not fetch equity prices from Yahoo, Stooq SPY, or Stooq ^SPX.\n' ...
             'Last error: %s'], ME_spx.message);
    end
end

% =========================================================================
% Local helper: resample a signal vector to a monthly end-of-month grid.
%   Returns the last non-NaN observation within each calendar month.
%   Uses year×100+month integer key to avoid timezone issues.
% =========================================================================
function vals = buildSignals_resampleMonthly(srcTime, srcVals, monthGrid)
    n     = numel(monthGrid);
    vals  = nan(n, 1);
    srcYM = year(srcTime) * 100 + month(srcTime);

    for k = 1 : n
        ym   = year(monthGrid(k)) * 100 + month(monthGrid(k));
        mask = srcYM == ym;
        v    = srcVals(mask);
        v    = v(~isnan(v));
        if ~isempty(v)
            vals(k) = v(end);   % last non-NaN observation in the month
        end
    end
end
