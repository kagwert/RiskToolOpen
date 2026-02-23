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
        CompAlphaField         matlab.ui.control.NumericEditField
        CompBetaField          matlab.ui.control.NumericEditField
        CompGammaField         matlab.ui.control.NumericEditField
        CompThreshField        matlab.ui.control.NumericEditField
        CompResultsText        matlab.ui.control.TextArea
        CompStepAxes           matlab.ui.control.UIAxes
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

            app.LeftGrid = uigridlayout(app.LeftPanel, [29 1]);
            app.LeftGrid.RowHeight = [ ...
                {'fit'} {28} {'fit'} {28} {28} ...       % 1-5:  DATA header, dates, download btns
                {4} ...                                   % 6:    spacer
                {'fit'} {28} {28} {28} {28} {28} ...     % 7-12: SIGNALS header + 5 import btns
                {4} ...                                   % 13:   spacer
                {'fit'} {'fit'} ...                       % 13-14: STRATEGY header + dropdown
                {4} ...                                   % 15:   spacer
                {'fit'} {'fit'} {'fit'} ...               % 16-18: BACKTEST header + rebal + txcost
                {4} ...                                   % 19:   spacer
                {'fit'} {34} {34} {28} ...                % 20-23: ACTIONS header + buttons
                {'fit'} ...                               % 24: save/load row
                repmat({'fit'}, 1, 4) ...                 % 25-28: reserve
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
            app.EndDateField = uieditfield(dateRow, 'text', 'Value', datestr(datetime('today'), 'yyyymmdd')); %#ok<DATST>

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
            createBacktestTab(app);
            createPerformanceTab(app);
            createStressTab(app);
            createIndividualTab(app);
        end

        %% ---- Signals Tab ----
        function createSignalsTab(app)
            app.SignalsTab = uitab(app.TabGroup, 'Title', 'Signals');
            app.SignalsGrid = uigridlayout(app.SignalsTab, [2 1]);
            app.SignalsGrid.RowHeight = {'0.4x', '0.6x'};

            app.SignalTable = uitable(app.SignalsGrid, 'ColumnName', {'Signal','Mean','Std','Min','Max','NaN%'});

            app.SignalAxes = uiaxes(app.SignalsGrid);
            title(app.SignalAxes, 'Signal Time Series');
            xlabel(app.SignalAxes, 'Date'); ylabel(app.SignalAxes, 'Signal Value');
        end

        %% ---- Strategy Tab ----
        function createStrategyTab(app)
            app.StrategyTab = uitab(app.TabGroup, 'Title', 'Strategy');
            app.StrategyGrid = uigridlayout(app.StrategyTab, [1 1]);

            % Composite Panel
            app.CompositePanel = uipanel(app.StrategyGrid, 'Title', 'Composite Signal Strategy');
            app.CompGrid = uigridlayout(app.CompositePanel, [3 2]);
            app.CompGrid.RowHeight = {'0.3x','0.2x','0.5x'};
            app.CompGrid.ColumnWidth = {'1x','1x'};

            app.CompWeightsTable = uitable(app.CompGrid, 'ColumnName', {'Signal','Weight'}, 'ColumnEditable', [false true]);
            app.CompWeightsTable.Layout.Row = 1; app.CompWeightsTable.Layout.Column = 1;

            objGrid = uigridlayout(app.CompGrid, [4 2]);
            objGrid.Layout.Row = 1; objGrid.Layout.Column = 2;
            objGrid.ColumnWidth = {'fit','1x'}; objGrid.Padding = [4 4 4 4]; objGrid.RowSpacing = 2;
            uilabel(objGrid, 'Text', 'Sharpe wt (α):');
            app.CompAlphaField = uieditfield(objGrid, 'numeric', 'Value', 1.0);
            uilabel(objGrid, 'Text', 'Return wt (β):');
            app.CompBetaField = uieditfield(objGrid, 'numeric', 'Value', 0.0);
            uilabel(objGrid, 'Text', 'MaxDD pen (γ):');
            app.CompGammaField = uieditfield(objGrid, 'numeric', 'Value', 0.5);
            uilabel(objGrid, 'Text', '# Thresholds:');
            app.CompThreshField = uieditfield(objGrid, 'numeric', 'Value', 3, 'Limits', [1 10]);

            app.CompResultsText = uitextarea(app.CompGrid, 'Value', {'Optimize to see results.'}, 'Editable', 'off');
            app.CompResultsText.Layout.Row = 2; app.CompResultsText.Layout.Column = [1 2];

            app.CompStepAxes = uiaxes(app.CompGrid);
            app.CompStepAxes.Layout.Row = 3; app.CompStepAxes.Layout.Column = [1 2];
            title(app.CompStepAxes, 'Composite → Equity Weight Step Function');

            % Risk Budget Panel
            app.RiskBudgetPanel = uipanel(app.StrategyGrid, 'Title', 'Risk Budget Strategy', 'Visible', 'off');
            app.RBGrid = uigridlayout(app.RiskBudgetPanel, [3 1]);
            app.RBGrid.RowHeight = {'0.35x', 'fit', '0.5x'};

            app.RBTable = uitable(app.RBGrid, ...
                'ColumnName', {'Signal','Budget','Translation'}, ...
                'ColumnEditable', [false true true], ...
                'ColumnFormat', {'char', 'numeric', {'Linear','Threshold','Sigmoid','Quantile'}});

            macroRow = uigridlayout(app.RBGrid, [1 5]);
            macroRow.ColumnWidth = {'fit','fit','fit','1x','fit'}; macroRow.Padding = [0 0 0 0]; macroRow.ColumnSpacing = 6;
            app.RBMacroCondCheck = uicheckbox(macroRow, 'Text', 'Macro Cond.');
            uilabel(macroRow, 'Text', 'Variable:');
            app.RBMacroVarDrop = uidropdown(macroRow, 'Items', {'YieldSlope','VIX','HY_Spread','GDP_YoY'});
            uilabel(macroRow, 'Text', '');
            uilabel(macroRow, 'Text', 'Thresh:');
            app.RBMacroThreshField = uieditfield(app.RBGrid, 'numeric', 'Value', 0);

            app.RBStackedAxes = uiaxes(app.RBGrid);
            title(app.RBStackedAxes, 'Per-Signal Allocation (Stacked)');

            % Decision Tree Panel
            app.DecisionTreePanel = uipanel(app.StrategyGrid, 'Title', 'Decision Tree Strategy', 'Visible', 'off');
            app.DTGrid = uigridlayout(app.DecisionTreePanel, [4 2]);
            app.DTGrid.RowHeight = {'fit','0.35x','0.35x','fit'};
            app.DTGrid.ColumnWidth = {'1x','1x'};

            dtCtrlGrid = uigridlayout(app.DTGrid, [1 6]);
            dtCtrlGrid.Layout.Row = 1; dtCtrlGrid.Layout.Column = [1 2];
            dtCtrlGrid.ColumnWidth = {'fit','fit','fit','fit','fit','fit'}; dtCtrlGrid.Padding = [0 0 0 0]; dtCtrlGrid.ColumnSpacing = 6;
            uilabel(dtCtrlGrid, 'Text', 'Mode:');
            app.DTModeDropDown = uidropdown(dtCtrlGrid, 'Items', {'AutoOptimize','RuleBased'});
            uilabel(dtCtrlGrid, 'Text', 'Depth:');
            app.DTDepthField = uieditfield(dtCtrlGrid, 'numeric', 'Value', 3, 'Limits', [1 8]);
            uilabel(dtCtrlGrid, 'Text', 'Min Leaf:');
            app.DTLeafField = uieditfield(dtCtrlGrid, 'numeric', 'Value', 50, 'Limits', [10 500]);

            app.DTRulesTable = uitable(app.DTGrid, ...
                'ColumnName', {'Variable','Operator','Threshold','EqWeight'}, ...
                'ColumnEditable', [true true true true], ...
                'ColumnFormat', {'char', {'>', '>=', '<', '<=', '=='}, 'numeric', 'numeric'});
            app.DTRulesTable.Layout.Row = 2; app.DTRulesTable.Layout.Column = 1;

            app.DTRulesText = uitextarea(app.DTGrid, 'Value', {'Tree rules will appear here.'}, 'Editable', 'off');
            app.DTRulesText.Layout.Row = 2; app.DTRulesText.Layout.Column = 2;

            app.DTImportanceAxes = uiaxes(app.DTGrid);
            app.DTImportanceAxes.Layout.Row = 3; app.DTImportanceAxes.Layout.Column = [1 2];
            title(app.DTImportanceAxes, 'Variable Importance');

            app.DTAutoOptButton = uibutton(app.DTGrid, 'Text', 'Auto-Optimize Tree', ...
                'BackgroundColor', [0.3 0.5 0.85], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) onOptimize(app));
            app.DTAutoOptButton.Layout.Row = 4; app.DTAutoOptButton.Layout.Column = [1 2];
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

        %% ---- Strategy Mode Changed ----
        function onStrategyModeChanged(app)
            mode = app.StrategyDropDown.Value;
            app.CompositePanel.Visible    = 'off';
            app.RiskBudgetPanel.Visible   = 'off';
            app.DecisionTreePanel.Visible = 'off';

            switch mode
                case 'Composite'
                    app.CompositePanel.Visible = 'on';
                case 'Risk Budget'
                    app.RiskBudgetPanel.Visible = 'on';
                case 'Decision Tree'
                    app.DecisionTreePanel.Visible = 'on';
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
                        opts = struct();
                        opts.nThresh    = app.CompThreshField.Value;
                        opts.alphaObj   = app.CompAlphaField.Value;
                        opts.betaObj    = app.CompBetaField.Value;
                        opts.gammaObj   = app.CompGammaField.Value;
                        opts.rebalFreq  = rebalFreq;
                        opts.txCost     = txCost;

                        result = sigstrat.optimizeComposite(app.SignalData, app.SignalNames, app.MktData, opts);
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
                        opts.mode       = app.DTModeDropDown.Value;
                        opts.maxDepth   = app.DTDepthField.Value;
                        opts.minLeafSize = app.DTLeafField.Value;
                        opts.rebalFreq  = rebalFreq;
                        opts.txCost     = txCost;

                        if strcmp(opts.mode, 'RuleBased')
                            opts.rules = readDTRules(app);
                        end

                        result = sigstrat.decisionTreeStrategy(app.SignalData, app.SignalNames, app.MktData, app.MacroData, opts);
                        app.StrategyResult = result;
                        app.EqWts = result.eqWts;

                        updateDecisionTreeResults(app, result);
                end

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

            % Composite weights table
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
            lines{end+1} = sprintf('Thresholds: %s', mat2str(round(result.thresholds', 3)));
            lines{end+1} = sprintf('Equity Levels: %s', mat2str(round(result.eqLevels', 2)));
            lines{end+1} = '';
            lines{end+1} = sprintf('In-Sample:  Sharpe=%.2f, Return=%.1f%%, MaxDD=%.1f%%', ...
                result.inPerf.sharpe, result.inPerf.annReturn*100, result.inPerf.maxDD*100);
            if isfield(result.outPerf, 'sharpe') && isfinite(result.outPerf.sharpe)
                lines{end+1} = sprintf('Out-Sample: Sharpe=%.2f, Return=%.1f%%, MaxDD=%.1f%%', ...
                    result.outPerf.sharpe, result.outPerf.annReturn*100, result.outPerf.maxDD*100);
            end
            app.CompResultsText.Value = lines;

            % Step function plot
            cla(app.CompStepAxes);
            plot(app.CompStepAxes, result.stepFcnX, result.stepFcnY * 100, 'b-', 'LineWidth', 2);
            xlabel(app.CompStepAxes, 'Composite Signal');
            ylabel(app.CompStepAxes, 'Equity Weight (%)');
            title(app.CompStepAxes, 'Composite → Equity Weight Step Function');
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
                    caxis(app.MonthlyHeatmapAxes, [-8 8]); %#ok<CAXIS>
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
                tblData{i, 2} = datestr(st.StartDate(i), 'yyyy-mm-dd'); %#ok<DATST>
                tblData{i, 3} = datestr(st.EndDate(i), 'yyyy-mm-dd');   %#ok<DATST>
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
