function normalized = normalizeSignals(rawSignals, method, opts)
%SIGSTRAT.NORMALIZESIGNALS Normalize raw signals to [-1, +1] range.
%   normalized = sigstrat.normalizeSignals(rawSignals, method, opts)
%
% Inputs:
%   rawSignals - TxN matrix of raw signal values
%   method     - string: 'RobustZ','StandardZ','RollingZ','Percentile','MinMax'
%   opts       - struct with optional fields:
%     .window     - rolling window size (default 252, used by RollingZ/MinMax)
%     .tanhScale  - tanh scaling divisor (default 2, used by RobustZ/StandardZ/RollingZ)
%     .minHistory - minimum observations before producing output (default 63)
%
% Output:
%   normalized - TxN matrix with values in [-1, +1]

    if nargin < 2 || isempty(method), method = 'RobustZ'; end
    if nargin < 3, opts = struct(); end

    window     = getOpt(opts, 'window', 252);
    tanhScale  = getOpt(opts, 'tanhScale', 2);
    minHistory = getOpt(opts, 'minHistory', 63);

    [T, N] = size(rawSignals);
    normalized = NaN(T, N);

    for j = 1:N
        x = rawSignals(:, j);

        switch method
            case 'RobustZ'
                normalized(:, j) = robustZNorm(x, tanhScale, minHistory);

            case 'StandardZ'
                normalized(:, j) = standardZNorm(x, tanhScale, minHistory);

            case 'RollingZ'
                normalized(:, j) = rollingZNorm(x, window, tanhScale, minHistory);

            case 'Percentile'
                normalized(:, j) = percentileNorm(x, minHistory);

            case 'MinMax'
                normalized(:, j) = minMaxNorm(x, window, minHistory);

            otherwise
                warning('sigstrat:normalizeSignals', ...
                    'Unknown method "%s", defaulting to RobustZ.', method);
                normalized(:, j) = robustZNorm(x, tanhScale, minHistory);
        end
    end

    fprintf('Signals normalized (%s): %d signals, %d observations.\n', method, N, T);
end

%% ---- Robust Z-score: median + 1.4826*MAD expanding → tanh ----
function out = robustZNorm(x, tanhScale, minHistory)
    T = numel(x);
    out = NaN(T, 1);
    for t = minHistory:T
        history = x(1:t);
        valid = history(isfinite(history));
        if numel(valid) < minHistory
            continue;
        end
        med = median(valid);
        madVal = median(abs(valid - med));
        scale = 1.4826 * max(madVal, 1e-8);
        z = (x(t) - med) / scale;
        out(t) = tanh(z / tanhScale);
    end
end

%% ---- Standard Z-score: mean + std expanding → tanh ----
function out = standardZNorm(x, tanhScale, minHistory)
    T = numel(x);
    out = NaN(T, 1);
    for t = minHistory:T
        history = x(1:t);
        valid = history(isfinite(history));
        if numel(valid) < minHistory
            continue;
        end
        mu = mean(valid);
        sigma = max(std(valid), 1e-8);
        z = (x(t) - mu) / sigma;
        out(t) = tanh(z / tanhScale);
    end
end

%% ---- Rolling Z-score: rolling window z → tanh ----
function out = rollingZNorm(x, window, tanhScale, minHistory)
    T = numel(x);
    out = NaN(T, 1);
    effMin = max(minHistory, window);
    for t = effMin:T
        i0 = max(1, t - window + 1);
        history = x(i0:t);
        valid = history(isfinite(history));
        if numel(valid) < minHistory
            continue;
        end
        mu = mean(valid);
        sigma = max(std(valid), 1e-8);
        z = (x(t) - mu) / sigma;
        out(t) = tanh(z / tanhScale);
    end
end

%% ---- Expanding percentile rank → [-1, +1] ----
function out = percentileNorm(x, minHistory)
    T = numel(x);
    out = NaN(T, 1);
    for t = minHistory:T
        history = x(1:t);
        valid = history(isfinite(history));
        if numel(valid) < minHistory
            continue;
        end
        pctRank = mean(valid <= x(t));
        out(t) = 2 * pctRank - 1;
    end
end

%% ---- Rolling min-max scaling → [-1, +1] ----
function out = minMaxNorm(x, window, minHistory)
    T = numel(x);
    out = NaN(T, 1);
    effMin = max(minHistory, window);
    for t = effMin:T
        i0 = max(1, t - window + 1);
        history = x(i0:t);
        valid = history(isfinite(history));
        if numel(valid) < minHistory
            continue;
        end
        lo = min(valid);
        hi = max(valid);
        rng = hi - lo;
        if rng < 1e-12
            out(t) = 0;
        else
            out(t) = 2 * (x(t) - lo) / rng - 1;
        end
    end
end

%% ---- Get option with default ----
function v = getOpt(opts, name, default)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = default;
    end
end
