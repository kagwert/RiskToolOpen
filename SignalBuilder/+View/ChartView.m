classdef ChartView < View.BaseView
% ChartView  Renders OHLCV price data and signal overlays from timetables.
%
%   All data must be passed as timetable arguments — never as raw arrays.
%   RowTimes provide the x-axis; column names label series automatically.
%
%   Usage:
%       cv = View.ChartView('AAPL Price & Signals');
%       cv.setPriceData(md.getPrices());
%       cv.setSignalData(sig.getSignals(['SMA_20','SMA_50']));
%       cv.render();
%       cv.show();

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Timetable with at least a Close column (from MarketData).
        PriceData   timetable = timetable.empty

        % Timetable of signal columns to overlay on the price panel.
        SignalData  timetable = timetable.empty

        % Timetable with columns StrategyReturn / EquityCurve (from Strategy).
        EquityData  timetable = timetable.empty
    end

    properties
        % Colour order for overlaid signal lines.
        LineColors  (:,3) double = lines(8)
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = ChartView(title)
        % ChartView  Constructor.
        %   cv = View.ChartView('SPY Dashboard')
            arguments
                title (1,1) string = "Price & Signals"
            end
            obj = obj@View.BaseView(title);
        end

        % -------------------------------------------------------------- %
        function setPriceData(obj, tt)
        % setPriceData  Assign a price timetable (must contain Close).
            arguments
                obj
                tt timetable
            end
            Model.BaseModel.validateTimetable(tt, "Close");
            obj.PriceData = tt;
        end

        % -------------------------------------------------------------- %
        function setSignalData(obj, tt)
        % setSignalData  Assign signal columns to overlay on price chart.
            arguments
                obj
                tt timetable
            end
            obj.SignalData = tt;
        end

        % -------------------------------------------------------------- %
        function setEquityData(obj, tt)
        % setEquityData  Assign backtest equity curve timetable.
            arguments
                obj
                tt timetable
            end
            obj.EquityData = tt;
        end

        % -------------------------------------------------------------- %
        function render(obj)
        % render  Build or refresh the chart figure.
        %
        %   Creates up to 3 stacked panels:
        %       1. Price + signal overlays
        %       2. Volume bars (if present in PriceData)
        %       3. Equity curve (if EquityData is set)
            if isempty(obj.PriceData)
                error('SignalBuilder:ChartView:noData', ...
                    'Set PriceData before calling render().');
            end
            if ~obj.hasFigure()
                obj.createFigure();
            end
            obj.clearAxes();
            obj.Figure.Visible = 'on';

            hasVolume = ismember('Volume', obj.PriceData.Properties.VariableNames);
            hasEquity = ~isempty(obj.EquityData);

            nPanels  = 1 + hasVolume + hasEquity;
            heights  = obj.panelHeights(hasVolume, hasEquity);
            axs      = obj.buildTiledLayout(nPanels, heights);

            panelIdx = 1;
            obj.renderPricePanel(axs(panelIdx));

            if hasVolume
                panelIdx = panelIdx + 1;
                obj.renderVolumePanel(axs(panelIdx));
            end
            if hasEquity
                panelIdx = panelIdx + 1;
                obj.renderEquityPanel(axs(panelIdx));
            end

            obj.IsRendered = true;
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function renderPricePanel(obj, ax)
            t     = obj.PriceData.Time;
            close = obj.PriceData.Close;
            plot(ax, t, close, 'Color', [0.2 0.2 0.2], 'LineWidth', 1.2, ...
                'DisplayName', 'Close');
            hold(ax, 'on');
            % Overlay signal columns
            if ~isempty(obj.SignalData)
                vars = obj.SignalData.Properties.VariableNames;
                for k = 1 : numel(vars)
                    col = obj.SignalData.(vars{k});
                    % Only overlay price-scale signals (magnitude similar to Close)
                    if median(col,'omitnan') > 1
                        c = obj.LineColors(mod(k-1, size(obj.LineColors,1))+1, :);
                        plot(ax, obj.SignalData.Time, col, ...
                            'Color', c, 'LineWidth', 1, ...
                            'DisplayName', vars{k});
                    end
                end
            end
            hold(ax, 'off');
            ylabel(ax, 'Price');
            legend(ax, 'Location', 'northwest');
            grid(ax, 'on');
            ax.XTickLabelRotation = 30;
            title(ax, obj.Title);
        end

        function renderVolumePanel(obj, ax)
            t   = obj.PriceData.Time;
            vol = obj.PriceData.Volume;
            bar(ax, t, vol, 'FaceColor', [0.5 0.7 0.9], 'EdgeColor', 'none');
            ylabel(ax, 'Volume');
            grid(ax, 'on');
            ax.XTickLabelRotation = 30;
        end

        function renderEquityPanel(obj, ax)
            if ~ismember('EquityCurve', obj.EquityData.Properties.VariableNames)
                return;
            end
            t  = obj.EquityData.Time;
            ec = obj.EquityData.EquityCurve;
            plot(ax, t, ec, 'Color', [0.1 0.6 0.3], 'LineWidth', 1.5);
            yline(ax, ec(1), '--', 'Color', [0.6 0.6 0.6]);
            ylabel(ax, 'Equity ($)');
            grid(ax, 'on');
            ax.XTickLabelRotation = 30;
            title(ax, 'Equity Curve');
        end

        function axs = buildTiledLayout(obj, nPanels, heights)
            tl  = tiledlayout(obj.Figure, nPanels, 1, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            axs = gobjects(nPanels, 1);
            for k = 1 : nPanels
                axs(k) = nexttile(tl);
                axs(k).TileIndexing = 'rowmajor';
            end
            % Set relative tile heights
            tl.RowHeight = num2cell(heights);
        end

        function h = panelHeights(~, hasVolume, hasEquity)
            h = 3;   % price panel
            if hasVolume, h = [h, 1]; end
            if hasEquity, h = [h, 2]; end
        end
    end
end
