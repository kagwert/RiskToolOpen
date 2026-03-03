classdef Strategy < Model.BaseModel
% Strategy  Handle class defining entry/exit rules and backtest results.
%
%   A Strategy combines a Signal object with user-defined rule parameters
%   to produce a BacktestResults timetable containing position, P&L, and
%   equity-curve columns.
%
%   Usage:
%       strat = Model.Strategy('MACrossover', sig);
%       strat.setEntryRule('SMA_20_X_SMA_50', 1);   % go long on +1 cross
%       strat.setExitRule('SMA_20_X_SMA_50', -1);   % exit on -1 cross
%       strat.run();
%       tt = strat.BacktestResults;

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Display name for this strategy.
        StrategyName  (1,1) string  = "Unnamed"

        % Handle to the Signal object — not copied.
        % R2021b: explicit empty default avoids default-constructor call.
        SignalRef     Model.Signal = Model.Signal.empty

        % Entry/exit rule specifications (struct arrays).
        EntryRules    struct = struct('column', {}, 'triggerValue', {})
        ExitRules     struct = struct('column', {}, 'triggerValue', {})

        % Backtest output timetable.
        % Columns: Position, Return, StrategyReturn, EquityCurve
        BacktestResults timetable = timetable.empty

        % Scalar performance metrics (populated after run).
        Metrics struct = struct()

        % Whether the strategy has been run since last rule change.
        IsStale (1,1) logical = true
    end

    properties
        % Initial capital for equity curve calculation.
        InitialCapital (1,1) double {mustBePositive} = 100000

        % Transaction cost per trade as a fraction (e.g. 0.001 = 10 bps).
        TransactionCost (1,1) double {mustBeNonnegative} = 0.001

        % Maximum position size as a fraction of capital (1 = fully invested).
        MaxPositionSize (1,1) double {mustBeInRange(MaxPositionSize,0,1)} = 1.0
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = Strategy(name, signalObj)
        % Strategy  Constructor.
        %   strat = Model.Strategy('MyStrat', signalObj)
            arguments
                name      (1,1) string
                signalObj (1,1) Model.Signal
            end
            obj = obj@Model.BaseModel("Strategy:" + name);
            obj.StrategyName = name;
            obj.SignalRef    = signalObj;
            addlistener(signalObj, 'Changed', @(~,~) obj.onSignalChanged());
        end

        % -------------------------------------------------------------- %
        function setEntryRule(obj, signalColumn, triggerValue)
        % setEntryRule  Add or replace an entry rule.
        %
        %   strat.setEntryRule('SMA_20_X_SMA_50', 1)
        %   Entry fires when signalColumn == triggerValue.
            arguments
                obj
                signalColumn  (1,1) string
                triggerValue  (1,1) double
            end
            obj.upsertRule('entry', signalColumn, triggerValue);
        end

        % -------------------------------------------------------------- %
        function setExitRule(obj, signalColumn, triggerValue)
        % setExitRule  Add or replace an exit rule.
        %
        %   strat.setExitRule('SMA_20_X_SMA_50', -1)
            arguments
                obj
                signalColumn  (1,1) string
                triggerValue  (1,1) double
            end
            obj.upsertRule('exit', signalColumn, triggerValue);
        end

        % -------------------------------------------------------------- %
        function run(obj)
        % run  Execute the backtest and populate BacktestResults.
        %
        %   Requires at least one entry and one exit rule to be defined.
        %   Results are stored in obj.BacktestResults (timetable).
            if isempty(obj.EntryRules) || isempty(obj.ExitRules)
                error('SignalBuilder:Strategy:noRules', ...
                    'Define at least one entry rule and one exit rule before running.');
            end
            prices  = obj.SignalRef.MarketDataRef.Prices;
            signals = obj.SignalRef.SignalTable;
            n       = height(prices);

            position = zeros(n, 1);
            ret      = [NaN; diff(prices.Close) ./ prices.Close(1:end-1)];
            trades   = zeros(n, 1);   % +1 buy, -1 sell, 0 hold

            for i = 2 : n
                prevPos = position(i-1);
                % Check entry
                entered = obj.evalRules(obj.EntryRules, signals, i);
                exited  = obj.evalRules(obj.ExitRules,  signals, i);

                if prevPos == 0 && entered && ~exited
                    position(i) = obj.MaxPositionSize;
                    trades(i)   = 1;
                elseif prevPos ~= 0 && exited
                    position(i) = 0;
                    trades(i)   = -1;
                else
                    position(i) = prevPos;
                end
            end

            % --- 1-bar implementation lag ---
            % position(i) is decided using signal(i) at COB bar i.
            % posLag(i) = position active during bar i (decided at COB bar i-1).
            posLag = [0; position(1:end-1)];

            % Strategy returns: earn posLag(i)*ret(i); pay cost on rebalance bar.
            cost     = abs(diff([0; position])) * obj.TransactionCost;
            stratRet = posLag .* ret - cost;
            stratRet(isnan(stratRet)) = 0;

            % Equity curve
            equity = obj.InitialCapital * cumprod(1 + stratRet);

            % Position column stores posLag: position active during each bar.
            obj.BacktestResults = timetable(prices.Time, ...
                posLag, ret, stratRet, equity, trades, ...
                'VariableNames', ...
                {'Position','AssetReturn','StrategyReturn','EquityCurve','Trade'});
            obj.BacktestResults.Properties.Description = ...
                obj.StrategyName + " backtest results";

            obj.computeMetrics(stratRet, equity);
            obj.IsStale = false;
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        function disp(obj)
            fprintf('Strategy: %s\n', obj.StrategyName);
            fprintf('  Stale : %d\n', obj.IsStale);
            if ~isempty(fieldnames(obj.Metrics))
                flds = fieldnames(obj.Metrics);
                for k = 1:numel(flds)
                    fprintf('  %-20s: %.4f\n', flds{k}, obj.Metrics.(flds{k}));
                end
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function upsertRule(obj, kind, col, val)
            if strcmp(kind, 'entry')
                rules = obj.EntryRules;
            else
                rules = obj.ExitRules;
            end
            idx = find(strcmp({rules.column}, col), 1);
            newRule = struct('column', col, 'triggerValue', val);
            if isempty(idx)
                rules(end+1) = newRule;
            else
                rules(idx) = newRule;
            end
            if strcmp(kind, 'entry')
                obj.EntryRules = rules;
            else
                obj.ExitRules = rules;
            end
            obj.IsStale = true;
        end

        function tf = evalRules(~, rules, signals, row)
            tf = false;
            if isempty(rules)
                return;
            end
            for k = 1 : numel(rules)
                col = rules(k).column;
                val = rules(k).triggerValue;
                if ~ismember(col, signals.Properties.VariableNames)
                    return;
                end
                if signals.(col)(row) ~= val
                    return;
                end
            end
            tf = true;
        end

        function computeMetrics(obj, stratRet, equity)
            m = struct();
            m.TotalReturn     = (equity(end) - obj.InitialCapital) / obj.InitialCapital;
            rfDaily           = 0;   % risk-free rate placeholder
            excess            = stratRet - rfDaily;
            m.SharpeRatio     = mean(excess,'omitnan') / ...
                                 max(std(excess,'omitnan'), eps) * sqrt(252);
            running           = cummax(equity);
            drawdown          = (equity - running) ./ running;
            m.MaxDrawdown     = min(drawdown);
            posRet            = stratRet(stratRet > 0);
            negRet            = stratRet(stratRet < 0);
            m.WinRate         = numel(posRet) / max(numel(posRet)+numel(negRet), 1);
            m.ProfitFactor    = sum(posRet) / max(abs(sum(negRet)), eps);
            obj.Metrics = m;
        end

        function onSignalChanged(obj)
            obj.IsStale = true;
            obj.BacktestResults = timetable.empty;
            obj.Metrics = struct();
        end
    end
end
