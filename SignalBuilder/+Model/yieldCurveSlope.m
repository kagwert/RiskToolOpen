function tt = yieldCurveSlope(dm, opts)
% yieldCurveSlope  Bounded signal from FRED 10Y-2Y Treasury yield spread.
%
%   tt = Model.yieldCurveSlope(dm)
%   tt = Model.yieldCurveSlope(dm, ZScoreWindow=60, SmoothHalfLife=3)
%
%   Fetches T10Y2Y (10-Year minus 2-Year Treasury Constant Maturity Rate,
%   daily, %) from FRED via the supplied DataManager and returns a timetable:
%
%       Spread   – raw daily spread level (%)
%       ZScore   – causal rolling z-score of the spread
%       Signal   – EMA-smoothed, tanh-compressed signal in (-1, +1)
%                  Positive = steep curve (risk-on)
%                  Negative = flat / inverted curve (risk-off)
%
% -------------------------------------------------------------------------
%  SIGNAL CONSTRUCTION
% -------------------------------------------------------------------------
%  Step 1  Raw spread:   S_t  = T10Y_t − T2Y_t  (fetched from FRED)
%
%  Step 2  Rolling z-score (causal, trailing window W × 21 trading days):
%                        z_t  = (S_t − μ_t) / σ_t
%          where μ_t, σ_t are the trailing mean and std of the spread.
%          A steep curve (above historical average) → z > 0 → positive.
%          An inverted curve (below historical average) → z < 0 → negative.
%
%  Step 3  EMA smoothing (applied to z):
%                        m_t  = α·z_t + (1−α)·m_{t−1}
%                        α    = 1 − exp(−ln2 / SmoothHalfLife_days)
%          NaN gaps (weekends, FRED reporting lags) are bridged by carry.
%
%  Step 4  Tanh compression:
%                        S_t  = tanh(TanhScale · m_t)  ∈ (−1, +1)
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm                (1,1) Model.DataManager  – initialised DataManager
%   ZScoreWindow      (1,1) int   ≥ 12         – trailing z-score window (months)
%                                                [default 60]
%   SmoothHalfLife    (1,1) double > 0         – EMA half-life (months)
%                                                [default 3]
%   TanhScale         (1,1) double > 0         – steepness of tanh mapping
%                                                [default 1.0]
%   StartDate         (1,1) string             – FRED fetch start 'yyyy-MM-dd'
%                                                [default "" → full history]
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager(); dm.init();
%   tt = Model.yieldCurveSlope(dm);
%   plot(tt.Time, tt.Signal); yline(0,'k--'); ylim([-1.1 1.1])
%   title('10Y-2Y Yield Curve Signal')

    arguments
        dm                   (1,1) Model.DataManager
        opts.ZScoreWindow    (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.SmoothHalfLife  (1,1) double {mustBePositive}               = 3
        opts.TanhScale       (1,1) double {mustBePositive}               = 1.0
        opts.StartDate       (1,1) string                                 = ""
    end

    if opts.ZScoreWindow < 12
        error('SignalBuilder:yieldCurveSlope:badParam', ...
            'ZScoreWindow must be >= 12 months; got %d.', opts.ZScoreWindow);
    end

    SERIES_ID     = 'T10Y2Y';
    DAYS_PER_MON  = 21;   % approximate trading days per month

    % ------------------------------------------------------------------ %
    % 1. Fetch T10Y2Y from FRED (daily, %)
    % ------------------------------------------------------------------ %
    rawTT = dm.fetch_fred(SERIES_ID, opts.StartDate);

    if isempty(rawTT)
        error('SignalBuilder:yieldCurveSlope:noData', ...
            'DataManager returned an empty timetable for FRED:%s.', SERIES_ID);
    end

    colName = matlab.lang.makeValidName(SERIES_ID);   % → 'T10Y2Y'
    if ~ismember(colName, rawTT.Properties.VariableNames)
        error('SignalBuilder:yieldCurveSlope:unexpectedSchema', ...
            'Expected column "%s"; found: %s.', ...
            colName, strjoin(rawTT.Properties.VariableNames, ', '));
    end

    rawTT  = sortrows(rawTT);
    times  = rawTT.Time;
    spread = rawTT.(colName);   % daily spread in %
    n      = numel(spread);

    % Window in trading days
    W = opts.ZScoreWindow * DAYS_PER_MON;

    if n < W + 10
        error('SignalBuilder:yieldCurveSlope:insufficientData', ...
            'Need at least %d observations for ZScoreWindow=%d months; got %d.', ...
            W + 10, opts.ZScoreWindow, n);
    end

    % ------------------------------------------------------------------ %
    % 2. Causal rolling z-score
    %    movmean/movstd with [W-1, 0] lag vector = strictly trailing window.
    %    omitnan to bridge FRED NaN gaps (e.g. weekends in some releases).
    % ------------------------------------------------------------------ %
    rollMu  = movmean(spread, [W-1, 0], 'omitnan');
    rollSig = movstd( spread, [W-1, 0], 0, 'omitnan');

    % Suppress near-zero variance (e.g. during peg/floor periods)
    rollSig(rollSig < 1e-4) = NaN;

    zScore = (spread - rollMu) ./ rollSig;

    % ------------------------------------------------------------------ %
    % 3. EMA smoothing of z-score (half-life in trading days)
    %    NaN gaps are bridged by carrying the previous smoothed value.
    % ------------------------------------------------------------------ %
    halfLifeDays = opts.SmoothHalfLife * DAYS_PER_MON;
    alpha        = 1 - exp(-log(2) / halfLifeDays);
    smoothed     = nan(n, 1);

    firstValid = find(~isnan(zScore), 1);
    if isempty(firstValid)
        error('SignalBuilder:yieldCurveSlope:allNaN', ...
            'All z-scores are NaN — check data quality for FRED:%s.', SERIES_ID);
    end

    smoothed(firstValid) = zScore(firstValid);
    for i = firstValid + 1 : n
        if isnan(zScore(i))
            smoothed(i) = smoothed(i-1);      % carry forward across gaps
        else
            smoothed(i) = alpha * zScore(i) + (1 - alpha) * smoothed(i-1);
        end
    end

    % ------------------------------------------------------------------ %
    % 4. Tanh compression → bounded signal in (-1, +1)
    % ------------------------------------------------------------------ %
    signal = tanh(opts.TanhScale .* smoothed);

    % ------------------------------------------------------------------ %
    % 5. Pack into timetable
    % ------------------------------------------------------------------ %
    tt = timetable(times, spread, zScore, signal, ...
        'VariableNames', {'Spread', 'ZScore', 'Signal'});
    tt.Properties.DimensionNames{1} = 'Time';

    tt.Properties.Description = sprintf( ...
        'T10Y2Y yield curve signal | ZWin=%dmo, SmoothHL=%gmo, TanhScale=%g', ...
        opts.ZScoreWindow, opts.SmoothHalfLife, opts.TanhScale);

    tt.Properties.VariableUnits = {'%', '', ''};

    tt.Properties.VariableDescriptions = { ...
        '10Y-2Y Treasury Constant Maturity spread (FRED T10Y2Y, %)', ...
        sprintf('Causal rolling z-score (trailing window = %d months)', ...
            opts.ZScoreWindow), ...
        sprintf('tanh(%g × EMA(z, HL=%g mo)) | positive=steep, negative=inverted', ...
            opts.TanhScale, opts.SmoothHalfLife)};
end
