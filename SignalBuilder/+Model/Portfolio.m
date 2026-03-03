classdef Portfolio < Model.BaseModel
% Portfolio  Handle class managing a collection of Strategy objects.
%
%   Aggregates multiple strategies into a portfolio-level timetable with
%   combined equity curve and cross-strategy analytics.
%
%   Usage:
%       port = Model.Portfolio('MyPortfolio');
%       port.addStrategy(strat1, 0.6);   % 60% weight
%       port.addStrategy(strat2, 0.4);   % 40% weight
%       port.run();
%       tt = port.EquityCurve;

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        PortfolioName (1,1) string  = "Portfolio"

        % Struct array: fields Strategy (handle) and Weight (double).
        Positions     struct = struct('Strategy', {}, 'Weight', {})

        % Combined portfolio equity curve timetable.
        % Columns: one per strategy return + CombinedReturn + EquityCurve.
        EquityCurve   timetable = timetable.empty

        % Portfolio-level performance metrics.
        Metrics struct = struct()
    end

    properties
        InitialCapital (1,1) double {mustBePositive} = 100000
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = Portfolio(name)
        % Portfolio  Constructor.
        %   port = Model.Portfolio('AllWeather')
            arguments
                name (1,1) string = "Portfolio"
            end
            obj = obj@Model.BaseModel("Portfolio:" + name);
            obj.PortfolioName = name;
        end

        % -------------------------------------------------------------- %
        function addStrategy(obj, stratObj, weight)
        % addStrategy  Register a Strategy with an allocation weight.
        %
        %   Weights need not sum to 1 — they are normalised at run time.
        %
        %   port.addStrategy(strat1, 0.5)
            arguments
                obj
                stratObj (1,1) Model.Strategy
                weight   (1,1) double {mustBePositive} = 1
            end
            % Replace if already registered
            names = arrayfun(@(p) p.Strategy.StrategyName, obj.Positions, ...
                'UniformOutput', false);
            idx = find(strcmp(names, stratObj.StrategyName), 1);
            newPos = struct('Strategy', stratObj, 'Weight', weight);
            if isempty(idx)
                obj.Positions(end+1) = newPos;
            else
                obj.Positions(idx) = newPos;
            end
            % Listen for strategy changes
            addlistener(stratObj, 'Changed', @(~,~) obj.onStrategyChanged());
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        function removeStrategy(obj, strategyName)
        % removeStrategy  Remove a strategy from the portfolio by name.
            arguments
                obj
                strategyName (1,1) string
            end
            names = arrayfun(@(p) p.Strategy.StrategyName, obj.Positions, ...
                'UniformOutput', false);
            idx = strcmp(names, strategyName);
            if ~any(idx)
                error('SignalBuilder:Portfolio:notFound', ...
                    'Strategy "%s" not in portfolio.', strategyName);
            end
            obj.Positions(idx) = [];
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        function run(obj)
        % run  Compute portfolio-level equity curve from all strategies.
        %
        %   All strategy BacktestResults must already be populated
        %   (i.e. Strategy.run() called on each).  Stale strategies will
        %   trigger a warning.
            if isempty(obj.Positions)
                error('SignalBuilder:Portfolio:empty', ...
                    'No strategies registered.');
            end
            % Warn on stale strategies
            for k = 1 : numel(obj.Positions)
                s = obj.Positions(k).Strategy;
                if s.IsStale
                    warning('SignalBuilder:Portfolio:staleStrategy', ...
                        'Strategy "%s" is stale — run it first.', ...
                        s.StrategyName);
                end
            end

            % Normalise weights
            weights = [obj.Positions.Weight];
            weights = weights / sum(weights);

            % Gather all strategy return timetables and synchronise
            ttList = cell(numel(obj.Positions), 1);
            for k = 1 : numel(obj.Positions)
                s   = obj.Positions(k).Strategy;
                ret = s.BacktestResults(:, 'StrategyReturn');
                ret.Properties.VariableNames = {s.StrategyName};
                ttList{k} = ret;
            end
            combined = ttList{1};
            for k = 2 : numel(ttList)
                combined = synchronize(combined, ttList{k}, ...
                    'union', 'fillwithconstant', 0);
            end

            % Weighted portfolio return
            varNames = combined.Properties.VariableNames;
            mat      = table2array(combined(:, varNames));
            portRet  = mat * weights(:);

            equity   = obj.InitialCapital * cumprod(1 + portRet);
            combined.PortfolioReturn = portRet;
            combined.EquityCurve     = equity;

            obj.EquityCurve = combined;
            obj.computeMetrics(portRet, equity);
            obj.notifyChanged();
        end

        % -------------------------------------------------------------- %
        function disp(obj)
            fprintf('Portfolio: %s  (%d strategies)\n', ...
                obj.PortfolioName, numel(obj.Positions));
            for k = 1 : numel(obj.Positions)
                fprintf('  [%.1f%%] %s\n', ...
                    obj.Positions(k).Weight * 100, ...
                    obj.Positions(k).Strategy.StrategyName);
            end
            if ~isempty(fieldnames(obj.Metrics))
                fprintf('Performance:\n');
                flds = fieldnames(obj.Metrics);
                for k = 1:numel(flds)
                    fprintf('  %-20s: %.4f\n', flds{k}, obj.Metrics.(flds{k}));
                end
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function computeMetrics(obj, portRet, equity)
            m = struct();
            m.TotalReturn  = (equity(end) - obj.InitialCapital) / obj.InitialCapital;
            excess         = portRet;
            m.SharpeRatio  = mean(excess,'omitnan') / ...
                              max(std(excess,'omitnan'), eps) * sqrt(252);
            running        = cummax(equity);
            m.MaxDrawdown  = min((equity - running) ./ running);
            m.Volatility   = std(portRet, 'omitnan') * sqrt(252);
            obj.Metrics    = m;
        end

        function onStrategyChanged(obj)
            obj.EquityCurve = timetable.empty;
            obj.Metrics     = struct();
        end
    end
end
