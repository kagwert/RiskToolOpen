classdef StrategyView < View.BaseView
% StrategyView  Summary panel for strategy performance metrics.
%
%   Displays a formatted metrics table and a drawdown chart derived
%   from the strategy's BacktestResults timetable.
%
%   Usage:
%       sv = View.StrategyView('MACrossover Summary');
%       sv.setResults(strat.BacktestResults, strat.Metrics);
%       sv.render();
%       sv.show();

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % BacktestResults timetable from a Strategy object.
        Results timetable = timetable.empty

        % Performance metrics struct from Strategy.Metrics.
        Metrics struct = struct()

        % Strategy name for display.
        StrategyName (1,1) string = ""
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = StrategyView(title)
        % StrategyView  Constructor.
            arguments
                title (1,1) string = "Strategy Summary"
            end
            obj = obj@View.BaseView(title);
        end

        % -------------------------------------------------------------- %
        function setResults(obj, resultsTT, metrics, strategyName)
        % setResults  Supply backtest data for rendering.
        %
        %   sv.setResults(strat.BacktestResults, strat.Metrics, strat.StrategyName)
            arguments
                obj
                resultsTT    timetable
                metrics      struct    = struct()
                strategyName (1,1) string = ""
            end
            Model.BaseModel.validateTimetable(resultsTT, ...
                ["StrategyReturn","EquityCurve"]);
            obj.Results      = resultsTT;
            obj.Metrics      = metrics;
            obj.StrategyName = strategyName;
        end

        % -------------------------------------------------------------- %
        function render(obj)
        % render  Draw metrics table and drawdown chart in a 2-panel figure.
            if isempty(obj.Results)
                error('SignalBuilder:StrategyView:noData', ...
                    'Call setResults() before render().');
            end
            if ~obj.hasFigure()
                obj.createFigure();
            end
            obj.clearAxes();
            obj.Figure.Visible = 'on';

            tl = tiledlayout(obj.Figure, 2, 1, ...
                'TileSpacing', 'compact', 'Padding', 'compact');

            % Panel 1 — Equity curve
            axEq = nexttile(tl);
            obj.renderEquity(axEq);

            % Panel 2 — Drawdown
            axDd = nexttile(tl);
            obj.renderDrawdown(axDd);

            sgtitle(tl, obj.Title, 'FontWeight', 'bold');

            % Metrics summary as text annotation
            obj.addMetricsAnnotation(axEq);

            obj.IsRendered = true;
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function renderEquity(obj, ax)
            t  = obj.Results.Time;
            ec = obj.Results.EquityCurve;
            area(ax, t, ec, 'FaceColor', [0.8 0.93 0.85], ...
                'EdgeColor', [0.1 0.6 0.3], 'LineWidth', 1.5);
            ylabel(ax, 'Equity ($)');
            grid(ax, 'on');
            title(ax, 'Equity Curve — ' + obj.StrategyName);
            ax.XTickLabelRotation = 30;
        end

        function renderDrawdown(obj, ax)
            ec      = obj.Results.EquityCurve;
            running = cummax(ec);
            dd      = (ec - running) ./ running * 100;
            t       = obj.Results.Time;
            area(ax, t, dd, 'FaceColor', [0.95 0.8 0.8], ...
                'EdgeColor', [0.8 0.1 0.1], 'LineWidth', 1);
            ylabel(ax, 'Drawdown (%)');
            yline(ax, 0, '-', 'Color', [0.5 0.5 0.5]);
            grid(ax, 'on');
            title(ax, 'Drawdown');
            ax.XTickLabelRotation = 30;
        end

        function addMetricsAnnotation(obj, ax)
            if isempty(fieldnames(obj.Metrics))
                return;
            end
            flds  = fieldnames(obj.Metrics);
            lines_ = cell(numel(flds), 1);
            for k = 1 : numel(flds)
                lines_{k} = sprintf('%s: %.3f', flds{k}, obj.Metrics.(flds{k}));
            end
            txt = strjoin(lines_, '  |  ');
            xlabel(ax, txt, 'FontSize', 8, 'Color', [0.3 0.3 0.3]);
        end
    end
end
