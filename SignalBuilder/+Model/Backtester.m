classdef Backtester < Model.BaseModel
% Backtester  Handle class that executes a signal-driven backtest and
%             optionally optimises SignalEngine.Params via Bayesian
%             optimisation (bayesopt).
%
%   Consumes a composite-signal timetable produced by Model.SignalEngine
%   and converts it into portfolio positions subject to configurable budget
%   constraints before computing per-bar P&L and performance metrics.
%
%   Metrics produced by run():
%     SharpeRatio    — annualised Sharpe  (×√252, excess over risk-free)
%     SortinoRatio   — annualised Sortino (×√252, downside semi-deviation)
%     MaxDrawdown    — peak-to-trough drawdown fraction (≤ 0)
%     TurnoverDaily  — mean |Δposition| per bar (0 = buy-and-hold)
%     TurnoverAnnual — TurnoverDaily × 252
%     TotalReturn    — (final equity − InitialCapital) / InitialCapital
%
%   Budget constraints (Constraints struct), applied elementwise each bar:
%     MaxLeverage        |position| ≤ MaxLeverage
%     MaxWeightPerAsset  position   ≤ MaxWeightPerAsset
%     MinWeightPerAsset  position   ≥ MinWeightPerAsset (negative = short)
%
%   NaN composite-signal bars are treated as flat (position = 0).
%
%   Usage — basic backtest:
%       md  = Model.MarketData('SPY');  md.loadFromFile('SPY.csv');
%       eng = Model.SignalEngine(md);
%       eng.addMovingAverage('Close', 20);
%       eng.addZScore('Close', 60);
%       compositeTT = eng.aggregate(eng.SignalNames, 'risk_parity');
%
%       bt = Model.Backtester(eng);
%       bt.Constraints.MinWeightPerAsset = -1.0;   % allow short
%       bt.run(compositeTT);
%       disp(bt)
%
%   Usage — Bayesian optimisation:
%       vars = [
%           optimizableVariable('MAWindow',     [5, 60],  'Type','integer')
%           optimizableVariable('ZScoreWindow', [10,120], 'Type','integer')];
%       result = bt.optimize(@myBuilder, 'risk_parity', vars);
%       % myBuilder: @(eng) (eng.clearSignals(), eng.addMovingAverage('Close'), ...)

    % ------------------------------------------------------------------ %
    %  Tunable parameters
    % ------------------------------------------------------------------ %
    properties
        % Starting equity used for the equity-curve calculation.
        InitialCapital (1,1) double {mustBePositive} = 100000

        % One-way transaction cost as a fraction of trade value.
        % 0.001 = 10 basis points per trade.
        TransactionCost (1,1) double {mustBeNonnegative} = 0.001

        % Annualised risk-free rate used in the Sharpe / Sortino numerators.
        % 0 = no adjustment; 0.05 = 5 % annual.
        RiskFreeRateAnnual (1,1) double = 0

        % Budget constraints applied elementwise each bar.
        %   MaxLeverage:       clamps |position| ≤ MaxLeverage
        %   MaxWeightPerAsset: clamps  position  ≤ MaxWeightPerAsset
        %   MinWeightPerAsset: clamps  position  ≥ MinWeightPerAsset
        % Effective per-bar bound:
        %   lower = max(MinWeightPerAsset, -MaxLeverage)
        %   upper = min(MaxWeightPerAsset,  MaxLeverage)
        Constraints struct = struct( ...
            'MaxLeverage',       1.0, ...
            'MaxWeightPerAsset', 1.0, ...
            'MinWeightPerAsset', 0.0)   % default: long-only, no leverage

        % Settings forwarded to bayesopt inside optimize().
        %   MaxObjectiveEvaluations: number of function evaluations (trials)
        %   AcquisitionFunctionName: bayesopt acquisition strategy
        %     e.g. 'expected-improvement-plus' (default), 'lower-confidence-bound'
        %   Verbose: 0 = silent; 1 = console; 2 = full diagnostics
        OptimOptions struct = struct( ...
            'MaxObjectiveEvaluations', 30,                     ...
            'AcquisitionFunctionName', "expected-improvement-plus", ...
            'Verbose',                 0)
    end

    % ------------------------------------------------------------------ %
    %  Read-only results
    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Handle to the SignalEngine supplying signals.
        % R2021b: explicit empty default avoids default-constructor call.
        EngineRef Model.SignalEngine = Model.SignalEngine.empty

        % Per-bar backtest output timetable (populated by run()).
        % Columns: Position, AssetReturn, StrategyReturn, EquityCurve, Turnover
        BacktestResults timetable = timetable.empty

        % Scalar performance metrics (populated by run()).
        % Fields: SharpeRatio, SortinoRatio, MaxDrawdown,
        %         TurnoverDaily, TurnoverAnnual, TotalReturn
        Metrics struct = struct()

        % BayesianOptimization result object from the last optimize() call.
        % [] until optimize() is called.
        OptimResult = []

        % Best SignalEngine.Params found by the last optimize() call.
        OptimalParams struct = struct()
    end

    properties (Dependent)
        % True once run() has completed at least once.
        IsRun (1,1) logical
    end

    % ------------------------------------------------------------------ %
    methods

        function obj = Backtester(sigEngine)
        % Backtester  Constructor.
        %   bt = Model.Backtester(sigEngine)
        %   where sigEngine is a Model.SignalEngine handle.
            arguments
                sigEngine (1,1) Model.SignalEngine
            end
            obj = obj@Model.BaseModel( ...
                "Backtester:" + sigEngine.MarketDataRef.Ticker);
            obj.EngineRef = sigEngine;
        end

        % -------------------------------------------------------------- %
        function run(obj, compositeTT)
        % run  Execute a backtest from a composite-signal timetable.
        %
        %   compositeTT must be a timetable with a 'CompositeSignal' column
        %   whose row count matches the source MarketData price series.
        %
        %   Positions are derived by clamping the composite signal to the
        %   Constraints bounds (NaN → flat).  Metrics are stored in
        %   obj.Metrics; per-bar results in obj.BacktestResults.
        %
        %   bt.run(eng.aggregate(eng.SignalNames, 'static'))
            arguments
                obj
                compositeTT timetable
            end
            obj.validateCompositeTT(compositeTT);
            prices   = obj.EngineRef.MarketDataRef.Prices;

            % --- Position sizing with budget constraints ---
            signal   = compositeTT.CompositeSignal;
            position = obj.applyConstraints(signal);

            % --- 1-bar implementation lag ---
            % signal(i) is computed from Close(i) known only at COB bar i.
            % The trade is executed at COB bar i; it can only earn ret(i+1).
            % posLag(i) = position entered at COB bar i-1, active during bar i.
            posLag   = [0; position(1:end-1)];

            % --- Returns ---
            % ret(i) = (Close(i) - Close(i-1)) / Close(i-1)
            ret      = [NaN; diff(prices.Close) ./ prices.Close(1:end-1)];

            % --- Transaction costs ---
            % posChg(i) = trade executed at COB bar i (signal i → position i).
            % Cost is charged on the rebalance bar, before next bar opens.
            posChg   = abs(diff([0; position]));
            cost     = posChg * obj.TransactionCost;

            % --- Strategy returns ---
            % Earn posLag(i) * ret(i); pay cost(i) for today's rebalance.
            stratRet = posLag .* ret - cost;
            stratRet(isnan(stratRet)) = 0;         % NaN bars → no P&L

            % --- Equity curve ---
            equity   = obj.InitialCapital * cumprod(1 + stratRet);

            % --- Store backtest timetable ---
            % Position column stores posLag: the position active during each bar.
            obj.BacktestResults = timetable(prices.Time, ...
                posLag, ret, stratRet, equity, posChg, ...
                'VariableNames', ...
                {'Position','AssetReturn','StrategyReturn', ...
                 'EquityCurve','Turnover'});
            obj.BacktestResults.Properties.Description = ...
                obj.Name + " backtest";

            obj.computeMetrics(stratRet, equity, posChg);
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        function result = optimize(obj, signalBuilderFn, aggregateMethod, ...
                                   paramVars, aggOptions)
        % optimize  Bayesian optimisation of SignalEngine.Params.
        %
        %   Maximises the Sharpe Ratio by searching over the specified
        %   optimisableVariable parameters using bayesopt (Statistics and
        %   Machine Learning Toolbox).  Objective returned to bayesopt is
        %   the negative Sharpe Ratio (minimisation convention).
        %
        %   signalBuilderFn  @(eng) function called each trial.
        %                    Must call eng.clearSignals() then add desired
        %                    transforms using the current eng.Params values.
        %   aggregateMethod  'static' | 'risk_parity' | 'logic_gate'
        %   paramVars        optimizableVariable array.  Each .Name must
        %                    match a field of Model.SignalEngine.Params.
        %   aggOptions       (optional) struct forwarded to aggregate().
        %     .SignalCols    string array — subset of columns to aggregate.
        %                   Default: all columns after signalBuilderFn runs.
        %
        %   After optimisation the engine is left in the optimal-param state,
        %   run() has been called with the best composite signal, and
        %   obj.OptimalParams holds the winning parameter values.
        %
        %   Example:
        %     vars = [
        %         optimizableVariable('MAWindow',     [5, 60], 'Type','integer')
        %         optimizableVariable('ZScoreWindow', [10,120],'Type','integer')];
        %     bt.optimize(@(e)(e.clearSignals(),e.addMovingAverage('Close')), ...
        %                 'static', vars);
            arguments
                obj
                signalBuilderFn (1,1) function_handle
                aggregateMethod (1,1) string ...
                    {mustBeMember(aggregateMethod, ...
                    ["static","risk_parity","logic_gate"])}
                paramVars     % optimizableVariable or array — typed by bayesopt
                aggOptions struct = struct()
            end

            % Verify toolbox availability before running
            if ~(exist('bayesopt', 'file') || exist('bayesopt', 'builtin'))
                error('SignalBuilder:Backtester:toolboxMissing', ...
                    ['bayesopt requires the Statistics and Machine ' ...
                     'Learning Toolbox.']);
            end

            % Build objective-function closure over this object's context
            objFn = @(tp) obj.evaluateParams( ...
                tp, signalBuilderFn, aggregateMethod, aggOptions);

            % Run Bayesian optimisation (minimises objective = -Sharpe)
            result = bayesopt(objFn, paramVars, ...
                'MaxObjectiveEvaluations', ...
                    obj.OptimOptions.MaxObjectiveEvaluations, ...
                'AcquisitionFunctionName', ...
                    char(obj.OptimOptions.AcquisitionFunctionName), ...
                'Verbose', obj.OptimOptions.Verbose, ...
                'PlotFcn', []);

            % Store results
            obj.OptimResult   = result;
            best              = result.XAtMinObjective;
            obj.OptimalParams = table2struct(best);

            % Final backtest with optimal parameters
            obj.applyParamsFromTable(best);
            obj.EngineRef.clearSignals();
            signalBuilderFn(obj.EngineRef);
            cols        = obj.resolveAggregateCols(aggOptions);
            aggOptsClean = obj.stripSignalCols(aggOptions);
            compositeTT = obj.EngineRef.aggregate( ...
                cols, aggregateMethod, aggOptsClean);
            obj.run(compositeTT);
        end

        % -------------------------------------------------------------- %
        function tf = get.IsRun(obj)
            tf = ~isempty(obj.BacktestResults);
        end

        % -------------------------------------------------------------- %
        function disp(obj)
            fprintf('Backtester : %s\n', obj.Name);
            fprintf('  IsRun    : %d\n', obj.IsRun);
            if obj.IsRun && ~isempty(fieldnames(obj.Metrics))
                m    = obj.Metrics;
                flds = fieldnames(m);
                for k = 1:numel(flds)
                    fprintf('  %-22s: %8.4f\n', flds{k}, m.(flds{k}));
                end
            end
        end

    end

    % ------------------------------------------------------------------ %
    methods (Access = private)

        function pos = applyConstraints(obj, signal)
        % applyConstraints  Map composite signal to a constrained position.
        %
        %   NaN signal bars → flat (0).
        %   Effective per-bar bound:
        %     lower = max(MinWeightPerAsset, -MaxLeverage)
        %     upper = min(MaxWeightPerAsset,  MaxLeverage)
            c     = obj.Constraints;
            pos   = signal;
            pos(isnan(pos)) = 0;
            upper = min(c.MaxWeightPerAsset,  c.MaxLeverage);
            lower = max(c.MinWeightPerAsset, -c.MaxLeverage);
            pos   = max(min(pos, upper), lower);
        end

        % -------------------------------------------------------------- %
        function computeMetrics(obj, stratRet, equity, turnover)
        % computeMetrics  Populate obj.Metrics from return and equity series.
        %
        %   Sharpe  = E[excess] / std(excess)  × √252
        %   Sortino = E[excess] / semi-dev      × √252
        %             semi-dev = sqrt(E[min(excess, 0)^2])  (downside RMS)
            m       = struct();
            rfDaily = obj.RiskFreeRateAnnual / 252;
            excess  = stratRet - rfDaily;

            % Sharpe ratio (annualised)
            m.SharpeRatio  = mean(excess, 'omitnan') / ...
                             max(std(excess, 'omitnan'), eps) * sqrt(252);

            % Sortino ratio: penalise only downside returns
            negExcess      = min(excess, 0);              % zero for up-bars
            downsideStd    = sqrt(mean(negExcess .^ 2, 'omitnan'));
            m.SortinoRatio = mean(excess, 'omitnan') / ...
                             max(downsideStd, eps) * sqrt(252);

            % Max drawdown (peak-to-trough, ≤ 0)
            running       = cummax(equity);
            m.MaxDrawdown = min((equity - running) ./ running);

            % Turnover
            m.TurnoverDaily  = mean(turnover, 'omitnan');
            m.TurnoverAnnual = m.TurnoverDaily * 252;

            % Total return
            m.TotalReturn = (equity(end) - obj.InitialCapital) / ...
                             obj.InitialCapital;

            obj.Metrics = m;
        end

        % -------------------------------------------------------------- %
        function negSharpe = evaluateParams(obj, trialParams, ...
                signalBuilderFn, aggregateMethod, aggOptions)
        % evaluateParams  Objective function called by bayesopt each trial.
        %
        %   Updates EngineRef.Params from the bayesopt trial table, rebuilds
        %   signals via signalBuilderFn, aggregates, runs backtest, and
        %   returns negative Sharpe Ratio.
        %
        %   Returns 0 (neutral, not penalised) on any error so that
        %   optimisation continues past degenerate parameter combinations.
            obj.applyParamsFromTable(trialParams);
            obj.EngineRef.clearSignals();
            signalBuilderFn(obj.EngineRef);

            cols        = obj.resolveAggregateCols(aggOptions);
            aggOptsClean = obj.stripSignalCols(aggOptions);
            try
                compositeTT = obj.EngineRef.aggregate( ...
                    cols, aggregateMethod, aggOptsClean);
                obj.run(compositeTT);
                negSharpe = -obj.Metrics.SharpeRatio;
                if ~isfinite(negSharpe)
                    negSharpe = 0;   % degenerate (all-flat or inf returns)
                end
            catch
                negSharpe = 0;       % neutral penalty for invalid configs
            end
        end

        % -------------------------------------------------------------- %
        function cols = resolveAggregateCols(obj, aggOptions)
        % resolveAggregateCols  Determine which signal columns to aggregate.
        %   Uses aggOptions.SignalCols if provided; otherwise all SignalNames.
            if isfield(aggOptions, 'SignalCols') && ...
               ~isempty(aggOptions.SignalCols)
                cols = string(aggOptions.SignalCols);
            else
                cols = obj.EngineRef.SignalNames;
            end
        end

        % -------------------------------------------------------------- %
        function cleaned = stripSignalCols(~, aggOptions)
        % stripSignalCols  Remove SignalCols before forwarding to aggregate.
            cleaned = aggOptions;
            if isfield(cleaned, 'SignalCols')
                cleaned = rmfield(cleaned, 'SignalCols');
            end
        end

        % -------------------------------------------------------------- %
        function applyParamsFromTable(obj, tbl)
        % applyParamsFromTable  Write bayesopt trial values to EngineRef.Params.
            flds = tbl.Properties.VariableNames;
            for k = 1:numel(flds)
                obj.EngineRef.Params.(flds{k}) = tbl.(flds{k})(1);
            end
        end

        % -------------------------------------------------------------- %
        function validateCompositeTT(obj, tt)
        % validateCompositeTT  Verify the composite timetable is compatible.
            if ~ismember('CompositeSignal', tt.Properties.VariableNames)
                error('SignalBuilder:Backtester:missingColumn', ...
                    'compositeTT must contain a ''CompositeSignal'' column.');
            end
            prices = obj.EngineRef.MarketDataRef.Prices;
            if height(tt) ~= height(prices)
                error('SignalBuilder:Backtester:sizeMismatch', ...
                    ['compositeTT has %d rows but MarketData has %d rows. ' ...
                     'Ensure the signal is aligned to the price series.'], ...
                    height(tt), height(prices));
            end
        end

    end
end
