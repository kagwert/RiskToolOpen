function eqWt = mapSignalToWeight(signal, method, params)
%SIGSTRAT.MAPSIGNALTOWEIGHT Map signal [-1,+1] to equity weight [0,1].
%   eqWt = sigstrat.mapSignalToWeight(signal, method, params)
%
% Inputs:
%   signal - Tx1 vector of signal values in [-1, +1]
%   method - string: 'Step','Linear','Sigmoid','PiecewiseLinear','Spline','Power'
%   params - struct with method-specific parameters:
%     Step:            .thresholds (Kx1), .levels ((K+1)x1)
%     Linear:          (none)
%     Sigmoid:         .k (steepness, default 5)
%     PiecewiseLinear: .breakpoints (Mx2, [signal, weight])
%     Spline:          .breakpoints (Mx2, [signal, weight])
%     Power:           .p (exponent, default 1)
%
% Output:
%   eqWt - Tx1 vector of equity weights in [0, 1]

    if nargin < 2 || isempty(method), method = 'Sigmoid'; end
    if nargin < 3, params = struct(); end

    signal = signal(:);
    T = numel(signal);

    switch method
        case 'Step'
            eqWt = stepMapping(signal, T, params);

        case 'Linear'
            eqWt = (signal + 1) / 2;

        case 'Sigmoid'
            k = getOpt(params, 'k', 5);
            eqWt = 1 ./ (1 + exp(-k * signal));

        case 'PiecewiseLinear'
            bp = getOpt(params, 'breakpoints', defaultBreakpoints());
            eqWt = piecewiseLinearMapping(signal, bp);

        case 'Spline'
            bp = getOpt(params, 'breakpoints', defaultBreakpoints());
            eqWt = splineMapping(signal, bp);

        case 'Power'
            p = getOpt(params, 'p', 1);
            eqWt = 0.5 + 0.5 * sign(signal) .* abs(signal).^p;

        otherwise
            warning('sigstrat:mapSignalToWeight', ...
                'Unknown method "%s", defaulting to Sigmoid.', method);
            eqWt = 1 ./ (1 + exp(-5 * signal));
    end

    % Handle NaN: map to neutral 0.5
    eqWt(~isfinite(eqWt)) = 0.5;

    % Clip to [0, 1]
    eqWt = max(0, min(1, eqWt));
end

%% ---- Step function mapping ----
function eqWt = stepMapping(signal, T, params)
    thresholds = getOpt(params, 'thresholds', [-0.3; 0; 0.3]);
    levels     = getOpt(params, 'levels', [0; 0.3; 0.7; 1]);
    thresholds = sort(thresholds(:));
    K = numel(thresholds);
    eqWt = NaN(T, 1);

    for t = 1:T
        if ~isfinite(signal(t))
            eqWt(t) = 0.5;
            continue;
        end
        assigned = false;
        for ki = 1:K
            if signal(t) < thresholds(ki)
                eqWt(t) = levels(ki);
                assigned = true;
                break;
            end
        end
        if ~assigned
            eqWt(t) = levels(K + 1);
        end
    end
end

%% ---- Piecewise linear interpolation ----
function eqWt = piecewiseLinearMapping(signal, bp)
    bp = sortrows(bp, 1);
    xBp = bp(:, 1);
    yBp = bp(:, 2);

    eqWt = interp1(xBp, yBp, signal, 'linear', 'extrap');
    eqWt = max(0, min(1, eqWt));
end

%% ---- Monotone cubic spline (pchip) ----
function eqWt = splineMapping(signal, bp)
    bp = sortrows(bp, 1);
    xBp = bp(:, 1);
    yBp = bp(:, 2);

    eqWt = interp1(xBp, yBp, signal, 'pchip', 'extrap');
    eqWt = max(0, min(1, eqWt));
end

%% ---- Default breakpoints ----
function bp = defaultBreakpoints()
    bp = [-1, 0; -0.3, 0.2; 0, 0.5; 0.3, 0.8; 1, 1];
end

%% ---- Get option with default ----
function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
