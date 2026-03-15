function tt = creditSpreadSignal(dm, opts)
% creditSpreadSignal  Bounded risk-off signal from FRED HY OAS credit spread.
%
%   tt = Model.creditSpreadSignal(dm)
%   tt = Model.creditSpreadSignal(dm, ZScoreWindow=60, WinsorPct=97)
%
%   Fetches BAMLH0A0HYM2 (ICE BofA US High Yield Index Option-Adjusted
%   Spread, daily, %) from FRED via the supplied DataManager and returns:
%
%       Spread   – raw daily OAS level (%)
%       ZScore   – causal rolling z-score of the spread
%       Signal   – EMA-smoothed, tanh-compressed signal in (-1, +1)
%                  INVERTED: wide spreads (stress) → negative signal
%                  Positive = tight spreads (risk-on)
%                  Negative = wide spreads (credit stress, risk-off)
%
% -------------------------------------------------------------------------
%  SIGNAL CONSTRUCTION
% -------------------------------------------------------------------------
%  Step 1  Raw OAS:   C_t  (daily, %)
%
%  Step 2  Expanding-window winsorization (DENOMINATOR PATH only):
%                     C_wins_t = min(C_t, Q_t)
%                     Q_t = expanding WinsorPct-percentile of C_{1..t}
%          Prevents GFC (2008: ~20%) and COVID (2020: ~11%) spikes from
%          inflating rollStd and muting the signal for years afterward.
%
%  Step 3  Causal rolling z-score (W × 21 trading days):
%                     z_t  = (C_t − μ_t) / σ_t
%          μ_t, σ_t computed on winsorized series for robustness.
%          Raw C_t is used in the numerator to preserve the current level.
%
%  Step 4  EMA smoothing (applied to z):
%                     m_t  = α·z_t + (1−α)·m_{t−1}
%
%  Step 5  Tanh compression, INVERTED (high spread → negative signal):
%                     S_t  = tanh(−TanhScale · m_t)  ∈ (−1, +1)
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm                (1,1) Model.DataManager  – initialised DataManager
%   ZScoreWindow      (1,1) int   ≥ 12         – trailing z-score window (months)
%                                                [default 60]
%   SmoothHalfLife    (1,1) double > 0         – EMA half-life (months)
%                                                [default 1] — reacts fast to
%                                                credit blowouts
%   TanhScale         (1,1) double > 0         – steepness of tanh mapping
%                                                [default 1.0]
%   WinsorPct         (1,1) double [0, 100)    – expanding-window percentile
%                                                cap for rollStd denominator.
%                                                0 = disabled. [default 97]
%   StartDate         (1,1) string             – FRED fetch start 'yyyy-MM-dd'
%                                                [default "" → full history]
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager(); dm.init();
%   tt = Model.creditSpreadSignal(dm);
%   yyaxis left;  plot(tt.Time, tt.Spread); ylabel('HY OAS (%)')
%   yyaxis right; plot(tt.Time, tt.Signal); yline(0,'k--'); ylim([-1.1 1.1])
%   title('HY Credit Spread Signal')

    arguments
        dm                   (1,1) Model.DataManager
        opts.ZScoreWindow    (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.SmoothHalfLife  (1,1) double {mustBePositive}               = 1
        opts.TanhScale       (1,1) double {mustBePositive}               = 1.0
        opts.WinsorPct       (1,1) double                                 = 97
        opts.StartDate       (1,1) string                                 = ""
    end

    if opts.ZScoreWindow < 12
        error('SignalBuilder:creditSpreadSignal:badParam', ...
            'ZScoreWindow must be >= 12 months; got %d.', opts.ZScoreWindow);
    end
    if opts.WinsorPct < 0 || opts.WinsorPct >= 100
        error('SignalBuilder:creditSpreadSignal:badParam', ...
            'WinsorPct must be in [0, 100); got %g.', opts.WinsorPct);
    end

    SERIES_ID     = 'BAMLH0A0HYM2';
    DAYS_PER_MON  = 21;
    MIN_WIN_OBS   = 24 * DAYS_PER_MON;   % ~2 years before winsor cap is reliable

    % ------------------------------------------------------------------ %
    % 1. Fetch BAMLH0A0HYM2 from FRED (daily, %)
    % ------------------------------------------------------------------ %
    rawTT = dm.fetch_fred(SERIES_ID, opts.StartDate);

    if isempty(rawTT)
        error('SignalBuilder:creditSpreadSignal:noData', ...
            'DataManager returned an empty timetable for FRED:%s.', SERIES_ID);
    end

    colName = matlab.lang.makeValidName(SERIES_ID);   % → 'BAMLH0A0HYM2'
    if ~ismember(colName, rawTT.Properties.VariableNames)
        error('SignalBuilder:creditSpreadSignal:unexpectedSchema', ...
            'Expected column "%s"; found: %s.', ...
            colName, strjoin(rawTT.Properties.VariableNames, ', '));
    end

    rawTT  = sortrows(rawTT);
    times  = rawTT.Time;
    spread = rawTT.(colName);   % daily OAS in %
    n      = numel(spread);

    W = opts.ZScoreWindow * DAYS_PER_MON;

    if n < W + 10
        error('SignalBuilder:creditSpreadSignal:insufficientData', ...
            'Need at least %d observations for ZScoreWindow=%d months; got %d.', ...
            W + 10, opts.ZScoreWindow, n);
    end

    % ------------------------------------------------------------------ %
    % 2. Expanding-window winsorization for rolling std denominator
    %    Caps extreme spikes (GFC 2008, COVID 2020) so they don't inflate
    %    σ and mute the signal for years afterward.
    % ------------------------------------------------------------------ %
    spread_wins = spread;

    if opts.WinsorPct > 0
        validSoFar = [];
        for i = 1 : n
            if isnan(spread(i)); continue; end
            validSoFar(end+1, 1) = spread(i); %#ok<AGROW>
            if numel(validSoFar) >= MIN_WIN_OBS
                capVal = creditSpreadSignal_prctile(validSoFar, opts.WinsorPct);
                if spread(i) > capVal
                    spread_wins(i) = capVal;
                end
            end
        end
    end

    % ------------------------------------------------------------------ %
    % 3. Causal rolling z-score on winsorized series
    %    Raw spread in numerator, winsorized stats in denominator.
    % ------------------------------------------------------------------ %
    rollMu  = movmean(spread_wins, [W-1, 0], 'omitnan');
    rollSig = movstd( spread_wins, [W-1, 0], 0, 'omitnan');

    rollSig(rollSig < 1e-4) = NaN;

    zScore = (spread - rollMu) ./ rollSig;   % raw spread / winsorized std

    % ------------------------------------------------------------------ %
    % 4. EMA smoothing
    % ------------------------------------------------------------------ %
    halfLifeDays = opts.SmoothHalfLife * DAYS_PER_MON;
    alpha        = 1 - exp(-log(2) / halfLifeDays);
    smoothed     = nan(n, 1);

    firstValid = find(~isnan(zScore), 1);
    if isempty(firstValid)
        error('SignalBuilder:creditSpreadSignal:allNaN', ...
            'All z-scores are NaN — check data quality for FRED:%s.', SERIES_ID);
    end

    smoothed(firstValid) = zScore(firstValid);
    for i = firstValid + 1 : n
        if isnan(zScore(i))
            smoothed(i) = smoothed(i-1);
        else
            smoothed(i) = alpha * zScore(i) + (1 - alpha) * smoothed(i-1);
        end
    end

    % ------------------------------------------------------------------ %
    % 5. Tanh compression — INVERTED
    %    Wide spreads (high z-score) → negative signal (underweight equities)
    % ------------------------------------------------------------------ %
    signal = tanh(-opts.TanhScale .* smoothed);

    % ------------------------------------------------------------------ %
    % 6. Pack into timetable
    % ------------------------------------------------------------------ %
    tt = timetable(times, spread, zScore, signal, ...
        'VariableNames', {'Spread', 'ZScore', 'Signal'});
    tt.Properties.DimensionNames{1} = 'Time';

    tt.Properties.Description = sprintf( ...
        ['HY OAS credit spread signal | ZWin=%dmo, SmoothHL=%gmo, ' ...
         'TanhScale=%g, WinsorPct=%g'], ...
        opts.ZScoreWindow, opts.SmoothHalfLife, opts.TanhScale, opts.WinsorPct);

    tt.Properties.VariableUnits = {'%', '', ''};

    tt.Properties.VariableDescriptions = { ...
        'ICE BofA US HY Index OAS (FRED BAMLH0A0HYM2, %)', ...
        sprintf('Causal rolling z-score (window=%d months, winsorized denom)', ...
            opts.ZScoreWindow), ...
        sprintf(['tanh(-%g × EMA(z, HL=%g mo)) | INVERTED: ' ...
            'wide=negative, tight=positive'], ...
            opts.TanhScale, opts.SmoothHalfLife)};
end

% =========================================================================
% Local helper — toolbox-free percentile (nearest-rank method).
% =========================================================================
function q = creditSpreadSignal_prctile(x, p)
    x = sort(x(~isnan(x)));
    if isempty(x); q = NaN; return; end
    idx = max(1, ceil(p / 100 * numel(x)));
    q   = x(idx);
end
