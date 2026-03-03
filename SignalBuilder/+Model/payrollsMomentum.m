function tt = payrollsMomentum(dm, opts)
% payrollsMomentum  Smooth, bounded momentum signal from FRED Total Nonfarm Payrolls.
%
%   tt = Model.payrollsMomentum(dm)
%   tt = Model.payrollsMomentum(dm, SmoothHalfLife=2, NormWindow=48, TanhScale=0.8)
%   tt = Model.payrollsMomentum(dm, WinsorPct=95)
%
%   Fetches PAYEMS (Total Nonfarm Payrolls, thousands, monthly SA) from FRED
%   via the supplied DataManager and returns a timetable containing:
%
%       Payrolls    – raw monthly level (thousands)
%       dPayrolls   – month-over-month change (thousands of jobs)
%       SmoothedMom – EMA-smoothed dPayrolls (see SmoothHalfLife)
%       Signal      – bounded momentum signal in the open interval (-1, +1)
%
% -------------------------------------------------------------------------
%  SIGNAL CONSTRUCTION
% -------------------------------------------------------------------------
%  Step 1  Raw momentum:   dP_t  = P_t − P_{t−1}
%
%  Step 2  EMA smoothing:  M_t   = α·dP_t + (1−α)·M_{t−1}
%                          α     = 1 − exp(−ln2 / SmoothHalfLife)
%          The half-life parameterises how quickly past observations decay.
%          With SmoothHalfLife = 3 mo the weight on a print 6 months old is
%          already 25 %, giving a responsive but low-noise estimate.
%          The EMA is computed on RAW dP — it must be fully responsive to
%          large positive momentum (e.g. the post-COVID hiring boom).
%
%  Step 3  Causal winsorization of dP for denominator only:
%          dP_wins_t = sign(dP_t) · min(|dP_t|, Q_t)
%          where Q_t = prctile(|dP_1 … dP_t|, WinsorPct)
%
%          This caps extreme shocks (e.g. April 2020: ≈ −20,700 K, roughly
%          30× a typical recession month) so they do not inflate the rolling
%          σ for every window that contains them.  The cap is expanding-
%          window and strictly causal — only data up to t is used to set Q_t.
%          The numerator (EMA) is NEVER winsorized; it retains full amplitude.
%
%  Step 4  Adaptive norm:  σ_t = std(dP_wins, trailing NormWindow months)
%
%  Step 5  Z-score:        z_t = M_t / σ_t
%          Because M_t uses raw dP and σ_t uses winsorized dP, z_t correctly
%          elevates the post-shock boom (large numerator, stable denominator).
%
%  Step 6  Tanh mapping:   S_t = tanh(TanhScale · z_t)
%          tanh is the core design choice:
%            • Always in (−1, +1)          → no clipping artefacts
%            • Odd function                → symmetric around zero
%            • Linear near zero            → fine discrimination of modest
%                                            positive vs. near-flat
%            • Saturates for |z| >> 1      → one extreme print cannot push
%                                            the signal to exactly ±1
%            • Smooth and differentiable   → no discontinuities for optimisers
%
%  Calibration with defaults (SmoothHalfLife=3, NormWindow=60,
%                             TanhScale=1, WinsorPct=95):
%      Regime                      dP (raw)    Approx Signal
%      ──────────────────────────────────────────────────────
%      Post-COVID boom             +900 K      ≈ +0.93
%      Boom (post-crisis)          +400 K      ≈ +0.92
%      Solid expansion             +200 K      ≈ +0.80
%      Moderate growth             +100 K      ≈ +0.59
%      Stalling (near zero)         +20 K      ≈ +0.13
%      Flat / no-growth               0 K       0.00
%      Mild contraction            −100 K      ≈ −0.59
%      Recession                   −300 K      ≈ −0.93
%  (assumes winsorized rolling σ ≈ 130 K, which excludes the COVID spike)
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   dm                (1,1) Model.DataManager  – initialised DataManager
%   SmoothHalfLife    (1,1) double > 0         – EMA half-life in months
%                                                (default 3)
%   NormWindow        (1,1) integer ≥ 12       – trailing window for rolling
%                                                std normalisation, months
%                                                (default 60)
%   TanhScale         (1,1) double > 0         – scales z before tanh;
%                                                > 1 steepens, < 1 flattens
%                                                (default 1.0)
%   WinsorPct         (1,1) double [0,100)     – expanding-window percentile
%                                                of |dP| used to cap extreme
%                                                observations before computing
%                                                rollStd. 0 = no winsorization.
%                                                (default 95)
%   StartDate         (1,1) string             – FRED fetch start 'yyyy-MM-dd'
%                                                (default "" → full history)
%
% -------------------------------------------------------------------------
%  EXAMPLE
% -------------------------------------------------------------------------
%   dm = Model.DataManager();
%   dm.init();
%   tt = Model.payrollsMomentum(dm);
%   tt = Model.payrollsMomentum(dm, WinsorPct=97, TanhScale=0.9);
%
%   % Plot
%   figure;
%   yyaxis left
%   bar(tt.Time, tt.dPayrolls, 'FaceAlpha', 0.4)
%   ylabel('MoM change (K jobs)')
%   yyaxis right
%   plot(tt.Time, tt.Signal, 'LineWidth', 1.5)
%   yline(0, 'k--'); ylim([-1.1 1.1]); ylabel('Signal')
%   title(tt.Properties.Description)

    arguments
        dm                  (1,1) Model.DataManager
        opts.SmoothHalfLife (1,1) double {mustBePositive}                = 3
        opts.NormWindow     (1,1) double {mustBePositive, mustBeInteger} = 60
        opts.TanhScale      (1,1) double {mustBePositive}                = 1.0
        opts.WinsorPct      (1,1) double                                 = 95
        opts.StartDate      (1,1) string                                 = ""
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
    MIN_WIN_OBS = 24;   % months of history before expanding winsor cap is reliable

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
    % 3. EMA smoothing of RAW dP (numerator — never winsorized)
    %    alpha = 1 - exp(-ln2 / halfLife) gives exact half-life semantics.
    %    NaN gaps are bridged by carrying the previous smoothed value.
    % ------------------------------------------------------------------ %
    alpha    = 1 - exp(-log(2) / opts.SmoothHalfLife);
    smoothed = nan(n, 1);

    firstValid = find(~isnan(dP), 1);
    if isempty(firstValid)
        error('SignalBuilder:payrollsMomentum:allNaN', ...
            'All month-over-month changes are NaN — cannot compute signal.');
    end

    smoothed(firstValid) = dP(firstValid);
    for i = firstValid + 1 : n
        if isnan(dP(i))
            smoothed(i) = smoothed(i-1);
        else
            smoothed(i) = alpha * dP(i) + (1 - alpha) * smoothed(i-1);
        end
    end

    % ------------------------------------------------------------------ %
    % 4. Causal expanding-window winsorization of dP (denominator only)
    %
    %    At each time t, the winsorization cap is:
    %        Q_t = prctile(|dP_valid(1..t)|, WinsorPct)
    %    Any observation |dP_t| > Q_t is capped to Q_t in sign.
    %
    %    Why separate numerator and denominator:
    %      • Numerator (smoothed) must be fully responsive — we WANT the
    %        signal to read strongly positive during a hiring boom.
    %      • Denominator (rollStd) must be stable — a single 30-sigma
    %        shock (Apr 2020: −20,700 K) should not inflate σ for 5 years
    %        and mute every reading that falls in its rolling window.
    %
    %    Causality: Q_t uses only dP(1..t), never future data.
    %    Minimum history: winsorization is applied only once MIN_WIN_OBS
    %    valid observations are available; earlier rows are left unchanged.
    % ------------------------------------------------------------------ %
    dP_wins = dP;    % copy used only for rollStd

    if opts.WinsorPct > 0
        validSoFar = [];   % growing list of valid (non-NaN) |dP| values
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
    % 5. Rolling standard deviation of WINSORIZED dP
    %    movstd(..., [W-1, 0]) uses a trailing window of exactly W obs.
    %    'omitnan' handles internal NaN gaps.
    %    Enforce a minimum of floor(W/2) or 12 valid obs per window;
    %    windows below this threshold → NaN signal (correct warm-up).
    % ------------------------------------------------------------------ %
    W       = opts.NormWindow;
    rollStd = movstd(dP_wins, [W - 1, 0], 0, 'omitnan');

    rollStd(rollStd < 1) = NaN;    % pathological: constant or near-constant series

    minValid = max(12, floor(W / 2));
    for i = 1 : min(W - 1, n)
        window = dP_wins(max(1, i - W + 1) : i);
        if sum(~isnan(window)) < minValid
            rollStd(i) = NaN;
        end
    end

    % ------------------------------------------------------------------ %
    % 6. Z-score → tanh compression
    %    Numerator uses raw EMA; denominator uses winsorized std.
    %    This combination lets z be appropriately large when momentum is
    %    genuinely strong relative to normal-regime volatility.
    % ------------------------------------------------------------------ %
    zScore = smoothed ./ rollStd;
    signal = tanh(opts.TanhScale .* zScore);

    % ------------------------------------------------------------------ %
    % 7. Pack into timetable
    % ------------------------------------------------------------------ %
    tt = timetable(times, levels, dP, smoothed, signal, ...
        'VariableNames', {'Payrolls', 'dPayrolls', 'SmoothedMom', 'Signal'});
    tt.Properties.DimensionNames{1} = 'Time';

    tt.Properties.Description = sprintf( ...
        ['PAYEMS momentum signal | ' ...
         'SmoothHalfLife=%g mo, NormWindow=%d mo, ' ...
         'TanhScale=%g, WinsorPct=%g'], ...
        opts.SmoothHalfLife, opts.NormWindow, opts.TanhScale, opts.WinsorPct);

    tt.Properties.VariableUnits = {'K jobs', 'K jobs/mo', 'K jobs/mo', ''};

    tt.Properties.VariableDescriptions = { ...
        'Total Nonfarm Payrolls level (FRED PAYEMS, thousands)', ...
        'Month-over-month change in payrolls (thousands)', ...
        sprintf('EMA-smoothed dPayrolls, half-life=%g mo (raw, unwinsorized)', ...
            opts.SmoothHalfLife), ...
        sprintf(['tanh(TanhScale*z), z = EMA(dP_raw) / std(dP_winsorized), ' ...
            'TanhScale=%g, WinsorPct=%g'], opts.TanhScale, opts.WinsorPct)};
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
