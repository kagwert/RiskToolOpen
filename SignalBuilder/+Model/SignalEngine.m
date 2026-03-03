classdef SignalEngine < Model.BaseModel
% SignalEngine  Handle class for vectorised signal transformations and
%               flexible multi-signal aggregation.
%
%   Provides a library of rolling-window transforms that append columns to
%   a timetable (SignalTable), plus an aggregate() method supporting three
%   weighting regimes:
%
%     'static'      — user-supplied constant weight vector
%     'risk_parity' — inverse-rolling-volatility weights (time-varying)
%     'logic_gate'  — conditional activation: primary signal fires only
%                     when a regime signal exceeds a threshold
%
%   All lookback windows and thresholds live in the public Params struct
%   so an external optimiser can write to them without touching methods.
%
%   Usage:
%       eng = Model.SignalEngine(md);
%       eng.Params.MAWindow = 20;
%
%       eng.addMovingAverage('Close');
%       eng.addZScore('Close');
%       eng.addRelativeStrength('Close');
%       eng.addVolNormReturn('Close');
%
%       % Static 60/40 blend of two columns
%       tt = eng.aggregate(['MA_Close_20','ZScore_Close_60'], ...
%                          'static', struct('Weights',[0.6 0.4]));
%
%       % Risk-parity blend
%       tt = eng.aggregate(['MA_Close_20','ZScore_Close_60'], 'risk_parity');
%
%       % Logic gate: MA fires only when ZScore (regime) > 0
%       opts = struct('PrimarySignalCol', 'MA_Close_20', ...
%                     'RegimeSignalCol',  'ZScore_Close_60', ...
%                     'RegimeThreshold',  0);
%       tt = eng.aggregate([], 'logic_gate', opts);

    % ------------------------------------------------------------------ %
    %  Tunable parameters — all modifiable by external optimisers
    % ------------------------------------------------------------------ %
    properties
        % Public parameter struct.  All windows and thresholds live here.
        % External code (e.g. a grid-search or gradient-free optimiser)
        % can read/write these fields directly:
        %   eng.Params.MAWindow = 30;
        %   eng.Params.GateThreshold = 0.5;
        Params struct = struct( ...
            'MAWindow',              20,  ...   % rolling mean window
            'ZScoreWindow',          60,  ...   % z-score window
            'RSWindow',              14,  ...   % relative strength window
            'VolNormWindow',         21,  ...   % vol-norm-return window
            'RiskParityVolLookback', 21,  ...   % vol window for risk parity
            'GateThreshold',          0)         % regime activation threshold
    end

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Handle reference to source MarketData.
        MarketDataRef Model.MarketData

        % Accumulated signal columns (all transforms share this timetable).
        SignalTable timetable = timetable.empty
    end

    properties (Dependent)
        % Names of columns currently in SignalTable.
        SignalNames (1,:) string
    end

    % ------------------------------------------------------------------ %
    methods

        function obj = SignalEngine(marketDataObj)
        % SignalEngine  Constructor.
        %   eng = Model.SignalEngine(md)   where md is a Model.MarketData
            arguments
                marketDataObj (1,1) Model.MarketData
            end
            obj = obj@Model.BaseModel("SignalEngine:" + marketDataObj.Ticker);
            obj.MarketDataRef = marketDataObj;
            if marketDataObj.NumBars > 0
                obj.SignalTable = timetable(marketDataObj.Prices.Time);
            end
            addlistener(marketDataObj, 'Changed', ...
                @(~,~) obj.onDataChanged());
        end

        % -------------------------------------------------------------- %
        %  Transforms
        % -------------------------------------------------------------- %

        function addMovingAverage(obj, col, window)
        % addMovingAverage  Rolling mean of a price or signal column.
        %
        %   Adds column 'MA_{col}_{window}' to SignalTable.
        %   Window defaults to Params.MAWindow.
        %
        %   eng.addMovingAverage('Close')
        %   eng.addMovingAverage('Close', 10)
            arguments
                obj
                col    (1,1) string
                window (1,1) {mustBeNonnegative, mustBeInteger} = 0
            end
            if window == 0, window = obj.Params.MAWindow; end
            values  = obj.resolveInputCol(col);
            ma      = movmean(values, window, 'Endpoints', 'discard');
            result  = [nan(window-1, 1); ma];
            colName = sprintf('MA_%s_%d', col, window);
            obj.upsertColumn(colName, result);
        end

        % -------------------------------------------------------------- %
        function addZScore(obj, col, window)
        % addZScore  Rolling z-score: (x - mu) / sigma.
        %
        %   Uses the sample standard deviation (N-1).
        %   Adds column 'ZScore_{col}_{window}'.
        %   Window defaults to Params.ZScoreWindow.
        %
        %   eng.addZScore('Close')
        %   eng.addZScore('Close', 30)
            arguments
                obj
                col    (1,1) string
                window (1,1) {mustBeNonnegative, mustBeInteger} = 0
            end
            if window == 0, window = obj.Params.ZScoreWindow; end
            values = obj.resolveInputCol(col);
            mu     = movmean(values, window, 'Endpoints', 'discard');
            sigma  = movstd(values,  window, 0, 'Endpoints', 'discard');
            mu     = [nan(window-1, 1); mu];
            sigma  = [nan(window-1, 1); sigma];
            z      = (values - mu) ./ max(sigma, eps);
            colName = sprintf('ZScore_%s_%d', col, window);
            obj.upsertColumn(colName, z);
        end

        % -------------------------------------------------------------- %
        function addRelativeStrength(obj, col, window)
        % addRelativeStrength  Rolling sum-of-gains / sum-of-losses ratio.
        %
        %   RS_t = sum(max(delta,0), window) / sum(abs(min(delta,0)), window)
        %   Analagous to the numerator/denominator of RSI before the 100
        %   scaling; output is an unbounded positive ratio.
        %
        %   Adds column 'RS_{col}_{window}'.
        %   Window defaults to Params.RSWindow.
        %
        %   eng.addRelativeStrength('Close')
            arguments
                obj
                col    (1,1) string
                window (1,1) {mustBeNonnegative, mustBeInteger} = 0
            end
            if window == 0, window = obj.Params.RSWindow; end
            values = obj.resolveInputCol(col);
            delta  = [NaN; diff(values)];
            gains  = max(delta, 0);
            losses = abs(min(delta, 0));

            sumGains  = movsum(gains,  window, 'Endpoints', 'discard');
            sumLosses = movsum(losses, window, 'Endpoints', 'discard');
            % Pad NaNs for the warm-up period
            sumGains  = [nan(window-1, 1); sumGains];
            sumLosses = [nan(window-1, 1); sumLosses];

            rs      = sumGains ./ max(sumLosses, eps);
            colName = sprintf('RS_%s_%d', col, window);
            obj.upsertColumn(colName, rs);
        end

        % -------------------------------------------------------------- %
        function addVolNormReturn(obj, col, window)
        % addVolNormReturn  Return divided by rolling volatility.
        %
        %   VNR_t = ret_t / rolling_std(ret, window)
        %   where ret_t = (P_t - P_{t-1}) / P_{t-1}
        %
        %   Scales returns by local volatility, producing a normalised
        %   signal with approximately unit variance in quiet periods.
        %
        %   Adds column 'VNR_{col}_{window}'.
        %   Window defaults to Params.VolNormWindow.
        %
        %   eng.addVolNormReturn('Close')
            arguments
                obj
                col    (1,1) string
                window (1,1) {mustBeNonnegative, mustBeInteger} = 0
            end
            if window == 0, window = obj.Params.VolNormWindow; end
            values   = obj.resolveInputCol(col);
            ret      = [NaN; diff(values) ./ values(1:end-1)];
            rolVol   = movstd(ret, window, 0, 'Endpoints', 'discard');
            rolVol   = [nan(window-1, 1); rolVol];
            vnr      = ret ./ max(rolVol, eps);
            colName  = sprintf('VNR_%s_%d', col, window);
            obj.upsertColumn(colName, vnr);
        end

        % -------------------------------------------------------------- %
        %  Aggregation
        % -------------------------------------------------------------- %

        function tt = aggregate(obj, signalCols, method, options)
        % aggregate  Combine signal columns into a single composite signal.
        %
        %   tt = eng.aggregate(signalCols, method)
        %   tt = eng.aggregate(signalCols, method, options)
        %
        %   Returns a timetable with column 'CompositeSignal'.
        %
        %   --- 'static' ---
        %   Linear weighted sum, weights normalised to sum to 1.
        %   options.Weights (1 x nCols double)  — default: equal weights
        %
        %   tt = eng.aggregate(['MA_Close_20','ZScore_Close_60'], ...
        %                      'static', struct('Weights',[0.6 0.4]));
        %
        %   --- 'risk_parity' ---
        %   Time-varying weights = 1/sigma_i(t), normalised each bar.
        %   Sigma computed as rolling std of each signal column.
        %   options.VolLookback (int) — default: Params.RiskParityVolLookback
        %
        %   tt = eng.aggregate(['MA_Close_20','ZScore_Close_60'], 'risk_parity');
        %
        %   --- 'logic_gate' ---
        %   Decision-tree gate: primary signal is zeroed when a regime
        %   signal falls below a threshold.  Multiple gates are applied
        %   sequentially (AND logic: all conditions must be active).
        %   options.PrimarySignalCol (string)  — column to activate
        %   options.Gates (struct array) — array of gate conditions:
        %     .RegimeSignalCol  (string) — regime indicator column
        %     .Threshold        (double) — activation threshold
        %   If options.Gates is absent, a single gate is built from:
        %     options.RegimeSignalCol  and  options.RegimeThreshold
        %     (RegimeThreshold defaults to Params.GateThreshold)
        %
        %   tt = eng.aggregate([], 'logic_gate', ...
        %        struct('PrimarySignalCol','MA_Close_20', ...
        %               'RegimeSignalCol', 'ZScore_Close_60', ...
        %               'RegimeThreshold', 0.5));
            arguments
                obj
                signalCols (1,:) string = string.empty
                method     (1,1) string ...
                    {mustBeMember(method, ...
                    ["static","risk_parity","logic_gate"])} = "static"
                options    struct = struct()
            end
            switch method
                case "static"
                    tt = obj.aggregateStatic(signalCols, options);
                case "risk_parity"
                    tt = obj.aggregateRiskParity(signalCols, options);
                case "logic_gate"
                    tt = obj.aggregateLogicGate(options);
            end
        end

        % -------------------------------------------------------------- %
        function clearSignals(obj)
        % clearSignals  Remove all computed signal columns.
            obj.SignalTable = timetable(obj.MarketDataRef.Prices.Time);
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        %  Dependent getter
        function names = get.SignalNames(obj)
            if isempty(obj.SignalTable)
                names = string.empty;
            else
                names = string(obj.SignalTable.Properties.VariableNames);
            end
        end

    end

    % ------------------------------------------------------------------ %
    %  Private — aggregation implementations
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function tt = aggregateStatic(obj, signalCols, options)
        % aggregateStatic  Weighted linear combination.
            obj.requireSignalCols(signalCols);
            mat = table2array(obj.SignalTable(:, signalCols));
            n   = numel(signalCols);

            if isfield(options, 'Weights') && ~isempty(options.Weights)
                w = options.Weights(:);
                if numel(w) ~= n
                    error('SignalBuilder:SignalEngine:weightsMismatch', ...
                        'Weights length (%d) must match number of signals (%d).', ...
                        numel(w), n);
                end
            else
                w = ones(n, 1);   % equal weights
            end
            w = w / sum(w);   % normalise

            composite = mat * w;
            % Preserve NaN where any input is NaN
            composite(any(isnan(mat), 2)) = NaN;

            tt = timetable(obj.SignalTable.Time, composite, ...
                'VariableNames', {'CompositeSignal'});
            tt.Properties.Description = 'Static-weighted composite';
        end

        % -------------------------------------------------------------- %
        function tt = aggregateRiskParity(obj, signalCols, options)
        % aggregateRiskParity  Inverse-volatility weighted combination.
        %   w_i(t) = (1/sigma_i(t)) / sum_j(1/sigma_j(t))
        %   where sigma_i(t) is the rolling std of signal column i.
            obj.requireSignalCols(signalCols);

            if isfield(options, 'VolLookback') && ~isempty(options.VolLookback)
                volLB = options.VolLookback;
            else
                volLB = obj.Params.RiskParityVolLookback;
            end

            mat = table2array(obj.SignalTable(:, signalCols));
            [nRows, nCols] = size(mat);

            % Rolling volatility matrix (nRows x nCols)
            rolVol = nan(nRows, nCols);
            for k = 1 : nCols
                v = mat(:, k);
                if volLB >= 2
                    rv = movstd(v, volLB, 0, 'Endpoints', 'discard');
                    rolVol(volLB:end, k) = rv;
                else
                    rolVol(:, k) = abs(v);
                end
            end

            % Inverse vol weights, normalised row-wise
            invVol    = 1 ./ max(rolVol, eps);
            rowSum    = sum(invVol, 2);
            w_t       = invVol ./ max(rowSum, eps);   % nRows x nCols

            composite = sum(w_t .* mat, 2);
            % Rows where any input or weight is NaN remain NaN
            composite(any(isnan(mat) | isnan(w_t), 2)) = NaN;

            tt = timetable(obj.SignalTable.Time, composite, ...
                'VariableNames', {'CompositeSignal'});
            tt.Properties.Description = ...
                sprintf('Risk-parity composite (volLB=%d)', volLB);
        end

        % -------------------------------------------------------------- %
        function tt = aggregateLogicGate(obj, options)
        % aggregateLogicGate  Conditional activation via regime gating.
        %
        %   Reads PrimarySignalCol from SignalTable.
        %   Applies one or more Gates sequentially (AND logic):
        %     composite = primarySignal * prod_k(regime_k > threshold_k)
            if ~isfield(options, 'PrimarySignalCol')
                error('SignalBuilder:SignalEngine:missingOption', ...
                    'options.PrimarySignalCol is required for logic_gate.');
            end
            primaryCol = string(options.PrimarySignalCol);
            obj.requireSignalCols(primaryCol);
            composite = obj.SignalTable.(primaryCol);

            % Build gates array
            if isfield(options, 'Gates') && ~isempty(options.Gates)
                gates = options.Gates;
            else
                % Single gate from flat options fields
                if ~isfield(options, 'RegimeSignalCol')
                    error('SignalBuilder:SignalEngine:missingOption', ...
                        'Provide options.RegimeSignalCol or options.Gates.');
                end
                threshold = obj.Params.GateThreshold;
                if isfield(options, 'RegimeThreshold')
                    threshold = options.RegimeThreshold;
                end
                gates = struct( ...
                    'RegimeSignalCol', options.RegimeSignalCol, ...
                    'Threshold',       threshold);
            end

            % Apply each gate: mask primary signal where regime is below threshold
            for k = 1 : numel(gates)
                regCol = string(gates(k).RegimeSignalCol);
                thresh = gates(k).Threshold;
                obj.requireSignalCols(regCol);
                regime    = obj.SignalTable.(regCol);
                mask      = double(regime > thresh);
                % NaN regime → inactive (conservative)
                mask(isnan(regime)) = 0;
                composite = composite .* mask;
            end

            tt = timetable(obj.SignalTable.Time, composite, ...
                'VariableNames', {'CompositeSignal'});
            tt.Properties.Description = ...
                sprintf('Logic-gate composite (%d gate(s))', numel(gates));
        end

    end

    % ------------------------------------------------------------------ %
    %  Private — shared helpers
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function values = resolveInputCol(obj, col)
        % resolveInputCol  Read from Prices timetable or existing SignalTable.
            pricesVars = string( ...
                obj.MarketDataRef.Prices.Properties.VariableNames);
            sigVars    = obj.SignalNames;

            if ismember(col, pricesVars)
                values = obj.MarketDataRef.Prices.(col);
            elseif ismember(col, sigVars)
                values = obj.SignalTable.(col);
            else
                error('SignalBuilder:SignalEngine:columnNotFound', ...
                    'Column "%s" not found in Prices or SignalTable.', col);
            end
        end

        function upsertColumn(obj, colName, values)
            cName = char(colName);   % R2021b: VariableNames needs char, not string
            if isempty(obj.SignalTable) || ...
               isempty(obj.SignalTable.Properties.VariableNames)
                obj.SignalTable = timetable( ...
                    obj.MarketDataRef.Prices.Time, values, ...
                    'VariableNames', {cName});
            elseif ismember(cName, obj.SignalTable.Properties.VariableNames)
                obj.SignalTable.(cName) = values;
            else
                newCol = timetable( ...
                    obj.MarketDataRef.Prices.Time, values, ...
                    'VariableNames', {cName});
                obj.SignalTable = synchronize(obj.SignalTable, newCol);
            end
            obj.notifyChanged();
        end

        function requireSignalCols(obj, colNames)
            missing = colNames(~ismember(colNames, ...
                string(obj.SignalTable.Properties.VariableNames)));
            if ~isempty(missing)
                error('SignalBuilder:SignalEngine:missingColumn', ...
                    'Signal columns not found in SignalTable: %s', ...
                    strjoin(missing, ', '));
            end
        end

        function onDataChanged(obj)
            obj.SignalTable = timetable(obj.MarketDataRef.Prices.Time);
            obj.notifyChanged();
        end

    end
end
