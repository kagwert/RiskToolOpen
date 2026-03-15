function tt = payrollsMomentum(dm, opts)
% payrollsMomentum  Smooth, bounded momentum signal from FRED Total Nonfarm Payrolls.
%
%   tt = Model.payrollsMomentum(dm)
%   tt = Model.payrollsMomentum(dm, PrefilterWindow=3, SmoothHalfLife=3)
%   tt = Model.payrollsMomentum(dm, WinsorPct=95, TanhScale=1.0)
%
%   Fetches PAYEMS (Total Nonfarm Payrolls, thousands, monthly SA) from FRED
%   via the supplied DataManager and returns a timetable containing:
%
%       Payrolls    – raw monthly level (thousands)
%       dPayrolls   – month-over-month change (thousands of jobs)
%       SmoothedMom – prefiltered + EMA-smoothed momentum (numerator)
%       Signal      – bounded momentum signal in the open interval (-1, +1)
%
% -------------------------------------------------------------------------
%  SIGNAL CONSTRUCTION
% -------------------------------------------------------------------------
%  Step 1  Raw momentum:    dP_t = P_t − P_{t−1}
%
%  Step 2  Median prefilter (noise gate for the numerator):
%                           dP_filt_t = median(dP_{t-W+1} … dP_t)
%                           W = PrefilterWindow (default 3)
%
%          This is the key addition for noise reduction without reactivity
%          loss.  The trailing median acts as a gate:
%            • ONE anomalous month (weather, strike, seasonal revision):
%              the median of three months is the middle value, so a single
%              outlier is replaced by a neighbour — no impact on signal.
%            • TWO OR MORE months in the same direction (genuine shift):
%              the median equals that direction — passes through unchanged.
%          Contrast with increasing SmoothHalfLife: a longer EMA adds the
%          same lag to both noise and genuine inflections.  The median
%          prefilter adds at most 1 month of lag to genuine changes while
%          completely suppressing isolated prints.
%
%  Step 3  EMA smoothing:   M_t = α·dP_filt_t + (1−α)·M_{t−1}
%                           α   = 1 − exp(−ln2 / SmoothHalfLife)
%          Applied to the prefiltered series, not raw dP.
%
%  Step 4  Causal winsorization of RAW dP for the denominator only:
%                           dP_wins_t = sign(dP_t)·min(|dP_t|, Q_t)
%                           Q_t = expanding percentile of |dP_1…t|
%          Prevents catastrophic shocks (Apr 2020: ≈ −20,700 K) from
%          inflating rollStd and muting the signal for years afterward.
%          The denominator uses raw (not prefiltered) dP so that genuine
%          regime volatility is captured in σ.
%
%  Step 5  Adaptive norm:   σ_t = std(dP_wins, trailing NormWindow months)
%
%  Step 6  Z-score:         z_t = M_t / σ_t
%
%  Step 7  Tanh mapping:    S_t = tanh(TanhScale · z_t)  ∈ (−1, +1)
%
%  ┌─────────────────────────────────────────────────────────────────┐
%  │  Numerator path:  dP → median prefilter → EMA → M_t            │
%  │  Denominator path: dP → winsorize → rollStd → σ_t              │
%  │  Signal:  tanh(TanhScale · M_t / σ_t)                          │
%  └─────────────────────────────────────────────────────────────────┘
%
%  Calibration with defaults (PrefilterWindow=3, SmoothHalfLife=3,
%                             NormWindow=60, TanhScale=1, WinsorPct=95):
%      Regime                      dP (raw)    Approx Signal
%      ──────────────────────────────────────────────────────
%      Post-COVID boom             +900 K      ≈ +0.93
%      Solid expansion             +200 K      ≈ +0.80
%      Moderate growth             +100 K      ≈ +0.59
%      Stalling                     +20 K      ≈ +0.13
%      Flat / no-growth               0 K       0.00
%      Mild contraction            −100 K      ≈ −0.59
%      Recession                   −300 K      ≈ −0.93
%      Isolated spike (1 month)    ±500 K      ≈ ±0.00  ← prefiltered away
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm                (1,1) Model.DataManager  – initialised DataManager
%
%   PrefilterWindow   (1,1) integer ≥ 1        – trailing median window (months)
%                                                applied to dP before EMA.
%                                                1 = disabled (no prefilter).
%                                                3 = default: removes isolated
%                                                    one-month anomalies.
%                                                5 = stronger; removes up to
%                                                    2 consecutive anomalies.
%
%   SmoothHalfLife    (1,1) double > 0         – EMA half-life in months,
%                                                applied after prefilter.
%                                                (default 3)
%
%   NormWindow        (1,1) integer ≥ 12       – trailing window for rolling
%                                                std normalisation (months).
%                                                (default 60)
%
%   TanhScale         (1,1) double > 0         – scales z before tanh;
%                                                > 1 steepens, < 1 flattens.
%                                                (default 1.0)
%
%   WinsorPct         (1,1) double [0, 100)    – expanding-window percentile
%                                                cap for rollStd denominator.
%                                                0 = disabled. (default 95)
%
%   StartDate         (1,1) string             – FRED fetch start 'yyyy-MM-dd'
%                                                (default "" → full history)
%
% -------------------------------------------------------------------------
%  TUNING GUIDE
% -------------------------------------------------------------------------
%   Goal                              Suggested change
%   ────────────────────────────────────────────────────────────────────
%   Less noise, same trend lag        PrefilterWindow 3 → 5
%   Faster reaction to trend shifts   SmoothHalfLife  3 → 2
%   Signal more decisive (±0.7+)      TanhScale       1 → 1.3
%   Signal more graded (stays ±0.5)   TanhScale       1 → 0.7
%   Sharper post-shock recovery       WinsorPct      95 → 97
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager();
%   dm.init();
%   tt = Model.payrollsMomentum(dm);
%
%   % Compare prefiltered vs raw
%   tt_raw  = Model.payrollsMomentum(dm, PrefilterWindow=1);
%   tt_filt = Model.payrollsMomentum(dm, PrefilterWindow=3);
%
%   % Plot
%   figure;
%   yyaxis left
%   bar(tt.Time, tt.dPayrolls, 'FaceAlpha', 0.3); ylabel('MoM change (K jobs)')
%   yyaxis right
%   plot(tt_raw.Time,  tt_raw.Signal,  ':', 'LineWidth', 1, 'DisplayName', 'No prefilter')
%   hold on
%   plot(tt_filt.Time, tt_filt.Signal, '-', 'LineWidth', 2, 'DisplayName', 'Prefilter=3')
%   yline(0,'k--'); ylim([-1.1 1.1]); ylabel('Signal'); legend; grid on
%   title(tt_filt.Properties.Description)

    arguments
        dm                   (1,1) Model.DataManager
        opts.PrefilterWindow (1,1) double {mustBePositive, mustBeInteger} = 3
        opts.SmoothHalfLife  (1,1) double {mustBePositive}                = 3
        opts.NormWindow      (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.TanhScale       (1,1) double {mustBePositive}                = 1.0
        opts.WinsorPct       (1,1) double                                 = 95
        opts.StartDate       (1,1) string                                 = ""
    end

    if opts.NormWindow < 12
        error('SignalBuilder:payrollsMomentum:badParam', ...
            'NormWindow must be >= 12 months; got %d.', opts.NormWindow);
    end
    if opts.WinsorPct < 0 || opts.WinsorPct >= 100
        error('SignalBuilder:payrollsMomentum:badParam', ...
            'WinsorPct must be in [0, 100); got %g.', opts.WinsorPct);
    end

    SERIES_ID   = 'PAYEMS';
    MIN_WIN_OBS = 24;   % months before the expanding winsorization cap is reliable

    % ------------------------------------------------------------------ %
    % 1. Fetch PAYEMS from FRED (cache-aware)
    % ------------------------------------------------------------------ %
    rawTT = dm.fetch_fred(SERIES_ID, opts.StartDate);

    if isempty(rawTT)
        error('SignalBuilder:payrollsMomentum:noData', ...
            'DataManager returned an empty timetable for FRED:%s.', SERIES_ID);
    end

    colName = matlab.lang.makeValidName(SERIES_ID);   % → 'PAYEMS'
    if ~ismember(colName, rawTT.Properties.VariableNames)
        error('SignalBuilder:payrollsMomentum:unexpectedSchema', ...
            'Expected column "%s" in FRED timetable; found: %s.', ...
            colName, strjoin(rawTT.Properties.VariableNames, ', '));
    end

    rawTT  = sortrows(rawTT);
    times  = rawTT.Time;
    levels = rawTT.(colName);
    n      = numel(levels);

    if n < opts.NormWindow + 2
        error('SignalBuilder:payrollsMomentum:insufficientData', ...
            'Need at least %d observations to compute signal; got %d.', ...
            opts.NormWindow + 2, n);
    end

    % ------------------------------------------------------------------ %
    % 2. Month-over-month change
    % ------------------------------------------------------------------ %
    dP        = nan(n, 1);
    dP(2:end) = diff(levels);

    % ------------------------------------------------------------------ %
    % 3. Trailing median prefilter on dP  →  dP_filt  (NUMERATOR PATH)
    %
    %    movmedian with a [W-1, 0] lag vector gives a strictly trailing
    %    (causal) window of W observations: current + W-1 prior months.
    %
    %    Effect on different signal types:
    %      Isolated spike  (1 month): median = middle of 3 → neighbour value
    %      Genuine move    (2+ months in same direction): median = that direction
    %      Trend inflection (gradual): at most 1 month of additional lag
    %
    %    The denominator (rollStd) is NOT prefiltered — it uses raw dP so
    %    that genuine regime volatility is faithfully represented in σ.
    % ------------------------------------------------------------------ %
    W_pre = opts.PrefilterWindow;
    if W_pre > 1
        dP_filt = movmedian(dP, [W_pre - 1, 0], 'omitnan');
    else
        dP_filt = dP;   % PrefilterWindow = 1 → identity (disabled)
    end

    % ------------------------------------------------------------------ %
    % 4. EMA smoothing of prefiltered dP  →  smoothed  (NUMERATOR)
    %    alpha = 1 - exp(-ln2 / halfLife) gives exact half-life semantics.
    %    NaN gaps (FRED revisions, early history) are bridged by carrying
    %    the previous smoothed value rather than restarting the EMA.
    % ------------------------------------------------------------------ %
    alpha    = 1 - exp(-log(2) / opts.SmoothHalfLife);
    smoothed = nan(n, 1);

    firstValid = find(~isnan(dP_filt), 1);
    if isempty(firstValid)
        error('SignalBuilder:payrollsMomentum:allNaN', ...
            'All month-over-month changes are NaN — cannot compute signal.');
    end

    smoothed(firstValid) = dP_filt(firstValid);
    for i = firstValid + 1 : n
        if isnan(dP_filt(i))
            smoothed(i) = smoothed(i-1);           % carry forward through gaps
        else
            smoothed(i) = alpha * dP_filt(i) + (1 - alpha) * smoothed(i-1);
        end
    end

    % ------------------------------------------------------------------ %
    % 5. Causal expanding-window winsorization of RAW dP (DENOMINATOR PATH)
    %
    %    Cap = expanding percentile of |dP(1..t)|, applied only once
    %    MIN_WIN_OBS valid observations have accumulated.
    %    The prefiltered series is deliberately NOT used here: we want σ to
    %    reflect genuine volatility in the underlying series, not an
    %    artificially smoothed version of it.
    % ------------------------------------------------------------------ %
    dP_wins = dP;

    if opts.WinsorPct > 0
        validSoFar = [];
        for i = 1 : n
            if isnan(dP(i))
                continue
            end
            validSoFar(end+1, 1) = abs(dP(i)); %#ok<AGROW>
            if numel(validSoFar) >= MIN_WIN_OBS
                capVal = payrollsMomentum_prctile(validSoFar, opts.WinsorPct);
                if abs(dP(i)) > capVal
                    dP_wins(i) = sign(dP(i)) * capVal;
                end
            end
        end
    end

    % ------------------------------------------------------------------ %
    % 6. Rolling standard deviation of winsorized dP  →  σ  (DENOMINATOR)
    %    Trailing window of NormWindow months; omitnan for internal gaps.
    %    Warm-up: require floor(W/2) or 12 valid obs before σ is trusted.
    % ------------------------------------------------------------------ %
    W       = opts.NormWindow;
    rollStd = movstd(dP_wins, [W - 1, 0], 0, 'omitnan');

    rollStd(rollStd < 1) = NaN;    % pathological: near-constant series

    minValid = max(12, floor(W / 2));
    for i = 1 : min(W - 1, n)
        window = dP_wins(max(1, i - W + 1) : i);
        if sum(~isnan(window)) < minValid
            rollStd(i) = NaN;
        end
    end

    % ------------------------------------------------------------------ %
    % 7. Z-score → tanh compression
    % ------------------------------------------------------------------ %
    zScore = smoothed ./ rollStd;
    signal = tanh(opts.TanhScale .* zScore);

    % ------------------------------------------------------------------ %
    % 8. Pack into timetable
    % ------------------------------------------------------------------ %
    tt = timetable(times, levels, dP, smoothed, signal, ...
        'VariableNames', {'Payrolls', 'dPayrolls', 'SmoothedMom', 'Signal'});
    tt.Properties.DimensionNames{1} = 'Time';

    tt.Properties.Description = sprintf( ...
        ['PAYEMS momentum | PrefilterWin=%d, SmoothHL=%g mo, ' ...
         'NormWin=%d mo, TanhScale=%g, WinsorPct=%g'], ...
        opts.PrefilterWindow, opts.SmoothHalfLife, ...
        opts.NormWindow, opts.TanhScale, opts.WinsorPct);

    tt.Properties.VariableUnits = {'K jobs', 'K jobs/mo', 'K jobs/mo', ''};

    tt.Properties.VariableDescriptions = { ...
        'Total Nonfarm Payrolls level (FRED PAYEMS, thousands)', ...
        'Month-over-month change in payrolls (thousands, raw)', ...
        sprintf(['Trailing-median(W=%d) prefiltered dP, ' ...
            'then EMA(halfLife=%g mo)'], ...
            opts.PrefilterWindow, opts.SmoothHalfLife), ...
        sprintf(['tanh(%g * EMA(median(dP)) / std(dP_winsorized)), ' ...
            'WinsorPct=%g'], opts.TanhScale, opts.WinsorPct)};
end

% =========================================================================
% Local helper — toolbox-free percentile (nearest-rank method).
% Used instead of prctile() to avoid a Statistics Toolbox dependency.
% x must be a non-empty numeric vector; p is a scalar in [0, 100].
% =========================================================================
function q = payrollsMomentum_prctile(x, p)
    x = sort(x(~isnan(x)));
    if isempty(x)
        q = NaN;
        return;
    end
    idx = max(1, ceil(p / 100 * numel(x)));
    q   = x(idx);
end
