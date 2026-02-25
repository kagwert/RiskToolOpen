classdef SignalStrategyApp < matlab.apps.AppBase
    % SignalStrategyApp - Signal Strategy: Equity/Cash Allocation
    %
    % Three strategy modes:
    %   1. Composite: weighted composite signal with optimized thresholds
    %   2. Risk Budget: per-signal risk budgets with translation functions
    %   3. Decision Tree: rule-based or CART auto-optimized
    %
    % Full walk-forward backtesting, stress testing, and per-signal analysis.

    %================ UI COMPONENTS ================
    properties (Access = public)
        UIFigure              matlab.ui.Figure
        Grid                  matlab.ui.container.GridLayout
        LeftPanel             matlab.ui.container.Panel
        RightPanel            matlab.ui.container.Panel
        LeftGrid              matlab.ui.container.GridLayout

        % DATA section
        StartDateField        matlab.ui.control.EditField
        EndDateField          matlab.ui.control.EditField
        DownloadMktButton     matlab.ui.control.Button
        DownloadMacroButton   matlab.ui.control.Button

        % SIGNALS section
        ImportCSVButton       matlab.ui.control.Button
        ImportExcelButton     matlab.ui.control.Button
        ImportWSButton        matlab.ui.control.Button
        DemoSignalsButton     matlab.ui.control.Button
        ExtendedSignalsButton matlab.ui.control.Button
        AddSignalButton       matlab.ui.control.Button
        RemoveSignalButton    matlab.ui.control.Button

        % STRATEGY section
        StrategyDropDown      matlab.ui.control.DropDown

        % BACKTEST section
        RebalFreqField        matlab.ui.control.NumericEditField
        TxCostField           matlab.ui.control.NumericEditField

        % ACTIONS section
        RunBacktestButton     matlab.ui.control.Button
        OptimizeButton        matlab.ui.control.Button
        ExportButton          matlab.ui.control.Button
        SaveSessionButton     matlab.ui.control.Button
        LoadSessionButton     matlab.ui.control.Button

        % Right panel tabs
        RightGrid             matlab.ui.container.GridLayout
        TabGroup              matlab.ui.container.TabGroup

        % Signals tab
        SignalsTab             matlab.ui.container.Tab
        SignalsGrid            matlab.ui.container.GridLayout
        SignalTable            matlab.ui.control.Table
        SignalAxes             matlab.ui.control.UIAxes

        % Strategy tab
        StrategyTab            matlab.ui.container.Tab
        StrategyGrid           matlab.ui.container.GridLayout
        % Composite panel
        CompositePanel         matlab.ui.container.Panel
        CompGrid               matlab.ui.container.GridLayout
        CompWeightsTable       matlab.ui.control.Table
        CompThreshField        matlab.ui.control.NumericEditField
        CompResultsText        matlab.ui.control.TextArea
        CompStepAxes           matlab.ui.control.UIAxes
        CompPerfTable          matlab.ui.control.Table

        % Signal Config (Zone A)
        SigConfigTable         matlab.ui.control.Table
        SigConfigDetailPanel   matlab.ui.container.Panel
        SigDetailGrid          matlab.ui.container.GridLayout
        SigDetailActivation    matlab.ui.control.DropDown
        SigDetailSkipDays      matlab.ui.control.NumericEditField
        SigDetailVolFloor      matlab.ui.control.NumericEditField
        SigDetailTanhScale     matlab.ui.control.NumericEditField
        SigDetailFastSpan      matlab.ui.control.NumericEditField
        SigDetailSlowSpan      matlab.ui.control.NumericEditField
        SigDetailFastLabel     matlab.ui.control.Label
        SigDetailSlowLabel     matlab.ui.control.Label
        SigRebuildButton       matlab.ui.control.Button

        % Objective (Zone B)
        ObjDropDown            matlab.ui.control.DropDown
        ObjPenaltySlider       matlab.ui.control.Slider

        % Constraints (Zone B)
        ConstrEqMinCheck       matlab.ui.control.CheckBox
        ConstrEqMinField       matlab.ui.control.NumericEditField
        ConstrEqMaxCheck       matlab.ui.control.CheckBox
        ConstrEqMaxField       matlab.ui.control.NumericEditField
        ConstrTurnoverCheck    matlab.ui.control.CheckBox
        ConstrTurnoverField    matlab.ui.control.NumericEditField
        ConstrSigWtMinCheck    matlab.ui.control.CheckBox
        ConstrSigWtMinField    matlab.ui.control.NumericEditField
        ConstrSigWtMaxCheck    matlab.ui.control.CheckBox
        ConstrSigWtMaxField    matlab.ui.control.NumericEditField
        ConstrMaxDDCheck       matlab.ui.control.CheckBox
        ConstrMaxDDField       matlab.ui.control.NumericEditField
        ConstrPriorityDrop     matlab.ui.control.DropDown
        % Risk Budget panel
        RiskBudgetPanel        matlab.ui.container.Panel
        RBGrid                 matlab.ui.container.GridLayout
        RBTable                matlab.ui.control.Table
        RBMacroCondCheck       matlab.ui.control.CheckBox
        RBMacroVarDrop         matlab.ui.control.DropDown
        RBMacroThreshField     matlab.ui.control.NumericEditField
        RBStackedAxes          matlab.ui.control.UIAxes
        % Decision Tree panel
        DecisionTreePanel      matlab.ui.container.Panel
        DTGrid                 matlab.ui.container.GridLayout
        DTModeDropDown         matlab.ui.control.DropDown
        DTRulesTable           matlab.ui.control.Table
        DTAutoOptButton        matlab.ui.control.Button
        DTDepthField           matlab.ui.control.NumericEditField
        DTLeafField            matlab.ui.control.NumericEditField
        DTRulesText            matlab.ui.control.TextArea
        DTImportanceAxes       matlab.ui.control.UIAxes

        % Backtest tab
        BacktestTab            matlab.ui.container.Tab
        BacktestGrid           matlab.ui.container.GridLayout
        CumRetAxes             matlab.ui.control.UIAxes
        DrawdownAxes           matlab.ui.control.UIAxes
        RollSharpeAxes         matlab.ui.control.UIAxes
        EqWeightAxes           matlab.ui.control.UIAxes

        % Performance tab
        PerformanceTab         matlab.ui.container.Tab
        PerfGrid               matlab.ui.container.GridLayout
        PerfSummaryTable       matlab.ui.control.Table
        MonthlyHeatmapAxes     matlab.ui.control.UIAxes

        % Stress tab
        StressTab              matlab.ui.container.Tab
        StressGrid             matlab.ui.container.GridLayout
        StressTable            matlab.ui.control.Table

        % Individual tab
        IndividualTab          matlab.ui.container.Tab
        IndivGrid              matlab.ui.container.GridLayout
        IndivSignalDrop        matlab.ui.control.DropDown
        IndivPerfTable         matlab.ui.control.Table
        IndivCumRetAxes        matlab.ui.control.UIAxes

        StatusLabel            matlab.ui.control.Label

        % Normalization controls (Signals tab)
        NormMethodDrop         matlab.ui.control.DropDown
        NormWindowField        matlab.ui.control.NumericEditField
        NormTanhField          matlab.ui.control.NumericEditField
        ReNormalizeButton      matlab.ui.control.Button

        % Composite: new optimization controls
        CompMappingDrop        matlab.ui.control.DropDown
        CompSigmoidKField     matlab.ui.control.NumericEditField
        CompLambdaField        matlab.ui.control.NumericEditField
        CompCVFoldsField       matlab.ui.control.NumericEditField
        CompWalkFwdCheck       matlab.ui.control.CheckBox
        CompReoptFreqField     matlab.ui.control.NumericEditField
        CompSensitivityCheck   matlab.ui.control.CheckBox

        % Decision Tree: new controls
        DTRegressionCheck      matlab.ui.control.CheckBox
        DTCVFoldsField         matlab.ui.control.NumericEditField

        % Definition tab
        DefinitionTab          matlab.ui.container.Tab
        DefinitionGrid         matlab.ui.container.GridLayout
        % Composite definition panel
        DefCompPanel           matlab.ui.container.Panel
        DefCompWeightsTable    matlab.ui.control.Table
        DefCompParamsText      matlab.ui.control.TextArea
        DefCompMappingAxes     matlab.ui.control.UIAxes
        % Risk Budget definition panel
        DefRBPanel             matlab.ui.container.Panel
        DefRBTable             matlab.ui.control.Table
        DefRBParamsText        matlab.ui.control.TextArea
        DefRBAllocAxes         matlab.ui.control.UIAxes
        % Decision Tree definition panel
        DefDTPanel             matlab.ui.container.Panel
        DefDTRulesText         matlab.ui.control.TextArea
        DefDTParamsText        matlab.ui.control.TextArea
        DefDTImportanceAxes    matlab.ui.control.UIAxes
        DefDTTreeAxes          matlab.ui.control.UIAxes    % Node-link tree diagram
    end

    %================ STATE ================
    properties (Access = private)
        MktData        struct = struct()
        MacroData      table  = table()
        SignalData     double = []
        SignalNames    cell   = {}
        BacktestResult struct = struct()
        PerfResult     struct = struct()
        StressResult   table  = table()
        StrategyResult struct = struct()
        EqWts          double = []
    end

    %================ CONSTRUCTOR ================
    methods (Access = public)
        function app = SignalStrategyApp
            createComponents(app);
        end

    end

    %================ UI CREATION ================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Signal Strategy: Equity/Cash Allocation', ...
                'Position', [50 30 1600 980]);

            app.Grid = uigridlayout(app.UIFigure, [2 2]);
            app.Grid.ColumnWidth = {360, '1x'};
            app.Grid.RowHeight   = {'1x', 22};
            app.Grid.Padding = [0 0 0 0];
            app.Grid.ColumnSpacing = 2;
            app.Grid.RowSpacing = 0;

            %% Left Panel
            app.LeftPanel = uipanel(app.Grid, 'Title', 'Controls', 'FontWeight', 'bold');
            app.LeftPanel.Layout.Row = 1; app.LeftPanel.Layout.Column = 1;

            app.LeftGrid = uigridlayout(app.LeftPanel, [30 1]);
            app.LeftGrid.RowHeight = [ ...
                {'fit'} {28} {'fit'} {28} {28} ...       % 1-5:  DATA header, dates, download btns
                {4} ...                                   % 6:    spacer
                {'fit'} {28} {28} {28} {28} {28} ...     % 7-12: SIGNALS header + 5 import btns
                {28} ...                                  % 13:   Add/Remove signal row
                {4} ...                                   % 14:   spacer
                {'fit'} {'fit'} ...                       % 15-16: STRATEGY header + dropdown
                {4} ...                                   % 17:   spacer
                {'fit'} {'fit'} {'fit'} ...               % 18-20: BACKTEST header + rebal + txcost
                {4} ...                                   % 21:   spacer
                {'fit'} {34} {34} {28} ...                % 22-25: ACTIONS header + buttons
                {'fit'} ...                               % 26: save/load row
                repmat({'fit'}, 1, 4) ...                 % 27-30: reserve
            ];
            app.LeftGrid.Padding = [10 10 10 10];
            app.LeftGrid.RowSpacing = 3;

            createLeftPanelControls(app);

            %% Right Panel
            app.RightPanel = uipanel(app.Grid, 'Title', 'Analysis', 'FontWeight', 'bold');
            app.RightPanel.Layout.Row = 1; app.RightPanel.Layout.Column = 2;

            app.RightGrid = uigridlayout(app.RightPanel, [1 1]);
            app.RightGrid.Padding = [4 4 4 4];

            app.TabGroup = uitabgroup(app.RightGrid);
            createTabs(app);

            %% Status bar
            app.StatusLabel = uilabel(app.Grid, 'Text', 'Ready.', 'FontColor', [0.3 0.3 0.3]);
            app.StatusLabel.Layout.Row = 2;
            app.StatusLabel.Layout.Column = [1 2];
        end

        %% ---- Left Panel Controls ----
        function createLeftPanelControls(app)
            row = 0;

            % DATA section
            row = row + 1;
            uilabel(app.LeftGrid, 'Text', 'DATA', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.15 0.25 0.55]);

            row = row + 1;
            dateRow = uigridlayout(app.LeftGrid, [1 4]);
            dateRow.ColumnWidth = {'fit','1x','fit','1x'}; dateRow.Padding = [0 0 0 0]; dateRow.ColumnSpacing = 4;
            uilabel(dateRow, 'Text', 'Start:');
            app.StartDateField = uieditfield(dateRow, 'text', 'Value', '19900101');
            uilabel(dateRow, 'Text', 'End:');
            app.EndDateField = uieditfield(dateRow, 'text', 'Value', datestr(datetime('today'), 'yyyymmdd'));

            row = row + 1;
            app.DownloadMktButton = uibutton(app.LeftGrid, 'Text', 'Download Market Data (SPX + Cash)', ...
                'ButtonPushedFcn', @(~,~) onDownloadData(app));

            row = row + 1;
            app.DownloadMacroButton = uibutton(app.LeftGrid, 'Text', 'Download FRED Macro Data', ...
                'ButtonPushedFcn', @(~,~) onDownloadMacro(app));
            app.DownloadMacroButton.Enable = 'off';

            row = row + 1; %#ok<NASGU>
            % spacer (empty)
            uilabel(app.LeftGrid, 'Text', '');

            % SIGNALS section
            uilabel(app.LeftGrid, 'Text', 'SIGNALS', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.15 0.25 0.55]);

            app.ImportCSVButton = uibutton(app.LeftGrid, 'Text', 'Import Signals CSV', ...
                'ButtonPushedFcn', @(~,~) onImportCSV(app));
            app.ImportExcelButton = uibutton(app.LeftGrid, 'Text', 'Import Signals Excel', ...
                'ButtonPushedFcn', @(~,~) onImportExcel(app));
            app.ImportWSButton = uibutton(app.LeftGrid, 'Text', 'Import from Workspace', ...
                'ButtonPushedFcn', @(~,~) onImportWorkspace(app));
            app.DemoSignalsButton = uibutton(app.LeftGrid, 'Text', 'Generate Demo Signals (5)', ...
                'ButtonPushedFcn', @(~,~) onDemoSignals(app));
            app.DemoSignalsButton.Enable = 'off';

            app.ExtendedSignalsButton = uibutton(app.LeftGrid, 'Text', 'Generate Extended Signals (12)', ...
                'ButtonPushedFcn', @(~,~) onExtendedSignals(app));
            app.ExtendedSignalsButton.Enable = 'off';

            addRemRow = uigridlayout(app.LeftGrid, [1 2]);
            addRemRow.ColumnWidth = {'1x','1x'}; addRemRow.Padding = [0 0 0 0]; addRemRow.ColumnSpacing = 4;
            app.AddSignalButton = uibutton(addRemRow, 'Text', 'Add Signal', ...
                'ButtonPushedFcn', @(~,~) onAddSignal(app));
            app.AddSignalButton.Enable = 'off';
            app.RemoveSignalButton = uibutton(addRemRow, 'Text', 'Remove Signal', ...
                'ButtonPushedFcn', @(~,~) onRemoveSignal(app));
            app.RemoveSignalButton.Enable = 'off';

            % spacer
            uilabel(app.LeftGrid, 'Text', '');

            % STRATEGY section
            uilabel(app.LeftGrid, 'Text', 'STRATEGY MODE', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.15 0.25 0.55]);

            app.StrategyDropDown = uidropdown(app.LeftGrid, ...
                'Items', {'Composite', 'Risk Budget', 'Decision Tree'}, ...
                'Value', 'Composite', ...
                'ValueChangedFcn', @(~,~) onStrategyModeChanged(app));

            % spacer
            uilabel(app.LeftGrid, 'Text', '');

            % BACKTEST section
            uilabel(app.LeftGrid, 'Text', 'BACKTEST PARAMS', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.15 0.25 0.55]);

            rebalRow = uigridlayout(app.LeftGrid, [1 4]);
            rebalRow.ColumnWidth = {'fit','1x','fit','1x'}; rebalRow.Padding = [0 0 0 0]; rebalRow.ColumnSpacing = 4;
            uilabel(rebalRow, 'Text', 'Rebal Freq:');
            app.RebalFreqField = uieditfield(rebalRow, 'numeric', 'Value', 21, 'Limits', [1 252]);
            uilabel(rebalRow, 'Text', 'Tx bps:');
            app.TxCostField = uieditfield(rebalRow, 'numeric', 'Value', 10, 'Limits', [0 100]);

            % Placeholder for additional backtest settings
            uilabel(app.LeftGrid, 'Text', '');

            % spacer
            uilabel(app.LeftGrid, 'Text', '');

            % ACTIONS section
            uilabel(app.LeftGrid, 'Text', 'ACTIONS', 'FontWeight', 'bold', ...
                'FontSize', 12, 'FontColor', [0.15 0.25 0.55]);

            app.RunBacktestButton = uibutton(app.LeftGrid, 'Text', 'Run Backtest', ...
                'BackgroundColor', [0.3 0.75 0.4], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~,~) onRunBacktest(app));
            app.RunBacktestButton.Enable = 'off';

            app.OptimizeButton = uibutton(app.LeftGrid, 'Text', 'Optimize Strategy', ...
                'BackgroundColor', [0.3 0.5 0.85], 'FontWeight', 'bold', 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) onOptimize(app));
            app.OptimizeButton.Enable = 'off';

            app.ExportButton = uibutton(app.LeftGrid, 'Text', 'Export Results', ...
                'ButtonPushedFcn', @(~,~) onExportResults(app));

            savLoadRow = uigridlayout(app.LeftGrid, [1 2]);
            savLoadRow.ColumnWidth = {'1x','1x'}; savLoadRow.Padding = [0 0 0 0]; savLoadRow.ColumnSpacing = 4;
            app.SaveSessionButton = uibutton(savLoadRow, 'Text', 'Save Session', ...
                'ButtonPushedFcn', @(~,~) onSaveSession(app));
            app.LoadSessionButton = uibutton(savLoadRow, 'Text', 'Load Session', ...
                'ButtonPushedFcn', @(~,~) onLoadSession(app));
        end

        %% ---- Create Tabs ----
        function createTabs(app)
            createSignalsTab(app);
            createStrategyTab(app);
            createDefinitionTab(app);
            createBacktestTab(app);
            createPerformanceTab(app);
            createStressTab(app);
            createIndividualTab(app);
        end

        %% ---- Signals Tab ----
        function createSignalsTab(app)
            app.SignalsTab = uitab(app.TabGroup, 'Title', 'Signals');
            app.SignalsGrid = uigridlayout(app.SignalsTab, [3 1]);
            app.SignalsGrid.RowHeight = {'fit', '0.35x', '0.6x'};

            % Normalization controls row
            normRow = uigridlayout(app.SignalsGrid, [1 9]);
            normRow.ColumnWidth = {'fit','fit','fit','fit','fit','fit','fit','fit','fit'};
            normRow.Padding = [4 4 4 4]; normRow.ColumnSpacing = 6;
            uilabel(normRow, 'Text', 'Normalization:', 'FontWeight', 'bold');
            app.NormMethodDrop = uidropdown(normRow, ...
                'Items', {'RobustZ','StandardZ','RollingZ','Percentile','MinMax'}, ...
                'Value', 'RobustZ');
            uilabel(normRow, 'Text', 'Window:');
            app.NormWindowField = uieditfield(normRow, 'numeric', 'Value', 252, 'Limits', [20 1000]);
            uilabel(normRow, 'Text', 'Tanh Scale:');
            app.NormTanhField = uieditfield(normRow, 'numeric', 'Value', 2, 'Limits', [0.1 10]);
            app.ReNormalizeButton = uibutton(normRow, 'Text', 'Re-normalize', ...
                'ButtonPushedFcn', @(~,~) onReNormalize(app));
            uilabel(normRow, 'Text', '');
            uilabel(normRow, 'Text', '');

            app.SignalTable = uitable(app.SignalsGrid, 'ColumnName', {'Signal','Mean','Std','Min','Max','NaN%'});

            app.SignalAxes = uiaxes(app.SignalsGrid);
            title(app.SignalAxes, 'Signal Time Series');
            xlabel(app.SignalAxes, 'Date'); ylabel(app.SignalAxes, 'Signal Value');
        end

        %% ---- Strategy Tab ----
        function createStrategyTab(app)
            app.StrategyTab = uitab(app.TabGroup, 'Title', 'Strategy');
            app.StrategyGrid = uigridlayout(app.StrategyTab, [1 1]);
            app.StrategyGrid.Padding = [0 0 0 0];

            % ===== Composite Panel =====
            app.CompositePanel = uipanel(app.StrategyGrid, 'Title', 'Composite Signal Strategy');
            app.CompositePanel.Layout.Row = 1; app.CompositePanel.Layout.Column = 1;
            app.CompGrid = uigridlayout(app.CompositePanel, [3 2]);
            app.CompGrid.RowHeight = {'0.45x', 'fit', '0.55x'};
            app.CompGrid.ColumnWidth = {'1x', '1x'};
            app.CompGrid.Padding = [6 6 6 6];
            app.CompGrid.RowSpacing = 6;
            app.CompGrid.ColumnSpacing = 6;

            % ---- Zone A: Signal Config (Row 1, spans both columns) ----
            zoneAGrid = uigridlayout(app.CompGrid, [1 2]);
            zoneAGrid.Layout.Row = 1; zoneAGrid.Layout.Column = [1 2];
            zoneAGrid.ColumnWidth = {'0.6x', '0.4x'};
            zoneAGrid.Padding = [0 0 0 0]; zoneAGrid.ColumnSpacing = 6;

            app.SigConfigTable = uitable(zoneAGrid, ...
                'ColumnName', {'Include','Signal','Weight','Type'}, ...
                'ColumnEditable', [true false true false], ...
                'ColumnFormat', {'logical','char','numeric','char'}, ...
                'CellSelectionCallback', @(src,evt) onSignalConfigSelect(app, evt));

            app.SigConfigDetailPanel = uipanel(zoneAGrid, 'Title', 'Signal Parameters', 'BorderType', 'line');
            app.SigDetailGrid = uigridlayout(app.SigConfigDetailPanel, [8 2]);
            app.SigDetailGrid.ColumnWidth = {'fit', '1x'};
            app.SigDetailGrid.RowHeight = repmat({22}, 1, 8);
            app.SigDetailGrid.Padding = [4 4 4 4];
            app.SigDetailGrid.RowSpacing = 3;

            uilabel(app.SigDetailGrid, 'Text', 'Activation:');
            app.SigDetailActivation = uidropdown(app.SigDetailGrid, ...
                'Items', {'tanh','sigmoid','revertSigmoid'}, 'Value', 'tanh');
            uilabel(app.SigDetailGrid, 'Text', 'Skip Days:');
            app.SigDetailSkipDays = uieditfield(app.SigDetailGrid, 'numeric', 'Value', 0, 'Limits', [0 21]);
            uilabel(app.SigDetailGrid, 'Text', 'Vol Floor:');
            app.SigDetailVolFloor = uieditfield(app.SigDetailGrid, 'numeric', 'Value', 0, 'Limits', [0 1]);
            uilabel(app.SigDetailGrid, 'Text', 'Tanh Scale:');
            app.SigDetailTanhScale = uieditfield(app.SigDetailGrid, 'numeric', 'Value', 2, 'Limits', [0.1 10]);
            app.SigDetailFastLabel = uilabel(app.SigDetailGrid, 'Text', 'Fast Span:');
            app.SigDetailFastSpan = uieditfield(app.SigDetailGrid, 'numeric', 'Value', 16, 'Limits', [2 200]);
            app.SigDetailSlowLabel = uilabel(app.SigDetailGrid, 'Text', 'Slow Span:');
            app.SigDetailSlowSpan = uieditfield(app.SigDetailGrid, 'numeric', 'Value', 64, 'Limits', [2 500]);
            uilabel(app.SigDetailGrid, 'Text', '');
            app.SigRebuildButton = uibutton(app.SigDetailGrid, 'Text', 'Rebuild Signal', ...
                'BackgroundColor', [0.3 0.6 0.85], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) onRebuildSignal(app));
            % Hide EWMAC-specific fields by default
            app.SigDetailFastLabel.Visible = 'off';
            app.SigDetailFastSpan.Visible = 'off';
            app.SigDetailSlowLabel.Visible = 'off';
            app.SigDetailSlowSpan.Visible = 'off';

            % ---- Zone B: Objective & Constraints (Row 2, spans both columns) ----
            zoneBGrid = uigridlayout(app.CompGrid, [1 2]);
            zoneBGrid.Layout.Row = 2; zoneBGrid.Layout.Column = [1 2];
            zoneBGrid.ColumnWidth = {'0.4x', '0.6x'};
            zoneBGrid.Padding = [0 0 0 0]; zoneBGrid.ColumnSpacing = 6;

            % Objective panel (left)
            objPanel = uipanel(zoneBGrid, 'Title', 'Objective', 'BorderType', 'line');
            objInner = uigridlayout(objPanel, [5 2]);
            objInner.ColumnWidth = {'fit', '1x'};
            objInner.RowHeight = {22, 22, 22, 22, 22};
            objInner.Padding = [4 4 4 4]; objInner.RowSpacing = 3;

            uilabel(objInner, 'Text', 'Preset:');
            app.ObjDropDown = uidropdown(objInner, ...
                'Items', {'Max Sharpe','Max Sortino','Max Calmar','Max Return', ...
                          'Min Volatility','Min Max Drawdown','Risk Parity'}, ...
                'Value', 'Max Sharpe');
            uilabel(objInner, 'Text', 'Risk Aversion:');
            app.ObjPenaltySlider = uislider(objInner, 'Limits', [0 2], 'Value', 0.5);
            uilabel(objInner, 'Text', '# Thresholds:');
            app.CompThreshField = uieditfield(objInner, 'numeric', 'Value', 3, 'Limits', [1 10]);
            uilabel(objInner, 'Text', 'Mapping:');
            app.CompMappingDrop = uidropdown(objInner, ...
                'Items', {'Step','Sigmoid','PiecewiseLinear','Spline','Power'}, ...
                'Value', 'Sigmoid');
            uilabel(objInner, 'Text', 'Sigmoid K:');
            app.CompSigmoidKField = uieditfield(objInner, 'numeric', 'Value', 5, 'Limits', [0.1 50]);

            % Constraints panel (right)
            constrPanel = uipanel(zoneBGrid, 'Title', 'Constraints', 'BorderType', 'line');
            constrGrid = uigridlayout(constrPanel, [4 4]);
            constrGrid.ColumnWidth = {'fit', 60, 'fit', 60};
            constrGrid.RowHeight = {22, 22, 22, 22};
            constrGrid.Padding = [4 4 4 4]; constrGrid.RowSpacing = 3; constrGrid.ColumnSpacing = 4;

            app.ConstrEqMinCheck = uicheckbox(constrGrid, 'Text', 'Eq Min Wt');
            app.ConstrEqMinField = uieditfield(constrGrid, 'numeric', 'Value', 0.0, 'Limits', [0 1]);
            app.ConstrEqMaxCheck = uicheckbox(constrGrid, 'Text', 'Eq Max Wt');
            app.ConstrEqMaxField = uieditfield(constrGrid, 'numeric', 'Value', 1.0, 'Limits', [0 1]);
            app.ConstrTurnoverCheck = uicheckbox(constrGrid, 'Text', 'Max Turn/Yr');
            app.ConstrTurnoverField = uieditfield(constrGrid, 'numeric', 'Value', 12.0, 'Limits', [0 100]);
            app.ConstrSigWtMinCheck = uicheckbox(constrGrid, 'Text', 'Sig Wt Min');
            app.ConstrSigWtMinField = uieditfield(constrGrid, 'numeric', 'Value', 0.0, 'Limits', [0 1]);
            app.ConstrSigWtMaxCheck = uicheckbox(constrGrid, 'Text', 'Sig Wt Max');
            app.ConstrSigWtMaxField = uieditfield(constrGrid, 'numeric', 'Value', 0.5, 'Limits', [0 1]);
            app.ConstrMaxDDCheck = uicheckbox(constrGrid, 'Text', 'Max DD Stop');
            app.ConstrMaxDDField = uieditfield(constrGrid, 'numeric', 'Value', 0.20, 'Limits', [0.01 1]);
            uilabel(constrGrid, 'Text', 'Priority:');
            app.ConstrPriorityDrop = uidropdown(constrGrid, ...
                'Items', {'None','Equity Bounds','Turnover','Drawdown'}, 'Value', 'None');

            % Advanced settings (collapsible row in Zone B)
            advPanel = uipanel(constrGrid, 'Title', '', 'BorderType', 'none');
            advPanel.Layout.Row = 4; advPanel.Layout.Column = [3 4];
            advGrid = uigridlayout(advPanel, [1 6]);
            advGrid.ColumnWidth = {'fit','fit','fit','fit','fit','fit'};
            advGrid.RowHeight = {22}; advGrid.Padding = [0 0 0 0]; advGrid.ColumnSpacing = 3;
            uilabel(advGrid, 'Text', 'Reg:');
            app.CompLambdaField = uieditfield(advGrid, 'numeric', 'Value', 0.1, 'Limits', [0 10]);
            uilabel(advGrid, 'Text', 'CV:');
            app.CompCVFoldsField = uieditfield(advGrid, 'numeric', 'Value', 5, 'Limits', [2 20]);
            app.CompWalkFwdCheck = uicheckbox(advGrid, 'Text', 'WF');
            app.CompReoptFreqField = uieditfield(advGrid, 'numeric', 'Value', 252, 'Limits', [21 1000]);

            % Sensitivity check (in objective panel, reusing available space)
            app.CompSensitivityCheck = uicheckbox(advPanel, 'Text', 'Sensitivity', 'Visible', 'off');

            % ---- Zone C: Results (Row 3) ----
            % Left column: Performance stats table
            app.CompPerfTable = uitable(app.CompGrid, ...
                'ColumnName', {'Metric','Strategy','60/40','100% Equity'}, ...
                'ColumnEditable', false(1,4), ...
                'RowName', {}, ...
                'Data', cell(9, 4));
            app.CompPerfTable.Layout.Row = 3; app.CompPerfTable.Layout.Column = 1;

            % Right column: Step axes on top, results text below
            zoneCRight = uigridlayout(app.CompGrid, [2 1]);
            zoneCRight.Layout.Row = 3; zoneCRight.Layout.Column = 2;
            zoneCRight.RowHeight = {'0.6x', '0.4x'};
            zoneCRight.Padding = [0 0 0 0]; zoneCRight.RowSpacing = 4;

            app.CompStepAxes = uiaxes(zoneCRight);
            title(app.CompStepAxes, 'Composite Signal to Equity Weight');

            app.CompResultsText = uitextarea(zoneCRight, 'Value', {'Optimize to see results.'}, 'Editable', 'off');

            % Hidden legacy table for internal weight storage
            app.CompWeightsTable = uitable(app.CompositePanel, 'Visible', 'off');

            % ===== Risk Budget Panel =====
            app.RiskBudgetPanel = uipanel(app.StrategyGrid, 'Title', 'Risk Budget Strategy', 'Visible', 'off');
            app.RiskBudgetPanel.Layout.Row = 1; app.RiskBudgetPanel.Layout.Column = 1;
            app.RBGrid = uigridlayout(app.RiskBudgetPanel, [3 1]);
            app.RBGrid.RowHeight = {'0.4x', 'fit', '0.55x'};
            app.RBGrid.Padding = [6 6 6 6];
            app.RBGrid.RowSpacing = 6;

            app.RBTable = uitable(app.RBGrid, ...
                'ColumnName', {'Signal','Budget','Translation'}, ...
                'ColumnEditable', [false true true], ...
                'ColumnFormat', {'char', 'numeric', {'Linear','Threshold','Sigmoid','Quantile','PiecewiseLinear','Spline','Power'}});

            macroRow = uigridlayout(app.RBGrid, [1 6]);
            macroRow.ColumnWidth = {'fit','fit','fit','fit','fit','1x'};
            macroRow.Padding = [0 0 0 0]; macroRow.ColumnSpacing = 6;
            app.RBMacroCondCheck = uicheckbox(macroRow, 'Text', 'Macro Cond.');
            uilabel(macroRow, 'Text', 'Variable:');
            app.RBMacroVarDrop = uidropdown(macroRow, 'Items', {'YieldSlope','VIX','HY_Spread','GDP_YoY'});
            uilabel(macroRow, 'Text', 'Thresh:');
            app.RBMacroThreshField = uieditfield(macroRow, 'numeric', 'Value', 0);
            uilabel(macroRow, 'Text', '');

            app.RBStackedAxes = uiaxes(app.RBGrid);
            title(app.RBStackedAxes, 'Per-Signal Allocation (Stacked)');

            % ===== Decision Tree Panel =====
            app.DecisionTreePanel = uipanel(app.StrategyGrid, 'Title', 'Decision Tree Strategy', 'Visible', 'off');
            app.DecisionTreePanel.Layout.Row = 1; app.DecisionTreePanel.Layout.Column = 1;
            app.DTGrid = uigridlayout(app.DecisionTreePanel, [4 2]);
            app.DTGrid.RowHeight = {'fit', '0.4x', '0.4x', 'fit'};
            app.DTGrid.ColumnWidth = {'1x', '1x'};
            app.DTGrid.Padding = [6 6 6 6];
            app.DTGrid.RowSpacing = 6;

            % Row 1: Control bar (two rows of controls to avoid horizontal overflow)
            dtCtrlGrid = uigridlayout(app.DTGrid, [2 6]);
            dtCtrlGrid.Layout.Row = 1; dtCtrlGrid.Layout.Column = [1 2];
            dtCtrlGrid.ColumnWidth = {'fit','fit','fit','fit','fit','1x'};
            dtCtrlGrid.RowHeight = {26, 26};
            dtCtrlGrid.Padding = [0 0 0 0]; dtCtrlGrid.ColumnSpacing = 8;
            dtCtrlGrid.RowSpacing = 4;
            % Row 1
            uilabel(dtCtrlGrid, 'Text', 'Mode:');
            app.DTModeDropDown = uidropdown(dtCtrlGrid, 'Items', {'AutoOptimize','RuleBased'});
            uilabel(dtCtrlGrid, 'Text', 'Depth:');
            app.DTDepthField = uieditfield(dtCtrlGrid, 'numeric', 'Value', 3, 'Limits', [1 8]);
            uilabel(dtCtrlGrid, 'Text', 'Min Leaf:');
            app.DTLeafField = uieditfield(dtCtrlGrid, 'numeric', 'Value', 50, 'Limits', [10 500]);
            % Row 2
            app.DTRegressionCheck = uicheckbox(dtCtrlGrid, 'Text', 'Regression', 'Value', true);
            uilabel(dtCtrlGrid, 'Text', 'CV Folds:');
            app.DTCVFoldsField = uieditfield(dtCtrlGrid, 'numeric', 'Value', 3, 'Limits', [2 10]);
            uilabel(dtCtrlGrid, 'Text', '');
            uilabel(dtCtrlGrid, 'Text', '');
            uilabel(dtCtrlGrid, 'Text', '');
            uilabel(dtCtrlGrid, 'Text', '');

            % Row 2: Rules table (left) and rules text (right)
            app.DTRulesTable = uitable(app.DTGrid, ...
                'ColumnName', {'Variable','Operator','Threshold','EqWeight'}, ...
                'ColumnEditable', [true true true true], ...
                'ColumnFormat', {'char', {'>', '>=', '<', '<=', '=='}, 'numeric', 'numeric'});
            app.DTRulesTable.Layout.Row = 2; app.DTRulesTable.Layout.Column = 1;

            app.DTRulesText = uitextarea(app.DTGrid, 'Value', {'Tree rules will appear here.'}, 'Editable', 'off');
            app.DTRulesText.Layout.Row = 2; app.DTRulesText.Layout.Column = 2;

            % Row 3: Variable importance plot
            app.DTImportanceAxes = uiaxes(app.DTGrid);
            app.DTImportanceAxes.Layout.Row = 3; app.DTImportanceAxes.Layout.Column = [1 2];
            title(app.DTImportanceAxes, 'Variable Importance');

            % Row 4: Button
            app.DTAutoOptButton = uibutton(app.DTGrid, 'Text', 'Auto-Optimize Tree', ...
                'BackgroundColor', [0.3 0.5 0.85], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) onOptimize(app));
            app.DTAutoOptButton.Layout.Row = 4; app.DTAutoOptButton.Layout.Column = [1 2];
        end

        %% ---- Definition Tab ----
        function createDefinitionTab(app)
            app.DefinitionTab = uitab(app.TabGroup, 'Title', 'Definition');
            app.DefinitionGrid = uigridlayout(app.DefinitionTab, [1 1]);
            app.DefinitionGrid.Padding = [0 0 0 0];

            % ===== Composite Definition Panel =====
            app.DefCompPanel = uipanel(app.DefinitionGrid, 'Title', 'Composite Strategy Definition');
            app.DefCompPanel.Layout.Row = 1; app.DefCompPanel.Layout.Column = 1;
            defCompGrid = uigridlayout(app.DefCompPanel, [2 2]);
            defCompGrid.RowHeight = {'0.4x', '0.6x'};
            defCompGrid.ColumnWidth = {'1x', '1x'};
            defCompGrid.Padding = [6 6 6 6];
            defCompGrid.RowSpacing = 6; defCompGrid.ColumnSpacing = 6;

            app.DefCompWeightsTable = uitable(defCompGrid, ...
                'ColumnName', {'Signal', 'Weight', 'Type'}, ...
                'ColumnEditable', false(1,3), 'RowName', {});
            app.DefCompWeightsTable.Layout.Row = 1; app.DefCompWeightsTable.Layout.Column = 1;

            app.DefCompParamsText = uitextarea(defCompGrid, ...
                'Value', {'Optimize to see definition.'}, 'Editable', 'off');
            app.DefCompParamsText.Layout.Row = 1; app.DefCompParamsText.Layout.Column = 2;

            app.DefCompMappingAxes = uiaxes(defCompGrid);
            app.DefCompMappingAxes.Layout.Row = 2; app.DefCompMappingAxes.Layout.Column = [1 2];
            title(app.DefCompMappingAxes, 'Composite Signal → Equity Weight (%)');

            % ===== Risk Budget Definition Panel =====
            app.DefRBPanel = uipanel(app.DefinitionGrid, 'Title', 'Risk Budget Strategy Definition', 'Visible', 'off');
            app.DefRBPanel.Layout.Row = 1; app.DefRBPanel.Layout.Column = 1;
            defRBGrid = uigridlayout(app.DefRBPanel, [2 2]);
            defRBGrid.RowHeight = {'0.4x', '0.6x'};
            defRBGrid.ColumnWidth = {'1x', '1x'};
            defRBGrid.Padding = [6 6 6 6];
            defRBGrid.RowSpacing = 6; defRBGrid.ColumnSpacing = 6;

            app.DefRBTable = uitable(defRBGrid, ...
                'ColumnName', {'Signal', 'Budget (%)', 'Translation'}, ...
                'ColumnEditable', false(1,3), 'RowName', {});
            app.DefRBTable.Layout.Row = 1; app.DefRBTable.Layout.Column = 1;

            app.DefRBParamsText = uitextarea(defRBGrid, ...
                'Value', {'Optimize to see definition.'}, 'Editable', 'off');
            app.DefRBParamsText.Layout.Row = 1; app.DefRBParamsText.Layout.Column = 2;

            app.DefRBAllocAxes = uiaxes(defRBGrid);
            app.DefRBAllocAxes.Layout.Row = 2; app.DefRBAllocAxes.Layout.Column = [1 2];
            title(app.DefRBAllocAxes, 'Per-Signal Allocation (Stacked)');

            % ===== Decision Tree Definition Panel =====
            app.DefDTPanel = uipanel(app.DefinitionGrid, 'Title', 'Decision Tree Strategy Definition', 'Visible', 'off');
            app.DefDTPanel.Layout.Row = 1; app.DefDTPanel.Layout.Column = 1;
            defDTGrid = uigridlayout(app.DefDTPanel, [3 2]);
            defDTGrid.RowHeight = {'0.45x', '0.25x', '0.3x'};
            defDTGrid.ColumnWidth = {'1x', '1x'};
            defDTGrid.Padding = [6 6 6 6];
            defDTGrid.RowSpacing = 6; defDTGrid.ColumnSpacing = 6;

            app.DefDTTreeAxes = uiaxes(defDTGrid);
            app.DefDTTreeAxes.Layout.Row = 1; app.DefDTTreeAxes.Layout.Column = [1 2];
            title(app.DefDTTreeAxes, 'Decision Tree Structure');

            app.DefDTRulesText = uitextarea(defDTGrid, ...
                'Value', {'Optimize to see tree rules.'}, 'Editable', 'off');
            app.DefDTRulesText.Layout.Row = 2; app.DefDTRulesText.Layout.Column = 1;

            app.DefDTParamsText = uitextarea(defDTGrid, ...
                'Value', {'Optimize to see parameters.'}, 'Editable', 'off');
            app.DefDTParamsText.Layout.Row = 2; app.DefDTParamsText.Layout.Column = 2;

            app.DefDTImportanceAxes = uiaxes(defDTGrid);
            app.DefDTImportanceAxes.Layout.Row = 3; app.DefDTImportanceAxes.Layout.Column = [1 2];
            title(app.DefDTImportanceAxes, 'Variable Importance');
        end

        %% ---- Backtest Tab ----
        function createBacktestTab(app)
            app.BacktestTab = uitab(app.TabGroup, 'Title', 'Backtest');
            app.BacktestGrid = uigridlayout(app.BacktestTab, [2 2]);

            app.CumRetAxes = uiaxes(app.BacktestGrid);
            app.CumRetAxes.Layout.Row = 1; app.CumRetAxes.Layout.Column = 1;
            title(app.CumRetAxes, 'Cumulative Return');

            app.DrawdownAxes = uiaxes(app.BacktestGrid);
            app.DrawdownAxes.Layout.Row = 1; app.DrawdownAxes.Layout.Column = 2;
            title(app.DrawdownAxes, 'Drawdown');

            app.RollSharpeAxes = uiaxes(app.BacktestGrid);
            app.RollSharpeAxes.Layout.Row = 2; app.RollSharpeAxes.Layout.Column = 1;
            title(app.RollSharpeAxes, 'Rolling 252d Sharpe');

            app.EqWeightAxes = uiaxes(app.BacktestGrid);
            app.EqWeightAxes.Layout.Row = 2; app.EqWeightAxes.Layout.Column = 2;
            title(app.EqWeightAxes, 'Equity Weight');
        end

        %% ---- Performance Tab ----
        function createPerformanceTab(app)
            app.PerformanceTab = uitab(app.TabGroup, 'Title', 'Performance');
            app.PerfGrid = uigridlayout(app.PerformanceTab, [2 1]);
            app.PerfGrid.RowHeight = {'0.4x', '0.6x'};

            app.PerfSummaryTable = uitable(app.PerfGrid, ...
                'ColumnName', {'Metric', 'Strategy', '60/40', '100% Equity'});

            app.MonthlyHeatmapAxes = uiaxes(app.PerfGrid);
            title(app.MonthlyHeatmapAxes, 'Monthly Returns Heatmap');
        end

        %% ---- Stress Tab ----
        function createStressTab(app)
            app.StressTab = uitab(app.TabGroup, 'Title', 'Stress');
            app.StressGrid = uigridlayout(app.StressTab, [1 1]);

            app.StressTable = uitable(app.StressGrid, ...
                'ColumnName', {'Episode','Start','End','Strategy %','60/40 %','Equity %','Avg EqWt %','Strat MaxDD %'});
        end

        %% ---- Individual Tab ----
        function createIndividualTab(app)
            app.IndividualTab = uitab(app.TabGroup, 'Title', 'Individual');
            app.IndivGrid = uigridlayout(app.IndividualTab, [3 1]);
            app.IndivGrid.RowHeight = {'fit', '0.3x', '0.6x'};

            app.IndivSignalDrop = uidropdown(app.IndivGrid, 'Items', {'(none)'}, ...
                'ValueChangedFcn', @(~,~) onIndivSignalChanged(app));

            app.IndivPerfTable = uitable(app.IndivGrid, ...
                'ColumnName', {'Metric', 'Value'});

            app.IndivCumRetAxes = uiaxes(app.IndivGrid);
            title(app.IndivCumRetAxes, 'Per-Signal Cumulative Return');
        end
    end

    %================ CALLBACKS ================
    methods (Access = private)

        %% ---- Download Market Data ----
        function onDownloadData(app)
            setStatus(app, 'Downloading market data...');
            drawnow;
            try
                app.MktData = sigstrat.downloadMarketData(app.StartDateField.Value, app.EndDateField.Value);
                app.DownloadMacroButton.Enable = 'on';
                setStatus(app, sprintf('Market data loaded: %d days.', numel(app.MktData.retDates)));
                checkEnableButtons(app);
            catch ME
                setStatus(app, ['Market data error: ' ME.message]);
            end
        end

        %% ---- Download Macro Data ----
        function onDownloadMacro(app)
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end
            setStatus(app, 'Downloading FRED macro data...');
            drawnow;
            try
                app.MacroData = sigstrat.downloadMacroData(app.MktData.retDates);
                app.DemoSignalsButton.Enable = 'on';
                setStatus(app, sprintf('Macro data loaded: %d rows, %d columns.', height(app.MacroData), width(app.MacroData)-1));
            catch ME
                setStatus(app, ['Macro data error: ' ME.message]);
            end
        end

        %% ---- Import Signals CSV ----
        function onImportCSV(app)
            [file, path] = uigetfile({'*.csv','CSV Files'}, 'Select Signal CSV');
            if isequal(file, 0), return; end
            setStatus(app, 'Importing CSV...');
            drawnow;
            try
                T = readtable(fullfile(path, file));
                parseSignalTable(app, T);
                setStatus(app, sprintf('Imported %d signals from CSV.', numel(app.SignalNames)));
            catch ME
                setStatus(app, ['CSV import error: ' ME.message]);
            end
        end

        %% ---- Import Signals Excel ----
        function onImportExcel(app)
            [file, path] = uigetfile({'*.xlsx;*.xls','Excel Files'}, 'Select Signal Excel');
            if isequal(file, 0), return; end
            setStatus(app, 'Importing Excel...');
            drawnow;
            try
                T = readtable(fullfile(path, file));
                parseSignalTable(app, T);
                setStatus(app, sprintf('Imported %d signals from Excel.', numel(app.SignalNames)));
            catch ME
                setStatus(app, ['Excel import error: ' ME.message]);
            end
        end

        %% ---- Import from Workspace ----
        function onImportWorkspace(app)
            try
                vars = evalin('base', 'whos');
                varNames = {vars.name};
                if isempty(varNames)
                    setStatus(app, 'No variables in workspace.');
                    return;
                end
                [sel, ok] = listdlg('ListString', varNames, 'SelectionMode', 'single', ...
                    'PromptString', 'Select signal matrix (TxN double):');
                if ~ok, return; end
                sigData = evalin('base', varNames{sel});
                if ~isnumeric(sigData)
                    setStatus(app, 'Selected variable must be numeric.');
                    return;
                end

                % Ask for signal names
                [T2, N2] = size(sigData);
                names = cell(1, N2);
                for j = 1:N2
                    names{j} = sprintf('Signal_%d', j);
                end

                % Try to find a matching names variable
                [sel2, ok2] = listdlg('ListString', varNames, 'SelectionMode', 'single', ...
                    'PromptString', 'Select signal names (1xN cell) or Cancel for default:');
                if ok2
                    nameVar = evalin('base', varNames{sel2});
                    if iscell(nameVar) && numel(nameVar) == N2
                        names = nameVar(:)';
                    end
                end

                alignAndStoreSignals(app, sigData, names);
                setStatus(app, sprintf('Imported %d signals (%d days) from workspace.', N2, T2));
            catch ME
                setStatus(app, ['Workspace import error: ' ME.message]);
            end
        end

        %% ---- Generate Demo Signals ----
        function onDemoSignals(app)
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end
            setStatus(app, 'Generating demo signals...');
            drawnow;
            try
                [app.SignalData, app.SignalNames] = sigstrat.generateDemoSignals(app.MacroData, app.MktData);
                updateSignalsTab(app);
                updateStrategyTabData(app);
                checkEnableButtons(app);
                setStatus(app, sprintf('Generated %d demo signals.', numel(app.SignalNames)));
            catch ME
                setStatus(app, ['Demo signal error: ' ME.message]);
            end
        end

        %% ---- Generate Extended Signals ----
        function onExtendedSignals(app)
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end
            setStatus(app, 'Generating extended signals (12 fast/medium/slow)...');
            drawnow;
            try
                [app.SignalData, app.SignalNames] = sigstrat.generateExtendedSignals(app.MacroData, app.MktData);
                updateSignalsTab(app);
                updateStrategyTabData(app);
                checkEnableButtons(app);
                setStatus(app, sprintf('Generated %d extended signals.', numel(app.SignalNames)));
            catch ME
                setStatus(app, ['Extended signal error: ' ME.message]);
            end
        end

        %% ---- Add Individual Signal ----
        function onAddSignal(app)
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end
            setStatus(app, 'Opening Signal Builder...');
            drawnow;
            try
                dlg = SignalBuilderDialog(app.MktData, app.MacroData, app.SignalNames);
                [sig, meta] = dlg.waitForUser();
                if isempty(sig)
                    setStatus(app, 'Signal builder cancelled.');
                    return;
                end
                % Append signal
                if isempty(app.SignalData)
                    app.SignalData = sig;
                else
                    app.SignalData = [app.SignalData, sig];
                end
                app.SignalNames{end+1} = meta.name;
                updateSignalsTab(app);
                updateStrategyTabData(app);
                checkEnableButtons(app);
                setStatus(app, sprintf('Added signal: %s', meta.name));
            catch ME
                setStatus(app, ['Add signal error: ' ME.message]);
            end
        end

        %% ---- Remove Signal ----
        function onRemoveSignal(app)
            if isempty(app.SignalNames)
                setStatus(app, 'No signals to remove.');
                return;
            end
            [sel, ok] = listdlg('ListString', app.SignalNames, ...
                'SelectionMode', 'multiple', ...
                'PromptString', 'Select signals to remove:', ...
                'Name', 'Remove Signals', ...
                'ListSize', [300 250]);
            if ~ok || isempty(sel), return; end

            names = strjoin(app.SignalNames(sel), ', ');
            answer = uiconfirm(app.UIFigure, ...
                sprintf('Remove %d signal(s): %s?', numel(sel), names), ...
                'Confirm Removal', 'Options', {'Remove','Cancel'}, 'DefaultOption', 'Cancel');
            if ~strcmp(answer, 'Remove'), return; end

            keep = setdiff(1:numel(app.SignalNames), sel);
            app.SignalData  = app.SignalData(:, keep);
            app.SignalNames = app.SignalNames(keep);

            % Clear stale strategy results (weights no longer valid)
            app.EqWts = [];
            app.StrategyResult = struct();

            updateSignalsTab(app);
            updateStrategyTabData(app);
            checkEnableButtons(app);
            setStatus(app, sprintf('Removed %d signal(s).', numel(sel)));
        end

        %% ---- Re-normalize Signals ----
        function onReNormalize(app)
            if isempty(app.SignalData)
                setStatus(app, 'Import signals first.');
                return;
            end
            setStatus(app, 'Re-normalizing signals...');
            drawnow;
            try
                normOpts = struct();
                normOpts.window    = app.NormWindowField.Value;
                normOpts.tanhScale = app.NormTanhField.Value;
                method = app.NormMethodDrop.Value;
                app.SignalData = sigstrat.normalizeSignals(app.SignalData, method, normOpts);
                updateSignalsTab(app);
                setStatus(app, sprintf('Signals re-normalized (%s).', method));
            catch ME
                setStatus(app, ['Normalization error: ' ME.message]);
            end
        end

        %% ---- Strategy Mode Changed ----
        function onStrategyModeChanged(app)
            mode = app.StrategyDropDown.Value;
            app.CompositePanel.Visible    = 'off';
            app.RiskBudgetPanel.Visible   = 'off';
            app.DecisionTreePanel.Visible = 'off';
            app.DefCompPanel.Visible      = 'off';
            app.DefRBPanel.Visible        = 'off';
            app.DefDTPanel.Visible        = 'off';

            switch mode
                case 'Composite'
                    app.CompositePanel.Visible = 'on';
                    app.DefCompPanel.Visible   = 'on';
                case 'Risk Budget'
                    app.RiskBudgetPanel.Visible = 'on';
                    app.DefRBPanel.Visible      = 'on';
                case 'Decision Tree'
                    app.DecisionTreePanel.Visible = 'on';
                    app.DefDTPanel.Visible        = 'on';
            end
        end

        %% ---- Optimize Strategy ----
        function onOptimize(app)
            if isempty(app.SignalData)
                setStatus(app, 'Import signals first.');
                return;
            end
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end

            mode = app.StrategyDropDown.Value;
            setStatus(app, sprintf('Optimizing %s strategy...', mode));
            drawnow;

            rebalFreq = app.RebalFreqField.Value;
            txCost = app.TxCostField.Value / 10000;

            try
                switch mode
                    case 'Composite'
                        % Filter signals by SigConfigTable Include column
                        tblData = app.SigConfigTable.Data;
                        if ~isempty(tblData)
                            includeMask = false(1, size(tblData, 1));
                            sigWeights = zeros(1, size(tblData, 1));
                            for si = 1:size(tblData, 1)
                                includeMask(si) = tblData{si, 1};
                                sigWeights(si) = tblData{si, 3};
                            end
                            filtSignals = app.SignalData(:, includeMask);
                            filtNames = app.SignalNames(includeMask);
                        else
                            filtSignals = app.SignalData;
                            filtNames = app.SignalNames;
                        end

                        mappingMethod = app.CompMappingDrop.Value;
                        opts = struct();
                        opts.nThresh       = app.CompThreshField.Value;
                        opts.rebalFreq     = rebalFreq;
                        opts.txCost        = txCost;
                        opts = readObjectiveOpts(app, opts);
                        opts.constraints   = readConstraints(app);

                        if strcmp(mappingMethod, 'Step')
                            result = sigstrat.optimizeComposite(filtSignals, filtNames, app.MktData, opts);
                        else
                            opts.mappingMethod = mappingMethod;
                            opts.sigmoidK      = app.CompSigmoidKField.Value;
                            opts.lambda        = app.CompLambdaField.Value;
                            opts.nFolds        = app.CompCVFoldsField.Value;
                            opts.walkForward   = app.CompWalkFwdCheck.Value;
                            opts.reoptFreq     = app.CompReoptFreqField.Value;
                            opts.sensitivity   = app.CompSensitivityCheck.Value;
                            result = sigstrat.robustOptimize(filtSignals, filtNames, app.MktData, opts);
                        end
                        app.StrategyResult = result;
                        app.EqWts = result.eqWts;

                        updateCompositeResults(app, result);

                    case 'Risk Budget'
                        opts = struct();
                        opts.rebalFreq = rebalFreq;
                        opts.txCost    = txCost;
                        opts = readRiskBudgetOpts(app, opts);

                        result = sigstrat.riskBudgetStrategy(app.SignalData, app.SignalNames, app.MktData, app.MacroData, opts);
                        app.StrategyResult = result;
                        app.EqWts = result.eqWts;

                        updateRiskBudgetResults(app, result);

                    case 'Decision Tree'
                        opts = struct();
                        opts.mode          = app.DTModeDropDown.Value;
                        opts.maxDepth      = app.DTDepthField.Value;
                        opts.minLeafSize   = app.DTLeafField.Value;
                        opts.rebalFreq     = rebalFreq;
                        opts.txCost        = txCost;
                        opts.useRegression = app.DTRegressionCheck.Value;
                        opts.nFolds        = app.DTCVFoldsField.Value;

                        if strcmp(opts.mode, 'RuleBased')
                            opts.rules = readDTRules(app);
                        end

                        result = sigstrat.decisionTreeStrategy(app.SignalData, app.SignalNames, app.MktData, app.MacroData, opts);
                        app.StrategyResult = result;
                        app.EqWts = result.eqWts;

                        updateDecisionTreeResults(app, result);
                end

                updateDefinitionTab(app);
                app.RunBacktestButton.Enable = 'on';
                setStatus(app, sprintf('%s optimization complete.', mode));
            catch ME
                setStatus(app, ['Optimization error: ' ME.message]);
            end
        end

        %% ---- Run Backtest ----
        function onRunBacktest(app)
            if isempty(app.EqWts)
                setStatus(app, 'Optimize strategy first to get equity weights.');
                return;
            end
            setStatus(app, 'Running backtest...');
            drawnow;

            rebalFreq = app.RebalFreqField.Value;
            txCost = app.TxCostField.Value / 10000;

            try
                app.BacktestResult = sigstrat.backtestEquityCash(app.EqWts, app.MktData, rebalFreq, txCost);
                app.PerfResult = sigstrat.computeStrategyPerf(app.BacktestResult);
                app.StressResult = sigstrat.stressTestStrategy(app.BacktestResult);

                updateBacktestTab(app);
                updatePerformanceTab(app);
                updateStressTab(app);
                updateIndividualTab(app);

                app.TabGroup.SelectedTab = app.BacktestTab;
                setStatus(app, sprintf('Backtest complete. Sharpe=%.2f, MaxDD=%.1f%%', ...
                    app.PerfResult.sharpe, app.PerfResult.maxDD*100));
            catch ME
                setStatus(app, ['Backtest error: ' ME.message]);
            end
        end

        %% ---- Export Results ----
        function onExportResults(app)
            [file, path] = uiputfile({'*.mat','MAT File'; '*.xlsx','Excel'}, 'Export Results');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);

            try
                results = struct();
                results.mkt = app.MktData;
                results.signals = app.SignalData;
                results.signalNames = app.SignalNames;
                results.eqWts = app.EqWts;
                results.backtest = app.BacktestResult;
                results.perf = app.PerfResult;
                results.stress = app.StressResult;
                results.strategy = app.StrategyResult;

                [~, ~, ext] = fileparts(filepath);
                if strcmp(ext, '.mat')
                    save(filepath, '-struct', 'results');
                else
                    if ~isempty(fieldnames(app.PerfResult)) && isfield(app.PerfResult, 'table')
                        writetable(app.PerfResult.table, filepath, 'Sheet', 'Performance');
                    end
                    if ~isempty(app.StressResult) && istable(app.StressResult) && height(app.StressResult) > 0
                        writetable(app.StressResult, filepath, 'Sheet', 'Stress');
                    end
                end
                setStatus(app, ['Results exported to: ' filepath]);
            catch ME
                setStatus(app, ['Export error: ' ME.message]);
            end
        end

        %% ---- Save / Load Session ----
        function onSaveSession(app)
            [file, path] = uiputfile('*.mat', 'Save Session');
            if isequal(file, 0), return; end
            try
                session.MktData = app.MktData;
                session.MacroData = app.MacroData;
                session.SignalData = app.SignalData;
                session.SignalNames = app.SignalNames;
                session.EqWts = app.EqWts;
                session.BacktestResult = app.BacktestResult;
                session.PerfResult = app.PerfResult;
                session.StressResult = app.StressResult;
                session.StrategyResult = app.StrategyResult;
                session.StartDate = app.StartDateField.Value;
                session.EndDate = app.EndDateField.Value;
                session.StrategyMode = app.StrategyDropDown.Value;
                save(fullfile(path, file), '-struct', 'session');
                setStatus(app, 'Session saved.');
            catch ME
                setStatus(app, ['Save error: ' ME.message]);
            end
        end

        function onLoadSession(app)
            [file, path] = uigetfile('*.mat', 'Load Session');
            if isequal(file, 0), return; end
            try
                s = load(fullfile(path, file));
                if isfield(s, 'MktData'),        app.MktData = s.MktData; end
                if isfield(s, 'MacroData'),       app.MacroData = s.MacroData; end
                if isfield(s, 'SignalData'),       app.SignalData = s.SignalData; end
                if isfield(s, 'SignalNames'),      app.SignalNames = s.SignalNames; end
                if isfield(s, 'EqWts'),            app.EqWts = s.EqWts; end
                if isfield(s, 'BacktestResult'),   app.BacktestResult = s.BacktestResult; end
                if isfield(s, 'PerfResult'),        app.PerfResult = s.PerfResult; end
                if isfield(s, 'StressResult'),      app.StressResult = s.StressResult; end
                if isfield(s, 'StrategyResult'),    app.StrategyResult = s.StrategyResult; end
                if isfield(s, 'StartDate'),        app.StartDateField.Value = s.StartDate; end
                if isfield(s, 'EndDate'),          app.EndDateField.Value = s.EndDate; end
                if isfield(s, 'StrategyMode'),     app.StrategyDropDown.Value = s.StrategyMode; end

                checkEnableButtons(app);
                if ~isempty(app.SignalData)
                    updateSignalsTab(app);
                    updateStrategyTabData(app);
                end
                if isfield(app.BacktestResult, 'portRet') && ~isempty(app.BacktestResult.portRet)
                    updateBacktestTab(app);
                    updatePerformanceTab(app);
                    updateStressTab(app);
                    updateIndividualTab(app);
                end
                onStrategyModeChanged(app);
                setStatus(app, 'Session loaded.');
            catch ME
                setStatus(app, ['Load error: ' ME.message]);
            end
        end

        %% ---- Individual Signal Selection Changed ----
        function onIndivSignalChanged(app)
            updateIndividualSignalDetail(app);
        end

        %% ==================== UPDATE METHODS ====================

        %% ---- Update Signals Tab ----
        function updateSignalsTab(app)
            if isempty(app.SignalData), return; end
            N = numel(app.SignalNames);
            T = size(app.SignalData, 1);

            % Summary table
            tblData = cell(N, 6);
            for j = 1:N
                s = app.SignalData(:, j);
                tblData{j, 1} = app.SignalNames{j};
                tblData{j, 2} = round(mean(s, 'omitnan'), 4);
                tblData{j, 3} = round(std(s, 'omitnan'), 4);
                tblData{j, 4} = round(min(s), 4);
                tblData{j, 5} = round(max(s), 4);
                tblData{j, 6} = round(sum(isnan(s)) / T * 100, 1);
            end
            app.SignalTable.Data = tblData;

            % Plot signals
            cla(app.SignalAxes);
            hold(app.SignalAxes, 'on');
            dates = app.MktData.retDates;
            colors = lines(N);
            for j = 1:N
                plot(app.SignalAxes, dates, app.SignalData(:, j), 'Color', colors(j,:), 'LineWidth', 1);
            end
            hold(app.SignalAxes, 'off');
            legend(app.SignalAxes, app.SignalNames, 'Location', 'best', 'FontSize', 7);
            ylabel(app.SignalAxes, 'Signal Value');
            title(app.SignalAxes, 'Signal Time Series');
            grid(app.SignalAxes, 'on');
        end

        %% ---- Update Strategy Tab Data ----
        function updateStrategyTabData(app)
            if isempty(app.SignalNames), return; end
            N = numel(app.SignalNames);

            % Signal Config table (Zone A)
            sigCfgData = cell(N, 4);
            for j = 1:N
                sigCfgData{j, 1} = true;  % Include
                sigCfgData{j, 2} = app.SignalNames{j};
                sigCfgData{j, 3} = round(1/N, 3);
                sigCfgData{j, 4} = inferSignalType(app.SignalNames{j});
            end
            app.SigConfigTable.Data = sigCfgData;

            % Legacy hidden weights table
            compData = cell(N, 2);
            for j = 1:N
                compData{j, 1} = app.SignalNames{j};
                compData{j, 2} = round(1/N, 3);
            end
            app.CompWeightsTable.Data = compData;

            % Risk budget table
            rbData = cell(N, 3);
            for j = 1:N
                rbData{j, 1} = app.SignalNames{j};
                rbData{j, 2} = round(1/N, 3);
                rbData{j, 3} = 'Linear';
            end
            app.RBTable.Data = rbData;

            % Decision tree rules table (default)
            dtData = cell(2, 4);
            dtData{1, 1} = app.SignalNames{1};
            dtData{1, 2} = '>';
            dtData{1, 3} = 0;
            dtData{1, 4} = 0.80;
            dtData{2, 1} = app.SignalNames{1};
            dtData{2, 2} = '<=';
            dtData{2, 3} = 0;
            dtData{2, 4} = 0.30;
            app.DTRulesTable.Data = dtData;

            % Individual signal dropdown
            app.IndivSignalDrop.Items = app.SignalNames;

            onStrategyModeChanged(app);
        end

        %% ---- Update Composite Results ----
        function updateCompositeResults(app, result)
            % Update weights table
            N = numel(result.signalNames);
            compData = cell(N, 2);
            for j = 1:N
                compData{j, 1} = result.signalNames{j};
                compData{j, 2} = round(result.weights(j), 3);
            end
            app.CompWeightsTable.Data = compData;

            % Results text
            lines = {};
            lines{end+1} = sprintf('Optimal Weights: %s', mat2str(round(result.weights', 3)));
            if isfield(result, 'thresholds') && ~isempty(result.thresholds)
                lines{end+1} = sprintf('Thresholds: %s', mat2str(round(result.thresholds', 3)));
            end
            if isfield(result, 'eqLevels') && ~isempty(result.eqLevels)
                lines{end+1} = sprintf('Equity Levels: %s', mat2str(round(result.eqLevels', 2)));
            end
            if isfield(result, 'mappingMethod')
                lines{end+1} = sprintf('Mapping: %s', result.mappingMethod);
            end
            if isfield(result, 'regularization')
                lines{end+1} = sprintf('Regularization: λ=%.2f, κ=%.2f', ...
                    result.regularization.lambda, result.regularization.kappa);
            end
            lines{end+1} = '';
            lines{end+1} = sprintf('In-Sample:  Sharpe=%.2f, Return=%.1f%%, MaxDD=%.1f%%', ...
                result.inPerf.sharpe, result.inPerf.annReturn*100, result.inPerf.maxDD*100);
            if isfield(result.outPerf, 'sharpe') && isfinite(result.outPerf.sharpe)
                lines{end+1} = sprintf('Out-Sample: Sharpe=%.2f, Return=%.1f%%, MaxDD=%.1f%%', ...
                    result.outPerf.sharpe, result.outPerf.annReturn*100, result.outPerf.maxDD*100);
            end
            % CV fold metrics
            if isfield(result, 'cvFolds') && ~isempty(result.cvFolds)
                lines{end+1} = '';
                lines{end+1} = sprintf('Cross-Validation (%d folds):', numel(result.cvFolds));
                for fi = 1:numel(result.cvFolds)
                    f = result.cvFolds(fi);
                    if isfield(f, 'oosSharpe')
                        lines{end+1} = sprintf('  Fold %d: OOS Sharpe=%.2f, Return=%.1f%%, MaxDD=%.1f%%', ...
                            fi, f.oosSharpe, f.oosReturn*100, f.oosMaxDD*100); %#ok<AGROW>
                    end
                end
                lines{end+1} = sprintf('  Avg OOS Sharpe: %.2f', mean([result.cvFolds.oosSharpe], 'omitnan'));
            end
            % Weight stability
            if isfield(result, 'weightStability') && isfield(result.weightStability, 'std')
                ws = result.weightStability;
                lines{end+1} = '';
                lines{end+1} = sprintf('Sensitivity (%d bootstraps):', ws.nBoot);
                for si = 1:numel(result.signalNames)
                    lines{end+1} = sprintf('  %s: %.3f +/- %.3f [%.3f, %.3f]', ...
                        result.signalNames{si}, ws.mean(si), ws.std(si), ws.pct5(si), ws.pct95(si)); %#ok<AGROW>
                end
            end
            app.CompResultsText.Value = lines;

            % Performance statistics table
            metrics = {'Ann. Return (%)'; 'Ann. Vol (%)'; 'Sharpe'; 'Sortino'; ...
                       'Calmar'; 'Max DD (%)'; 'Hit Rate (%)'; 'Skewness'; 'Kurtosis'};
            inP = result.inPerf;
            isVals = {sprintf('%.2f', inP.annReturn*100); sprintf('%.2f', inP.annVol*100); ...
                      sprintf('%.2f', inP.sharpe); sprintf('%.2f', inP.sortino); ...
                      sprintf('%.2f', inP.calmar); sprintf('%.2f', inP.maxDD*100); ...
                      sprintf('%.1f', inP.hitRate*100); sprintf('%.2f', inP.skewness); ...
                      sprintf('%.2f', inP.kurtosis)};
            if isfield(result.outPerf, 'sharpe') && isfinite(result.outPerf.sharpe)
                oP = result.outPerf;
                oosVals = {sprintf('%.2f', oP.annReturn*100); sprintf('%.2f', oP.annVol*100); ...
                           sprintf('%.2f', oP.sharpe); sprintf('%.2f', oP.sortino); ...
                           sprintf('%.2f', oP.calmar); sprintf('%.2f', oP.maxDD*100); ...
                           sprintf('%.1f', oP.hitRate*100); sprintf('%.2f', oP.skewness); ...
                           sprintf('%.2f', oP.kurtosis)};
            else
                oosVals = repmat({'-'}, 9, 1);
            end
            perfData = [metrics, isVals, oosVals, repmat({'-'}, 9, 1)];
            app.CompPerfTable.ColumnName = {'Metric','In-Sample','Out-of-Sample','Full Sample'};
            app.CompPerfTable.Data = perfData;

            % Mapping function plot
            cla(app.CompStepAxes);
            if isfield(result, 'mappingFcnX')
                plot(app.CompStepAxes, result.mappingFcnX, result.mappingFcnY * 100, 'b-', 'LineWidth', 2);
            else
                plot(app.CompStepAxes, result.stepFcnX, result.stepFcnY * 100, 'b-', 'LineWidth', 2);
            end
            xlabel(app.CompStepAxes, 'Composite Signal');
            ylabel(app.CompStepAxes, 'Equity Weight (%)');
            if isfield(result, 'mappingMethod')
                title(app.CompStepAxes, sprintf('Signal → Weight (%s)', result.mappingMethod));
            else
                title(app.CompStepAxes, 'Composite → Equity Weight Step Function');
            end
            grid(app.CompStepAxes, 'on');
            ylim(app.CompStepAxes, [-5 105]);
        end

        %% ---- Update Risk Budget Results ----
        function updateRiskBudgetResults(app, result)
            % Stacked area chart
            cla(app.RBStackedAxes);
            dates = app.MktData.retDates;
            alloc = result.allocations;

            area(app.RBStackedAxes, dates, alloc * 100);
            legend(app.RBStackedAxes, app.SignalNames, 'Location', 'best', 'FontSize', 7);
            ylabel(app.RBStackedAxes, 'Equity Allocation (%)');
            title(app.RBStackedAxes, 'Per-Signal Allocation (Stacked)');
            ylim(app.RBStackedAxes, [0 110]);
            grid(app.RBStackedAxes, 'on');
        end

        %% ---- Update Decision Tree Results ----
        function updateDecisionTreeResults(app, result)
            % Rules text
            if isfield(result, 'rulesText') && ~isempty(result.rulesText)
                if iscell(result.rulesText)
                    app.DTRulesText.Value = result.rulesText;
                else
                    app.DTRulesText.Value = strsplit(result.rulesText, '\n');
                end
            end

            % Variable importance bar chart
            if ~isempty(result.importance) && any(result.importance > 0)
                cla(app.DTImportanceAxes);
                nF = numel(result.importance);
                barh(app.DTImportanceAxes, 1:nF, result.importance);
                if numel(result.featureNames) == nF
                    yticks(app.DTImportanceAxes, 1:nF);
                    yticklabels(app.DTImportanceAxes, result.featureNames);
                end
                xlabel(app.DTImportanceAxes, 'Importance');
                title(app.DTImportanceAxes, 'Variable Importance');
                grid(app.DTImportanceAxes, 'on');
            end
        end

        %% ---- Update Definition Tab ----
        function updateDefinitionTab(app)
            mode = app.StrategyDropDown.Value;
            result = app.StrategyResult;
            if isempty(fieldnames(result)), return; end

            switch mode
                case 'Composite'
                    % --- Weights table ---
                    N = numel(result.signalNames);
                    wtData = cell(N, 3);
                    for j = 1:N
                        wtData{j, 1} = result.signalNames{j};
                        wtData{j, 2} = round(result.weights(j), 4);
                        wtData{j, 3} = inferSignalType(result.signalNames{j});
                    end
                    app.DefCompWeightsTable.Data = wtData;

                    % --- Params text ---
                    lines = {};
                    lines{end+1} = '=== COMPOSITE STRATEGY DEFINITION ===';
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Objective: %s', app.ObjDropDown.Value);
                    lines{end+1} = sprintf('Risk Aversion: %.2f', app.ObjPenaltySlider.Value);
                    lines{end+1} = '';
                    if isfield(result, 'mappingMethod')
                        lines{end+1} = sprintf('Mapping: %s', result.mappingMethod);
                    else
                        lines{end+1} = sprintf('Mapping: Step (%d thresholds)', app.CompThreshField.Value);
                    end
                    lines{end+1} = sprintf('Sigmoid K: %.1f', app.CompSigmoidKField.Value);
                    if isfield(result, 'thresholds') && ~isempty(result.thresholds)
                        lines{end+1} = sprintf('Thresholds: %s', mat2str(round(result.thresholds', 3)));
                    end
                    if isfield(result, 'eqLevels') && ~isempty(result.eqLevels)
                        lines{end+1} = sprintf('Equity Levels: %s', mat2str(round(result.eqLevels', 2)));
                    end
                    lines{end+1} = '';
                    if isfield(result, 'regularization')
                        lines{end+1} = sprintf('Regularization: lambda=%.3f, kappa=%.3f', ...
                            result.regularization.lambda, result.regularization.kappa);
                    else
                        lines{end+1} = sprintf('Regularization: lambda=%.3f', app.CompLambdaField.Value);
                    end
                    lines{end+1} = sprintf('CV Folds: %d', app.CompCVFoldsField.Value);
                    if isfield(result, 'cvFolds') && ~isempty(result.cvFolds)
                        lines{end+1} = sprintf('Avg OOS Sharpe: %.2f', mean([result.cvFolds.oosSharpe], 'omitnan'));
                    end
                    lines{end+1} = sprintf('Walk-Forward: %s', onoff(app.CompWalkFwdCheck.Value));
                    if app.CompWalkFwdCheck.Value
                        lines{end+1} = sprintf('Reopt Freq: %d days', app.CompReoptFreqField.Value);
                    end
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Rebalance Freq: %d days', app.RebalFreqField.Value);
                    lines{end+1} = sprintf('Tx Cost: %d bps', app.TxCostField.Value);
                    lines{end+1} = '';
                    % Constraints
                    lines{end+1} = '--- Constraints ---';
                    if app.ConstrEqMinCheck.Value
                        lines{end+1} = sprintf('Eq Min Weight: %.0f%%', app.ConstrEqMinField.Value*100);
                    end
                    if app.ConstrEqMaxCheck.Value
                        lines{end+1} = sprintf('Eq Max Weight: %.0f%%', app.ConstrEqMaxField.Value*100);
                    end
                    if app.ConstrTurnoverCheck.Value
                        lines{end+1} = sprintf('Max Turnover/Yr: %.1f', app.ConstrTurnoverField.Value);
                    end
                    if app.ConstrSigWtMinCheck.Value
                        lines{end+1} = sprintf('Sig Wt Min: %.2f', app.ConstrSigWtMinField.Value);
                    end
                    if app.ConstrSigWtMaxCheck.Value
                        lines{end+1} = sprintf('Sig Wt Max: %.2f', app.ConstrSigWtMaxField.Value);
                    end
                    if app.ConstrMaxDDCheck.Value
                        lines{end+1} = sprintf('Max DD Stop: %.0f%%', app.ConstrMaxDDField.Value*100);
                    end
                    lines{end+1} = sprintf('Priority: %s', app.ConstrPriorityDrop.Value);
                    lines{end+1} = '';
                    % Performance summary
                    lines{end+1} = '--- Performance ---';
                    lines{end+1} = sprintf('IS:  Sharpe=%.2f  Return=%.1f%%  MaxDD=%.1f%%', ...
                        result.inPerf.sharpe, result.inPerf.annReturn*100, result.inPerf.maxDD*100);
                    if isfield(result.outPerf, 'sharpe') && isfinite(result.outPerf.sharpe)
                        lines{end+1} = sprintf('OOS: Sharpe=%.2f  Return=%.1f%%  MaxDD=%.1f%%', ...
                            result.outPerf.sharpe, result.outPerf.annReturn*100, result.outPerf.maxDD*100);
                    end
                    % Weight stability
                    if isfield(result, 'weightStability') && isfield(result.weightStability, 'std')
                        ws = result.weightStability;
                        lines{end+1} = '';
                        lines{end+1} = '--- Weight Stability ---';
                        for si = 1:numel(result.signalNames)
                            lines{end+1} = sprintf('  %s: %.3f +/- %.3f [%.3f, %.3f]', ...
                                result.signalNames{si}, ws.mean(si), ws.std(si), ws.pct5(si), ws.pct95(si)); %#ok<AGROW>
                        end
                    end
                    app.DefCompParamsText.Value = lines;

                    % --- Mapping curve ---
                    cla(app.DefCompMappingAxes);
                    if isfield(result, 'mappingFcnX')
                        plot(app.DefCompMappingAxes, result.mappingFcnX, result.mappingFcnY * 100, 'b-', 'LineWidth', 2);
                    elseif isfield(result, 'stepFcnX')
                        plot(app.DefCompMappingAxes, result.stepFcnX, result.stepFcnY * 100, 'b-', 'LineWidth', 2);
                    end
                    xlabel(app.DefCompMappingAxes, 'Composite Signal');
                    ylabel(app.DefCompMappingAxes, 'Equity Weight (%)');
                    if isfield(result, 'mappingMethod')
                        title(app.DefCompMappingAxes, sprintf('Signal to Weight (%s)', result.mappingMethod));
                    else
                        title(app.DefCompMappingAxes, 'Composite Signal to Equity Weight');
                    end
                    grid(app.DefCompMappingAxes, 'on');
                    ylim(app.DefCompMappingAxes, [-5 105]);

                case 'Risk Budget'
                    % --- Budget table ---
                    tblData = app.RBTable.Data;
                    if ~isempty(tblData)
                        N = size(tblData, 1);
                        rbData = cell(N, 3);
                        for j = 1:N
                            rbData{j, 1} = tblData{j, 1};
                            rbData{j, 2} = round(tblData{j, 2} * 100, 1);
                            rbData{j, 3} = tblData{j, 3};
                        end
                        app.DefRBTable.Data = rbData;
                    end

                    % --- Params text ---
                    lines = {};
                    lines{end+1} = '=== RISK BUDGET STRATEGY DEFINITION ===';
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Macro Conditioning: %s', onoff(app.RBMacroCondCheck.Value));
                    if app.RBMacroCondCheck.Value
                        lines{end+1} = sprintf('  Variable: %s', app.RBMacroVarDrop.Value);
                        lines{end+1} = sprintf('  Threshold: %.2f', app.RBMacroThreshField.Value);
                    end
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Rebalance Freq: %d days', app.RebalFreqField.Value);
                    lines{end+1} = sprintf('Tx Cost: %d bps', app.TxCostField.Value);
                    app.DefRBParamsText.Value = lines;

                    % --- Stacked allocation chart ---
                    cla(app.DefRBAllocAxes);
                    if isfield(result, 'allocations') && isfield(app.MktData, 'retDates')
                        dates = app.MktData.retDates;
                        alloc = result.allocations;
                        area(app.DefRBAllocAxes, dates, alloc * 100);
                        legend(app.DefRBAllocAxes, app.SignalNames, 'Location', 'best', 'FontSize', 7);
                        ylabel(app.DefRBAllocAxes, 'Equity Allocation (%)');
                        title(app.DefRBAllocAxes, 'Per-Signal Allocation (Stacked)');
                        ylim(app.DefRBAllocAxes, [0 110]);
                        grid(app.DefRBAllocAxes, 'on');
                    end

                case 'Decision Tree'
                    % --- Tree diagram ---
                    cla(app.DefDTTreeAxes);
                    if isfield(result, 'treeModel') && ~isempty(result.treeModel)
                        plotTreeDiagram(app.DefDTTreeAxes, result.treeModel);
                    else
                        % RuleBased fallback: show rules as text on axes
                        text(app.DefDTTreeAxes, 0.5, 0.5, ...
                            'No tree model available (RuleBased mode)', ...
                            'HorizontalAlignment', 'center', 'FontSize', 11);
                        set(app.DefDTTreeAxes, 'XLim', [0 1], 'YLim', [0 1]);
                        app.DefDTTreeAxes.XTick = []; app.DefDTTreeAxes.YTick = [];
                        title(app.DefDTTreeAxes, 'Decision Tree Structure');
                    end

                    % --- Rules text ---
                    if isfield(result, 'rulesText') && ~isempty(result.rulesText)
                        if iscell(result.rulesText)
                            app.DefDTRulesText.Value = result.rulesText;
                        else
                            app.DefDTRulesText.Value = strsplit(result.rulesText, '\n');
                        end
                    end

                    % --- Params text ---
                    lines = {};
                    lines{end+1} = '=== DECISION TREE STRATEGY DEFINITION ===';
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Mode: %s', app.DTModeDropDown.Value);
                    lines{end+1} = sprintf('Regression: %s', onoff(app.DTRegressionCheck.Value));
                    lines{end+1} = sprintf('Max Depth: %d', app.DTDepthField.Value);
                    lines{end+1} = sprintf('Min Leaf Size: %d', app.DTLeafField.Value);
                    lines{end+1} = '';
                    lines{end+1} = sprintf('CV Folds: %d', app.DTCVFoldsField.Value);
                    if isfield(result, 'cvMetrics') && isfield(result.cvMetrics, 'avgCVSharpe') ...
                            && isfinite(result.cvMetrics.avgCVSharpe)
                        lines{end+1} = sprintf('Best CV Sharpe: %.2f', result.cvMetrics.avgCVSharpe);
                    end
                    if isfield(result, 'cvMetrics') && isfield(result.cvMetrics, 'bestDepth')
                        lines{end+1} = sprintf('CV Best Depth: %d', result.cvMetrics.bestDepth);
                        lines{end+1} = sprintf('CV Best MinLeaf: %d', result.cvMetrics.bestLeaf);
                    end
                    lines{end+1} = '';
                    lines{end+1} = sprintf('Rebalance Freq: %d days', app.RebalFreqField.Value);
                    lines{end+1} = sprintf('Tx Cost: %d bps', app.TxCostField.Value);
                    app.DefDTParamsText.Value = lines;

                    % --- Variable importance bar chart ---
                    cla(app.DefDTImportanceAxes);
                    if isfield(result, 'importance') && ~isempty(result.importance) && any(result.importance > 0)
                        nF = numel(result.importance);
                        barh(app.DefDTImportanceAxes, 1:nF, result.importance);
                        if isfield(result, 'featureNames') && numel(result.featureNames) == nF
                            yticks(app.DefDTImportanceAxes, 1:nF);
                            yticklabels(app.DefDTImportanceAxes, result.featureNames);
                        end
                        xlabel(app.DefDTImportanceAxes, 'Importance');
                        title(app.DefDTImportanceAxes, 'Variable Importance');
                        grid(app.DefDTImportanceAxes, 'on');
                    end
            end
        end

        %% ---- Update Backtest Tab ----
        function updateBacktestTab(app)
            bt = app.BacktestResult;
            perf = app.PerfResult;
            dates = bt.dates;

            % Cumulative Return
            cla(app.CumRetAxes);
            hold(app.CumRetAxes, 'on');
            plot(app.CumRetAxes, dates, bt.cumRet, 'b-', 'LineWidth', 1.5);
            plot(app.CumRetAxes, dates, bt.bench6040, 'r--', 'LineWidth', 1);
            plot(app.CumRetAxes, dates, bt.benchEq, 'Color', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1);
            hold(app.CumRetAxes, 'off');
            legend(app.CumRetAxes, {'Strategy', '60/40', '100% Equity'}, 'Location', 'northwest');
            ylabel(app.CumRetAxes, 'Cumulative Wealth');
            title(app.CumRetAxes, 'Cumulative Return');
            grid(app.CumRetAxes, 'on');

            % Drawdown
            cla(app.DrawdownAxes);
            hold(app.DrawdownAxes, 'on');
            area(app.DrawdownAxes, dates, perf.drawdown * 100, 'FaceColor', [0.8 0.2 0.2], 'FaceAlpha', 0.4, 'EdgeColor', 'none');
            plot(app.DrawdownAxes, dates, perf.dd6040 * 100, 'r--', 'LineWidth', 0.8);
            hold(app.DrawdownAxes, 'off');
            legend(app.DrawdownAxes, {'Strategy', '60/40'}, 'Location', 'southwest');
            ylabel(app.DrawdownAxes, 'Drawdown (%)');
            title(app.DrawdownAxes, 'Drawdown');
            grid(app.DrawdownAxes, 'on');

            % Rolling Sharpe
            cla(app.RollSharpeAxes);
            hold(app.RollSharpeAxes, 'on');
            plot(app.RollSharpeAxes, dates, perf.rollingSharpe, 'b-', 'LineWidth', 1);
            yline(app.RollSharpeAxes, 0, 'k--');
            hold(app.RollSharpeAxes, 'off');
            ylabel(app.RollSharpeAxes, 'Sharpe');
            title(app.RollSharpeAxes, 'Rolling 252d Sharpe');
            grid(app.RollSharpeAxes, 'on');

            % Equity Weight
            cla(app.EqWeightAxes);
            area(app.EqWeightAxes, dates, bt.eqWeight * 100, 'FaceColor', [0.2 0.5 0.8], 'FaceAlpha', 0.5, 'EdgeColor', 'none');
            ylabel(app.EqWeightAxes, 'Equity Weight (%)');
            title(app.EqWeightAxes, 'Equity Weight Over Time');
            ylim(app.EqWeightAxes, [0 105]);
            grid(app.EqWeightAxes, 'on');
        end

        %% ---- Update Performance Tab ----
        function updatePerformanceTab(app)
            perf = app.PerfResult;

            % Summary table
            if isfield(perf, 'table')
                app.PerfSummaryTable.Data = table2cell(perf.table);
                app.PerfSummaryTable.ColumnName = perf.table.Properties.VariableNames;
            end

            % Monthly heatmap
            if ~isempty(perf.monthlyMatrix)
                cla(app.MonthlyHeatmapAxes);
                imagesc(app.MonthlyHeatmapAxes, perf.monthlyMatrix * 100);
                colormap(app.MonthlyHeatmapAxes, buildRdGnColormap());
                colorbar(app.MonthlyHeatmapAxes);
                try
                    clim(app.MonthlyHeatmapAxes, [-8 8]);
                catch
                    caxis(app.MonthlyHeatmapAxes, [-8 8]);
                end

                nYears = numel(perf.monthlyYears);
                yticks(app.MonthlyHeatmapAxes, 1:nYears);
                yticklabels(app.MonthlyHeatmapAxes, string(perf.monthlyYears));
                xticks(app.MonthlyHeatmapAxes, 1:12);
                xticklabels(app.MonthlyHeatmapAxes, {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'});
                title(app.MonthlyHeatmapAxes, 'Monthly Returns (%)');

                % Overlay text
                for r = 1:nYears
                    for c = 1:12
                        v = perf.monthlyMatrix(r, c);
                        if isfinite(v)
                            text(app.MonthlyHeatmapAxes, c, r, sprintf('%.1f', v*100), ...
                                'HorizontalAlignment', 'center', 'FontSize', 7);
                        end
                    end
                end
            end
        end

        %% ---- Update Stress Tab ----
        function updateStressTab(app)
            if isempty(app.StressResult) || ~istable(app.StressResult), return; end
            st = app.StressResult;
            nEp = height(st);
            tblData = cell(nEp, 8);
            for i = 1:nEp
                tblData{i, 1} = st.Episode{i};
                tblData{i, 2} = datestr(st.StartDate(i), 'yyyy-mm-dd');
                tblData{i, 3} = datestr(st.EndDate(i), 'yyyy-mm-dd');
                tblData{i, 4} = round(st.Strategy_pct(i), 1);
                tblData{i, 5} = round(st.Bench6040_pct(i), 1);
                tblData{i, 6} = round(st.Equity_pct(i), 1);
                tblData{i, 7} = round(st.AvgEqWt_pct(i), 1);
                tblData{i, 8} = round(st.StratMaxDD_pct(i), 1);
            end
            app.StressTable.Data = tblData;
        end

        %% ---- Update Individual Tab ----
        function updateIndividualTab(app)
            if isempty(app.SignalNames), return; end
            app.IndivSignalDrop.Items = app.SignalNames;
            updateIndividualSignalDetail(app);
        end

        function updateIndividualSignalDetail(app)
            if isempty(app.SignalData) || ~isfield(app.MktData, 'retDates')
                return;
            end

            sigName = app.IndivSignalDrop.Value;
            idx = find(strcmp(app.SignalNames, sigName), 1);
            if isempty(idx), return; end

            sig = app.SignalData(:, idx);

            % Simple threshold-at-0 backtest for this signal
            eqWts = double(sig > 0);
            eqWts(isnan(sig)) = 0.5;

            rebalFreq = app.RebalFreqField.Value;
            txCost = app.TxCostField.Value / 10000;

            try
                bt = sigstrat.backtestEquityCash(eqWts, app.MktData, rebalFreq, txCost);
                perf = sigstrat.computeStrategyPerf(bt);

                % Performance table
                tblData = {
                    'Ann. Return (%)', round(perf.annReturn*100, 2);
                    'Ann. Vol (%)',    round(perf.annVol*100, 2);
                    'Sharpe',          round(perf.sharpe, 3);
                    'Sortino',         round(perf.sortino, 3);
                    'Max DD (%)',      round(perf.maxDD*100, 2);
                    'Hit Rate (%)',    round(perf.hitRate*100, 1);
                    'Calmar',          round(perf.calmar, 3);
                };
                app.IndivPerfTable.Data = tblData;

                % Cumulative return plot
                cla(app.IndivCumRetAxes);
                hold(app.IndivCumRetAxes, 'on');
                plot(app.IndivCumRetAxes, bt.dates, bt.cumRet, 'b-', 'LineWidth', 1.5);
                plot(app.IndivCumRetAxes, bt.dates, bt.bench6040, 'r--', 'LineWidth', 1);
                plot(app.IndivCumRetAxes, bt.dates, bt.benchEq, ':', 'Color', [0.5 0.5 0.5]);
                hold(app.IndivCumRetAxes, 'off');
                legend(app.IndivCumRetAxes, {[sigName ' > 0'], '60/40', 'Equity'}, 'Location', 'northwest');
                title(app.IndivCumRetAxes, sprintf('Per-Signal: %s (threshold=0)', sigName));
                ylabel(app.IndivCumRetAxes, 'Cumulative Wealth');
                grid(app.IndivCumRetAxes, 'on');
            catch ME
                setStatus(app, ['Individual signal error: ' ME.message]);
            end
        end

        %% ==================== HELPER METHODS ====================

        function setStatus(app, msg)
            app.StatusLabel.Text = msg;
            drawnow('limitrate');
        end

        function checkEnableButtons(app)
            hasMkt = isfield(app.MktData, 'retDates') && ~isempty(app.MktData.retDates);
            hasSig = ~isempty(app.SignalData);

            app.DownloadMacroButton.Enable  = onoff(hasMkt);
            hasMacro = hasMkt && ~isempty(app.MacroData) && istable(app.MacroData) && height(app.MacroData) > 0;
            app.DemoSignalsButton.Enable    = onoff(hasMacro);
            app.ExtendedSignalsButton.Enable = onoff(hasMacro);
            app.AddSignalButton.Enable      = onoff(hasMacro);
            app.RemoveSignalButton.Enable   = onoff(hasSig);
            app.OptimizeButton.Enable       = onoff(hasMkt && hasSig);
            app.RunBacktestButton.Enable    = onoff(~isempty(app.EqWts));
        end

        function parseSignalTable(app, T)
            % Parse table with Date column + signal columns
            vn = T.Properties.VariableNames;
            dateCol = find(strcmpi(vn, 'Date') | strcmpi(vn, 'Dates'), 1);
            if isempty(dateCol), dateCol = 1; end

            sigCols = setdiff(1:width(T), dateCol);
            sigData = T{:, sigCols};
            sigNames = vn(sigCols);

            if ~isnumeric(sigData)
                sigData = str2double(string(sigData));
            end

            % Try to parse dates for alignment
            if isfield(app.MktData, 'retDates') && ~isempty(app.MktData.retDates)
                try
                    fileDates = datetime(T{:, dateCol});
                    alignAndStoreSignals(app, sigData, sigNames, fileDates);
                catch
                    alignAndStoreSignals(app, sigData, sigNames);
                end
            else
                alignAndStoreSignals(app, sigData, sigNames);
            end
        end

        function alignAndStoreSignals(app, sigData, sigNames, fileDates)
            if nargin >= 4 && isfield(app.MktData, 'retDates') && ~isempty(app.MktData.retDates)
                % Align to return dates via forward-fill
                targetDates = app.MktData.retDates;
                T2 = numel(targetDates);
                N2 = size(sigData, 2);
                aligned = NaN(T2, N2);
                for j = 1:N2
                    aligned(:, j) = forwardFillVec(fileDates, sigData(:, j), targetDates);
                end
                app.SignalData = aligned;
            else
                app.SignalData = sigData;
            end
            app.SignalNames = sigNames(:)';
            updateSignalsTab(app);
            updateStrategyTabData(app);
            checkEnableButtons(app);
        end

        %% ---- Signal Config Table Selection ----
        function onSignalConfigSelect(app, event)
            if isempty(event.Indices), return; end
            row = event.Indices(1, 1);
            tblData = app.SigConfigTable.Data;
            if isempty(tblData) || row > size(tblData, 1), return; end

            sigName = tblData{row, 2};
            sigType = tblData{row, 4};

            % Show/hide EWMAC-specific fields
            isEWMAC = strcmp(sigType, 'EWMAC');
            vis = onoff(isEWMAC);
            app.SigDetailFastLabel.Visible = vis;
            app.SigDetailFastSpan.Visible = vis;
            app.SigDetailSlowLabel.Visible = vis;
            app.SigDetailSlowSpan.Visible = vis;

            % Populate defaults based on type
            app.SigDetailActivation.Value = 'tanh';
            app.SigDetailSkipDays.Value = 0;
            app.SigDetailVolFloor.Value = 0;
            app.SigDetailTanhScale.Value = 2;
            if isEWMAC
                app.SigDetailFastSpan.Value = 16;
                app.SigDetailSlowSpan.Value = 64;
            end

            app.SigConfigDetailPanel.Title = sprintf('Parameters: %s', sigName);
        end

        %% ---- Rebuild Signal ----
        function onRebuildSignal(app)
            if isempty(app.SigConfigTable.Data)
                setStatus(app, 'No signals configured.');
                return;
            end
            if ~isfield(app.MktData, 'retDates')
                setStatus(app, 'Download market data first.');
                return;
            end

            % Find selected row from table (use first signal if none selected)
            tblData = app.SigConfigTable.Data;
            selectedRow = 1;  % default
            N = size(tblData, 1);

            for row = 1:N
                sigName = tblData{row, 2};
                sigType = tblData{row, 4};

                % Build params from detail panel
                params = struct();
                params.activation = app.SigDetailActivation.Value;
                params.skipDays = app.SigDetailSkipDays.Value;
                params.volFloor = app.SigDetailVolFloor.Value;
                params.tanhScale = app.SigDetailTanhScale.Value;

                if strcmp(sigType, 'EWMAC')
                    params.fastSpan = app.SigDetailFastSpan.Value;
                    params.slowSpan = app.SigDetailSlowSpan.Value;
                end

                % Only rebuild the signal matching the detail panel title
                if contains(app.SigConfigDetailPanel.Title, sigName)
                    selectedRow = row;
                    break;
                end
            end

            sigName = tblData{selectedRow, 2}; %#ok<NASGU>
            sigType = tblData{selectedRow, 4};

            params = struct();
            params.activation = app.SigDetailActivation.Value;
            params.skipDays = app.SigDetailSkipDays.Value;
            params.volFloor = app.SigDetailVolFloor.Value;
            params.tanhScale = app.SigDetailTanhScale.Value;
            if strcmp(sigType, 'EWMAC')
                params.fastSpan = app.SigDetailFastSpan.Value;
                params.slowSpan = app.SigDetailSlowSpan.Value;
            end

            setStatus(app, sprintf('Rebuilding signal %d...', selectedRow));
            drawnow;
            try
                [newSig, ~] = sigstrat.buildSignal(sigType, params, app.MktData, app.MacroData);
                app.SignalData(:, selectedRow) = newSig;
                updateSignalsTab(app);
                setStatus(app, sprintf('Signal %d rebuilt.', selectedRow));
            catch ME
                setStatus(app, ['Rebuild error: ' ME.message]);
            end
        end

        %% ---- Read Objective Options ----
        function opts = readObjectiveOpts(app, opts)
            preset = app.ObjDropDown.Value;
            penalty = app.ObjPenaltySlider.Value;

            % Reset flags
            opts.useSortino = false;
            opts.useCalmar = false;
            opts.minVol = false;
            opts.riskParity = false;

            switch preset
                case 'Max Sharpe'
                    opts.alphaObj = 1; opts.betaObj = 0; opts.gammaObj = penalty;
                case 'Max Sortino'
                    opts.alphaObj = 0; opts.betaObj = 0; opts.gammaObj = penalty;
                    opts.useSortino = true;
                case 'Max Calmar'
                    opts.alphaObj = 0; opts.betaObj = 0; opts.gammaObj = 0;
                    opts.useCalmar = true;
                case 'Max Return'
                    opts.alphaObj = 0; opts.betaObj = 1; opts.gammaObj = penalty;
                case 'Min Volatility'
                    opts.alphaObj = 0; opts.betaObj = 0; opts.gammaObj = penalty;
                    opts.minVol = true;
                case 'Min Max Drawdown'
                    opts.alphaObj = 0; opts.betaObj = 0; opts.gammaObj = 1;
                case 'Risk Parity'
                    opts.alphaObj = 0; opts.betaObj = 0; opts.gammaObj = penalty;
                    opts.riskParity = true;
            end
        end

        %% ---- Read Constraints ----
        function constr = readConstraints(app)
            constr = struct();
            if app.ConstrEqMinCheck.Value
                constr.eqMin = app.ConstrEqMinField.Value;
            end
            if app.ConstrEqMaxCheck.Value
                constr.eqMax = app.ConstrEqMaxField.Value;
            end
            if app.ConstrTurnoverCheck.Value
                constr.maxTurnover = app.ConstrTurnoverField.Value;
            end
            if app.ConstrSigWtMinCheck.Value
                constr.sigWtMin = app.ConstrSigWtMinField.Value;
            end
            if app.ConstrSigWtMaxCheck.Value
                constr.sigWtMax = app.ConstrSigWtMaxField.Value;
            end
            if app.ConstrMaxDDCheck.Value
                constr.maxDD = app.ConstrMaxDDField.Value;
            end
            constr.priority = app.ConstrPriorityDrop.Value;
        end

        function opts = readRiskBudgetOpts(app, opts)
            % Read risk budget config from table
            tblData = app.RBTable.Data;
            if isempty(tblData), return; end
            N = size(tblData, 1);
            budgets = zeros(1, N);
            translations = cell(1, N);
            for j = 1:N
                budgets(j) = tblData{j, 2};
                translations{j} = tblData{j, 3};
            end
            opts.budgets = budgets;
            opts.translations = translations;
            opts.macroCond = app.RBMacroCondCheck.Value;
            opts.macroVar = app.RBMacroVarDrop.Value;
            opts.macroThresh = app.RBMacroThreshField.Value;
        end

        function rules = readDTRules(app)
            tblData = app.DTRulesTable.Data;
            if isempty(tblData)
                rules = {};
                return;
            end
            rules = tblData;
        end
    end
end

%% ==================== STANDALONE HELPER FUNCTIONS ====================

function s = onoff(val)
    if val, s = 'on'; else, s = 'off'; end
end

function vals = forwardFillVec(srcDates, srcVals, targetDates)
    N = numel(targetDates);
    vals = NaN(N, 1);
    srcDates = srcDates(:);
    srcVals  = srcVals(:);
    [srcDates, si] = sort(srcDates);
    srcVals = srcVals(si);
    j = 1;
    lastVal = NaN;
    for i = 1:N
        while j <= numel(srcDates) && srcDates(j) <= targetDates(i)
            lastVal = srcVals(j);
            j = j + 1;
        end
        vals(i) = lastVal;
    end
end

function sigType = inferSignalType(sigName)
%INFERSIGNALTYPE Infer signal type from its name pattern.
    sigName = lower(sigName);
    if contains(sigName, 'ewmac')
        sigType = 'EWMAC';
    elseif contains(sigName, 'mom') || contains(sigName, 'momentum')
        sigType = 'Momentum';
    elseif contains(sigName, 'ensemble')
        sigType = 'Ensemble';
    elseif contains(sigName, 'meanrev') || contains(sigName, 'reversion')
        sigType = 'MeanReversion';
    elseif contains(sigName, 'composite') || contains(sigName, 'macro')
        sigType = 'MacroZ';
    else
        sigType = 'Momentum';
    end
end

function plotTreeDiagram(ax, treeModel)
%PLOTTREEDIAGRAM Draw a node-link tree diagram on a UIAxes.
    cla(ax); hold(ax, 'on');

    nNodes   = numel(treeModel.IsBranchNode);
    children = treeModel.Children;           % nNodes x 2
    isBranch = treeModel.IsBranchNode;
    cutPred  = treeModel.CutPredictor;       % cell array
    cutPoint = treeModel.CutPoint;           % numeric

    isRegression = isa(treeModel, 'classreg.learning.regr.CompactRegressionTree') || ...
                   isa(treeModel, 'ClassificationTree') == false && isprop(treeModel, 'NodeMean');

    % --- Compute depth (y-level) via BFS ---
    depth = zeros(nNodes, 1);
    queue = 1;
    while ~isempty(queue)
        node = queue(1); queue(1) = [];
        ch = children(node, :);
        ch = ch(ch > 0);
        for c = ch
            depth(c) = depth(node) + 1;
            queue(end+1) = c; %#ok<AGROW>
        end
    end
    maxDepth = max(depth);

    % --- Assign x-positions bottom-up (leaves get sequential x, parents center above children) ---
    xPos = zeros(nNodes, 1);
    % Process nodes from deepest to shallowest
    leafCounter = 0;
    % Sort nodes by depth descending, then by node index for stable ordering
    [~, order] = sortrows([depth, (1:nNodes)'], [-1 2]);
    for idx = 1:nNodes
        node = order(idx);
        ch = children(node, :);
        ch = ch(ch > 0);
        if isempty(ch)
            leafCounter = leafCounter + 1;
            xPos(node) = leafCounter;
        else
            xPos(node) = mean(xPos(ch));
        end
    end

    % Map y: root at top (maxDepth), leaves at bottom (0)
    yPos = maxDepth - depth;

    % --- Draw edges ---
    for node = 1:nNodes
        ch = children(node, :);
        ch = ch(ch > 0);
        for c = ch
            plot(ax, [xPos(node) xPos(c)], [yPos(node) yPos(c)], '-', ...
                'Color', [0.6 0.6 0.6], 'LineWidth', 1.2);
        end
    end

    % --- Draw nodes ---
    % Compute box size relative to tree
    xRange = max(xPos) - min(xPos) + 1;
    boxW = max(0.35, xRange * 0.06);
    boxH = max(0.25, (maxDepth + 1) * 0.06);

    for node = 1:nNodes
        x = xPos(node); y = yPos(node);
        if isBranch(node)
            % Branch node: light blue box with split condition
            faceColor = [0.78 0.88 1.0];
            varName = cutPred{node};
            thresh  = cutPoint(node);
            label = sprintf('%s < %.2f', varName, thresh);
        else
            % Leaf node: light green box with predicted value
            faceColor = [0.80 1.0 0.80];
            if isRegression
                val = treeModel.NodeMean(node);
                label = sprintf('%.1f%%', val * 100);
            else
                if isprop(treeModel, 'NodeClass')
                    nc = treeModel.NodeClass{node};
                    if isnumeric(nc)
                        label = sprintf('%.1f%%', nc * 100);
                    else
                        label = char(string(nc));
                    end
                else
                    label = sprintf('Node %d', node);
                end
            end
        end

        % Draw rounded rectangle
        rectangle(ax, 'Position', [x - boxW/2, y - boxH/2, boxW, boxH], ...
            'Curvature', [0.3 0.3], 'FaceColor', faceColor, ...
            'EdgeColor', [0.3 0.3 0.3], 'LineWidth', 0.8);
        % Draw label text
        text(ax, x, y, label, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 7, 'Interpreter', 'none');
    end

    % --- Style axes ---
    hold(ax, 'off');
    ax.XTick = []; ax.YTick = [];
    margin = max(boxW, 0.5);
    xlim(ax, [min(xPos) - margin, max(xPos) + margin]);
    ylim(ax, [-boxH, maxDepth + boxH + 0.3]);
    title(ax, 'Decision Tree Structure');
    ax.Box = 'on';
end

function cmap = buildRdGnColormap()
    % Red-White-Green diverging colormap
    n = 128;
    r_top = linspace(0.2, 1, n)';
    g_top = linspace(0.7, 1, n)';
    b_top = linspace(0.2, 1, n)';
    r_bot = linspace(1, 0.8, n)';
    g_bot = linspace(1, 0.2, n)';
    b_bot = linspace(1, 0.2, n)';
    cmap = [r_bot g_bot b_bot; r_top g_top b_top];
end
