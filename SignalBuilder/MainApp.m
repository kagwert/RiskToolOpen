classdef MainApp < matlab.apps.AppBase
% MainApp  Quantitative Strategy Designer — four-tab App Designer UI.
%
%   Wires the Model layer (MarketData → SignalEngine → Backtester) through
%   a tab-based uifigure.  All MVC objects are created lazily when the user
%   loads data via the Data Source tab.
%
%   Tabs
%     1. Data Source         — load OHLCV via Alpha Vantage, Stooq, or CSV (DataManager)
%     2. Signal Design       — add transforms; uitree of computed signals;
%                              signal-overlay uiaxes
%     3. Backtest Controls   — portfolio constraints + bayesopt tuning
%     4. Performance Dashboard — metric labels + parameter-sweep heatmap
%
%   Usage:
%       app = MainApp();

    % ------------------------------------------------------------------ %
    %  UI component properties
    % ------------------------------------------------------------------ %
    properties (Access = public)

        UIFigure        matlab.ui.Figure

        % Tab group
        TabGroup        matlab.ui.container.TabGroup
        DataTab         matlab.ui.container.Tab
        SignalTab       matlab.ui.container.Tab
        BacktestTab     matlab.ui.container.Tab
        DashboardTab    matlab.ui.container.Tab

        % ── Data Source tab ─────────────────────────────────────────────
        TickerLabel         matlab.ui.control.Label
        TickerField         matlab.ui.control.EditField
        SourceLabel         matlab.ui.control.Label
        SourceDropDown      matlab.ui.control.DropDown
        ApiKeyLabel         matlab.ui.control.Label
        ApiKeyField         matlab.ui.control.EditField
        StartDateLabel      matlab.ui.control.Label
        StartDateField      matlab.ui.control.EditField
        EndDateLabel        matlab.ui.control.Label
        EndDateField        matlab.ui.control.EditField
        LoadButton          matlab.ui.control.Button
        DataStatusLabel     matlab.ui.control.Label
        PriceAxes           matlab.ui.control.UIAxes

        % ── Signal Design tab ───────────────────────────────────────────
        SignalTree          matlab.ui.container.CheckBoxTree
        TransformLabel      matlab.ui.control.Label
        TransformDropDown   matlab.ui.control.DropDown
        PeriodLabel         matlab.ui.control.Label
        PeriodField         matlab.ui.control.NumericEditField
        AggMethodLabel      matlab.ui.control.Label
        AggMethodDropDown   matlab.ui.control.DropDown
        AddSignalButton     matlab.ui.control.Button
        ClearSignalsButton  matlab.ui.control.Button
        SignalAxes          matlab.ui.control.UIAxes

        % ── Backtest Controls tab ────────────────────────────────────────
        InitCapLabel        matlab.ui.control.Label
        InitCapField        matlab.ui.control.NumericEditField
        TxCostLabel         matlab.ui.control.Label
        TxCostField         matlab.ui.control.NumericEditField
        RfRateLabel         matlab.ui.control.Label
        RfRateField         matlab.ui.control.NumericEditField
        MaxLevLabel         matlab.ui.control.Label
        MaxLevField         matlab.ui.control.NumericEditField
        MaxWtLabel          matlab.ui.control.Label
        MaxWtField          matlab.ui.control.NumericEditField
        RunBacktestButton   matlab.ui.control.Button
        Param1NameLabel     matlab.ui.control.Label
        Param1NameField     matlab.ui.control.EditField
        Param1MinLabel      matlab.ui.control.Label
        Param1MinField      matlab.ui.control.NumericEditField
        Param1MaxLabel      matlab.ui.control.Label
        Param1MaxField      matlab.ui.control.NumericEditField
        Param2NameLabel     matlab.ui.control.Label
        Param2NameField     matlab.ui.control.EditField
        Param2MinLabel      matlab.ui.control.Label
        Param2MinField      matlab.ui.control.NumericEditField
        Param2MaxLabel      matlab.ui.control.Label
        Param2MaxField      matlab.ui.control.NumericEditField
        MaxEvalLabel        matlab.ui.control.Label
        MaxEvalField        matlab.ui.control.NumericEditField
        RunOptimButton      matlab.ui.control.Button
        BacktestStatusLabel matlab.ui.control.Label
        BacktestAxes        matlab.ui.control.UIAxes

        % ── Performance Dashboard tab ────────────────────────────────────
        SharpeLabel         matlab.ui.control.Label
        SharpeValueLabel    matlab.ui.control.Label
        SortinoLabel        matlab.ui.control.Label
        SortinoValueLabel   matlab.ui.control.Label
        MaxDDLabel          matlab.ui.control.Label
        MaxDDValueLabel     matlab.ui.control.Label
        TurnoverLabel       matlab.ui.control.Label
        TurnoverValueLabel  matlab.ui.control.Label
        TotalRetLabel       matlab.ui.control.Label
        TotalRetValueLabel  matlab.ui.control.Label
        HeatmapPanel        matlab.ui.container.Panel

    end

    % ------------------------------------------------------------------ %
    %  Private application state
    % ------------------------------------------------------------------ %
    properties (Access = private)
        MarketDataObj   = []    % Model.MarketData   (created on Load)
        SignalEngObj    = []    % Model.SignalEngine  (created on Load)
        BacktesterObj   = []    % Model.Backtester    (created on Load)
        HeatmapChart    = []    % heatmap chart handle (dashboard tab)
    end

    % ================================================================== %
    %  Callbacks
    % ================================================================== %
    methods (Access = private)

        % ── Tab 1: Data Source ───────────────────────────────────────────
        function onLoadButtonPushed(app, ~)
            ticker = strtrim(app.TickerField.Value);
            if isempty(ticker)
                app.DataStatusLabel.Text = 'Error: enter a ticker symbol.';
                return
            end
            app.DataStatusLabel.Text = 'Loading data…';
            drawnow;
            try
                startDt = datetime(app.StartDateField.Value, ...
                    'InputFormat', 'yyyy-MM-dd', ...
                    'TimeZone',    'America/New_York');
                endDt   = datetime(app.EndDateField.Value, ...
                    'InputFormat', 'yyyy-MM-dd', ...
                    'TimeZone',    'America/New_York');

                md       = Model.MarketData(ticker);
                startStr = char(startDt, 'yyyy-MM-dd');
                endStr   = char(endDt,   'yyyy-MM-dd');

                switch app.SourceDropDown.Value
                    case 'Alpha Vantage'
                        dm = Model.DataManager();
                        dm.init();
                        apiKey = strtrim(app.ApiKeyField.Value);
                        if ~isempty(apiKey)
                            dm.AlphaVantageApiKey = string(apiKey);
                        end
                        tt = dm.fetch_alphavantage(ticker, startStr, endStr);
                        md.loadFromTimetable(tt, 'alphavantage');

                    case 'Stooq (free)'
                        dm = Model.DataManager();
                        dm.init();
                        tt = dm.fetch_stooq(ticker, startStr, endStr);
                        md.loadFromTimetable(tt, 'stooq');

                    case 'CSV'
                        [f, p] = uigetfile('*.csv', ...
                            'Select OHLCV CSV file');
                        if isequal(f, 0)
                            app.DataStatusLabel.Text = 'Load cancelled.';
                            return
                        end
                        md.loadFromFile(fullfile(p, f));
                end

                app.MarketDataObj = md;
                app.SignalEngObj  = Model.SignalEngine(md);
                app.BacktesterObj = Model.Backtester(app.SignalEngObj);

                app.pushConstraintsToModel();
                app.plotPrice();
                app.populateSignalTree();

                app.DataStatusLabel.Text = sprintf( ...
                    'Loaded %d bars for %s.', md.NumBars, ticker);
            catch ME
                app.DataStatusLabel.Text = ['Error: ' ME.message];
            end
        end

        % ── Tab 2: Signal Design ─────────────────────────────────────────
        function onAddSignalButtonPushed(app, ~)
            if isempty(app.SignalEngObj)
                uialert(app.UIFigure, 'Load data first.', 'No Data');
                return
            end
            period = max(1, round(app.PeriodField.Value));
            try
                switch app.TransformDropDown.Value
                    case 'Moving Average'
                        app.SignalEngObj.addMovingAverage('Close', period);
                    case 'Z-Score'
                        app.SignalEngObj.addZScore('Close', period);
                    case 'Relative Strength'
                        app.SignalEngObj.addRelativeStrength('Close', period);
                    case 'Vol-Norm Return'
                        app.SignalEngObj.addVolNormReturn('Close', period);
                end
                app.populateSignalTree();
                app.plotSignals();
            catch ME
                uialert(app.UIFigure, ME.message, 'Signal Error');
            end
        end

        function onClearSignalsButtonPushed(app, ~)
            if ~isempty(app.SignalEngObj)
                app.SignalEngObj.clearSignals();
                app.populateSignalTree();
                cla(app.SignalAxes);
                title(app.SignalAxes, 'Signal Overlay');
            end
        end

        % ── Tab 3: Backtest Controls ─────────────────────────────────────
        function onRunBacktestButtonPushed(app, ~)
            if isempty(app.BacktesterObj)
                uialert(app.UIFigure, 'Load data first.', 'No Data');
                return
            end
            if isempty(app.SignalEngObj.SignalNames)
                uialert(app.UIFigure, ...
                    'Add at least one signal in the Signal Design tab.', ...
                    'No Signals');
                return
            end
            app.BacktestStatusLabel.Text = 'Running backtest…';
            drawnow;
            try
                app.pushConstraintsToModel();
                compositeTT = app.SignalEngObj.aggregate([], ...
                    app.resolvedAggMethod());
                app.BacktesterObj.run(compositeTT);
                app.plotEquityCurve();
                app.updateMetricLabels();
                m = app.BacktesterObj.Metrics;
                app.BacktestStatusLabel.Text = sprintf( ...
                    'Done. Sharpe: %.3f  |  MaxDD: %.2f%%  |  Return: %.2f%%', ...
                    m.SharpeRatio, m.MaxDrawdown * 100, m.TotalReturn * 100);
            catch ME
                app.BacktestStatusLabel.Text = ['Error: ' ME.message];
            end
        end

        function onRunOptimButtonPushed(app, ~)
            if isempty(app.BacktesterObj)
                uialert(app.UIFigure, 'Load data first.', 'No Data');
                return
            end
            app.BacktestStatusLabel.Text = 'Running Bayesian optimisation…';
            drawnow;
            try
                app.pushConstraintsToModel();

                % Build optimizableVariable array from UI fields
                p1name = strtrim(app.Param1NameField.Value);
                p1min  = round(app.Param1MinField.Value);
                p1max  = round(app.Param1MaxField.Value);

                if isempty(p1name)
                    error('SignalBuilder:MainApp:missingParam', ...
                        'Param 1 name is required (e.g. MAWindow).');
                end
                if p1min >= p1max
                    error('SignalBuilder:MainApp:invalidRange', ...
                        'Param 1 min must be less than Param 1 max.');
                end

                paramVars = optimizableVariable(p1name, [p1min p1max], ...
                    'Type', 'integer');

                p2name = strtrim(app.Param2NameField.Value);
                if ~isempty(p2name)
                    p2min = round(app.Param2MinField.Value);
                    p2max = round(app.Param2MaxField.Value);
                    if p2min < p2max
                        paramVars(end+1) = optimizableVariable(p2name, ...
                            [p2min p2max], 'Type', 'integer');
                    end
                end

                app.BacktesterObj.OptimOptions = struct( ...
                    'MaxObjectiveEvaluations', round(app.MaxEvalField.Value), ...
                    'AcquisitionFunctionName', "expected-improvement-plus", ...
                    'Verbose',                 0);

                builderFn = @(eng) app.dynamicBuilder(eng);
                app.BacktesterObj.optimize(builderFn, ...
                    app.resolvedAggMethod(), paramVars);

                app.populateSignalTree();
                app.plotEquityCurve();
                app.updateMetricLabels();
                app.drawSweepHeatmap(paramVars);

                m = app.BacktesterObj.Metrics;
                app.BacktestStatusLabel.Text = sprintf( ...
                    'Optimisation done. Best Sharpe: %.3f  |  Return: %.2f%%', ...
                    m.SharpeRatio, m.TotalReturn * 100);
            catch ME
                app.BacktestStatusLabel.Text = ['Error: ' ME.message];
            end
        end

    end   % end callbacks

    % ================================================================== %
    %  Private helpers
    % ================================================================== %
    methods (Access = private)

        % Convert AggMethodDropDown value to aggregate() method string.
        function s = resolvedAggMethod(app)
            s = lower(strrep(app.AggMethodDropDown.Value, ' ', '_'));
        end

        % Push UI constraint/capital fields into the Backtester handle.
        function pushConstraintsToModel(app)
            if isempty(app.BacktesterObj); return; end
            app.BacktesterObj.InitialCapital     = app.InitCapField.Value;
            app.BacktesterObj.TransactionCost    = app.TxCostField.Value;
            app.BacktesterObj.RiskFreeRateAnnual = app.RfRateField.Value / 100;
            app.BacktesterObj.Constraints = struct( ...
                'MaxLeverage',       app.MaxLevField.Value, ...
                'MaxWeightPerAsset', app.MaxWtField.Value, ...
                'MinWeightPerAsset', 0);
        end

        % Signal-builder callback used by Backtester.optimize().
        % eng.Params fields are updated by the optimiser before each call;
        % the chosen transform re-reads the updated window from eng.Params.
        function dynamicBuilder(app, eng)
            eng.clearSignals();
            switch app.TransformDropDown.Value
                case 'Moving Average'
                    eng.addMovingAverage('Close');    % uses eng.Params.MAWindow
                case 'Z-Score'
                    eng.addZScore('Close');           % uses eng.Params.ZScoreWindow
                case 'Relative Strength'
                    eng.addRelativeStrength('Close'); % uses eng.Params.RSWindow
                case 'Vol-Norm Return'
                    eng.addVolNormReturn('Close');    % uses eng.Params.VolNormWindow
            end
        end

        % ── Plot helpers ─────────────────────────────────────────────────

        function plotPrice(app)
            if isempty(app.MarketDataObj) || app.MarketDataObj.NumBars == 0
                return
            end
            ax = app.PriceAxes;
            cla(ax);
            tt = app.MarketDataObj.Prices;
            plot(ax, tt.Time, tt.Close, 'b-', 'LineWidth', 1.2);
            title(ax, [app.MarketDataObj.Ticker ' — Close Price']);
            xlabel(ax, 'Date');
            ylabel(ax, 'Price ($)');
            grid(ax, 'on');
        end

        function plotSignals(app)
            if isempty(app.SignalEngObj) || ...
                    isempty(app.SignalEngObj.SignalNames)
                return
            end
            ax = app.SignalAxes;
            cla(ax);
            hold(ax, 'on');

            % Normalise close to [0, 1] for overlay legibility
            c     = app.MarketDataObj.Prices.Close;
            cNorm = (c - min(c)) / max(range(c), eps);
            plot(ax, app.MarketDataObj.Prices.Time, cNorm, ...
                'k-', 'LineWidth', 1.5, 'DisplayName', 'Close (norm)');

            st   = app.SignalEngObj.SignalTable;
            cols = st.Properties.VariableNames;
            for i = 1:numel(cols)
                v     = st.(cols{i});
                vMin  = min(v, [], 'omitnan');
                vMax  = max(v, [], 'omitnan');
                vNorm = (v - vMin) / max(vMax - vMin, eps);
                plot(ax, st.Time, vNorm, 'DisplayName', cols{i});
            end

            legend(ax, 'Location', 'best', 'Interpreter', 'none');
            title(ax, 'Signal Overlay (min-max normalised)');
            xlabel(ax, 'Date');
            grid(ax, 'on');
            hold(ax, 'off');
        end

        function plotEquityCurve(app)
            if isempty(app.BacktesterObj) || ...
                    isempty(app.BacktesterObj.BacktestResults)
                return
            end
            res    = app.BacktesterObj.BacktestResults;
            equity = res.EquityCurve;
            dd     = (equity - cummax(equity)) ./ cummax(equity) * 100;

            ax = app.BacktestAxes;
            cla(ax);

            yyaxis(ax, 'left');
            plot(ax, res.Time, equity, 'b-', 'LineWidth', 1.5);
            ylabel(ax, 'Equity ($)');

            yyaxis(ax, 'right');
            area(ax, res.Time, dd, ...
                'FaceColor', [0.85 0.15 0.15], ...
                'FaceAlpha', 0.30, ...
                'EdgeColor', 'none');
            ylabel(ax, 'Drawdown (%)');

            title(ax, 'Equity Curve & Drawdown');
            xlabel(ax, 'Date');
            grid(ax, 'on');
        end

        function updateMetricLabels(app)
            m = app.BacktesterObj.Metrics;
            if isempty(fieldnames(m)); return; end
            app.SharpeValueLabel.Text   = sprintf('%.3f',    m.SharpeRatio);
            app.SortinoValueLabel.Text  = sprintf('%.3f',    m.SortinoRatio);
            app.MaxDDValueLabel.Text    = sprintf('%.2f%%',  m.MaxDrawdown * 100);
            app.TurnoverValueLabel.Text = sprintf('%.2f×/yr', m.TurnoverAnnual);
            app.TotalRetValueLabel.Text = sprintf('%.2f%%',  m.TotalReturn * 100);
        end

        % Rebuild CheckBoxTree nodes from current SignalEngine column names.
        function populateSignalTree(app)
            delete(app.SignalTree.Children);
            if isempty(app.SignalEngObj); return; end
            names = app.SignalEngObj.SignalNames;
            for i = 1:numel(names)
                uitreenode(app.SignalTree, 'Text', char(names(i)));
            end
        end

        % Draw Sharpe heatmap from bayesopt trace (requires ≥2 params).
        function drawSweepHeatmap(app, paramVars)
            res = app.BacktesterObj.OptimResult;
            if isempty(res) || numel(paramVars) < 2; return; end

            tbl     = res.XTrace;
            sharpes = -res.ObjectiveTrace;   % stored as negative Sharpe

            p1 = paramVars(1).Name;
            p2 = paramVars(2).Name;
            if ~ismember(p1, tbl.Properties.VariableNames) || ...
               ~ismember(p2, tbl.Properties.VariableNames)
                return
            end

            g1 = unique(tbl.(p1));
            g2 = unique(tbl.(p2));
            Z  = NaN(numel(g1), numel(g2));
            for k = 1:height(tbl)
                r = find(g1 == tbl.(p1)(k), 1);
                c = find(g2 == tbl.(p2)(k), 1);
                if ~isnan(sharpes(k))
                    if isnan(Z(r,c)) || sharpes(k) > Z(r,c)
                        Z(r,c) = sharpes(k);
                    end
                end
            end

            % Clear hint label and previous chart, then draw
            delete(app.HeatmapChart);
            delete(app.HeatmapPanel.Children);
            app.HeatmapChart = heatmap(app.HeatmapPanel, ...
                string(g2), string(g1), Z);
            app.HeatmapChart.Title    = 'Sharpe Ratio — Parameter Sweep';
            app.HeatmapChart.XLabel   = p2;
            app.HeatmapChart.YLabel   = p1;
            app.HeatmapChart.Colormap = parula;
        end

        % ── Row-factory helpers ──────────────────────────────────────────

        function [lbl, fld] = makeNumRow(~, parent, row, labelTxt, defVal, lims)
            lbl = uilabel(parent, 'Text', labelTxt, ...
                'HorizontalAlignment', 'right');
            lbl.Layout.Row = row; lbl.Layout.Column = 1;
            fld = uieditfield(parent, 'numeric', ...
                'Value', defVal, 'Limits', lims);
            fld.Layout.Row = row; fld.Layout.Column = 2;
        end

        function [lbl, fld] = makeStrRow(~, parent, row, labelTxt, defVal)
            lbl = uilabel(parent, 'Text', labelTxt, ...
                'HorizontalAlignment', 'right');
            lbl.Layout.Row = row; lbl.Layout.Column = 1;
            fld = uieditfield(parent, 'text', 'Value', defVal);
            fld.Layout.Row = row; fld.Layout.Column = 2;
        end

        function [lbl, val] = makeMetricRow(~, parent, row, labelTxt)
            lbl = uilabel(parent, 'Text', [labelTxt ':'], ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = row; lbl.Layout.Column = 1;
            val = uilabel(parent, 'Text', '—', ...
                'FontSize', 13, 'FontColor', [0 0.45 0.74]);
            val.Layout.Row = row; val.Layout.Column = 2;
        end

    end   % end helpers

    % ================================================================== %
    %  Component construction
    % ================================================================== %
    methods (Access = private)

        function createComponents(app)
            app.UIFigure          = uifigure('Visible', 'off');
            app.UIFigure.Position = [80 60 1280 780];
            app.UIFigure.Name     = 'Quantitative Strategy Designer';

            app.TabGroup          = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [0 0 1280 780];

            app.DataTab      = uitab(app.TabGroup, 'Title', 'Data Source');
            app.SignalTab    = uitab(app.TabGroup, 'Title', 'Signal Design');
            app.BacktestTab  = uitab(app.TabGroup, 'Title', 'Backtest Controls');
            app.DashboardTab = uitab(app.TabGroup, 'Title', 'Performance Dashboard');

            app.buildDataTab();
            app.buildSignalTab();
            app.buildBacktestTab();
            app.buildDashboardTab();

            app.UIFigure.Visible = 'on';
        end

        % ── Tab 1: Data Source ────────────────────────────────────────────
        function buildDataTab(app)
            gl = uigridlayout(app.DataTab, [1, 2]);
            gl.ColumnWidth   = {270, '1x'};
            gl.Padding       = [12 12 12 12];
            gl.ColumnSpacing = 12;

            % Left controls sub-grid (8 rows: ticker, source, api-key,
            %   start, end, load button, status, spacer)
            ctrlGL = uigridlayout(gl, [8, 2]);
            ctrlGL.Layout.Row    = 1;
            ctrlGL.Layout.Column = 1;
            ctrlGL.ColumnWidth   = {'fit', '1x'};
            ctrlGL.RowHeight     = {30, 30, 30, 30, 30, 34, 22, '1x'};
            ctrlGL.Padding       = [0 0 0 0];
            ctrlGL.RowSpacing    = 6;

            app.TickerLabel = uilabel(ctrlGL, 'Text', 'Ticker:');
            app.TickerLabel.Layout.Row = 1; app.TickerLabel.Layout.Column = 1;
            app.TickerField = uieditfield(ctrlGL, 'text', 'Value', 'SPY');
            app.TickerField.Layout.Row = 1; app.TickerField.Layout.Column = 2;

            app.SourceLabel = uilabel(ctrlGL, 'Text', 'Source:');
            app.SourceLabel.Layout.Row = 2; app.SourceLabel.Layout.Column = 1;
            app.SourceDropDown = uidropdown(ctrlGL, ...
                'Items', {'Alpha Vantage', 'Stooq (free)', 'CSV'});
            app.SourceDropDown.Layout.Row = 2; app.SourceDropDown.Layout.Column = 2;

            app.ApiKeyLabel = uilabel(ctrlGL, ...
                'Text', 'API Key:', 'Tooltip', ...
                'Alpha Vantage key (free at alphavantage.co) — ignored for Stooq/CSV');
            app.ApiKeyLabel.Layout.Row = 3; app.ApiKeyLabel.Layout.Column = 1;
            app.ApiKeyField = uieditfield(ctrlGL, 'text', 'Value', 'YNQ6E25JPWLS6M25', ...
                'Placeholder', 'alphavantage.co free key (or set env var ALPHAVANTAGE_API_KEY)');
            app.ApiKeyField.Layout.Row = 3; app.ApiKeyField.Layout.Column = 2;

            app.StartDateLabel = uilabel(ctrlGL, 'Text', 'Start Date:');
            app.StartDateLabel.Layout.Row = 4; app.StartDateLabel.Layout.Column = 1;
            app.StartDateField = uieditfield(ctrlGL, 'text', 'Value', '2020-01-01');
            app.StartDateField.Layout.Row = 4; app.StartDateField.Layout.Column = 2;

            app.EndDateLabel = uilabel(ctrlGL, 'Text', 'End Date:');
            app.EndDateLabel.Layout.Row = 5; app.EndDateLabel.Layout.Column = 1;
            app.EndDateField = uieditfield(ctrlGL, 'text', ...
                'Value', char(datetime('today'), 'yyyy-MM-dd'));
            app.EndDateField.Layout.Row = 5; app.EndDateField.Layout.Column = 2;

            app.LoadButton = uibutton(ctrlGL, 'push', 'Text', 'Load Data', ...
                'ButtonPushedFcn', @(~,~) app.onLoadButtonPushed([]));
            app.LoadButton.Layout.Row = 6; app.LoadButton.Layout.Column = [1 2];

            app.DataStatusLabel = uilabel(ctrlGL, ...
                'Text', 'Ready — select a source and click Load Data.', ...
                'FontColor', [0.40 0.40 0.40], 'WordWrap', 'on');
            app.DataStatusLabel.Layout.Row = 7; app.DataStatusLabel.Layout.Column = [1 2];

            % Right: price uiaxes
            app.PriceAxes = uiaxes(gl);
            app.PriceAxes.Layout.Row    = 1;
            app.PriceAxes.Layout.Column = 2;
            title(app.PriceAxes,  'Price Chart');
            xlabel(app.PriceAxes, 'Date');
            ylabel(app.PriceAxes, 'Close ($)');
        end

        % ── Tab 2: Signal Design ──────────────────────────────────────────
        function buildSignalTab(app)
            gl = uigridlayout(app.SignalTab, [1, 2]);
            gl.ColumnWidth   = {280, '1x'};
            gl.Padding       = [12 12 12 12];
            gl.ColumnSpacing = 12;

            % Left controls
            leftGL = uigridlayout(gl, [9, 2]);
            leftGL.Layout.Row    = 1;
            leftGL.Layout.Column = 1;
            leftGL.ColumnWidth   = {'fit', '1x'};
            leftGL.RowHeight     = {22, '1x', 30, 30, 30, 34, 34, 6, 22};
            leftGL.Padding       = [0 0 0 0];
            leftGL.RowSpacing    = 6;

            hdrLbl = uilabel(leftGL, 'Text', 'Computed Signals', ...
                'FontWeight', 'bold');
            hdrLbl.Layout.Row = 1; hdrLbl.Layout.Column = [1 2];

            app.SignalTree = uitree(leftGL, 'checkbox');
            app.SignalTree.Layout.Row    = 2;
            app.SignalTree.Layout.Column = [1 2];

            app.TransformLabel = uilabel(leftGL, 'Text', 'Transform:');
            app.TransformLabel.Layout.Row = 3; app.TransformLabel.Layout.Column = 1;
            app.TransformDropDown = uidropdown(leftGL, 'Items', ...
                {'Moving Average', 'Z-Score', 'Relative Strength', 'Vol-Norm Return'});
            app.TransformDropDown.Layout.Row = 3; app.TransformDropDown.Layout.Column = 2;

            app.PeriodLabel = uilabel(leftGL, 'Text', 'Period:');
            app.PeriodLabel.Layout.Row = 4; app.PeriodLabel.Layout.Column = 1;
            app.PeriodField = uieditfield(leftGL, 'numeric', ...
                'Value', 20, 'Limits', [1 1000], 'RoundFractionalValues', 'on');
            app.PeriodField.Layout.Row = 4; app.PeriodField.Layout.Column = 2;

            app.AggMethodLabel = uilabel(leftGL, 'Text', 'Aggregation:');
            app.AggMethodLabel.Layout.Row = 5; app.AggMethodLabel.Layout.Column = 1;
            app.AggMethodDropDown = uidropdown(leftGL, ...
                'Items', {'Static', 'Risk Parity', 'Logic Gate'});
            app.AggMethodDropDown.Layout.Row = 5; app.AggMethodDropDown.Layout.Column = 2;

            app.AddSignalButton = uibutton(leftGL, 'push', 'Text', 'Add Signal', ...
                'ButtonPushedFcn', @(~,~) app.onAddSignalButtonPushed([]));
            app.AddSignalButton.Layout.Row = 6; app.AddSignalButton.Layout.Column = [1 2];

            app.ClearSignalsButton = uibutton(leftGL, 'push', ...
                'Text', 'Clear All Signals', ...
                'ButtonPushedFcn', @(~,~) app.onClearSignalsButtonPushed([]));
            app.ClearSignalsButton.Layout.Row = 7; app.ClearSignalsButton.Layout.Column = [1 2];

            % Row 8 is a spacer; row 9 is a hint label
            hintLbl = uilabel(leftGL, ...
                'Text', 'Tip: period field maps to the Params window for optimisation.', ...
                'FontColor', [0.5 0.5 0.5], 'FontSize', 10, 'WordWrap', 'on');
            hintLbl.Layout.Row = 9; hintLbl.Layout.Column = [1 2];

            % Right: signal overlay uiaxes
            app.SignalAxes = uiaxes(gl);
            app.SignalAxes.Layout.Row    = 1;
            app.SignalAxes.Layout.Column = 2;
            title(app.SignalAxes, 'Signal Overlay');
            xlabel(app.SignalAxes, 'Date');
        end

        % ── Tab 3: Backtest Controls ──────────────────────────────────────
        function buildBacktestTab(app)
            gl = uigridlayout(app.BacktestTab, [1, 2]);
            gl.ColumnWidth   = {310, '1x'};
            gl.Padding       = [12 12 12 12];
            gl.ColumnSpacing = 12;

            % Left controls — 17 rows
            rowH = num2cell([22, repmat(28, 1, 5), 34, ...
                             22, repmat(28, 1, 7), 34, 30]);
            leftGL = uigridlayout(gl, [17, 2]);
            leftGL.Layout.Row    = 1;
            leftGL.Layout.Column = 1;
            leftGL.ColumnWidth   = {'fit', '1x'};
            leftGL.RowHeight     = rowH;
            leftGL.Padding       = [0 0 0 0];
            leftGL.RowSpacing    = 4;

            row = 1;
            lbl1 = uilabel(leftGL, 'Text', '── Portfolio Settings ──', ...
                'FontWeight', 'bold');
            lbl1.Layout.Row = row; lbl1.Layout.Column = [1 2]; row = row + 1;

            [app.InitCapLabel,  app.InitCapField]  = app.makeNumRow(leftGL, row, ...
                'Init. Capital ($):', 100000, [1 1e9]);     row = row + 1;
            [app.TxCostLabel,   app.TxCostField]   = app.makeNumRow(leftGL, row, ...
                'Tx Cost (frac):', 0.001, [0 0.5]);         row = row + 1;
            [app.RfRateLabel,   app.RfRateField]   = app.makeNumRow(leftGL, row, ...
                'Rf Rate (%/yr):', 0, [0 20]);              row = row + 1;
            [app.MaxLevLabel,   app.MaxLevField]   = app.makeNumRow(leftGL, row, ...
                'Max Leverage:', 1, [0 10]);                row = row + 1;
            [app.MaxWtLabel,    app.MaxWtField]    = app.makeNumRow(leftGL, row, ...
                'Max Wt/Asset:', 1, [0 1]);                 row = row + 1;

            app.RunBacktestButton = uibutton(leftGL, 'push', ...
                'Text', 'Run Backtest', ...
                'ButtonPushedFcn', @(~,~) app.onRunBacktestButtonPushed([]));
            app.RunBacktestButton.Layout.Row = row;
            app.RunBacktestButton.Layout.Column = [1 2]; row = row + 1;

            lbl2 = uilabel(leftGL, 'Text', '── Bayesian Optimisation ──', ...
                'FontWeight', 'bold');
            lbl2.Layout.Row = row; lbl2.Layout.Column = [1 2]; row = row + 1;

            [app.Param1NameLabel, app.Param1NameField] = app.makeStrRow(leftGL, row, ...
                'Param 1 name:', 'MAWindow');               row = row + 1;
            [app.Param1MinLabel,  app.Param1MinField]  = app.makeNumRow(leftGL, row, ...
                'Param 1 min:', 5, [1 500]);                row = row + 1;
            [app.Param1MaxLabel,  app.Param1MaxField]  = app.makeNumRow(leftGL, row, ...
                'Param 1 max:', 60, [2 500]);               row = row + 1;
            [app.Param2NameLabel, app.Param2NameField] = app.makeStrRow(leftGL, row, ...
                'Param 2 name (opt.):', '');                row = row + 1;
            [app.Param2MinLabel,  app.Param2MinField]  = app.makeNumRow(leftGL, row, ...
                'Param 2 min:', 10, [1 500]);               row = row + 1;
            [app.Param2MaxLabel,  app.Param2MaxField]  = app.makeNumRow(leftGL, row, ...
                'Param 2 max:', 120, [2 500]);              row = row + 1;
            [app.MaxEvalLabel,    app.MaxEvalField]    = app.makeNumRow(leftGL, row, ...
                'Max Evaluations:', 30, [5 200]);           row = row + 1;

            app.RunOptimButton = uibutton(leftGL, 'push', ...
                'Text', 'Run Optimisation (bayesopt)', ...
                'ButtonPushedFcn', @(~,~) app.onRunOptimButtonPushed([]));
            app.RunOptimButton.Layout.Row = row;
            app.RunOptimButton.Layout.Column = [1 2]; row = row + 1;

            app.BacktestStatusLabel = uilabel(leftGL, 'Text', 'Ready.', ...
                'FontColor', [0.40 0.40 0.40], 'WordWrap', 'on');
            app.BacktestStatusLabel.Layout.Row = row;
            app.BacktestStatusLabel.Layout.Column = [1 2];

            % Right: equity + drawdown uiaxes
            app.BacktestAxes = uiaxes(gl);
            app.BacktestAxes.Layout.Row    = 1;
            app.BacktestAxes.Layout.Column = 2;
            title(app.BacktestAxes,  'Equity Curve & Drawdown');
            xlabel(app.BacktestAxes, 'Date');
        end

        % ── Tab 4: Performance Dashboard ──────────────────────────────────
        function buildDashboardTab(app)
            gl = uigridlayout(app.DashboardTab, [1, 2]);
            gl.ColumnWidth   = {260, '1x'};
            gl.Padding       = [12 12 12 12];
            gl.ColumnSpacing = 12;

            % Left: metrics grid
            metricsGL = uigridlayout(gl, [7, 2]);
            metricsGL.Layout.Row    = 1;
            metricsGL.Layout.Column = 1;
            metricsGL.ColumnWidth   = {'1x', '1x'};
            metricsGL.RowHeight     = [44, repmat({42}, 1, 5), '1x'];
            metricsGL.Padding       = [0 0 0 0];
            metricsGL.RowSpacing    = 4;

            hdr = uilabel(metricsGL, 'Text', 'Performance Metrics', ...
                'FontWeight', 'bold', 'FontSize', 15, ...
                'HorizontalAlignment', 'center');
            hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];

            [app.SharpeLabel,   app.SharpeValueLabel]  = ...
                app.makeMetricRow(metricsGL, 2, 'Sharpe Ratio');
            [app.SortinoLabel,  app.SortinoValueLabel]  = ...
                app.makeMetricRow(metricsGL, 3, 'Sortino Ratio');
            [app.MaxDDLabel,    app.MaxDDValueLabel]    = ...
                app.makeMetricRow(metricsGL, 4, 'Max Drawdown');
            [app.TurnoverLabel, app.TurnoverValueLabel] = ...
                app.makeMetricRow(metricsGL, 5, 'Turnover / yr');
            [app.TotalRetLabel, app.TotalRetValueLabel] = ...
                app.makeMetricRow(metricsGL, 6, 'Total Return');

            % Right: panel that hosts the heatmap after optimisation
            app.HeatmapPanel = uipanel(gl, ...
                'Title',      'Parameter Sweep — Sharpe Ratio', ...
                'FontWeight', 'bold');
            app.HeatmapPanel.Layout.Row    = 1;
            app.HeatmapPanel.Layout.Column = 2;

            % Placeholder hint (deleted when heatmap is drawn)
            hintLbl = uilabel(app.HeatmapPanel, ...
                'Text', ['Run Bayesian Optimisation with two parameter ' ...
                         'variables to populate this heatmap.'], ...
                'FontColor', [0.50 0.50 0.50], ...
                'HorizontalAlignment', 'center', ...
                'WordWrap', 'on');
            hintLbl.Position = [20 20 560 60];

        end

    end   % end construction

    % ================================================================== %
    %  App lifecycle
    % ================================================================== %
    methods (Access = public)

        function app = MainApp()
            createComponents(app);
            registerApp(app, app.UIFigure);
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure)
        end

    end

end
