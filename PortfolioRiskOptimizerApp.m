classdef PortfolioRiskOptimizerApp < matlab.apps.AppBase
    % PortfolioRiskOptimizerApp - GUI for Portfolio Risk, SAA/TAA, and Conditional Bootstrap
    % Features:
    %  - SAA & TAA with Combined weights (TAA = active deltas on top of SAA)
    %  - VaR/CVaR (Historical, Parametric, Monte Carlo)
    %  - Sensitivity (+1% per-asset shock), Scenarios (approx PnL)
    %  - Optimizers: Min Var, Max Sharpe, Min CVaR, Min VaR, Risk Parity (ERC)
    %  - Conditional historical bootstrap via logical expressions over measures
    %  - NEW: TAA asset list & Add/Remove, Tracking Error + Attribution, Performance tab
    %
    % Requirements: Optimization Toolbox (fmincon/quadprog). GA optional.

    %================ UI COMPONENTS ================
    properties (Access = public)
        UIFigure            matlab.ui.Figure
        Grid                matlab.ui.container.GridLayout
        LeftPanel           matlab.ui.container.Panel
        RightPanel          matlab.ui.container.Panel

        LeftGrid            matlab.ui.container.GridLayout
        LoadCSVButton       matlab.ui.control.Button
        SampleDataButton    matlab.ui.control.Button
        DataTypeDropDown    matlab.ui.control.DropDown
        FreqDropDown        matlab.ui.control.DropDown
        VaRLabel            matlab.ui.control.Label
        VaRMethodDropDown   matlab.ui.control.DropDown
        AlphaField          matlab.ui.control.NumericEditField
        HorizonField        matlab.ui.control.NumericEditField

        ObjectiveLabel      matlab.ui.control.Label
        ObjectiveDropDown   matlab.ui.control.DropDown
        RiskFreeField       matlab.ui.control.NumericEditField
        TargetRetLabel      matlab.ui.control.Label
        TargetRetField      matlab.ui.control.NumericEditField

        LongOnlyCheck       matlab.ui.control.CheckBox
        LBField             matlab.ui.control.NumericEditField
        UBField             matlab.ui.control.NumericEditField

        OptimizerLabel      matlab.ui.control.Label
        OptimizerDropDown   matlab.ui.control.DropDown

        AssetsLabel         matlab.ui.control.Label
        AssetsList          matlab.ui.control.ListBox
        CurrenciesLabel     matlab.ui.control.Label
        CurrenciesList      matlab.ui.control.ListBox

        ComputeRiskButton   matlab.ui.control.Button
        OptimizeButton      matlab.ui.control.Button
        ExportWeightsButton matlab.ui.control.Button

        RightGrid           matlab.ui.container.GridLayout
        TabGroup            matlab.ui.container.TabGroup

        SummaryTab          matlab.ui.container.Tab
        DistributionTab     matlab.ui.container.Tab
        SensitivityTab      matlab.ui.container.Tab
        ScenariosTab        matlab.ui.container.Tab
        DataTab             matlab.ui.container.Tab

        % Allocation split tabs
        AllocationTab       matlab.ui.container.Tab  % SAA tab
        TAATab              matlab.ui.container.Tab  % TAA tab
        CombinedTab         matlab.ui.container.Tab  % Combined tab
        PerformanceTab      matlab.ui.container.Tab  % NEW Performance tab

        % Summary
        SummaryGrid         matlab.ui.container.GridLayout
        SummaryText         matlab.ui.control.TextArea
        WeightsTable        matlab.ui.control.Table

        % Plots
        DistAxes            matlab.ui.control.UIAxes
        SensAxes            matlab.ui.control.UIAxes

        % Scenarios
        ScenGrid            matlab.ui.container.GridLayout
        ScenLabel           matlab.ui.control.Label
        ScenTable           matlab.ui.control.Table

        % Data view
        DataTable           matlab.ui.control.Table

        % SAA tab
        AllocGrid           matlab.ui.container.GridLayout
        SAALabel            matlab.ui.control.Label
        SAATable            matlab.ui.control.Table
        NormalizeCheck      matlab.ui.control.CheckBox
        ResetSAAButton      matlab.ui.control.Button
        SAAMetricsText      matlab.ui.control.TextArea
        SAAStressTable      matlab.ui.control.Table

        % TAA tab
        TAAGrid             matlab.ui.container.GridLayout
        TAALabel            matlab.ui.control.Label
        TAAAssetsList       matlab.ui.control.ListBox
        TAAButtonsGrid      matlab.ui.container.GridLayout
        TAAAddButton        matlab.ui.control.Button
        TAARemoveButton     matlab.ui.control.Button
        TAAAddTradeBtn      matlab.ui.control.Button
        TAATradeLabel       matlab.ui.control.Label
        TAATradeTable       matlab.ui.control.Table
        TAATable            matlab.ui.control.Table
        ApplyTAAButton      matlab.ui.control.Button

        % Combined tab
        CombGrid            matlab.ui.container.GridLayout
        CombLabel           matlab.ui.control.Label
        CombinedTable       matlab.ui.control.Table
        TELabel             matlab.ui.control.Label
        TETable             matlab.ui.control.Table

        % Bootstrap tab
        BootstrapTab        matlab.ui.container.Tab
        BootGrid            matlab.ui.container.GridLayout
        LoadMeasuresButton  matlab.ui.control.Button
        MeasuresInfoLabel   matlab.ui.control.Label
        ConditionLabel      matlab.ui.control.Label
        ConditionText       matlab.ui.control.TextArea
        ConditionHelp       matlab.ui.control.Label
        BlockLenField       matlab.ui.control.NumericEditField
        PathsField          matlab.ui.control.NumericEditField
        RunBootstrapButton  matlab.ui.control.Button
        BootstrapSummary    matlab.ui.control.TextArea
        BootstrapAxes       matlab.ui.control.UIAxes
        BootCondAxes        matlab.ui.control.UIAxes
        % Bootstrap condition builder
        BootCondTable       matlab.ui.control.Table
        BootStatsTable      matlab.ui.control.Table
        BootAddCondBtn      matlab.ui.control.Button
        BootRemoveCondBtn   matlab.ui.control.Button
        BootCondLogicDrop   matlab.ui.control.DropDown

        % Performance tab
        PerfGrid            matlab.ui.container.GridLayout
        PerfRollingLabel    matlab.ui.control.Label
        PerfRollingField    matlab.ui.control.NumericEditField
        PerfTable           matlab.ui.control.Table
        % Performance charts
        PerfAxesCum       matlab.ui.control.UIAxes
        PerfAxesVol       matlab.ui.control.UIAxes

        GenerateReportBtn   matlab.ui.control.Button
        SaveSessionButton   matlab.ui.control.Button
        LoadSessionButton   matlab.ui.control.Button
        CustomTickerField   matlab.ui.control.EditField
        AddTickerButton     matlab.ui.control.Button
        StatusLabel         matlab.ui.control.Label

        % Market data download
        DownloadDataButton  matlab.ui.control.Button
        BloombergButton     matlab.ui.control.Button
        DatastreamButton    matlab.ui.control.Button
        StartDateField      matlab.ui.control.EditField
        EndDateField        matlab.ui.control.EditField
        DownloadMeasuresButton matlab.ui.control.Button

        % Correlation tab
        CorrelationTab      matlab.ui.container.Tab
        CorrGrid            matlab.ui.container.GridLayout
        CorrAxes            matlab.ui.control.UIAxes
        CorrRollAxes        matlab.ui.control.UIAxes
        CorrWindowField     matlab.ui.control.NumericEditField

        % Efficient Frontier tab
        FrontierTab         matlab.ui.container.Tab
        FrontierGrid        matlab.ui.container.GridLayout
        FrontierAxes        matlab.ui.control.UIAxes
        FrontierPointsField matlab.ui.control.NumericEditField
        ComputeFrontierBtn  matlab.ui.control.Button

        % Drawdown (Performance tab extension)
        PerfAxesDD          matlab.ui.control.UIAxes

        % Stress testing (Scenarios tab extension)
        LoadStressButton    matlab.ui.control.Button
        ScenarioDropDown    matlab.ui.control.DropDown
        ScenStatsText       matlab.ui.control.TextArea

        % CMA tab
        CMATab              matlab.ui.container.Tab
        CMAGrid             matlab.ui.container.GridLayout
        CMAMethodDropDown   matlab.ui.control.DropDown
        CMALookbackField    matlab.ui.control.NumericEditField
        ComputeCMABtn       matlab.ui.control.Button
        CMARetVolTable      matlab.ui.control.Table
        CMACorrTable        matlab.ui.control.Table
        UseCMAButton        matlab.ui.control.Button

        % FX overlay display (SAA tab)
        SAAFundedLabel      matlab.ui.control.Label
        SAAFXLabel          matlab.ui.control.Label
        SAAFXTable          matlab.ui.control.Table
        FXExposureText      matlab.ui.control.TextArea

        % FX overlay display (Combined tab)
        CombFundedLabel     matlab.ui.control.Label
        CombFXLabel         matlab.ui.control.Label
        CombFXTable         matlab.ui.control.Table
        CombAnalyticsText   matlab.ui.control.TextArea

        % Risk Decomp tab
        RiskDecompTab       matlab.ui.container.Tab
        RiskDecompGrid      matlab.ui.container.GridLayout
        RiskBudgetTable     matlab.ui.control.Table
        ConcentrationText   matlab.ui.control.TextArea
        RiskWaterfallAxes   matlab.ui.control.UIAxes
        FactorExposureTable matlab.ui.control.Table
        FactorVsSpecificText matlab.ui.control.TextArea
        RollingFactorAxes   matlab.ui.control.UIAxes
        FactorWindowField   matlab.ui.control.NumericEditField

        % Enhanced tabs
        FactorSensAxes      matlab.ui.control.UIAxes
        EigenTable          matlab.ui.control.Table
        FrontierDistLabel   matlab.ui.control.Label
    end

    %================ STATE ================
    properties (Access = private)
        R double = []                 % T x N returns
        Dates                        % T x 1 datetime or numeric index
        AssetNames cell = {}          % 1 x N asset names
        W double = []                 % N x 1 weights used for risk (Combined SAA+TAA)

        Freq char = 'Daily'
        DataType char = 'Prices'
        Alpha double = 0.95
        Horizon double = 1
        RF double = 0.00
        LongOnly logical = true
        LB double = 0
        UB double = 1
        Optimizer char = 'auto'
        Objective char = 'Max Sharpe'
        TargetRet double = NaN
        Scenarios table = table()

        % Allocations
        SAA table = table()           % Asset, WeightPct, Description
        TAA table = table()           % Asset, DeltaPct, Description
        NormalizeCombined logical = true

        % Measures for bootstrap
        Measures table = table()
        LastBootstrapDist double = []

        RandSeed double = 42
        MCPaths double = 20000

        % Asset ETF map (Nx2 cell: {name, 'TICKER (desc)'})
        AssetETFMap cell = {}

        % Risk Decomp state
        FactorBetas    double = []
        FactorR2       double = NaN
        FactorNames    cell = {}
        FactorResidVar double = NaN
    end

    %================ CONSTRUCTOR ================
    methods (Access = public)
        function app = PortfolioRiskOptimizerApp
            createComponents(app);
            rng(app.RandSeed);
        end
    end

    %================ UI CREATION ================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','Portfolio Risk & Optimization App','Position',[50 50 1560 980]);
            app.Grid = uigridlayout(app.UIFigure,[1 2]);
            app.Grid.ColumnWidth = {340,'1x'};
            app.Grid.Padding = [0 0 0 0]; app.Grid.ColumnSpacing = 2;

            % Left panel — scrollable
            app.LeftPanel = uipanel(app.Grid,'Title','Controls','FontWeight','bold');
            app.LeftPanel.Layout.Row = 1; app.LeftPanel.Layout.Column = 1;
            app.LeftGrid = uigridlayout(app.LeftPanel,[39 1]);
            app.LeftGrid.RowHeight = [ ...
                {'fit'}    ... % 1  DATA header
                {28}       ... % 2  Load CSV
                {28}       ... % 3  Sample Data
                {28}       ... % 4  Download Market Data (Stooq)
                {'fit'}    ... % 5  Bloomberg / Datastream row
                {'fit'}    ... % 6  Start/End date row
                {28}       ... % 7  Download FRED
                {'fit'}    ... % 8  DataType/Freq row
                {'fit'}    ... % 9  Add Custom Ticker row
                {'fit'}    ... % 10 Save/Load session row
                {4}        ... % 11 spacer
                {'fit'}    ... % 9  ASSETS header
                {90}       ... % 10 Asset listbox
                {'fit'}    ... % 11 OVERLAYS header
                {70}       ... % 12 Overlay listbox
                {4}        ... % 13 spacer
                {'fit'}    ... % 14 ACTIONS header
                {34}       ... % 15 Compute Risk
                {34}       ... % 16 Optimize Weights
                {28}       ... % 17 Export Weights
                {28}       ... % 18 Generate Report
                {4}        ... % 19 spacer
                {'fit'}    ... % 19 OPTIMIZATION header
                {'fit'}    ... % 20 Objective/Optimizer row
                {'fit'}    ... % 21 Rf / Target row
                {'fit'}    ... % 22 Bounds row
                {4}        ... % 23 spacer
                {'fit'}    ... % 24 RISK header
                {'fit'}    ... % 25 VaR Method dropdown
                {'fit'}    ... % 26 Alpha/Horizon row
                repmat({'fit'},1,10) ... % 27-36 reserve
            ];
            app.LeftGrid.Padding = [10 10 10 10];
            app.LeftGrid.RowSpacing = 3;

            % ========== 1. DATA LOADING ==========
            uilabel(app.LeftGrid,'Text','DATA','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);

            app.LoadCSVButton = uibutton(app.LeftGrid,'Text','Load Returns / Prices CSV', ...
                'ButtonPushedFcn',@(s,e)onLoadCSV(app),'Icon','');
            app.SampleDataButton = uibutton(app.LeftGrid,'Text','Use Sample Data', ...
                'ButtonPushedFcn',@(s,e)onUseSample(app));
            app.DownloadDataButton = uibutton(app.LeftGrid,'Text','Download Market Data (Stooq)', ...
                'ButtonPushedFcn',@(s,e)onLoadMarketData(app));

            bbgDsRow = uigridlayout(app.LeftGrid,[1 2]);
            bbgDsRow.ColumnWidth = {'1x','1x'}; bbgDsRow.Padding = [0 0 0 0]; bbgDsRow.ColumnSpacing = 4;
            app.BloombergButton = uibutton(bbgDsRow,'Text','Bloomberg', ...
                'ButtonPushedFcn',@(s,e)onLoadBloomberg(app));
            app.DatastreamButton = uibutton(bbgDsRow,'Text','Datastream', ...
                'ButtonPushedFcn',@(s,e)onLoadDatastream(app));

            dateRow = uigridlayout(app.LeftGrid,[1 4]);
            dateRow.ColumnWidth = {'fit','1x','fit','1x'}; dateRow.Padding = [0 0 0 0]; dateRow.ColumnSpacing = 4;
            uilabel(dateRow,'Text','Start:');
            app.StartDateField = uieditfield(dateRow,'text','Value','20100101');
            uilabel(dateRow,'Text','End:');
            app.EndDateField = uieditfield(dateRow,'text','Value',datestr(datetime('today'),'yyyymmdd')); %#ok<DATST>

            app.DownloadMeasuresButton = uibutton(app.LeftGrid,'Text','Download Measures (FRED)', ...
                'ButtonPushedFcn',@(s,e)onDownloadMeasures(app));

            dtRow = uigridlayout(app.LeftGrid,[1 4]);
            dtRow.ColumnWidth = {'fit','1x','fit','1x'}; dtRow.Padding = [0 0 0 0]; dtRow.ColumnSpacing = 4;
            uilabel(dtRow,'Text','Type:');
            app.DataTypeDropDown = uidropdown(dtRow,'Items',{'Prices','Returns'},'Value',app.DataType, ...
                'ValueChangedFcn',@(s,e)setField(app,'DataType',s.Value));
            uilabel(dtRow,'Text','Freq:');
            app.FreqDropDown = uidropdown(dtRow,'Items',{'Daily','Weekly','Monthly'},'Value',app.Freq, ...
                'ValueChangedFcn',@(s,e)setField(app,'Freq',s.Value));

            % Add Custom Ticker row
            tickerRow = uigridlayout(app.LeftGrid,[1 2]);
            tickerRow.ColumnWidth = {'1x',60}; tickerRow.Padding = [0 0 0 0]; tickerRow.ColumnSpacing = 4;
            app.CustomTickerField = uieditfield(tickerRow,'text','Value','','Placeholder','ETF ticker, e.g. tlt.us');
            app.AddTickerButton = uibutton(tickerRow,'Text','+ Add', ...
                'ButtonPushedFcn',@(s,e)onAddCustomTicker(app));

            % Save / Load session row
            slRow = uigridlayout(app.LeftGrid,[1 2]);
            slRow.ColumnWidth = {'1x','1x'}; slRow.Padding = [0 0 0 0]; slRow.ColumnSpacing = 4;
            app.SaveSessionButton = uibutton(slRow,'Text','Save Session', ...
                'ButtonPushedFcn',@(s,e)onSaveSession(app));
            app.LoadSessionButton = uibutton(slRow,'Text','Load Session', ...
                'ButtonPushedFcn',@(s,e)onLoadSession(app));

            % spacer
            uilabel(app.LeftGrid,'Text','');

            % ========== 2. ASSETS (visible right after loading) ==========
            app.AssetsLabel = uilabel(app.LeftGrid,'Text','ASSETS (funded)','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);
            app.AssetsList = uilistbox(app.LeftGrid,'Items',{},'Multiselect','on');
            app.CurrenciesLabel = uilabel(app.LeftGrid,'Text','OVERLAYS (incl. FX pairs)','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);
            app.CurrenciesList = uilistbox(app.LeftGrid,'Items',{},'Multiselect','on');

            % spacer
            uilabel(app.LeftGrid,'Text','');

            % ========== 3. ACTIONS (prominent, mid-panel) ==========
            uilabel(app.LeftGrid,'Text','ACTIONS','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);
            app.ComputeRiskButton = uibutton(app.LeftGrid,'Text','Compute Risk', ...
                'ButtonPushedFcn',@(s,e)onCompute(app), ...
                'BackgroundColor',[0.82 0.90 1.0],'FontWeight','bold','FontSize',13);
            app.OptimizeButton = uibutton(app.LeftGrid,'Text','Optimize Weights', ...
                'ButtonPushedFcn',@(s,e)onOptimize(app), ...
                'BackgroundColor',[0.82 0.96 0.82],'FontWeight','bold','FontSize',13);
            app.ExportWeightsButton = uibutton(app.LeftGrid,'Text','Export Weights CSV', ...
                'ButtonPushedFcn',@(s,e)onExportWeights(app));
            app.GenerateReportBtn = uibutton(app.LeftGrid,'Text','Generate PDF Report', ...
                'ButtonPushedFcn',@(s,e)onGenerateReport(app), ...
                'BackgroundColor',[0.95 0.90 0.78],'FontWeight','bold');

            % spacer
            uilabel(app.LeftGrid,'Text','');

            % ========== 4. OPTIMIZATION SETTINGS ==========
            uilabel(app.LeftGrid,'Text','OPTIMIZATION','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);

            objRow = uigridlayout(app.LeftGrid,[1 2]);
            objRow.ColumnWidth = {'1x','1x'}; objRow.Padding = [0 0 0 0]; objRow.ColumnSpacing = 6;
            app.ObjectiveDropDown = uidropdown(objRow,'Items', ...
                {'Min Variance','Max Sharpe','Equal Weight','Target Vol','Min CVaR (hist)','Min VaR (hist)','Risk Parity (ERC)','Black-Litterman'}, ...
                'Value',app.Objective,'ValueChangedFcn',@(s,e)setField(app,'Objective',s.Value));
            app.OptimizerDropDown = uidropdown(objRow,'Items',{'auto','quadprog','fmincon','ga'}, ...
                'Value',app.Optimizer,'ValueChangedFcn',@(s,e)setField(app,'Optimizer',s.Value));

            rfTargRow = uigridlayout(app.LeftGrid,[1 4]);
            rfTargRow.ColumnWidth = {'fit','1x','fit','1x'}; rfTargRow.Padding = [0 0 0 0]; rfTargRow.ColumnSpacing = 4;
            uilabel(rfTargRow,'Text','Rf:');
            app.RiskFreeField = uieditfield(rfTargRow,'numeric','Value',app.RF,'ValueDisplayFormat','%.4f', ...
                'ValueChangedFcn',@(s,e)setField(app,'RF',s.Value));
            uilabel(rfTargRow,'Text','Target:');
            app.TargetRetField = uieditfield(rfTargRow,'numeric','Value',0,'Limits',[-Inf Inf],'ValueDisplayFormat','%.6f', ...
                'ValueChangedFcn',@(s,e)setTargetRet(app,s.Value));

            boundsRow = uigridlayout(app.LeftGrid,[1 6]);
            boundsRow.ColumnWidth = {'fit','fit',50,'fit',50,'1x'}; boundsRow.Padding = [0 0 0 0]; boundsRow.ColumnSpacing = 4;
            app.LongOnlyCheck = uicheckbox(boundsRow,'Text','Long-only','Value',app.LongOnly, ...
                'ValueChangedFcn',@(s,e)setField(app,'LongOnly',s.Value));
            uilabel(boundsRow,'Text','LB:');
            app.LBField = uieditfield(boundsRow,'numeric','Value',app.LB,'ValueDisplayFormat','%.2f', ...
                'ValueChangedFcn',@(s,e)setField(app,'LB',s.Value));
            uilabel(boundsRow,'Text','UB:');
            app.UBField = uieditfield(boundsRow,'numeric','Value',app.UB,'ValueDisplayFormat','%.2f', ...
                'ValueChangedFcn',@(s,e)setField(app,'UB',s.Value));
            uilabel(boundsRow,'Text',''); % fill

            % spacer
            uilabel(app.LeftGrid,'Text','');

            % ========== 5. RISK SETTINGS ==========
            uilabel(app.LeftGrid,'Text','RISK','FontWeight','bold','FontSize',12,'FontColor',[0.15 0.25 0.55]);

            app.VaRMethodDropDown = uidropdown(app.LeftGrid,'Items', ...
                {'Historical','Parametric (Normal)','Monte Carlo (Normal)'},'Value','Historical');

            alphaRow = uigridlayout(app.LeftGrid,[1 4]);
            alphaRow.ColumnWidth = {'fit','1x','fit','1x'}; alphaRow.Padding = [0 0 0 0]; alphaRow.ColumnSpacing = 4;
            uilabel(alphaRow,'Text','Alpha:');
            app.AlphaField = uieditfield(alphaRow,'numeric','Value',app.Alpha,'Limits',[0.5 0.999], ...
                'LowerLimitInclusive','on','UpperLimitInclusive','off', ...
                'ValueChangedFcn',@(s,e)setField(app,'Alpha',s.Value));
            uilabel(alphaRow,'Text','Horizon:');
            app.HorizonField = uieditfield(alphaRow,'numeric','Value',app.Horizon,'Limits',[1 252], ...
                'ValueDisplayFormat','%.0f','ValueChangedFcn',@(s,e)setField(app,'Horizon',s.Value));

            % ==================== RIGHT PANEL ====================
            app.RightPanel = uipanel(app.Grid,'Title','Analysis','FontWeight','bold');
            app.RightPanel.Layout.Row = 1; app.RightPanel.Layout.Column = 2;
            app.RightGrid = uigridlayout(app.RightPanel,[1 1]);
            app.RightGrid.Padding = [4 4 4 4];

            app.TabGroup = uitabgroup(app.RightGrid);
            % --- Core ---
            app.SummaryTab      = uitab(app.TabGroup,'Title','Summary');
            app.DistributionTab = uitab(app.TabGroup,'Title','Distribution');
            app.SensitivityTab  = uitab(app.TabGroup,'Title','Sensitivity');
            app.ScenariosTab    = uitab(app.TabGroup,'Title','Stress');
            app.DataTab         = uitab(app.TabGroup,'Title','Data');
            % --- Allocation ---
            app.AllocationTab   = uitab(app.TabGroup,'Title','SAA');
            app.TAATab          = uitab(app.TabGroup,'Title','TAA');
            app.CombinedTab     = uitab(app.TabGroup,'Title','Combined');
            % --- Analytics ---
            app.PerformanceTab  = uitab(app.TabGroup,'Title','Perf');
            app.BootstrapTab    = uitab(app.TabGroup,'Title','Bootstrap');
            app.CorrelationTab  = uitab(app.TabGroup,'Title','Corr');
            app.FrontierTab     = uitab(app.TabGroup,'Title','Frontier');
            app.RiskDecompTab   = uitab(app.TabGroup,'Title','RiskDecomp');

            % ===== Summary tab =====
            app.SummaryGrid = uigridlayout(app.SummaryTab,[2 1]);
            app.SummaryGrid.RowHeight = {220,'1x'};
            app.SummaryGrid.Padding = [8 8 8 8]; app.SummaryGrid.RowSpacing = 6;
            app.SummaryText = uitextarea(app.SummaryGrid,'Editable','off', ...
                'FontName','Consolas','FontSize',11,'Value',{'Load data to begin...'});
            app.WeightsTable = uitable(app.SummaryGrid,'Data',table(),'ColumnWidth','auto','FontSize',11);

            % ===== Distribution tab =====
            distGrid = uigridlayout(app.DistributionTab,[1 1]);
            distGrid.Padding = [8 8 8 8];
            app.DistAxes = uiaxes(distGrid,'Box','on');
            title(app.DistAxes,'Portfolio Return Distribution');
            xlabel(app.DistAxes,'Return'); ylabel(app.DistAxes,'Frequency');
            app.DistAxes.XGrid='on'; app.DistAxes.YGrid='on';

            % ===== Sensitivity tab (2-row: asset shock + factor sensitivity) =====
            sensGrid = uigridlayout(app.SensitivityTab,[2 1]);
            sensGrid.Padding = [8 8 8 8]; sensGrid.RowHeight = {'1x','1x'};
            app.SensAxes = uiaxes(sensGrid,'Box','on');
            title(app.SensAxes,'dPnL for +1% Asset Shock');
            xlabel(app.SensAxes,'Asset'); ylabel(app.SensAxes,'Delta PnL');
            app.SensAxes.XGrid='on'; app.SensAxes.YGrid='on';
            app.FactorSensAxes = uiaxes(sensGrid,'Box','on');
            title(app.FactorSensAxes,'Portfolio PnL Impact: +1% Factor Move');
            xlabel(app.FactorSensAxes,'Factor'); ylabel(app.FactorSensAxes,'PnL Impact');
            app.FactorSensAxes.XGrid='on'; app.FactorSensAxes.YGrid='on';

            % ===== Stress / Scenarios tab =====
            app.ScenGrid = uigridlayout(app.ScenariosTab,[3 1]);
            app.ScenGrid.RowHeight = {'fit','1x',100};
            app.ScenGrid.Padding = [8 8 8 8]; app.ScenGrid.RowSpacing = 6;
            scenTopRow = uigridlayout(app.ScenGrid,[1 4]);
            scenTopRow.ColumnWidth = {'fit','fit','fit','1x'}; scenTopRow.Padding = [0 0 0 0]; scenTopRow.ColumnSpacing = 8;
            app.ScenLabel = uilabel(scenTopRow,'Text','Scenario:');
            app.ScenarioDropDown = uidropdown(scenTopRow, ...
                'Items',{'(Select episode)','All Historical','GFC (Oct 2008)','COVID (Mar 2020)','Rate Shock (2022)','EM Crisis (1998)','Inflation Spike','USD Surge'}, ...
                'Value','(Select episode)', ...
                'ValueChangedFcn',@(s,e)onScenarioDropDownChanged(app,s.Value));
            app.LoadStressButton = uibutton(scenTopRow,'Text','Load All Stresses', ...
                'ButtonPushedFcn',@(s,e)loadHistoricalStresses(app));
            uilabel(scenTopRow,'Text','Returns as decimals (e.g. -0.05 = -5%)','FontSize',10,'FontColor',[0.4 0.4 0.4]);
            app.ScenTable = uitable(app.ScenGrid,'Data',table(),'ColumnEditable',true,'FontSize',11);
            app.ScenTable.CellEditCallback = @(s,e) onScenarioChanged(app);
            % Portfolio scenario stats
            app.ScenStatsText = uitextarea(app.ScenGrid,'Editable','off','FontName','Consolas','FontSize',11);

            % ===== Data tab =====
            dataGrid = uigridlayout(app.DataTab,[1 1]);
            dataGrid.Padding = [8 8 8 8];
            app.DataTable = uitable(dataGrid,'Data',table(),'FontSize',10);

            % ===== SAA tab (10-row layout with FX overlay split) =====
            app.AllocGrid = uigridlayout(app.AllocationTab,[10 1]);
            app.AllocGrid.RowHeight = {'fit','1x','fit',100,50,'fit','fit',100,'fit','1x'};
            app.AllocGrid.Padding = [8 8 8 8]; app.AllocGrid.RowSpacing = 5;
            % Row 1: Funded label
            app.SAAFundedLabel = uilabel(app.AllocGrid,'Text','Funded Allocations (sum to 100%)','FontWeight','bold');
            % Row 2: Funded assets table (hidden master SAATable still exists as data source)
            app.SAATable = uitable(app.AllocGrid,'Data',table(),'ColumnEditable',[true true true],'FontSize',11);
            app.SAATable.ColumnName = {'Asset','WeightPct','Description'};
            app.SAATable.CellEditCallback = @(s,e)onSAATableEdited(app);
            % Row 3: FX Overlay label
            app.SAAFXLabel = uilabel(app.AllocGrid,'Text','Overlay Positions (no sum constraint)','FontWeight','bold');
            % Row 4: FX overlay table
            app.SAAFXTable = uitable(app.AllocGrid,'Data',table(),'ColumnEditable',[true true true],'FontSize',11);
            app.SAAFXTable.ColumnName = {'Asset','WeightPct','Description'};
            app.SAAFXTable.CellEditCallback = @(s,e)onSAAFXTableEdited(app);
            % Row 5: FX exposure summary
            app.FXExposureText = uitextarea(app.AllocGrid,'Editable','off','FontName','Consolas','FontSize',11, ...
                'Value',{'Gross FX: 0.0%  Net FX: 0.0%'});
            % Row 6: Normalize + Reset buttons
            saaBottomRow = uigridlayout(app.AllocGrid,[1 2]);
            saaBottomRow.ColumnWidth = {'1x','fit'}; saaBottomRow.Padding = [0 0 0 0];
            app.NormalizeCheck = uicheckbox(saaBottomRow,'Text','Normalize Combined to 100%','Value',true, ...
                'ValueChangedFcn',@(s,e)setField(app,'NormalizeCombined',s.Value));
            app.ResetSAAButton = uibutton(saaBottomRow,'Text','Reset SAA to Default', ...
                'ButtonPushedFcn',@(s,e)resetSAA(app));
            % Row 7: SAA Analytics label
            app.SAALabel = uilabel(app.AllocGrid,'Text','SAA Risk / Return Analytics','FontWeight','bold');
            % Row 8: SAA metrics
            app.SAAMetricsText = uitextarea(app.AllocGrid,'Editable','off','FontName','Consolas','FontSize',11);
            % Row 9: Stress label
            uilabel(app.AllocGrid,'Text','SAA Stress Scenario Performance','FontWeight','bold');
            % Row 10: Stress table
            app.SAAStressTable = uitable(app.AllocGrid,'Data',table(),'ColumnEditable',false,'FontSize',11);

            % ===== TAA tab =====
            app.TAAGrid = uigridlayout(app.TAATab,[6 1]);
            app.TAAGrid.RowHeight = {'fit',90,'fit','2x','fit','1x'};
            app.TAAGrid.Padding = [8 8 8 8]; app.TAAGrid.RowSpacing = 6;
            app.TAALabel = uilabel(app.TAAGrid,'Text','Tactical Asset Allocation (TAA) — active deltas on top of SAA','FontWeight','bold');
            app.TAAAssetsList = uilistbox(app.TAAGrid,'Items',{},'Multiselect','on');
            % Buttons row
            app.TAAButtonsGrid = uigridlayout(app.TAAGrid,[1 4]);
            app.TAAButtonsGrid.ColumnWidth = {110,90,120,'1x'}; app.TAAButtonsGrid.Padding = [0 0 0 0]; app.TAAButtonsGrid.ColumnSpacing = 6;
            app.TAAAddButton    = uibutton(app.TAAButtonsGrid,'Text','Add Selected', ...
                'ButtonPushedFcn',@(s,e)onTAAAddSelected(app));
            app.TAARemoveButton = uibutton(app.TAAButtonsGrid,'Text','Remove', ...
                'ButtonPushedFcn',@(s,e)onTAARemoveSelected(app));
            app.TAAAddTradeBtn  = uibutton(app.TAAButtonsGrid,'Text','Add Trade Pair', ...
                'ButtonPushedFcn',@(s,e)onTAAAddTradePair(app));
            app.ApplyTAAButton = uibutton(app.TAAButtonsGrid,'Text','Apply TAA -> Combined', ...
                'ButtonPushedFcn',@(s,e)applyTAA(app),'BackgroundColor',[0.82 0.96 0.82],'FontWeight','bold');
            % Main TAA table
            app.TAATable = uitable(app.TAAGrid,'Data',table(),'ColumnEditable',[true true true false true false false false],'FontSize',11);
            app.TAATable.ColumnName = {'TradeGroup','Asset','DeltaPct','Leg','Description','TE_bps','EqBeta','USD_Sens'};
            app.TAATable.CellEditCallback = @(s,e)onTAATableEdited(app);
            % Trade summary section
            app.TAATradeLabel = uilabel(app.TAAGrid,'Text','Trade-Level Summary:','FontWeight','bold');
            app.TAATradeTable = uitable(app.TAAGrid,'Data',table(),'ColumnEditable',false(1,5),'FontSize',11);
            app.TAATradeTable.ColumnName = {'TradeGroup','Legs','TE_bps','EqBeta','USD_Sens'};

            % ===== Combined tab (7-row layout with FX split + analytics) =====
            app.CombGrid = uigridlayout(app.CombinedTab,[7 1]);
            app.CombGrid.RowHeight = {'fit','1x','fit',90,80,'fit','1x'};
            app.CombGrid.Padding = [8 8 8 8]; app.CombGrid.RowSpacing = 6;
            % Row 1: Funded positions label
            app.CombFundedLabel = uilabel(app.CombGrid,'Text','Funded Positions','FontWeight','bold');
            % Row 2: Funded table
            app.CombinedTable = uitable(app.CombGrid,'Data',table(),'ColumnEditable',[false false false],'FontSize',11);
            app.CombinedTable.ColumnName = {'Asset','Weight','RiskContribution'};
            % Row 3: FX overlay label
            app.CombFXLabel = uilabel(app.CombGrid,'Text','Overlays','FontWeight','bold');
            % Row 4: FX overlay table
            app.CombFXTable = uitable(app.CombGrid,'Data',table(),'ColumnEditable',[false false false],'FontSize',11);
            app.CombFXTable.ColumnName = {'Asset','Weight','RiskContribution'};
            % Row 5: Combined analytics
            app.CombAnalyticsText = uitextarea(app.CombGrid,'Editable','off','FontName','Consolas','FontSize',11, ...
                'Value',{'Information Ratio: -   Hit Rate: -   ETL: -   CDaR: -'});
            % Row 6: TE label
            app.TELabel = uilabel(app.CombGrid,'Text','Tracking Error vs SAA:','FontWeight','bold');
            % Row 7: TE table
            app.TETable = uitable(app.CombGrid,'Data',table(),'ColumnEditable',[false false false],'FontSize',11);
            app.TETable.ColumnName = {'Asset','ActiveWeight','TE_RC','TE_RC_Pct'};

            % ===== Performance tab (3 charts + table) =====
            app.PerfGrid = uigridlayout(app.PerformanceTab,[5 1]);
            app.PerfGrid.RowHeight = {'fit','1x','1x','1x',160};
            app.PerfGrid.Padding = [8 8 8 8]; app.PerfGrid.RowSpacing = 4;

            perfCtrl = uigridlayout(app.PerfGrid,[1 3]);
            perfCtrl.ColumnWidth = {'fit',70,'1x'}; perfCtrl.Padding = [0 0 0 0];
            app.PerfRollingLabel = uilabel(perfCtrl,'Text','Rolling window:');
            app.PerfRollingField = uieditfield(perfCtrl,'numeric','Value',63,'Limits',[2 Inf],'ValueDisplayFormat','%.0f', ...
                'ValueChangedFcn',@(s,e)updatePerformanceTable(app));
            uilabel(perfCtrl,'Text','');

            app.PerfAxesCum = uiaxes(app.PerfGrid,'Box','on');
            title(app.PerfAxesCum,'Cumulative Performance');
            xlabel(app.PerfAxesCum,'Date'); ylabel(app.PerfAxesCum,'Return');
            app.PerfAxesCum.XGrid='on'; app.PerfAxesCum.YGrid='on';

            app.PerfAxesVol = uiaxes(app.PerfGrid,'Box','on');
            title(app.PerfAxesVol,'Rolling Volatility (ann.)');
            xlabel(app.PerfAxesVol,'Date'); ylabel(app.PerfAxesVol,'Volatility');
            app.PerfAxesVol.XGrid='on'; app.PerfAxesVol.YGrid='on';

            app.PerfAxesDD = uiaxes(app.PerfGrid,'Box','on');
            title(app.PerfAxesDD,'Drawdown (Underwater)');
            xlabel(app.PerfAxesDD,'Date'); ylabel(app.PerfAxesDD,'Drawdown');
            app.PerfAxesDD.XGrid='on'; app.PerfAxesDD.YGrid='on';

            app.PerfTable = uitable(app.PerfGrid,'Data',table(),'ColumnEditable',false(1,7),'FontSize',10);

            % ===== Bootstrap tab =====
            app.BootGrid = uigridlayout(app.BootstrapTab,[8 1]);
            app.BootGrid.RowHeight = {'fit','fit',100,'fit','fit','1x',80,120};
            app.BootGrid.Padding = [8 8 8 8]; app.BootGrid.RowSpacing = 6;

            % Row 1: Load measures + info
            bootRow1 = uigridlayout(app.BootGrid,[1 2]);
            bootRow1.ColumnWidth = {'fit','1x'}; bootRow1.Padding = [0 0 0 0];
            app.LoadMeasuresButton = uibutton(bootRow1,'Text','Load Measures CSV', ...
                'ButtonPushedFcn',@(s,e)onLoadMeasures(app));
            app.MeasuresInfoLabel = uilabel(bootRow1,'Text','Measures: GDP, CPI, NFP, RetailSales, VIX, Rates, Slopes, Spreads, Oil, DXY', ...
                'FontSize',10,'FontColor',[0.4 0.4 0.4]);

            % Row 2: Condition builder label + controls
            bootCondRow = uigridlayout(app.BootGrid,[1 5]);
            bootCondRow.ColumnWidth = {'fit','fit','fit','fit','1x'}; bootCondRow.Padding = [0 0 0 0]; bootCondRow.ColumnSpacing = 6;
            app.ConditionLabel = uilabel(bootCondRow,'Text','Conditions:','FontWeight','bold');
            app.BootAddCondBtn = uibutton(bootCondRow,'Text','+ Add Rule', ...
                'ButtonPushedFcn',@(s,e)onBootAddCondition(app));
            app.BootRemoveCondBtn = uibutton(bootCondRow,'Text','- Remove', ...
                'ButtonPushedFcn',@(s,e)onBootRemoveCondition(app));
            uilabel(bootCondRow,'Text','Combine with:');
            app.BootCondLogicDrop = uidropdown(bootCondRow,'Items',{'AND (all must hold)','OR (any must hold)'},'Value','AND (all must hold)');

            % Row 3: Condition table (editable dropdowns simulated via table)
            app.BootCondTable = uitable(app.BootGrid, ...
                'ColumnName',{'Measure','Condition','Value'}, ...
                'ColumnEditable',[true true true], ...
                'ColumnFormat',{{'GDP Growth (YoY)','Inflation (CPI YoY)','Inflation (CPI MoM)','Nonfarm Payrolls (MoM chg)','Retail Sales (YoY)','USD Momentum (DXY 3m)','VIX Level','Fed Funds Rate','2Y Treasury Yield','10Y Treasury Yield','Yield Curve Slope (10Y-2Y)','HY Credit Spread','IG Credit Spread','Oil Price (WTI 3m)'}, ...
                                {'> above','< below','>= at or above','<= at or below'}, ...
                                'numeric'}, ...
                'FontSize',11);
            % Default condition rows
            app.BootCondTable.Data = {
                'GDP Growth (YoY)',   '> above',   0.02
                'USD Momentum (DXY 3m)', '< below', 0.0
            };

            % Row 4: Hidden raw condition text (built from table)
            app.ConditionText = uitextarea(app.BootGrid,'Value',{'GDP_YoY > 0.02 & DXY_3m_return < 0'}, ...
                'FontName','Consolas','FontSize',10,'Editable','off','Visible','off');

            % Row 5: Block/Paths/Run
            bootRow3 = uigridlayout(app.BootGrid,[1 5]);
            bootRow3.ColumnWidth = {'fit',55,'fit',55,'fit'}; bootRow3.Padding = [0 0 0 0]; bootRow3.ColumnSpacing = 6;
            uilabel(bootRow3,'Text','Block:');
            app.BlockLenField = uieditfield(bootRow3,'numeric','Value',20,'Limits',[1 Inf],'ValueDisplayFormat','%.0f');
            uilabel(bootRow3,'Text','Paths:');
            app.PathsField = uieditfield(bootRow3,'numeric','Value',500,'Limits',[1 Inf],'ValueDisplayFormat','%.0f');
            app.RunBootstrapButton = uibutton(bootRow3,'Text','Run Bootstrap', ...
                'ButtonPushedFcn',@(s,e)onRunBootstrap(app),'BackgroundColor',[0.82 0.90 1.0],'FontWeight','bold');

            % Row 6: Conditional stats table (left) + Bootstrap distribution chart (right)
            bootChartRow = uigridlayout(app.BootGrid,[1 2]);
            bootChartRow.ColumnWidth = {280,'1x'}; bootChartRow.Padding = [0 0 0 0]; bootChartRow.ColumnSpacing = 6;
            app.BootStatsTable = uitable(bootChartRow,'Data',table(),'ColumnEditable',false,'FontSize',10);
            app.BootstrapAxes = uiaxes(bootChartRow,'Box','on');
            title(app.BootstrapAxes,'Bootstrap: annualized return distribution');
            xlabel(app.BootstrapAxes,'Annualized Return'); ylabel(app.BootstrapAxes,'Frequency');
            app.BootstrapAxes.XGrid='on'; app.BootstrapAxes.YGrid='on';

            % Row 7: Condition match timeline
            app.BootCondAxes = uiaxes(app.BootGrid,'Box','on');
            title(app.BootCondAxes,'Condition Match Timeline');
            app.BootCondAxes.YTick = []; app.BootCondAxes.XGrid='off'; app.BootCondAxes.YGrid='off';

            % Row 8: Summary text
            app.BootstrapSummary = uitextarea(app.BootGrid,'Editable','off','FontName','Consolas','FontSize',11);

            % ===== Correlation tab (4 rows: heatmap, controls, rolling, PCA eigenvalues) =====
            app.CorrGrid = uigridlayout(app.CorrelationTab,[4 1]);
            app.CorrGrid.RowHeight = {'1x','fit','1x',120};
            app.CorrGrid.Padding = [8 8 8 8]; app.CorrGrid.RowSpacing = 4;
            app.CorrAxes = uiaxes(app.CorrGrid,'Box','on');
            title(app.CorrAxes,'Correlation Heatmap');
            app.CorrAxes.XGrid='off'; app.CorrAxes.YGrid='off';
            corrCtrl = uigridlayout(app.CorrGrid,[1 3]);
            corrCtrl.ColumnWidth = {'fit',70,'1x'}; corrCtrl.Padding = [0 0 0 0];
            uilabel(corrCtrl,'Text','Rolling window:');
            app.CorrWindowField = uieditfield(corrCtrl,'numeric','Value',63,'Limits',[5 Inf],'ValueDisplayFormat','%.0f', ...
                'ValueChangedFcn',@(s,e)updateCorrelation(app));
            uilabel(corrCtrl,'Text','');
            app.CorrRollAxes = uiaxes(app.CorrGrid,'Box','on');
            title(app.CorrRollAxes,'Rolling Correlation vs Portfolio');
            xlabel(app.CorrRollAxes,'Date'); ylabel(app.CorrRollAxes,'Correlation');
            app.CorrRollAxes.XGrid='on'; app.CorrRollAxes.YGrid='on';
            % PCA eigenvalue table
            app.EigenTable = uitable(app.CorrGrid,'Data',table(),'ColumnEditable',false,'FontSize',10);
            app.EigenTable.ColumnName = {'PC','Eigenvalue','PctVariance','CumulativePct'};

            % ===== Efficient Frontier tab (3 rows: chart, controls, distance label) =====
            app.FrontierGrid = uigridlayout(app.FrontierTab,[3 1]);
            app.FrontierGrid.RowHeight = {'8x','fit','fit'};
            app.FrontierGrid.Padding = [8 8 8 8]; app.FrontierGrid.RowSpacing = 4;
            app.FrontierAxes = uiaxes(app.FrontierGrid,'Box','on');
            title(app.FrontierAxes,'Efficient Frontier');
            xlabel(app.FrontierAxes,'Volatility (ann.)'); ylabel(app.FrontierAxes,'Return (ann.)');
            app.FrontierAxes.XGrid='on'; app.FrontierAxes.YGrid='on';
            frontCtrl = uigridlayout(app.FrontierGrid,[1 3]);
            frontCtrl.ColumnWidth = {'fit',70,'fit'}; frontCtrl.Padding = [0 0 0 0]; frontCtrl.ColumnSpacing = 8;
            uilabel(frontCtrl,'Text','Frontier points:');
            app.FrontierPointsField = uieditfield(frontCtrl,'numeric','Value',50,'Limits',[10 500],'ValueDisplayFormat','%.0f');
            app.ComputeFrontierBtn = uibutton(frontCtrl,'Text','Compute Frontier', ...
                'ButtonPushedFcn',@(s,e)computeEfficientFrontier(app),'BackgroundColor',[0.82 0.90 1.0]);
            % Distance-to-frontier label
            app.FrontierDistLabel = uilabel(app.FrontierGrid,'Text','Distance to frontier: (compute frontier first)', ...
                'FontSize',11,'FontColor',[0.2 0.2 0.6]);

            % ===== Risk Decomp tab (4 rows x 2 cols) =====
            app.RiskDecompGrid = uigridlayout(app.RiskDecompTab,[4 2]);
            app.RiskDecompGrid.RowHeight = {'1x',80,'1x',60};
            app.RiskDecompGrid.ColumnWidth = {'1x','1x'};
            app.RiskDecompGrid.Padding = [8 8 8 8]; app.RiskDecompGrid.RowSpacing = 6;
            % Row 1, Col 1: Risk Budget Table
            app.RiskBudgetTable = uitable(app.RiskDecompGrid,'Data',table(),'ColumnEditable',false,'FontSize',10);
            app.RiskBudgetTable.ColumnName = {'Asset','Weight','MCR','ComponentRisk','PctTotalRisk'};
            app.RiskBudgetTable.Layout.Row = 1; app.RiskBudgetTable.Layout.Column = 1;
            % Row 1, Col 2: Risk Waterfall Chart
            app.RiskWaterfallAxes = uiaxes(app.RiskDecompGrid,'Box','on');
            app.RiskWaterfallAxes.Layout.Row = 1; app.RiskWaterfallAxes.Layout.Column = 2;
            title(app.RiskWaterfallAxes,'Risk Contribution Waterfall');
            app.RiskWaterfallAxes.XGrid='on'; app.RiskWaterfallAxes.YGrid='on';
            % Row 2, Cols 1-2: Concentration Metrics
            app.ConcentrationText = uitextarea(app.RiskDecompGrid,'Editable','off','FontName','Consolas','FontSize',11);
            app.ConcentrationText.Layout.Row = 2; app.ConcentrationText.Layout.Column = [1 2];
            % Row 3, Col 1: Factor Exposure Table
            app.FactorExposureTable = uitable(app.RiskDecompGrid,'Data',table(),'ColumnEditable',false,'FontSize',10);
            app.FactorExposureTable.ColumnName = {'Factor','Beta','tStat','Contribution'};
            app.FactorExposureTable.Layout.Row = 3; app.FactorExposureTable.Layout.Column = 1;
            % Row 3, Col 2: Rolling Factor Beta Chart + window field
            rollFactorPanel = uigridlayout(app.RiskDecompGrid,[2 1]);
            rollFactorPanel.Layout.Row = 3; rollFactorPanel.Layout.Column = 2;
            rollFactorPanel.RowHeight = {'1x','fit'}; rollFactorPanel.Padding = [0 0 0 0];
            app.RollingFactorAxes = uiaxes(rollFactorPanel,'Box','on');
            title(app.RollingFactorAxes,'Rolling Factor Betas');
            app.RollingFactorAxes.XGrid='on'; app.RollingFactorAxes.YGrid='on';
            factWinRow = uigridlayout(rollFactorPanel,[1 3]);
            factWinRow.ColumnWidth = {'fit',60,'1x'}; factWinRow.Padding = [0 0 0 0];
            uilabel(factWinRow,'Text','Window:');
            app.FactorWindowField = uieditfield(factWinRow,'numeric','Value',126,'Limits',[20 Inf],'ValueDisplayFormat','%.0f', ...
                'ValueChangedFcn',@(s,e)updateRollingFactorExposure(app));
            uilabel(factWinRow,'Text','');
            % Row 4, Cols 1-2: Factor vs Specific Variance
            app.FactorVsSpecificText = uitextarea(app.RiskDecompGrid,'Editable','off','FontName','Consolas','FontSize',11);
            app.FactorVsSpecificText.Layout.Row = 4; app.FactorVsSpecificText.Layout.Column = [1 2];

            % ===== CMA tab =====
            app.CMATab = uitab(app.TabGroup,'Title','CMA');
            app.CMAGrid = uigridlayout(app.CMATab,[5 1]);
            app.CMAGrid.RowHeight = {'fit','fit','1x','fit','1x'};
            app.CMAGrid.Padding = [8 8 8 8]; app.CMAGrid.RowSpacing = 6;
            cmaCtrl = uigridlayout(app.CMAGrid,[1 5]);
            cmaCtrl.ColumnWidth = {'fit','fit','fit',70,'1x'}; cmaCtrl.Padding = [0 0 0 0]; cmaCtrl.ColumnSpacing = 8;
            app.ComputeCMABtn = uibutton(cmaCtrl,'Text','Compute CMA', ...
                'ButtonPushedFcn',@(s,e)computeCMA(app),'BackgroundColor',[0.82 0.90 1.0],'FontWeight','bold');
            app.CMAMethodDropDown = uidropdown(cmaCtrl,'Items',{'Historical','Building-Block','BL-Equilibrium'},'Value','Historical');
            uilabel(cmaCtrl,'Text','Lookback:');
            app.CMALookbackField = uieditfield(cmaCtrl,'numeric','Value',0,'Limits',[0 Inf],'ValueDisplayFormat','%.0f');
            app.UseCMAButton = uibutton(cmaCtrl,'Text','Use CMA as Optimizer Inputs', ...
                'ButtonPushedFcn',@(s,e)onUseCMAInputs(app));
            uilabel(app.CMAGrid,'Text','Expected Returns & Volatility (editable)','FontWeight','bold');
            app.CMARetVolTable = uitable(app.CMAGrid,'Data',table(),'ColumnEditable',[false false true true false],'FontSize',11);
            app.CMARetVolTable.ColumnName = {'Asset','ETF','Exp_Return_Ann','Vol_Ann','Sharpe'};
            uilabel(app.CMAGrid,'Text','Correlation Matrix (from data)','FontWeight','bold');
            app.CMACorrTable = uitable(app.CMAGrid,'Data',table(),'ColumnEditable',false,'FontSize',10);

            % ===== Status bar =====
            app.StatusLabel = uilabel(app.UIFigure,'Text','Ready', ...
                'Position',[10 5 1480 26],'HorizontalAlignment','left', ...
                'FontSize',12,'FontName','Consolas','BackgroundColor',[0.93 0.93 0.95]);
        end
    end

    %================ CALLBACKS & HELPERS ================
    methods (Access = private)
        function setField(app,fname,val), app.(fname) = val; end

        function setTargetRet(app,val)
            if ~isfinite(val) || abs(val) < 1e-12
                app.TargetRet = NaN;
            else
                app.TargetRet = val;
            end
        end

        function onLoadCSV(app)
            try
                [f,p] = uigetfile({'*.csv;*.txt','CSV/TXT Files (*.csv,*.txt)'},'Select price/return file');
                if isequal(f,0), return; end
                T = readtable(fullfile(p,f));
                [R, names, Raw] = parseTableToReturns(app, T, app.DataType);  % also sets Dates
                app.R = R; app.AssetNames = names;
                populateAssetLists(app);
                app.TAAAssetsList.Items = names;
                app.DataTable.Data = Raw;
                app.W = initEqualWeights(app);
                ensureSAAInitialized(app);
                refreshScenariosTable(app);
                initAssetETFMap(app);
                app.StatusLabel.Text = sprintf('Loaded %s (%d obs x %d assets).', f, size(R,1), size(R,2));
                updateSummary(app); plotDistribution(app); plotSensitivity(app);
                updateTrackingError(app); updatePerformanceTable(app); updateCorrelation(app);
                updateSAAAnalytics(app);
                updateFXOverlayDisplay(app); updateRiskDecomp(app); updateCombinedAnalytics(app);
                updateCombinedFXSplit(app); updateEigenDecomp(app);
            catch ME
                uialert(app.UIFigure, ME.message, 'Load Error');
            end
        end

        function onUseSample(app)
            try
                Tn = 750; % ~3y daily
                [~, ~, RawOut] = generateRealisticSample(app, Tn);
                [R, names, RawOut] = parseTableToReturns(app, RawOut, 'Returns'); % sets Dates
                app.R = R; app.AssetNames = names;
                populateAssetLists(app);
                app.TAAAssetsList.Items = names;
                app.DataTable.Data = RawOut;
                app.W = initEqualWeights(app);
                ensureSAAInitialized(app);
                refreshScenariosTable(app);
                initAssetETFMap(app);
                app.StatusLabel.Text = sprintf('Loaded realistic sample data (%d obs x %d assets).', size(R,1), size(R,2));
                updateSummary(app); plotDistribution(app); plotSensitivity(app);
                updateTrackingError(app); updatePerformanceTable(app); updateCorrelation(app);
                updateSAAAnalytics(app);
                updateFXOverlayDisplay(app); updateRiskDecomp(app); updateCombinedAnalytics(app);
                updateCombinedFXSplit(app); updateEigenDecomp(app);
            catch ME
                uialert(app.UIFigure, ME.message, 'Sample Error');
            end
        end

        function onCompute(app)
            if isempty(app.R), uialert(app.UIFigure,'Load data first.','No Data'); return; end
            try
                updateSummary(app); plotDistribution(app); plotSensitivity(app);
                updateTrackingError(app); updatePerformanceTable(app); updateCorrelation(app);
                updateSAAAnalytics(app);
                updateRiskDecomp(app); updateCombinedAnalytics(app); updateEigenDecomp(app);
                app.StatusLabel.Text = 'Risk computed.';
            catch ME
                uialert(app.UIFigure, ME.message, 'Compute Error');
            end
        end

        function onOptimize(app)
            if isempty(app.R) || isempty(app.AssetNames), uialert(app.UIFigure,'Load data first.','No Data'); return; end
            try
                % Only optimize funded assets — overlays are set manually
                selFunded = app.AssetsList.Value; if isempty(selFunded), selFunded = app.AssetsList.Items; end
                idx = ismember(app.AssetNames, selFunded);
                R = app.R(:,idx);
                names = app.AssetNames(idx);
                rf = app.RF;
                objective = app.ObjectiveDropDown.Value;
                optimizer = app.OptimizerDropDown.Value;
                longOnly = app.LongOnly;
                lb = app.LB; ub = app.UB;
                targetRet = app.TargetRet;

                if longOnly, LB = max(0, lb) * ones(numel(names),1);
                else,         LB = lb * ones(numel(names),1); end
                UB = ub * ones(numel(names),1);
                nFunded = numel(names);
                w0 = ones(nFunded,1) / max(1,nFunded);

                [hasQP,hasFmin,hasGA] = checkSolvers(app);
                if strcmpi(optimizer,'auto')
                    if strcmpi(objective,'Min Variance') && hasQP, backend = 'quadprog';
                    elseif hasFmin, backend = 'fmincon';
                    elseif hasGA, backend = 'ga';
                    else, backend = 'fmincon'; end
                else, backend = optimizer; end

                mu = mean(R,1)'; Sigma = cov(R);
                k = app.annFactor();
                Aeq_funded = ones(1,numel(names)); beq_funded = 1;
                switch objective
                    case 'Min Variance'
                        Aeq = Aeq_funded; beq = beq_funded;
                        if isfinite(targetRet), Aeq = [Aeq; mu']; beq = [beq; targetRet]; end
                        switch backend
                            case 'quadprog'
                                H = 2*Sigma; f = zeros(numel(names),1);
                                opts = optimoptions('quadprog','Display','off');
                                [w,~,flag] = quadprog(H,f,[],[],Aeq,beq,LB,UB,[],opts);
                                if flag<=0, error('quadprog failed (flag=%d).',flag); end
                            otherwise
                                fun = @(w) w'*Sigma*w;
                                opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                                w = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);
                        end

                    case 'Max Sharpe'
                        Aeq = Aeq_funded; beq = beq_funded;
                        fun = @(w) -((w'*mu - rf) / max(1e-12, sqrt(w'*Sigma*w)));
                        opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                        w = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);

                    case 'Equal Weight'
                        % Equal weight across selected funded assets (no optimizer needed)
                        w = ones(nFunded,1) / nFunded;
                        backend = 'analytical';

                    case 'Target Vol'
                        % Target a specific annualized volatility level
                        % Use the Target field as the target vol (annualized, decimal)
                        targetVol = app.TargetRet; % repurpose Target field
                        if ~isfinite(targetVol) || targetVol <= 0
                            targetVol = 0.10; % default 10% vol
                        end
                        % First find Max Sharpe portfolio (unconstrained leverage)
                        % Allow leverage: sum of weights can differ from 1
                        % Cash asset can go negative (borrowing)
                        isCash = false(nFunded,1);
                        for ci = 1:nFunded
                            isCash(ci) = contains(lower(names{ci}), 'cash');
                        end
                        % Step 1: find tangency portfolio (sum-to-one)
                        Aeq = Aeq_funded; beq = beq_funded;
                        fun = @(w) -((w'*mu - rf) / max(1e-12, sqrt(w'*Sigma*w)));
                        opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                        w_tangent = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);
                        % Step 2: scale to target vol
                        vol_tangent = sqrt(w_tangent' * Sigma * w_tangent) * sqrt(k);
                        leverage = targetVol / max(1e-12, vol_tangent);
                        w = w_tangent * leverage;
                        % Excess/deficit goes to/from cash
                        cashDeficit = 1 - sum(w);
                        if any(isCash)
                            cashIdx = find(isCash, 1);
                            w(cashIdx) = w(cashIdx) + cashDeficit;
                        end
                        backend = sprintf('tangency x%.2f', leverage);

                    case 'Min CVaR (hist)'
                        Aeq = Aeq_funded; beq = beq_funded;
                        if isfinite(targetRet), Aeq = [Aeq; mu']; beq = [beq; targetRet]; end
                        fun = @(w) CVaR_hist(app, R*w, app.Alpha);
                        if hasGA && strcmpi(backend,'ga')
                            opts = optimoptions('ga','Display','none');
                            w = ga(fun, numel(names), [],[], Aeq,beq, LB,UB, [], opts);
                        else
                            opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                            w = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);
                        end

                    case 'Min VaR (hist)'
                        Aeq = Aeq_funded; beq = beq_funded;
                        if isfinite(targetRet), Aeq = [Aeq; mu']; beq = [beq; targetRet]; end
                        fun = @(w) VaR_hist(app, R*w, app.Alpha);
                        if hasGA && strcmpi(backend,'ga')
                            opts = optimoptions('ga','Display','none');
                            w = ga(fun, numel(names), [],[], Aeq,beq, LB,UB, [], opts);
                        else
                            opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                            w = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);
                        end

                    case 'Risk Parity (ERC)'
                        Aeq = Aeq_funded; beq = beq_funded;
                        iv = 1./max(1e-12, sqrt(diag(Sigma))); % inverse vol init
                        % Exclude cash — near-zero vol dominates risk parity
                        isCash = false(numel(names),1);
                        for ci = 1:numel(names)
                            isCash(ci) = contains(lower(names{ci}), 'cash');
                        end
                        iv(isCash) = 0;
                        LB(isCash) = 0; UB(isCash) = 0; % force cash to zero
                        w0 = iv / max(1e-12, sum(iv));
                        fun = @(w) app.riskParityObjective(Sigma, w);
                        opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                        w = fmincon(fun, w0, [],[], Aeq, beq, LB, UB, [], opts);

                    case 'Black-Litterman'
                        % Use TAA deltas as views on top of equilibrium returns
                        delta_ra = 2.5; % risk aversion
                        tau = 0.05;
                        w_mkt = w0; % market cap proxy = equal weight or SAA
                        w_saa_sub = app.getSAAWeightsVector();
                        if ~isempty(w_saa_sub) && numel(w_saa_sub)==numel(app.AssetNames)
                            w_mkt = w_saa_sub(idx);
                            if sum(w_mkt)>0, w_mkt = w_mkt/sum(w_mkt); end
                        end
                        % Equilibrium returns
                        pi_eq = delta_ra * Sigma * w_mkt;
                        % Build views from TAA deltas
                        [P, Q] = app.buildBLViews(names);
                        if isempty(P)
                            mu_bl = pi_eq;
                        else
                            Omega = diag(diag(P * (tau*Sigma) * P'));
                            M = tau*Sigma*P' / (P*tau*Sigma*P' + Omega);
                            mu_bl = pi_eq + M * (Q - P*pi_eq);
                        end
                        Aeq = Aeq_funded; beq = beq_funded;
                        fun = @(w) -((w'*mu_bl - rf) / max(1e-12, sqrt(w'*Sigma*w)));
                        opts = optimoptions('fmincon','Display','none','Algorithm','sqp');
                        w = fmincon(fun,w0,[],[],Aeq,beq,LB,UB,[],opts);

                    otherwise
                        error('Unknown objective.');
                end

                % Map back to full asset universe; preserve existing overlay weights
                Wfull = app.W;
                if isempty(Wfull) || numel(Wfull) ~= numel(app.AssetNames)
                    Wfull = zeros(numel(app.AssetNames),1);
                end
                % Zero out funded slots, keep overlay weights
                for fi = 1:numel(app.AssetNames)
                    if ~app.isFXOverlay(app.AssetNames{fi})
                        Wfull(fi) = 0;
                    end
                end
                Wfull(idx) = w;
                app.W = Wfull;

                % Update SAA table with optimized weights
                app.SAA = table(string(app.AssetNames(:)), Wfull(:)*100, repmat("",numel(app.AssetNames),1), ...
                    'VariableNames',{'Asset','WeightPct','Description'});

                updateSummary(app); plotDistribution(app); plotSensitivity(app);
                updateTrackingError(app); updatePerformanceTable(app); updateCorrelation(app);
                updateSAAAnalytics(app);
                updateFXOverlayDisplay(app); updateRiskDecomp(app); updateCombinedAnalytics(app);
                updateCombinedFXSplit(app);
                app.StatusLabel.Text = sprintf('Optimized using %s (%s).', backend, objective);
            catch ME
                uialert(app.UIFigure, ME.message, 'Optimize Error');
            end
        end

        function onExportWeights(app)
            if isempty(app.W), uialert(app.UIFigure,'No weights to export.','Export'); return; end
            T = table(app.AssetNames(:), app.W(:), 'VariableNames',{'Asset','Weight'});
            [f,p] = uiputfile('weights.csv','Save Weights CSV'); if isequal(f,0), return; end
            try, writetable(T, fullfile(p,f)); app.StatusLabel.Text = sprintf('Weights saved to %s', fullfile(p,f));
            catch ME, uialert(app.UIFigure, ME.message, 'Export Error'); end
        end

        %----- Market data download
        function onLoadMarketData(app)
            try
                tickers = {'bil.us','shy.us','ief.us','hyg.us','spy.us','vgk.us','ewj.us','eem.us','dbc.us','qai.us','gld.us', ...
                           'fxe.us','fxy.us','fxb.us','fxf.us','fxa.us','fxc.us'};
                names   = {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds','Equity_US','Equity_Europe','Equity_Japan','Equity_EM','Commodities','HedgeFunds','Gold', ...
                           'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};
                d1 = app.StartDateField.Value;
                d2 = app.EndDateField.Value;

                allDates = {};
                allClose = {};
                failed = {};
                for i = 1:numel(tickers)
                    app.StatusLabel.Text = sprintf('Downloading %s (%d/%d)...', names{i}, i, numel(tickers));
                    drawnow;
                    try
                        T = downloadStooqSeries(app, tickers{i}, d1, d2);
                        if isempty(T) || height(T) < 2
                            failed{end+1} = names{i}; %#ok<AGROW>
                            continue;
                        end
                        allDates{end+1} = T.Date; %#ok<AGROW>
                        allClose{end+1} = T.Close; %#ok<AGROW>
                    catch
                        failed{end+1} = names{i}; %#ok<AGROW>
                    end
                end

                processPriceData(app, allDates, allClose, names, failed, 'Stooq');
            catch ME
                uialert(app.UIFigure, ME.message, 'Market Data Error');
            end
        end

        function processPriceData(app, allDates, allClose, names, failed, source)
            % Shared helper: intersect dates, compute returns, update app state
            if isempty(allDates)
                uialert(app.UIFigure, 'All downloads failed. Check connection.', 'Download Error');
                return;
            end

            % Find intersection of dates
            commonDates = allDates{1};
            for i = 2:numel(allDates)
                commonDates = intersect(commonDates, allDates{i});
            end
            commonDates = sort(commonDates);

            if numel(commonDates) < 10
                uialert(app.UIFigure, sprintf('Only %d common dates found. Need at least 10.', numel(commonDates)), 'Insufficient Data');
                return;
            end

            % Build aligned price matrix
            nFailed = numel(failed);
            okNames = setdiff(names, failed, 'stable');
            P = zeros(numel(commonDates), numel(allDates));
            for i = 1:numel(allDates)
                [~, ia] = ismember(commonDates, allDates{i});
                P(:,i) = allClose{i}(ia);
            end

            % Log returns
            logRet = diff(log(P));
            dates = commonDates(2:end);

            % Remove any rows with NaN/Inf
            bad = any(~isfinite(logRet), 2);
            logRet = logRet(~bad, :);
            dates = dates(~bad);

            app.R = logRet;
            app.AssetNames = okNames;
            app.Dates = dates;
            populateAssetLists(app);
            app.TAAAssetsList.Items = okNames;
            app.DataTable.Data = array2table(logRet, 'VariableNames', okNames);
            app.W = initEqualWeights(app);
            ensureSAAInitialized(app);
            refreshScenariosTable(app);
            initAssetETFMap(app);

            msg = sprintf('%s data loaded: %d obs x %d assets (%s to %s).', source, size(logRet,1), numel(okNames), datestr(dates(1),'yyyy-mm-dd'), datestr(dates(end),'yyyy-mm-dd')); %#ok<DATST>
            if nFailed > 0
                msg = [msg sprintf(' Failed: %s.', strjoin(failed, ', '))];
            end
            app.StatusLabel.Text = msg;
            updateSummary(app); plotDistribution(app); plotSensitivity(app);
            updateTrackingError(app); updatePerformanceTable(app); updateCorrelation(app);
            updateSAAAnalytics(app);
            try updateFXOverlayDisplay(app); catch ex, warning('FXOverlay: %s', ex.message); end
            try updateRiskDecomp(app); catch ex, warning('RiskDecomp: %s', ex.message); end
            try updateCombinedAnalytics(app); catch ex, warning('CombAnalytics: %s', ex.message); end
            try updateCombinedFXSplit(app); catch ex, warning('CombFXSplit: %s', ex.message); end
            try updateEigenDecomp(app); catch ex, warning('EigenDecomp: %s', ex.message); end

            % Auto-download FRED measures for bootstrap
            try
                onDownloadMeasures(app);
            catch ex
                warning('Auto FRED measures: %s', ex.message);
            end
        end

        function onLoadBloomberg(app)
            % Download market data from Bloomberg Desktop via Datafeed Toolbox
            try
                % Default Bloomberg tickers and mapped names
                bbgTickers = {'BIL US Equity','SHY US Equity','IEF US Equity','HYG US Equity', ...
                              'SPY US Equity','VGK US Equity','EWJ US Equity','EEM US Equity', ...
                              'DBC US Equity','QAI US Equity','GLD US Equity', ...
                              'FXE US Equity','FXY US Equity','FXB US Equity', ...
                              'FXF US Equity','FXA US Equity','FXC US Equity'};
                names =       {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds', ...
                              'Equity_US','Equity_Europe','Equity_Japan','Equity_EM', ...
                              'Commodities','HedgeFunds','Gold', ...
                              'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};

                % Allow user to edit tickers
                prompt = strjoin(cellfun(@(t,n) sprintf('%s = %s', n, t), names, bbgTickers, 'Uni', false), '\n');
                answer = inputdlg({'Bloomberg tickers (name = BBG_TICKER, one per line):'}, ...
                    'Bloomberg Data', [20 80], {prompt});
                if isempty(answer), return; end

                % Parse user input
                lines = strsplit(answer{1}, newline);
                bbgTickers = {}; names = {};
                for li = 1:numel(lines)
                    ln = strtrim(lines{li});
                    if isempty(ln), continue; end
                    parts = strsplit(ln, '=');
                    if numel(parts) >= 2
                        names{end+1} = strtrim(parts{1}); %#ok<AGROW>
                        bbgTickers{end+1} = strtrim(strjoin(parts(2:end), '=')); %#ok<AGROW>
                    end
                end
                if isempty(bbgTickers)
                    uialert(app.UIFigure, 'No valid tickers parsed.', 'Bloomberg'); return;
                end

                d1 = datenum(app.StartDateField.Value, 'yyyymmdd'); %#ok<DATEFUN>
                d2 = datenum(app.EndDateField.Value, 'yyyymmdd'); %#ok<DATEFUN>

                app.StatusLabel.Text = 'Connecting to Bloomberg...'; drawnow;
                c = blp;  % connect to Bloomberg Desktop
                connCleanup = onCleanup(@() close(c));

                allDates = {}; allClose = {}; failed = {};
                for i = 1:numel(bbgTickers)
                    app.StatusLabel.Text = sprintf('Bloomberg: %s (%d/%d)...', names{i}, i, numel(bbgTickers));
                    drawnow;
                    try
                        d = history(c, bbgTickers{i}, 'LAST_PRICE', d1, d2, 'daily');
                        if isempty(d) || size(d,1) < 2
                            failed{end+1} = names{i}; %#ok<AGROW>
                            continue;
                        end
                        allDates{end+1} = datetime(d(:,1), 'ConvertFrom', 'datenum'); %#ok<AGROW>
                        allClose{end+1} = d(:,2); %#ok<AGROW>
                    catch dlErr
                        failed{end+1} = sprintf('%s (%s)', names{i}, dlErr.message); %#ok<AGROW>
                    end
                end

                processPriceData(app, allDates, allClose, names, failed, 'Bloomberg');
            catch ME
                if contains(ME.message, 'blp') || contains(ME.message, 'Bloomberg') || contains(ME.message, 'Undefined')
                    uialert(app.UIFigure, ...
                        ['Bloomberg connection failed. Ensure Bloomberg Terminal is running ' ...
                         'and Datafeed Toolbox is licensed.\n\nError: ' ME.message], ...
                        'Bloomberg Error');
                else
                    uialert(app.UIFigure, ME.message, 'Bloomberg Error');
                end
            end
        end

        function onLoadDatastream(app)
            % Download market data from Refinitiv Datastream via DSWS REST API
            try
                % Default Datastream codes and mapped names
                dsTickers = {'SBILX','SSHYX','SIEFX','SHYGX','SSPYX','SVGKX','SEWJX','SEEMX', ...
                             'SDBCX','SQAIX','SGLDX','SFXEX','SFXYX','SFXBX','SFXFX','SFXAX','SFXCX'};
                names =     {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds', ...
                             'Equity_US','Equity_Europe','Equity_Japan','Equity_EM', ...
                             'Commodities','HedgeFunds','Gold', ...
                             'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};

                % Allow user to edit tickers and credentials
                prompt = strjoin(cellfun(@(t,n) sprintf('%s = %s', n, t), names, dsTickers, 'Uni', false), '\n');
                answer = inputdlg({ ...
                    'Datastream username:', ...
                    'Datastream password:', ...
                    'Datastream codes (name = DS_CODE, one per line):'}, ...
                    'Datastream (DSWS)', [1 60; 1 60; 20 80], {'', '', prompt});
                if isempty(answer), return; end
                dsUser = strtrim(answer{1});
                dsPass = strtrim(answer{2});
                if isempty(dsUser) || isempty(dsPass)
                    uialert(app.UIFigure, 'Username and password are required for Datastream DSWS.', 'Datastream'); return;
                end

                % Parse user ticker input
                lines = strsplit(answer{3}, newline);
                dsTickers = {}; names = {};
                for li = 1:numel(lines)
                    ln = strtrim(lines{li});
                    if isempty(ln), continue; end
                    parts = strsplit(ln, '=');
                    if numel(parts) >= 2
                        names{end+1} = strtrim(parts{1}); %#ok<AGROW>
                        dsTickers{end+1} = strtrim(strjoin(parts(2:end), '=')); %#ok<AGROW>
                    end
                end
                if isempty(dsTickers)
                    uialert(app.UIFigure, 'No valid codes parsed.', 'Datastream'); return;
                end

                d1 = app.StartDateField.Value;
                d2 = app.EndDateField.Value;
                % Convert yyyymmdd to Datastream format yyyy-mm-dd
                dsStart = [d1(1:4) '-' d1(5:6) '-' d1(7:8)];
                dsEnd   = [d2(1:4) '-' d2(5:6) '-' d2(7:8)];

                % Authenticate with DSWS REST API
                app.StatusLabel.Text = 'Authenticating with Datastream DSWS...'; drawnow;
                tokenUrl = 'https://product.datastream.com/DSWSClient/V1/DSService.svc/rest/Token';
                tokenBody = struct('UserName', dsUser, 'Password', dsPass);
                tokenOpts = weboptions('MediaType', 'application/json', 'Timeout', 30, ...
                    'ContentType', 'json', 'RequestMethod', 'post');
                tokenResp = webwrite(tokenUrl, tokenBody, tokenOpts);
                if isfield(tokenResp, 'TokenValue')
                    token = tokenResp.TokenValue;
                else
                    uialert(app.UIFigure, 'Datastream authentication failed. Check credentials.', 'Datastream'); return;
                end

                % Download each series via DSWS Data endpoint
                dataUrl = 'https://product.datastream.com/DSWSClient/V1/DSService.svc/rest/Data';
                allDates = {}; allClose = {}; failed = {};

                for i = 1:numel(dsTickers)
                    app.StatusLabel.Text = sprintf('Datastream: %s (%d/%d)...', names{i}, i, numel(dsTickers));
                    drawnow;
                    try
                        reqBody = struct( ...
                            'TokenValue', token, ...
                            'DataRequest', struct( ...
                                'Instrument', struct('Value', dsTickers{i}, 'Properties', []), ...
                                'DataTypes', {{struct('Value', 'P', 'Properties', [])}}, ...
                                'Date', struct('Start', dsStart, 'End', dsEnd, 'Frequency', 'D', 'Kind', 1)));
                        dataOpts = weboptions('MediaType', 'application/json', 'Timeout', 60, ...
                            'ContentType', 'json', 'RequestMethod', 'post');
                        resp = webwrite(dataUrl, reqBody, dataOpts);

                        % Parse DSWS response: dates and values
                        if isfield(resp, 'DataTypeValues') && ~isempty(resp.DataTypeValues)
                            dtv = resp.DataTypeValues;
                            if iscell(dtv), dtv = dtv{1}; end
                            if isstruct(dtv) && isfield(dtv, 'SymbolValues')
                                sv = dtv.SymbolValues;
                                if iscell(sv), sv = sv{1}; end
                                if isstruct(sv) && isfield(sv, 'Value')
                                    vals = sv.Value;
                                    if iscell(vals), vals = cell2mat(vals); end
                                    vals = double(vals);
                                end
                            end
                        end
                        if isfield(resp, 'Dates') && exist('vals', 'var')
                            rawDates = resp.Dates;
                            if iscell(rawDates)
                                % DSWS dates: "/Date(milliseconds)/" format
                                dtVec = NaT(numel(rawDates), 1);
                                for di = 1:numel(rawDates)
                                    tok = regexp(rawDates{di}, '/Date\((\-?\d+)\)/', 'tokens');
                                    if ~isempty(tok)
                                        ms = str2double(tok{1}{1});
                                        dtVec(di) = datetime(ms/1000, 'ConvertFrom', 'posixtime');
                                    end
                                end
                            else
                                dtVec = datetime(rawDates, 'ConvertFrom', 'datenum');
                            end
                            % Filter valid data
                            valid = ~isnat(dtVec) & isfinite(vals) & vals > 0;
                            if sum(valid) >= 2
                                allDates{end+1} = dtVec(valid); %#ok<AGROW>
                                allClose{end+1} = vals(valid); %#ok<AGROW>
                            else
                                failed{end+1} = names{i}; %#ok<AGROW>
                            end
                        else
                            failed{end+1} = names{i}; %#ok<AGROW>
                        end
                        clear vals;
                    catch dlErr
                        failed{end+1} = sprintf('%s (%s)', names{i}, dlErr.message); %#ok<AGROW>
                    end
                end

                processPriceData(app, allDates, allClose, names, failed, 'Datastream');
            catch ME
                uialert(app.UIFigure, ME.message, 'Datastream Error');
            end
        end

        function T = downloadStooqSeries(~, ticker, startDate, endDate)
            url = sprintf('https://stooq.com/q/d/l/?s=%s&d1=%s&d2=%s&i=d', ticker, startDate, endDate);
            tmpFile = [tempname '.csv'];
            cleanUp = onCleanup(@() delete(tmpFile));
            try
                websave(tmpFile, url);
            catch ME
                error('Failed to download %s: %s', ticker, ME.message);
            end
            try
                raw = readtable(tmpFile, 'TextType', 'string');
            catch ME
                error('Failed to parse CSV for %s: %s', ticker, ME.message);
            end
            if isempty(raw) || height(raw) < 2
                T = table();
                return;
            end
            % Stooq returns: Date, Open, High, Low, Close, Volume
            if ismember('Date', raw.Properties.VariableNames)
                raw.Date = datetime(raw.Date);
            else
                error('No Date column in Stooq response for %s.', ticker);
            end
            if ~ismember('Close', raw.Properties.VariableNames)
                error('No Close column in Stooq response for %s.', ticker);
            end
            T = table(raw.Date, raw.Close, 'VariableNames', {'Date','Close'});
            % Remove NaN close prices
            bad = isnan(T.Close) | T.Close <= 0;
            T = T(~bad, :);
            T = sortrows(T, 'Date');
        end

        function onAddCustomTicker(app)
            % Download a custom ETF ticker and add it to the existing dataset
            ticker = strtrim(app.CustomTickerField.Value);
            if isempty(ticker)
                uialert(app.UIFigure, 'Enter an ETF ticker (e.g. tlt.us, qqq.us).', 'No Ticker');
                return;
            end
            % Ensure .us suffix for Stooq
            if ~contains(ticker, '.')
                ticker = [ticker '.us'];
            end
            % Derive asset name from ticker (uppercase, strip suffix)
            dotPos = find(ticker == '.', 1);
            assetName = upper(ticker(1:dotPos-1));

            % Check if already loaded
            if ~isempty(app.AssetNames) && any(strcmpi(app.AssetNames, assetName))
                uialert(app.UIFigure, sprintf('%s is already in the universe.', assetName), 'Duplicate');
                return;
            end

            d1 = app.StartDateField.Value;
            d2 = app.EndDateField.Value;
            app.StatusLabel.Text = sprintf('Downloading %s...', ticker);
            drawnow;

            try
                T = downloadStooqSeries(app, ticker, d1, d2);
            catch ME
                uialert(app.UIFigure, sprintf('Download failed: %s', ME.message), 'Download Error');
                app.StatusLabel.Text = 'Download failed.';
                return;
            end
            if isempty(T) || height(T) < 2
                uialert(app.UIFigure, sprintf('No data returned for %s. Check the ticker.', ticker), 'No Data');
                app.StatusLabel.Text = 'No data returned.';
                return;
            end

            if isempty(app.R)
                % First asset — initialize everything
                logRet = diff(log(T.Close));
                dates = T.Date(2:end);
                bad = ~isfinite(logRet);
                logRet = logRet(~bad);
                dates = dates(~bad);
                app.R = logRet;
                app.Dates = dates;
                app.AssetNames = {assetName};
                app.W = 1;
            else
                % Merge with existing data on common dates
                existingDates = app.Dates;
                newDates = T.Date;
                % Build returns for new asset
                newLogRet = [NaN; diff(log(T.Close))];
                newRetTbl = table(T.Date, newLogRet, 'VariableNames', {'Date','Ret'});
                % Find common dates (existing returns dates)
                [commonDates, ia, ib] = intersect(existingDates, newRetTbl.Date);
                if numel(commonDates) < 10
                    uialert(app.UIFigure, sprintf('Only %d overlapping dates with %s. Need at least 10.', numel(commonDates), assetName), 'Insufficient Overlap');
                    app.StatusLabel.Text = 'Insufficient date overlap.';
                    return;
                end
                % Subset existing data to common dates and append new column
                app.R = [app.R(ia, :), newRetTbl.Ret(ib)];
                app.Dates = commonDates;
                app.AssetNames{end+1} = assetName;
                app.W = [app.W; 0]; % new asset starts at 0 weight
            end

            % Update UI
            populateAssetLists(app);
            app.TAAAssetsList.Items = app.AssetNames;
            app.DataTable.Data = array2table(app.R, 'VariableNames', app.AssetNames);

            % Add to ETF map
            app.AssetETFMap{end+1, 1} = assetName;
            app.AssetETFMap{end, 2} = sprintf('%s (Custom)', upper(assetName));

            % Re-initialize SAA to include new asset
            ensureSAAInitialized(app);

            % Refresh analytics
            try updateSummary(app); catch; end
            try updateFXOverlayDisplay(app); catch; end
            try updateRiskDecomp(app); catch; end

            app.StatusLabel.Text = sprintf('Added %s (%d common dates).', assetName, size(app.R,1));
            app.CustomTickerField.Value = '';
        end

        %----- FRED macro data download
        function onDownloadMeasures(app)
            try
                if isempty(app.Dates)
                    uialert(app.UIFigure, 'Load market/sample data first so dates are available.', 'No Dates');
                    return;
                end
                targetDates = app.Dates;
                if ~isdatetime(targetDates)
                    uialert(app.UIFigure, 'Dates must be datetime for FRED alignment. Load market data first.', 'Date Format');
                    return;
                end

                % Extra lookback for derived columns (CPI YoY needs 13 months, DXY 3m needs ~4 months)
                startDt = targetDates(1) - calmonths(15);
                endDt = targetDates(end);
                d1 = datestr(startDt, 'yyyy-mm-dd'); %#ok<DATST>
                d2 = datestr(endDt, 'yyyy-mm-dd'); %#ok<DATST>

                % Define FRED series to download
                seriesIDs   = {'A191RL1Q225SBEA','CPIAUCSL','DTWEXBGS','VIXCLS','DFF','DGS10','DGS2', ...
                               'BAMLH0A0HYM2','BAMLC0A4CBBB','PAYEMS','RSAFS','DCOILWTICO'};
                seriesNames = {'GDP_pct','CPI_level','DXY_level','VIX','FedFunds','TenYr','TwoYr', ...
                               'HY_Spread','IG_Spread','NFP_level','RetailSales_level','WTI_level'};

                rawData = cell(1, numel(seriesIDs));
                failed = {};
                for i = 1:numel(seriesIDs)
                    app.StatusLabel.Text = sprintf('Downloading FRED %s (%d/%d)...', seriesIDs{i}, i, numel(seriesIDs));
                    drawnow;
                    ok = false;
                    for attempt = 1:2
                        try
                            rawData{i} = downloadFREDSeries(app, seriesIDs{i}, d1, d2);
                            if ~isempty(rawData{i}) && height(rawData{i}) >= 2
                                ok = true; break;
                            end
                        catch
                        end
                        if attempt == 1, pause(1); end  % brief pause before retry
                    end
                    if ~ok
                        failed{end+1} = seriesIDs{i}; %#ok<AGROW>
                        rawData{i} = table();
                    end
                end

                app.StatusLabel.Text = 'Aligning FRED data to returns dates...';
                drawnow;

                N = numel(targetDates);
                measures = table(targetDates(:), 'VariableNames', {'Date'});

                % Forward-fill each series to target dates
                for i = 1:numel(seriesIDs)
                    if isempty(rawData{i}) || height(rawData{i}) < 2
                        measures.(seriesNames{i}) = NaN(N, 1);
                        continue;
                    end
                    srcDates = rawData{i}.Date;
                    srcVals  = rawData{i}.Value;
                    measures.(seriesNames{i}) = forwardFillToTarget(app, srcDates, srcVals, targetDates);
                end

                % Compute derived columns
                % GDP_YoY: already annualized % change from FRED, just /100
                measures.GDP_YoY = measures.GDP_pct / 100;

                % CPI_YoY: year-over-year change from CPI level
                cpiLag = min(252, N-1);
                measures.CPI_YoY = NaN(N, 1);
                if cpiLag > 0
                    measures.CPI_YoY(cpiLag+1:end) = measures.CPI_level(cpiLag+1:end) ./ measures.CPI_level(1:end-cpiLag) - 1;
                end

                % CPI_MoM: month-over-month change (~21 trading days)
                cpiMoMLag = min(21, N-1);
                measures.CPI_MoM = NaN(N, 1);
                if cpiMoMLag > 0
                    measures.CPI_MoM(cpiMoMLag+1:end) = measures.CPI_level(cpiMoMLag+1:end) ./ measures.CPI_level(1:end-cpiMoMLag) - 1;
                end

                % DXY_3m_return: 3-month (~63 trading days) return
                dxyLag = min(63, N-1);
                measures.DXY_3m_return = NaN(N, 1);
                if dxyLag > 0
                    measures.DXY_3m_return(dxyLag+1:end) = measures.DXY_level(dxyLag+1:end) ./ measures.DXY_level(1:end-dxyLag) - 1;
                end

                % NFP_MoM: month-over-month change in Nonfarm Payrolls (thousands)
                nfpLag = min(21, N-1);
                measures.NFP_MoM = NaN(N, 1);
                if nfpLag > 0
                    measures.NFP_MoM(nfpLag+1:end) = measures.NFP_level(nfpLag+1:end) - measures.NFP_level(1:end-nfpLag);
                end

                % RetailSales_YoY: year-over-year change in retail sales
                rsLag = min(252, N-1);
                measures.RetailSales_YoY = NaN(N, 1);
                if rsLag > 0
                    measures.RetailSales_YoY(rsLag+1:end) = measures.RetailSales_level(rsLag+1:end) ./ measures.RetailSales_level(1:end-rsLag) - 1;
                end

                % Yield curve slope: 10Y - 2Y (in decimal)
                measures.YieldSlope = (measures.TenYr - measures.TwoYr) / 100;

                % Oil (WTI): 3-month return
                oilLag = min(63, N-1);
                measures.Oil_3m_return = NaN(N, 1);
                if oilLag > 0
                    measures.Oil_3m_return(oilLag+1:end) = measures.WTI_level(oilLag+1:end) ./ measures.WTI_level(1:end-oilLag) - 1;
                end

                % Convert rate series from percent to decimal
                measures.FedFunds = measures.FedFunds / 100;
                measures.TenYr = measures.TenYr / 100;
                measures.TwoYr = measures.TwoYr / 100;
                measures.HY_Spread = measures.HY_Spread / 100;
                measures.IG_Spread = measures.IG_Spread / 100;

                % Remove intermediate columns not needed for conditions
                measures = removevars(measures, {'GDP_pct','CPI_level','DXY_level','NFP_level','RetailSales_level','WTI_level'});

                app.Measures = measures;
                app.MeasuresInfoLabel.Text = sprintf('Measures: %d rows, %d columns (from FRED).', height(measures), width(measures)-1);

                msg = sprintf('FRED measures loaded: %d rows, columns: %s.', height(measures), strjoin(measures.Properties.VariableNames(2:end), ', '));
                if ~isempty(failed)
                    msg = [msg sprintf(' Failed: %s.', strjoin(failed, ', '))];
                end
                app.StatusLabel.Text = msg;
            catch ME
                uialert(app.UIFigure, ME.message, 'FRED Download Error');
            end
        end

        function T = downloadFREDSeries(~, seriesID, startDate, endDate)
            url = sprintf('https://fred.stlouisfed.org/graph/fredgraph.csv?bgcolor=%%23e1e9f0&fo=open+sans&id=%s&cosd=%s&coed=%s', ...
                seriesID, startDate, endDate);
            tmpFile = [tempname '.csv'];
            cleanUp = onCleanup(@() delete(tmpFile));
            try
                websave(tmpFile, url);
            catch ME
                error('Failed to download FRED %s: %s', seriesID, ME.message);
            end
            try
                % FRED CSV: columns are observation_date + seriesID
                % Value column may contain '.' for missing — read as text
                opts = detectImportOptions(tmpFile);
                % Find the value column (named after the series ID)
                vnames = opts.VariableNames;
                valIdx = find(~strcmpi(vnames, 'observation_date'), 1);
                if ~isempty(valIdx)
                    opts = setvartype(opts, vnames{valIdx}, 'string');
                end
                raw = readtable(tmpFile, opts);
            catch ME
                error('Failed to parse FRED CSV for %s: %s', seriesID, ME.message);
            end
            if isempty(raw) || height(raw) < 1
                T = table();
                return;
            end
            % Extract date column
            if ismember('observation_date', raw.Properties.VariableNames)
                dt = datetime(raw.observation_date);
            elseif ismember('DATE', raw.Properties.VariableNames)
                dt = datetime(raw.DATE);
            else
                dt = datetime(raw{:,1});
            end
            % Extract value column (second column, named after series ID)
            vnames = raw.Properties.VariableNames;
            valColIdx = ~strcmpi(vnames, 'observation_date') & ~strcmpi(vnames, 'DATE');
            valColName = vnames{find(valColIdx, 1)};
            valRaw = raw.(valColName);
            if isstring(valRaw) || iscellstr(valRaw)
                vals = str2double(valRaw); % '.' becomes NaN automatically
            else
                vals = double(valRaw);
            end
            T = table(dt, vals, 'VariableNames', {'Date','Value'});
            T = T(~isnan(T.Value), :);
            T = sortrows(T, 'Date');
        end

        function vals = forwardFillToTarget(~, srcDates, srcVals, targetDates)
            % Forward-fill srcVals (keyed by srcDates) onto targetDates
            N = numel(targetDates);
            vals = NaN(N, 1);
            srcDates = srcDates(:); srcVals = srcVals(:);
            [srcDates, ord] = sort(srcDates);
            srcVals = srcVals(ord);
            j = 1;
            for i = 1:N
                while j <= numel(srcDates) && srcDates(j) <= targetDates(i)
                    j = j + 1;
                end
                if j > 1
                    vals(i) = srcVals(j-1);
                end
            end
        end

        %----- TAA helpers (asset list → table)
        function onTAAAddSelected(app)
            if isempty(app.AssetNames), return; end
            sel = app.TAAAssetsList.Value;
            if isempty(sel), return; end
            Tcur = app.TAATable.Data;
            if isempty(Tcur) || ~istable(Tcur)
                Tcur = table(strings(0,1), string.empty(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
                    'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
            end
            % Backward compat: add TradeGroup/Leg if missing
            if ~ismember('TradeGroup', Tcur.Properties.VariableNames)
                Tcur.TradeGroup = strings(height(Tcur), 1);
            end
            if ~ismember('Leg', Tcur.Properties.VariableNames)
                Tcur.Leg = strings(height(Tcur), 1);
            end
            for i=1:numel(sel)
                a = string(sel{i});
                if ~any(strcmp(Tcur.Asset, a))
                    newRow = table("", a, 0.0, "", "", 'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
                    % Pad with metric columns if they already exist
                    for mc = {'TE_bps','EqBeta','USD_Sens'}
                        if ismember(mc{1}, Tcur.Properties.VariableNames)
                            newRow.(mc{1}) = 0;
                        end
                    end
                    Tcur = [Tcur; newRow]; %#ok<AGROW>
                end
            end
            app.TAATable.Data = Tcur;
            updateTAAMetrics(app);
            app.StatusLabel.Text = sprintf('Added %d asset(s) to TAA.', numel(sel));
        end

        function onTAARemoveSelected(app)
            sel = app.TAAAssetsList.Value;
            if isempty(sel), return; end
            Tcur = app.TAATable.Data;
            if isempty(Tcur) || height(Tcur)==0, return; end
            keep = true(height(Tcur),1);
            for i=1:numel(sel)
                a = string(sel{i});
                keep = keep & ~(Tcur.Asset == a);
            end
            app.TAATable.Data = Tcur(keep,:);
            app.StatusLabel.Text = sprintf('Removed selected assets from TAA list.');
        end

        function onTAAAddTradePair(app)
            if isempty(app.AssetNames), return; end
            sel = app.TAAAssetsList.Value;
            if numel(sel) ~= 2
                uialert(app.UIFigure, 'Select exactly 2 assets for a trade pair.', 'Trade Pair');
                return;
            end
            Tcur = app.TAATable.Data;
            if isempty(Tcur) || ~istable(Tcur)
                Tcur = table(strings(0,1), string.empty(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
                    'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
            end
            % Auto-name: find max trade number
            maxNum = 0;
            if ismember('TradeGroup', Tcur.Properties.VariableNames)
                for i = 1:height(Tcur)
                    tok = regexp(string(Tcur.TradeGroup(i)), 'Trade(\d+)', 'tokens');
                    if ~isempty(tok), maxNum = max(maxNum, str2double(tok{1}{1})); end
                end
            end
            tName = string(sprintf('Trade%d', maxNum + 1));
            longAsset  = string(sel{1});
            shortAsset = string(sel{2});
            longRow  = table(tName, longAsset,  1.0, "Long",  "", 'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
            shortRow = table(tName, shortAsset, -1.0, "Short", "", 'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
            % Pad with metric columns
            for mc = {'TE_bps','EqBeta','USD_Sens'}
                if ismember(mc{1}, Tcur.Properties.VariableNames)
                    longRow.(mc{1}) = 0; shortRow.(mc{1}) = 0;
                end
            end
            Tcur = [Tcur; longRow; shortRow]; %#ok<AGROW>
            app.TAATable.Data = Tcur;
            updateTAAMetrics(app);
            app.StatusLabel.Text = sprintf('Added trade pair %s: Long %s / Short %s.', tName, longAsset, shortAsset);
        end

        function onTAATableEdited(app)
            updateLegColumn(app);
        end

        function updateLegColumn(app)
            Tcur = app.TAATable.Data;
            if isempty(Tcur) || ~istable(Tcur) || height(Tcur)==0, return; end
            if ~ismember('DeltaPct', Tcur.Properties.VariableNames), return; end
            if ~ismember('Leg', Tcur.Properties.VariableNames)
                Tcur.Leg = strings(height(Tcur), 1);
            end
            for i = 1:height(Tcur)
                d = Tcur.DeltaPct(i);
                if d > 0, Tcur.Leg(i) = "Long";
                elseif d < 0, Tcur.Leg(i) = "Short";
                else, Tcur.Leg(i) = "";
                end
            end
            app.TAATable.Data = Tcur;
        end

        %----- Allocation helpers
        function ensureSAAInitialized(app)
            if isempty(app.SAA) || isempty(app.SAA.Asset)
                base = {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds','Equity_US','Equity_Europe','Equity_Japan','Equity_EM','Commodities','HedgeFunds','Gold', ...
                        'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};
                names = app.AssetNames;
                use = intersect(base, names, 'stable');
                if isempty(use), use = names; end
                % Funded assets share 100%; overlays get 0%
                w = zeros(numel(use),1);
                for ii = 1:numel(use)
                    if ~app.isFXOverlay(use{ii})
                        w(ii) = 1;
                    end
                end
                if sum(w) > 0, w = 100 * w / sum(w); end
                % Force overlay weights to exactly 0
                for ii = 1:numel(use)
                    if app.isFXOverlay(use{ii}), w(ii) = 0; end
                end
                app.SAA = table(string(use(:)), w, repmat("",numel(use),1), 'VariableNames',{'Asset','WeightPct','Description'});
                updateFXOverlayDisplay(app);
            else
                updateFXOverlayDisplay(app);
            end
            if isempty(app.TAA) || ~ismember('Asset', app.TAA.Properties.VariableNames) || isempty(app.TAA.Asset)
                app.TAA = table(strings(0,1), string.empty(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
                    'VariableNames',{'TradeGroup','Asset','DeltaPct','Leg','Description'});
            end
            app.TAATable.Data = app.TAA;
        end

        function resetSAA(app)
            app.SAA = table(string.empty(0,1), zeros(0,1), strings(0,1), 'VariableNames',{'Asset','WeightPct','Description'});
            ensureSAAInitialized(app);
            updateSAAAnalytics(app);
            app.StatusLabel.Text = 'SAA reset to default.';
        end

        function updateSAAAnalytics(app)
            if isempty(app.R) || isempty(app.AssetNames), return; end
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa) ~= size(app.R,2), return; end

            R = app.R; k = app.annFactor();
            rp = R * w_saa;
            mu_p = mean(rp); sig_p = std(rp);
            mu_ann = mu_p * k; vol_ann = sig_p * sqrt(k);
            sharpe_ann = mu_ann / max(1e-12, vol_ann);

            % VaR / CVaR
            VaR95 = app.VaR_hist(rp, 0.95);
            CVaR95 = app.CVaR_hist(rp, 0.95);
            VaR99 = app.VaR_hist(rp, 0.99);
            CVaR99 = app.CVaR_hist(rp, 0.99);

            % Max drawdown
            eq = cumprod(1 + rp);
            dd = 1 - eq ./ cummax(eq);
            maxDD = max(dd);

            % Sortino
            down = rp(rp < 0);
            if numel(down) > 1, dd_std = sqrt(mean(down.^2)); else, dd_std = 1e-12; end
            sortino = mu_ann / max(1e-12, dd_std * sqrt(k));

            % Funded vs overlay weight sums
            fundedPct = 0; fxPct = 0;
            S = app.SAA;
            if ~isempty(S) && istable(S) && ismember('Asset', S.Properties.VariableNames)
                for ii = 1:height(S)
                    if app.isFXOverlay(char(S.Asset(ii)))
                        fxPct = fxPct + S.WeightPct(ii);
                    else
                        fundedPct = fundedPct + S.WeightPct(ii);
                    end
                end
            end

            lines = {
                sprintf('Ann Return: %.2f%%   Ann Vol: %.2f%%   Sharpe: %.3f   Sortino: %.3f', mu_ann*100, vol_ann*100, sharpe_ann, sortino)
                sprintf('VaR95: %.4f   CVaR95: %.4f   VaR99: %.4f   CVaR99: %.4f', VaR95, CVaR95, VaR99, CVaR99)
                sprintf('Max Drawdown: %.2f%%   Obs: %d', maxDD*100, size(R,1))
                sprintf('Funded weight: %.1f%%   FX overlay: %.1f%%', fundedPct, fxPct)
            };
            app.SAAMetricsText.Value = lines;

            % Stress scenario PnL for SAA weights
            updateSAAStressTable(app, w_saa);
        end

        function updateSAAStressTable(app, w_saa)
            % Compute stress PnL using current scenarios
            if isempty(app.Scenarios) || isempty(app.AssetNames), return; end
            S = app.Scenarios;
            names = app.AssetNames;
            vars = S.Properties.VariableNames;

            nScen = height(S);
            scenNames = cell(nScen, 1);
            pnl = zeros(nScen, 1);
            for i = 1:nScen
                scenNames{i} = char(S.Scenario(i));
                for j = 1:numel(names)
                    col = find(strcmp(vars, names{j}), 1);
                    if ~isempty(col)
                        pnl(i) = pnl(i) + S{i, col} * w_saa(j);
                    end
                end
            end
            T = table(string(scenNames), pnl*100, ...
                'VariableNames', {'Scenario','PnL_pct'});
            app.SAAStressTable.Data = T;
        end

        function applyTAA(app)
            S = app.SAA; T = app.TAATable.Data;
            if ~ismember('Asset', S.Properties.VariableNames) || ~ismember('WeightPct', S.Properties.VariableNames)
                uialert(app.UIFigure,'SAA must have columns Asset and WeightPct.','SAA Error'); return;
            end
            if ~ismember('Asset', T.Properties.VariableNames) || ~ismember('DeltaPct', T.Properties.VariableNames)
                uialert(app.UIFigure,'TAA must have columns Asset and DeltaPct.','TAA Error'); return;
            end
            % Validate funded weights sum to ~100% (FX overlays excluded)
            fundedSum = 0;
            for fi = 1:height(S)
                if ~app.isFXOverlay(char(S.Asset(fi)))
                    fundedSum = fundedSum + S.WeightPct(fi);
                end
            end
            if abs(fundedSum-100) > 1e-6
                uialert(app.UIFigure,sprintf('Funded SAA weights sum to %.2f%% (must sum to 100%%). FX overlays excluded.',fundedSum),'SAA Sum Warning'); return;
            end
            % Build combined pct per asset name
            allAssets = unique([string(S.Asset(:)); string(T.Asset(:))],'stable');
            combPct = zeros(numel(allAssets),1);
            for i=1:numel(allAssets)
                a = allAssets(i);
                s = S.WeightPct(strcmp(string(S.Asset), a));
                t = T.DeltaPct(strcmp(string(T.Asset), a));
                combPct(i) = sum(s) + sum(t); % SAA + TAA delta
            end
            % Map to current universe order
            Wpct = zeros(numel(app.AssetNames),1);
            missing = string.empty(0,1);
            for j=1:numel(app.AssetNames)
                a = string(app.AssetNames{j});
                k = find(allAssets==a,1);
                if ~isempty(k), Wpct(j) = combPct(k); else, Wpct(j) = 0; end
            end
            for j=1:numel(allAssets)
                a = string(allAssets(j));
                if ~any(strcmp(app.AssetNames, a)), missing(end+1) = a; end %#ok<AGROW>
            end
            if ~isempty(missing)
                app.StatusLabel.Text = sprintf('Note: TAA instruments not in returns ignored: %s', strjoin(cellstr(missing), ', '));
            end
            if app.NormalizeCombined
                % Normalize funded assets to 100%; FX overlays stay as-is
                fundedIdx = false(numel(app.AssetNames),1);
                for fi = 1:numel(app.AssetNames)
                    fundedIdx(fi) = ~app.isFXOverlay(app.AssetNames{fi});
                end
                fundedSum = sum(Wpct(fundedIdx));
                if fundedSum ~= 0
                    Wpct(fundedIdx) = 100 * Wpct(fundedIdx) / fundedSum;
                end
            end
            app.W = Wpct(:)/100; % fraction
            app.SAA = S; app.TAA = T;
            updateSummary(app); plotDistribution(app); plotSensitivity(app);
            updateTrackingError(app); updateTAAMetrics(app); updatePerformanceTable(app); updateCorrelation(app);
            updateFXOverlayDisplay(app); updateRiskDecomp(app); updateCombinedAnalytics(app);
            updateCombinedFXSplit(app);
            app.StatusLabel.Text = 'Applied TAA to build combined portfolio weights.';
        end

        %----- Measures & bootstrap
        function onLoadMeasures(app)
            try
                [f,p] = uigetfile({'*.csv;*.txt','CSV/TXT Files (*.csv,*.txt)'},'Select Measures CSV');
                if isequal(f,0), return; end
                T = readtable(fullfile(p,f));
                if ismember('Date', T.Properties.VariableNames)
                    try, T.Date = datetime(T.Date); catch, end
                end
                app.Measures = T;
                app.MeasuresInfoLabel.Text = sprintf('Loaded measures: %d rows, %d columns.', height(T), width(T));
                app.StatusLabel.Text = 'Measures loaded.';
            catch ME, uialert(app.UIFigure, ME.message, 'Measures Load Error'); end
        end

        function onRunBootstrap(app)
            if isempty(app.R) || isempty(app.W)
                uialert(app.UIFigure,'Load returns and set weights (apply TAA) first.','No Data'); return;
            end
            if isempty(app.Measures) || height(app.Measures)==0
                % Auto-attempt FRED download if dates are available
                if ~isempty(app.Dates)
                    try
                        onDownloadMeasures(app);
                    catch
                    end
                end
                if isempty(app.Measures) || height(app.Measures)==0
                    uialert(app.UIFigure,'Load a Measures CSV or download FRED data first.','No Measures'); return;
                end
            end
            expr = app.buildConditionExpr();
            app.ConditionText.Value = {expr};  % update hidden text for reference
            try
                idx = app.evalConditionVector(app.Measures, expr);
                if ~any(idx)
                    % Diagnostic: show NaN counts and value ranges for referenced columns
                    diagLines = {sprintf('Condition: %s', expr), ''};
                    allNanCols = {};
                    mVars = app.Measures.Properties.VariableNames;
                    mVars(strcmpi(mVars,'Date')) = [];
                    for di = 1:numel(mVars)
                        v = mVars{di};
                        if contains(expr, v) && isnumeric(app.Measures.(v))
                            col = app.Measures.(v);
                            nNaN = sum(isnan(col));
                            nValid = sum(~isnan(col));
                            if nValid > 0
                                diagLines{end+1} = sprintf('  %s: %d valid, %d NaN, range [%.4g, %.4g]', ...
                                    v, nValid, nNaN, min(col,[],'omitnan'), max(col,[],'omitnan')); %#ok<AGROW>
                            else
                                diagLines{end+1} = sprintf('  %s: ALL NaN (%d rows) — FRED download may have failed', v, nNaN); %#ok<AGROW>
                                allNanCols{end+1} = v; %#ok<AGROW>
                            end
                        end
                    end
                    if ~isempty(allNanCols)
                        diagLines{end+1} = '';
                        diagLines{end+1} = sprintf('Columns with all NaN: %s', strjoin(allNanCols, ', '));
                        diagLines{end+1} = 'Try clicking "Download FRED Measures" to re-download, or remove these conditions.';
                    end
                    uialert(app.UIFigure, strjoin(diagLines, newline), 'No Matches — Diagnostic');
                    return;
                end
                Tret = size(app.R,1);
                Midx = idx(:);
                if numel(Midx) ~= Tret
                    n = min(numel(Midx), Tret);
                    app.StatusLabel.Text = sprintf('Warning: measures (%d rows) and returns (%d rows) differ; using last %d aligned rows.', ...
                        numel(Midx), Tret, n);
                    Midx = Midx(end-n+1:end);
                    Ruse = app.R(end-n+1:end,:);
                else
                    Ruse = app.R;
                end
                selRows = find(Midx);
                if numel(selRows) < 10
                    app.StatusLabel.Text = 'Warning: very few matching rows; bootstrap may be unstable.';
                end

                % ---- Condition match timeline heatmap ----
                if ~isempty(app.BootCondAxes) && isvalid(app.BootCondAxes)
                    cla(app.BootCondAxes);
                    nObs = numel(Midx);
                    x = app.Dates;
                    if isempty(x) || numel(x) < nObs
                        x = (1:nObs)';
                    else
                        x = x(end-nObs+1:end);
                    end
                    % Color strip: green = match, light gray = no match
                    hold(app.BootCondAxes, 'on');
                    if isdatetime(x)
                        % Plot as vertical bars for matched dates
                        matchX = x(Midx);
                        noMatchX = x(~Midx);
                        if ~isempty(noMatchX)
                            stem(app.BootCondAxes, noMatchX, ones(numel(noMatchX),1), 'Marker','none', 'Color',[0.85 0.85 0.85], 'LineWidth',0.5);
                        end
                        if ~isempty(matchX)
                            stem(app.BootCondAxes, matchX, ones(numel(matchX),1), 'Marker','none', 'Color',[0.2 0.7 0.3], 'LineWidth',1);
                        end
                    else
                        % Numeric index: use imagesc for compact display
                        imgData = double(Midx(:))';
                        imagesc(app.BootCondAxes, imgData);
                        colormap(app.BootCondAxes, [0.85 0.85 0.85; 0.2 0.7 0.3]);
                        app.BootCondAxes.CLim = [0 1];
                    end
                    hold(app.BootCondAxes, 'off');
                    nMatch = sum(Midx);
                    pctMatch = 100 * nMatch / nObs;
                    title(app.BootCondAxes, sprintf('Condition Match: %d / %d obs (%.1f%%)', nMatch, nObs, pctMatch));
                    app.BootCondAxes.YTick = [];
                    ylabel(app.BootCondAxes, '');
                end

                block = max(1, round(app.BlockLenField.Value));
                paths = max(1, round(app.PathsField.Value));
                rng(app.RandSeed);
                rp_full = Ruse*app.W;
                Tn = numel(rp_full);
                annK = app.annFactor();
                annRet = zeros(paths,1);
                for b=1:paths
                    seq = app.sampleBlocks(selRows, Tn, block);
                    pathRet = rp_full(seq);
                    mu_p = mean(pathRet);
                    annRet(b) = mu_p * annK;
                end
                app.LastBootstrapDist = annRet;
                cla(app.BootstrapAxes);
                histogram(app.BootstrapAxes, annRet, 40);
                title(app.BootstrapAxes, 'Bootstrap: annualized returns');
                m = mean(annRet); s = std(annRet);
                q = quantile(annRet,[0.05 0.5 0.95]);

                Rsel = Ruse(selRows,:);
                rp_sel = Rsel*app.W;
                C = corrcoef([rp_sel Rsel]);
                rho_p_assets = C(1, 2:end);
                [~,ix_hi] = maxk(rho_p_assets, min(3,numel(rho_p_assets)));
                [~,ix_lo] = mink(rho_p_assets, min(3,numel(rho_p_assets)));
                hi_list = strjoin(app.AssetNames(ix_hi), ', ');
                lo_list = strjoin(app.AssetNames(ix_lo), ', ');

                % Conditional annualized return & volatility per asset + portfolio
                nA = numel(app.AssetNames);
                condMu  = mean(Rsel, 1) * annK;        % annualized mean
                condVol = std(Rsel, 0, 1) * sqrt(annK); % annualized vol
                condSR  = condMu ./ max(condVol, 1e-12); % Sharpe ratio
                % Portfolio row
                portMu  = mean(rp_sel) * annK;
                portVol = std(rp_sel) * sqrt(annK);
                portSR  = portMu / max(portVol, 1e-12);
                % Also compute unconditional stats for comparison
                uncMu   = mean(Ruse, 1) * annK;
                uncVol  = std(Ruse, 0, 1) * sqrt(annK);
                rp_unc  = Ruse * app.W;
                uncPortMu  = mean(rp_unc) * annK;
                uncPortVol = std(rp_unc) * sqrt(annK);

                assetLabels = [app.AssetNames(:); {'PORTFOLIO'}];
                retCond  = [condMu(:)*100; portMu*100];
                volCond  = [condVol(:)*100; portVol*100];
                srCond   = [condSR(:); portSR];
                retUnc   = [uncMu(:)*100; uncPortMu*100];
                volUnc   = [uncVol(:)*100; uncPortVol*100];

                statsTbl = table(string(assetLabels), ...
                    round(retCond,2), round(volCond,2), round(srCond,2), ...
                    round(retUnc,2), round(volUnc,2), ...
                    'VariableNames', {'Asset','Ret_pct','Vol_pct','Sharpe','Unc_Ret','Unc_Vol'});
                app.BootStatsTable.Data = statsTbl;
                app.BootStatsTable.ColumnName = {'Asset','Ret%','Vol%','Sharpe','Unc Ret%','Unc Vol%'};
                app.BootStatsTable.ColumnWidth = {100,50,50,48,55,55};

                % Compute scenario-optimal weights (Max Sharpe on conditional subset)
                optLines = {};
                try
                    mu_s = mean(Rsel,1)'; Sigma_s = cov(Rsel);
                    N_a = numel(app.AssetNames);
                    w0_s = ones(N_a,1)/N_a;
                    LB_s = zeros(N_a,1); UB_s = ones(N_a,1);
                    Aeq_s = ones(1,N_a); beq_s = 1;
                    fun_s = @(w) -((w'*mu_s - app.RF) / max(1e-12, sqrt(w'*Sigma_s*w)));
                    opts_s = optimoptions('fmincon','Display','none','Algorithm','sqp');
                    w_opt = fmincon(fun_s, w0_s, [],[], Aeq_s, beq_s, LB_s, UB_s, [], opts_s);
                    optLines{end+1} = 'Scenario-optimal weights (Max Sharpe):';
                    for ai = 1:N_a
                        if abs(w_opt(ai)) > 0.005
                            optLines{end+1} = sprintf('  %s: %.1f%%', app.AssetNames{ai}, 100*w_opt(ai)); %#ok<AGROW>
                        end
                    end
                catch
                    optLines{end+1} = 'Scenario-optimal weights: optimization failed.';
                end

                summaryLines = {
                    sprintf('Rows matched: %d  |  Paths: %d  |  Block: %d', sum(Midx), paths, block)
                    sprintf('Ann. return: mean=%.4f  std=%.4f  |  Q[5/50/95%%]: %.4f / %.4f / %.4f', m, s, q(1), q(2), q(3))
                    sprintf('Top +corr: %s  |  Top -corr: %s', hi_list, lo_list)
                    };
                app.BootstrapSummary.Value = [summaryLines(:); optLines(:)];
                app.StatusLabel.Text = 'Conditional bootstrap completed.';
            catch ME
                uialert(app.UIFigure, ME.message, 'Bootstrap Error');
            end
        end
    end

    %================ DATA & RISK =================
    methods (Access = private)
        function [R, namesOut, RawOut] = parseTableToReturns(app, T, datatype) %#ok<INUSL>
            % Extract date if present
            hasDate = ismember('Date', T.Properties.VariableNames);
            if hasDate
                try, dt = datetime(T.Date); catch, dt = T.Date; end
            else
                dt = [];
            end
            varNames = T.Properties.VariableNames;
            idDate = find(strcmpi(varNames,'Date'),1);
            if ~isempty(idDate), data = T(:, setdiff(1:width(T), idDate)); else, data = T; end
            X = table2array(data);
            if ~isnumeric(X), error('Data columns must be numeric.'); end
            namesOut = data.Properties.VariableNames;

            if strcmpi(datatype,'Prices')
                R = diff(log(X));    % M-1 x N
                if ~isempty(dt), dt = dt(2:end); end
            else
                R = X;               % M x N
            end

            bad = any(~isfinite(R),2);
            R = R(~bad,:);
            if ~isempty(dt)
                if numel(dt) ~= size(R,1)
                    % Align by taking the last rows (common in price->return trim)
                    dt = dt(end-size(R,1)+1:end);
                end
                app.Dates = dt;
            else
                app.Dates = (1:size(R,1))';
            end

            RawOut = array2table(R);
            tmp = cell(1,numel(namesOut));
            for i=1:numel(namesOut), tmp{i} = char(string(namesOut{i})); end
            RawOut.Properties.VariableNames = tmp;
        end

        function ensureWeights(app)
            if isempty(app.R), return; end
            N = size(app.R,2);
            if isempty(app.W) || numel(app.W)~=N
                app.W = ones(N,1)/N;
            end
        end

        function w = getSAAWeightsVector(app)
            % Map SAA master table (pct) to current AssetNames vector (fraction)
            N = numel(app.AssetNames); w = zeros(N,1);
            if isempty(app.SAA) || ~istable(app.SAA) || height(app.SAA) == 0, return; end
            S = app.SAA;
            if ~ismember('Asset', S.Properties.VariableNames) || ~ismember('WeightPct', S.Properties.VariableNames)
                return;
            end
            for j=1:N
                a = string(app.AssetNames{j});
                s = S.WeightPct(strcmp(string(S.Asset), a));
                if ~isempty(s), w(j) = sum(s)/100; end
            end
            % Normalize funded weights to sum to 1; FX overlays kept as fraction
            fundedW = 0;
            for j2=1:N
                if ~app.isFXOverlay(app.AssetNames{j2}), fundedW = fundedW + w(j2); end
            end
            if fundedW > 0
                for j2=1:N
                    if ~app.isFXOverlay(app.AssetNames{j2}), w(j2) = w(j2) / fundedW; end
                end
            end
        end

        function updateSummary(app)
            if isempty(app.R), return; end
            app.ensureWeights();
            R = app.R; w = app.W; names = app.AssetNames;
            mu = mean(R,1)'; Sigma = cov(R); rp = R*w;
            switch lower(app.Freq)
                case 'daily',   k=252;
                case 'weekly',  k=52;
                case 'monthly', k=12;
                otherwise, k=252;
            end
            mu_p = w'*mu; sig_p = sqrt(max(0, w'*Sigma*w)); sharpe = (mu_p - app.RF)/max(1e-12,sig_p);
            eqCurve = cumprod(1+rp); dd = 1 - eqCurve./max(eqCurve); maxDD = max(dd);
            method = app.VaRMethodDropDown.Value;
            alpha = app.Alpha; h = max(1, round(app.Horizon));
            switch method
                case 'Historical', VaR1 = app.VaR_hist(rp, alpha); CVaR1 = app.CVaR_hist(rp, alpha);
                case 'Parametric (Normal)', VaR1 = app.VaR_parametric(mu_p, sig_p, alpha, h); CVaR1 = app.CVaR_parametric(mu_p, sig_p, alpha, h);
                case 'Monte Carlo (Normal)', rng(app.RandSeed); [VaR1,CVaR1] = app.VaR_CVaR_MC(mu_p, sig_p, alpha, h, app.MCPaths);
                otherwise, VaR1=NaN; CVaR1=NaN;
            end
            % Historical VaR/CVaR: no sqrt(h) scaling (non-parametric quantiles)
            % Parametric and MC methods already incorporate horizon internally.
            mu_ann = mu_p * k; vol_ann = sig_p * sqrt(k); sharpe_ann = (mu_ann - app.RF*k)/max(1e-12,vol_ann);
            % Sortino ratio (downside deviation)
            rp_excess = rp - app.RF;
            downside = rp_excess(rp_excess < 0);
            if numel(downside) > 1
                dd_std = sqrt(mean(downside.^2));
            else
                dd_std = 1e-12;
            end
            sortino_ann = (mu_ann - app.RF*k) / max(1e-12, dd_std * sqrt(k));
            % Calmar ratio
            calmar = mu_ann / max(1e-12, maxDD);
            % Higher moments
            sk = skewness(rp);
            ku = kurtosis(rp);
            % Multi-level ES (VaR/CVaR at 90/95/99%)
            alphas = [0.90 0.95 0.99];
            VaRs = zeros(1,3); CVaRs = zeros(1,3);
            for ai = 1:3
                VaRs(ai) = app.VaR_hist(rp, alphas(ai));
                CVaRs(ai) = app.CVaR_hist(rp, alphas(ai));
            end

            lines = {
                sprintf('Obs: %d   Assets: %d', size(R,1), size(R,2))
                sprintf('Mean(per): %.6f   Vol: %.6f   Sharpe: %.3f', mu_p, sig_p, sharpe)
                sprintf('Mean(ann): %.4f   Vol(ann): %.4f   Sharpe(ann): %.3f', mu_ann, vol_ann, sharpe_ann)
                sprintf('Sortino(ann): %.3f   Calmar: %.3f', sortino_ann, calmar)
                sprintf('Skewness: %.3f   Kurtosis: %.3f', sk, ku)
                sprintf('Max Drawdown: %.2f%%', 100*maxDD)
                sprintf('VaR @ %.1f%% (h=%d): %.4f   CVaR: %.4f   Method: %s', 100*alpha, h, VaR1, CVaR1, method)
                sprintf('ES (hist): VaR90=%.4f CVaR90=%.4f | VaR95=%.4f CVaR95=%.4f | VaR99=%.4f CVaR99=%.4f', VaRs(1),CVaRs(1),VaRs(2),CVaRs(2),VaRs(3),CVaRs(3))
                sprintf('rf(per): %.6f   Long-only: %d   Bounds [%.2f, %.2f]', app.RF, app.LongOnly, app.LB, app.UB)
                };
            % Append scenario PnL lines directly (computed inline)
            scenLines = computeScenarioLines(app);
            if ~isempty(scenLines)
                lines = [lines; scenLines(:)];
            end
            app.SummaryText.Value = lines;

            contrib = (Sigma*w); RC = w .* contrib;
            Tcomb = table(names(:), w(:), RC(:), 'VariableNames',{'Asset','Weight','RiskContribution'});
            app.WeightsTable.Data = Tcomb;

            % Mirror to Combined tab (with FX split)
            updateCombinedFXSplit(app);
        end

        function updateTrackingError(app)
            if isempty(app.R) || isempty(app.W), return; end
            Sigma = cov(app.R);
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa)~=numel(app.W), return; end
            wdiff = app.W - w_saa;
            per = app.annFactor();
            TE2 = max(0, wdiff' * Sigma * wdiff);
            TE_per = sqrt(TE2);
            TE_ann = TE_per * sqrt(per);

            m = Sigma * wdiff;               % marginal (variance) contributions
            RC = wdiff .* m;                 % variance contributions
            share = zeros(size(RC));
            if TE2>0, share = RC / TE2; end

            app.TELabel.Text = sprintf('Tracking Error vs SAA (annualized): %.4f', TE_ann);
            app.TETable.Data = table(app.AssetNames(:), wdiff(:), RC(:), share(:), ...
                                     'VariableNames',{'Asset','ActiveWeight','TE_RC','TE_RC_Pct'});
        end

        function updateTAAMetrics(app)
            % Populate TE_bps, EqBeta, USD_Sens columns in TAATable
            Tcur = app.TAATable.Data;
            if isempty(Tcur) || ~istable(Tcur) || height(Tcur) == 0, return; end
            if isempty(app.R) || isempty(app.AssetNames), return; end

            R = app.R;
            names = app.AssetNames;
            Sigma = cov(R);
            per = app.annFactor();
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa) ~= size(R,2)
                w_saa = zeros(size(R,2),1);
            end

            % Find equity and USD reference columns
            eqIdx = find(strcmp(names, 'Equity_US'), 1);
            usdIdx = find(strcmp(names, 'USD_Cash'), 1);

            nRows = height(Tcur);
            te_bps = zeros(nRows, 1);
            eqBeta = zeros(nRows, 1);
            usdSens = zeros(nRows, 1);

            for i = 1:nRows
                a = string(Tcur.Asset(i));
                aIdx = find(strcmp(names, a), 1);
                if isempty(aIdx), continue; end

                delta = 0;
                if ismember('DeltaPct', Tcur.Properties.VariableNames)
                    delta = Tcur.DeltaPct(i) / 100; % fraction
                end

                % Marginal TE: impact of this delta on tracking error vs SAA
                % TE = sqrt(wdiff' * Sigma * wdiff) where wdiff includes this delta
                wdiff_base = zeros(size(R,2), 1); % other deltas excluded for marginal
                wdiff_base(aIdx) = delta;
                te_var = max(0, wdiff_base' * Sigma * wdiff_base);
                te_bps(i) = sqrt(te_var) * sqrt(per) * 10000; % annualized bps

                % Equity beta: cov(asset, equity) / var(equity)
                if ~isempty(eqIdx)
                    eqBeta(i) = Sigma(aIdx, eqIdx) / max(1e-20, Sigma(eqIdx, eqIdx));
                end

                % USD sensitivity: cov(asset, USD_Cash) / var(USD_Cash)
                if ~isempty(usdIdx)
                    usdSens(i) = Sigma(aIdx, usdIdx) / max(1e-20, Sigma(usdIdx, usdIdx));
                end
            end

            Tcur.TE_bps = round(te_bps, 1);
            Tcur.EqBeta = round(eqBeta, 3);
            Tcur.USD_Sens = round(usdSens, 3);
            app.TAATable.Data = Tcur;

            % ---- Trade-level summary ----
            if ~ismember('TradeGroup', Tcur.Properties.VariableNames)
                app.TAATradeTable.Data = table();
                return;
            end
            groups = unique(Tcur.TradeGroup);
            groups = groups(strlength(groups) > 0); % skip empty
            if isempty(groups)
                app.TAATradeTable.Data = table();
                return;
            end
            nG = numel(groups);
            tLegs = strings(nG,1);
            tTE = zeros(nG,1);
            tBeta = zeros(nG,1);
            tUSD = zeros(nG,1);
            for gi = 1:nG
                mask = Tcur.TradeGroup == groups(gi);
                rows = Tcur(mask,:);
                % Build combined delta weight vector for this trade
                wdiff_trade = zeros(size(R,2), 1);
                legParts = strings(0,1);
                for ri = 1:height(rows)
                    a = string(rows.Asset(ri));
                    aIdx = find(strcmp(names, a), 1);
                    if isempty(aIdx), continue; end
                    d = rows.DeltaPct(ri) / 100;
                    wdiff_trade(aIdx) = wdiff_trade(aIdx) + d;
                    if d > 0
                        legParts(end+1) = "L:" + a; %#ok<AGROW>
                    elseif d < 0
                        legParts(end+1) = "S:" + a; %#ok<AGROW>
                    end
                end
                tLegs(gi) = strjoin(legParts, " / ");
                % Combined TE
                te_var_trade = max(0, wdiff_trade' * Sigma * wdiff_trade);
                tTE(gi) = round(sqrt(te_var_trade) * sqrt(per) * 10000, 1);
                % Combined equity beta: sum of (delta_i * beta_i)
                if ~isempty(eqIdx)
                    tBeta(gi) = round(wdiff_trade' * Sigma(:, eqIdx) / max(1e-20, Sigma(eqIdx, eqIdx)), 3);
                end
                % Combined USD sensitivity
                if ~isempty(usdIdx)
                    tUSD(gi) = round(wdiff_trade' * Sigma(:, usdIdx) / max(1e-20, Sigma(usdIdx, usdIdx)), 3);
                end
            end
            app.TAATradeTable.Data = table(groups(:), tLegs(:), tTE(:), tBeta(:), tUSD(:), ...
                'VariableNames',{'TradeGroup','Legs','TE_bps','EqBeta','USD_Sens'});
        end

              function updatePerformanceTable(app)
            if isempty(app.R) || isempty(app.W), return; end
            R = app.R; per = app.annFactor();
        
            % SAA baseline weights (fraction)
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa)~=size(R,2)
                return;
            end
        
            rpSAA  = R * w_saa;
            rpComb = R * app.W;
        
            % Cumulative perf (index-1)
            cumSAA  = cumprod(1+rpSAA) - 1;
            cumComb = cumprod(1+rpComb) - 1;
        
            % Rolling vol (annualized)
            L = max(2, round(app.PerfRollingField.Value));
            rvSAA  = movstd(rpSAA,  L) * sqrt(per);
            rvComb = movstd(rpComb, L) * sqrt(per);
        
            % X-axis: dates or index
            x = app.Dates;
            if isempty(x) || numel(x) ~= size(R,1)
                x = (1:size(R,1))';
            end
        
            % ---- Plot: Cumulative Performance
            if ~isempty(app.PerfAxesCum) && isvalid(app.PerfAxesCum)
                cla(app.PerfAxesCum);
                plot(app.PerfAxesCum, x, cumSAA,  'DisplayName','SAA'); hold(app.PerfAxesCum,'on');
                plot(app.PerfAxesCum, x, cumComb, 'DisplayName','Combined');
                hold(app.PerfAxesCum,'off');
                legend(app.PerfAxesCum,'show','Location','best');
                if ~isdatetime(x), xlabel(app.PerfAxesCum,'Observation'); end
                app.PerfAxesCum.XGrid='on'; app.PerfAxesCum.YGrid='on';
            end
        
            % ---- Plot: Rolling Volatility
            if ~isempty(app.PerfAxesVol) && isvalid(app.PerfAxesVol)
                cla(app.PerfAxesVol);
                plot(app.PerfAxesVol, x, rvSAA,  'DisplayName','SAA'); hold(app.PerfAxesVol,'on');
                plot(app.PerfAxesVol, x, rvComb, 'DisplayName','Combined');
                hold(app.PerfAxesVol,'off');
                legend(app.PerfAxesVol,'show','Location','best');
                if ~isdatetime(x), xlabel(app.PerfAxesVol,'Observation'); end
                app.PerfAxesVol.XGrid='on'; app.PerfAxesVol.YGrid='on';
            end
        
            % ---- Plot: Drawdown (Underwater)
            eqSAA  = cumprod(1+rpSAA);
            eqComb = cumprod(1+rpComb);
            ddSAA  = eqSAA  ./ cummax(eqSAA)  - 1;
            ddComb = eqComb ./ cummax(eqComb) - 1;
            if ~isempty(app.PerfAxesDD) && isvalid(app.PerfAxesDD)
                cla(app.PerfAxesDD);
                hold(app.PerfAxesDD,'on');
                area(app.PerfAxesDD, x, ddSAA,  'FaceAlpha',0.3, 'DisplayName','SAA');
                area(app.PerfAxesDD, x, ddComb, 'FaceAlpha',0.3, 'DisplayName','Combined');
                hold(app.PerfAxesDD,'off');
                legend(app.PerfAxesDD,'show','Location','best');
                title(app.PerfAxesDD,'Drawdown (Underwater)');
                if ~isdatetime(x), xlabel(app.PerfAxesDD,'Observation'); end
                app.PerfAxesDD.XGrid='on'; app.PerfAxesDD.YGrid='on';
            end

            % ---- Table
            app.PerfTable.Data = table(x, cumSAA, cumComb, rvSAA, rvComb, ddSAA, ddComb, ...
                'VariableNames', {'Date','Cum_SAA','Cum_Combined','RollVol_SAA','RollVol_Combined','DD_SAA','DD_Combined'});
            % Update performance table column count for editability
            app.PerfTable.ColumnEditable = false(1, 7);
        end


        function plotDistribution(app)
            if isempty(app.R) || isempty(app.W), return; end
            if isempty(app.DistAxes) || ~isvalid(app.DistAxes), return; end
            rp = app.R*app.W; cla(app.DistAxes); histogram(app.DistAxes, rp, 50);
            title(app.DistAxes,'Portfolio Return Distribution'); xlabel(app.DistAxes,'Return'); ylabel(app.DistAxes,'Frequency');
        end

        function plotSensitivity(app)
            if isempty(app.R) || isempty(app.W), return; end
            if isempty(app.SensAxes) || ~isvalid(app.SensAxes), return; end
            names = app.AssetNames; w = app.W; dPnL = 0.01 .* w; cla(app.SensAxes);
            bar(app.SensAxes, dPnL); xticks(app.SensAxes,1:numel(names)); xticklabels(app.SensAxes, names); app.SensAxes.XTickLabelRotation = 45;
            title(app.SensAxes,'dPnL for +1% Asset Shock'); xlabel(app.SensAxes,'Asset'); ylabel(app.SensAxes,'Delta PnL');
        end

        %----- Scenario table
        function refreshScenariosTable(app)
            names = app.AssetNames;
            if isempty(names), app.ScenTable.Data = table(); return; end
            varNames = [{'Scenario'}, names];
            Scen = table({'ShockMinus5All';'ShockMinus10All';'Custom0'},'VariableNames',{'Scenario'});
            Z = zeros(3, numel(names)); Z(1,:)=-0.05; Z(2,:)=-0.10;
            S = [Scen array2table(Z)];
            S.Properties.VariableNames = varNames;
            app.Scenarios = S;
            refreshScenarioDisplay(app);
            computeScenarioPnL(app);
        end

        function onScenarioChanged(app)
            % Map edits from transposed display back to app.Scenarios
            D = app.ScenTable.Data;
            if isempty(D) || ~istable(D), return; end
            names = app.AssetNames;
            nAssets = numel(names);
            if isempty(app.Scenarios), return; end
            S = app.Scenarios;
            nScen = height(S);
            scenCols = D.Properties.VariableNames(2:end);  % scenario column names
            % The return rows are rows 2..(nAssets+1) in the display table
            for si = 1:min(nScen, numel(scenCols))
                scenCol = scenCols{si};
                for ai = 1:nAssets
                    displayRow = 1 + ai;  % row 1=impact, rows 2..nAssets+1=returns
                    val = D{displayRow, scenCol};
                    if isnumeric(val) && isfinite(val)
                        assetCol = find(strcmp(S.Properties.VariableNames, names{ai}), 1);
                        if ~isempty(assetCol)
                            S{si, assetCol} = val / 100;  % display is %, internal is decimal
                        end
                    end
                end
            end
            app.Scenarios = S;
            refreshScenarioDisplay(app);
            computeScenarioPnL(app);
        end

        function refreshScenarioDisplay(app)
            % Build transposed display: scenarios as columns, assets as rows
            % Row structure: Portfolio Impact | asset returns (%) | asset contributions (%)
            if isempty(app.Scenarios) || isempty(app.AssetNames)
                app.ScenTable.Data = table(); return;
            end
            S = app.Scenarios; names = app.AssetNames; w = app.W;
            nScen = height(S);
            nAssets = numel(names);
            if isempty(w), w = zeros(nAssets, 1); end

            % Compute shocks matrix and portfolio impacts
            shockMat = zeros(nScen, nAssets);
            for si = 1:nScen
                for ai = 1:nAssets
                    col = find(strcmp(S.Properties.VariableNames, names{ai}), 1);
                    if ~isempty(col), shockMat(si, ai) = S{si, col}; end
                end
            end
            pnls = shockMat * w(:);           % portfolio impact per scenario
            contribs = shockMat .* w(:)';     % nScen x nAssets contribution matrix

            % Build row labels
            nRows = 1 + nAssets + 1 + nAssets;  % impact + returns + separator + contributions
            rowLabels = cell(nRows, 1);
            rowLabels{1} = 'PORTFOLIO IMPACT (%)';
            for ai = 1:nAssets
                rowLabels{1 + ai} = sprintf('%s (ret %%)', names{ai});
            end
            rowLabels{1 + nAssets + 1} = '--- CONTRIBUTIONS (%) ---';
            for ai = 1:nAssets
                rowLabels{1 + nAssets + 1 + ai} = sprintf('%s (w x r %%)', names{ai});
            end

            % Build scenario column names (sanitize for table variable names)
            scenNames = cell(1, nScen);
            for si = 1:nScen
                sn = char(string(S.Scenario(si)));
                sn = regexprep(sn, '[^a-zA-Z0-9]', '_');
                if isempty(sn) || ~isnan(str2double(sn(1)))
                    sn = ['S' sn]; %#ok<AGROW>
                end
                scenNames{si} = sn;
            end
            % Ensure unique names
            scenNames = matlab.lang.makeUniqueStrings(scenNames);

            % Build data matrix (all in %)
            dataMat = NaN(nRows, nScen);
            for si = 1:nScen
                dataMat(1, si) = pnls(si) * 100;               % portfolio impact %
                for ai = 1:nAssets
                    dataMat(1 + ai, si) = shockMat(si, ai) * 100;         % return %
                    dataMat(1 + nAssets + 1 + ai, si) = contribs(si, ai) * 100;  % contribution %
                end
                dataMat(1 + nAssets + 1, si) = NaN;  % separator row
            end

            % Build display table
            T = array2table(dataMat, 'VariableNames', scenNames);
            T = [table(rowLabels, 'VariableNames', {'Metric'}), T];

            % Add original scenario names as column headers via display
            % Use original scenario names for column headers
            origNames = cell(1, nScen);
            for si = 1:nScen
                origNames{si} = char(string(S.Scenario(si)));
            end

            app.ScenTable.Data = T;
            % First column (labels) not editable; scenario columns editable
            ce = true(1, nScen + 1); ce(1) = false;
            app.ScenTable.ColumnEditable = ce;
            app.ScenTable.ColumnWidth = [{180}, repmat({110}, 1, nScen)];

            % Set column names to original scenario names for readability
            app.ScenTable.ColumnName = [{'Metric'}, origNames];
        end

        function lines = computeScenarioLines(app)
            lines = {};
            if isempty(app.R) || isempty(app.W) || isempty(app.Scenarios), return; end
            S = app.Scenarios; names = app.AssetNames; w = app.W;
            vars = S.Properties.VariableNames;
            idKeep = false(1, numel(vars));
            for i=1:numel(vars), idKeep(i) = any(strcmp(vars{i}, names)); end
            shocks = S{:, idKeep};
            wShort = zeros(sum(idKeep),1); k=0;
            for i=1:numel(vars)
                if idKeep(i), k=k+1; idx=find(strcmp(names,vars{i}),1); wShort(k)=w(idx); end
            end
            pnl = shocks * wShort;
            lines{end+1} = 'Scenarios (approx PnL):';
            for i=1:height(S), lines{end+1} = sprintf('  - %s : %+0.3f', string(S.Scenario(i)), pnl(i)); end %#ok<AGROW>
        end

        function computeScenarioPnL(app)
            % Legacy wrapper: recompute full summary (which now includes scenarios)
            updateSummary(app);
            updateScenarioStats(app);
        end

        function updateScenarioStats(app)
            % Compute portfolio-level stats summary for scenarios
            if isempty(app.Scenarios) || isempty(app.R) || isempty(app.W)
                if ~isempty(app.ScenStatsText), app.ScenStatsText.Value = {'No scenario data or weights available.'}; end
                return;
            end
            S = app.Scenarios; names = app.AssetNames; w = app.W;
            vars = S.Properties.VariableNames;
            nScen = height(S);
            pnls = zeros(nScen, 1);
            for si = 1:nScen
                pnl_i = 0;
                for ai = 1:numel(names)
                    col = find(strcmp(vars, names{ai}), 1);
                    if ~isempty(col)
                        pnl_i = pnl_i + S{si, col} * w(ai);
                    end
                end
                pnls(si) = pnl_i;
            end
            lines = {};
            lines{end+1} = 'SCENARIO SUMMARY';
            lines{end+1} = '─────────────────────────────────────────────';
            lines{end+1} = sprintf('  Worst scenario:   %+.2f%%  (%s)', min(pnls)*100, char(string(S.Scenario(pnls==min(pnls)))));
            lines{end+1} = sprintf('  Best scenario:    %+.2f%%  (%s)', max(pnls)*100, char(string(S.Scenario(pnls==max(pnls)))));
            lines{end+1} = sprintf('  Average PnL:      %+.2f%%', mean(pnls)*100);
            app.ScenStatsText.Value = lines;
        end

        %----- Solvers & Risk helpers
        function [hasQP,hasFmin,hasGA] = checkSolvers(~)
            hasQP  = ~isempty(which('quadprog')); hasFmin = ~isempty(which('fmincon')); hasGA = ~isempty(which('ga'));
        end
        function v = VaR_hist(~, rp, alpha), v = quantile(-rp(:), alpha); end
        function c = CVaR_hist(~, rp, alpha), L=-rp(:); v=quantile(L,alpha); t=L(L>=v); if isempty(t), c=v; else, c=mean(t); end, end

        function z = z_from_alpha(~, alpha)
            z = sqrt(2) * erfinv(2*alpha - 1); % standard normal quantile via erfinv
        end
        function phi = normpdf_local(~, z)
            phi = (1/sqrt(2*pi))*exp(-0.5*z.^2);
        end
        function v = VaR_parametric(app, mu, sigma, alpha, h)
            z=app.z_from_alpha(alpha); v=max(0, z*sigma*sqrt(h)-mu*h);
        end
        function c = CVaR_parametric(app, mu, sigma, alpha, h)
            z=app.z_from_alpha(alpha); c=max(0, (app.normpdf_local(z)/(1-alpha))*sigma*sqrt(h)-mu*h);
        end
        function [v,c] = VaR_CVaR_MC(app, mu, sigma, alpha, h, M)
            Z=randn(M,1); rp=mu*h+sigma*sqrt(h)*Z; v=app.VaR_hist(rp,alpha); c=app.CVaR_hist(rp,alpha);
        end

        function f = riskParityObjective(~, Sigma, w)
            if any(~isfinite(w)) || any(w < -1e-8) || abs(sum(w)-1) > 1e-3
                f = 1e6; return;
            end
            sigp2 = w' * Sigma * w;
            if sigp2 <= 0, f = 1e6; return; end
            m  = Sigma * w;
            RC = w .* m;
            N = numel(w);
            target = sigp2 / N;
            f = sum((RC - target).^2);
        end

        %----- Correlation heatmap & rolling correlation
        function updateCorrelation(app)
            if isempty(app.R) || isempty(app.W), return; end
            R = app.R; names = app.AssetNames; w = app.W;
            C = corrcoef(R);
            N = size(R,2);

            % Heatmap
            if ~isempty(app.CorrAxes) && isvalid(app.CorrAxes)
                cla(app.CorrAxes);
                imagesc(app.CorrAxes, C);
                colorbar(app.CorrAxes);
                app.CorrAxes.CLim = [-1 1];
                colormap(app.CorrAxes, app.blueWhiteRedMap());
                app.CorrAxes.XTick = 1:N; app.CorrAxes.YTick = 1:N;
                app.CorrAxes.XTickLabel = names; app.CorrAxes.YTickLabel = names;
                app.CorrAxes.XTickLabelRotation = 45;
                title(app.CorrAxes, 'Correlation Heatmap');
                % Add text annotations
                for ii = 1:N
                    for jj = 1:N
                        text(app.CorrAxes, jj, ii, sprintf('%.2f', C(ii,jj)), ...
                            'HorizontalAlignment','center','FontSize',8);
                    end
                end
            end

            % Rolling correlation vs portfolio
            if ~isempty(app.CorrRollAxes) && isvalid(app.CorrRollAxes)
                cla(app.CorrRollAxes);
                L = max(5, round(app.CorrWindowField.Value));
                rp = R * w;
                x = app.Dates;
                if isempty(x) || numel(x) ~= size(R,1), x = (1:size(R,1))'; end
                hold(app.CorrRollAxes,'on');
                for j = 1:N
                    rc = app.rollingCorr(R(:,j), rp, L);
                    plot(app.CorrRollAxes, x, rc, 'DisplayName', names{j});
                end
                hold(app.CorrRollAxes,'off');
                legend(app.CorrRollAxes,'show','Location','best','FontSize',7);
                title(app.CorrRollAxes, sprintf('Rolling %d-period Correlation vs Portfolio', L));
            end
            % PCA eigenvalue decomposition
            updateEigenDecomp(app);
        end

        function rc = rollingCorr(~, x, y, L)
            T = numel(x);
            rc = NaN(T,1);
            for t = L:T
                seg_x = x(t-L+1:t);
                seg_y = y(t-L+1:t);
                tmp = corrcoef(seg_x, seg_y);
                rc(t) = tmp(1,2);
            end
        end

        function cmap = blueWhiteRedMap(~)
            n = 128;
            r = [linspace(0,1,n), ones(1,n)];
            g = [linspace(0,1,n), linspace(1,0,n)];
            b = [ones(1,n), linspace(1,0,n)];
            cmap = [r(:), g(:), b(:)];
        end

        %----- Efficient Frontier
        function computeEfficientFrontier(app)
            if isempty(app.R) || isempty(app.W)
                uialert(app.UIFigure,'Load data first.','No Data'); return;
            end
            try
                app.StatusLabel.Text = 'Computing efficient frontier...'; drawnow;
                R = app.R; mu = mean(R,1)'; Sigma = cov(R);
                N = size(R,2);
                k = app.annFactor();
                rf = app.RF;
                nPts = max(10, round(app.FrontierPointsField.Value));
                longOnly = app.LongOnly;
                lb = app.LB; ub = app.UB;
                if longOnly, LB = max(0,lb)*ones(N,1); else, LB = lb*ones(N,1); end
                UB = ub*ones(N,1);
                Aeq = ones(1,N); beq = 1;

                % Target return range
                mu_min = min(mu); mu_max = max(mu);
                targets = linspace(mu_min, mu_max, nPts);

                fVols = NaN(nPts,1); fRets = NaN(nPts,1);
                opts = optimoptions('quadprog','Display','off');
                H = 2*Sigma; f = zeros(N,1);
                for i = 1:nPts
                    Aeq2 = [ones(1,N); mu']; beq2 = [1; targets(i)];
                    [w,~,flag] = quadprog(H,f,[],[],Aeq2,beq2,LB,UB,[],opts);
                    if flag > 0
                        fRets(i) = w'*mu * k;
                        fVols(i) = sqrt(max(0, w'*Sigma*w)) * sqrt(k);
                    end
                end
                valid = ~isnan(fVols);
                fVols = fVols(valid); fRets = fRets(valid);

                % Individual assets
                aVols = sqrt(diag(Sigma)) * sqrt(k);
                aRets = mu * k;

                % Current portfolio
                pRet = app.W'*mu * k;
                pVol = sqrt(max(0, app.W'*Sigma*app.W)) * sqrt(k);

                % Max Sharpe tangent
                funS = @(w) -((w'*mu - rf) / max(1e-12, sqrt(w'*Sigma*w)));
                optsF = optimoptions('fmincon','Display','none','Algorithm','sqp');
                w0 = ones(N,1)/N;
                wTan = fmincon(funS,w0,[],[],Aeq,beq,LB,UB,[],optsF);
                tanRet = wTan'*mu * k;
                tanVol = sqrt(max(0, wTan'*Sigma*wTan)) * sqrt(k);

                % Plot
                if ~isempty(app.FrontierAxes) && isvalid(app.FrontierAxes)
                    cla(app.FrontierAxes);
                    hold(app.FrontierAxes,'on');
                    plot(app.FrontierAxes, fVols, fRets, 'b-', 'LineWidth',2, 'DisplayName','Frontier');
                    scatter(app.FrontierAxes, aVols, aRets, 50, 'filled', 'DisplayName','Assets');
                    for j=1:N
                        text(app.FrontierAxes, aVols(j), aRets(j), ['  ' app.AssetNames{j}], 'FontSize',7);
                    end
                    scatter(app.FrontierAxes, pVol, pRet, 120, 'p', 'filled', 'DisplayName','Current Portfolio');
                    scatter(app.FrontierAxes, tanVol, tanRet, 120, 'd', 'filled', 'DisplayName','Max Sharpe');
                    % Capital Market Line
                    cml_x = [0, tanVol*2];
                    cml_y = [rf*k, rf*k + (tanRet - rf*k)/tanVol * tanVol*2];
                    plot(app.FrontierAxes, cml_x, cml_y, 'k--', 'DisplayName','CML');
                    hold(app.FrontierAxes,'off');
                    legend(app.FrontierAxes,'show','Location','best');
                    title(app.FrontierAxes,'Efficient Frontier');
                    xlabel(app.FrontierAxes,'Volatility (ann.)'); ylabel(app.FrontierAxes,'Return (ann.)');
                end
                % Distance to frontier: find frontier vol at same return as current portfolio
                if ~isempty(fVols) && ~isempty(fRets)
                    % Interpolate frontier to find vol at pRet
                    [uRets, uIdx] = unique(fRets);
                    uVols = fVols(uIdx);
                    if pRet >= min(uRets) && pRet <= max(uRets) && numel(uRets) >= 2
                        frontierVol = interp1(uRets, uVols, pRet, 'linear');
                        excessVol = pVol - frontierVol;
                        app.FrontierDistLabel.Text = sprintf('Distance: %.2f%% excess vol (current: %.2f%%, frontier: %.2f%% at same return)', ...
                            excessVol*100, pVol*100, frontierVol*100);
                    else
                        app.FrontierDistLabel.Text = sprintf('Current portfolio (%.2f%% vol, %.2f%% ret) outside frontier range.', pVol*100, pRet*100);
                    end
                end
                app.StatusLabel.Text = 'Efficient frontier computed.';
            catch ME
                uialert(app.UIFigure, ME.message, 'Frontier Error');
            end
        end

        %----- Historical stress test presets
        function loadHistoricalStresses(app)
            if isempty(app.AssetNames)
                uialert(app.UIFigure,'Load data first.','No Data'); return;
            end
            names = app.AssetNames;
            presets = app.getStressPresets();
            defaultNames = {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds','Equity_US','Equity_Europe','Equity_Japan','Equity_EM','Commodities','HedgeFunds','Gold', ...
                            'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};
            nScen = size(presets,1);
            varNames = [{'Scenario'}, names];
            scenData = cell(nScen, 1+numel(names));
            for i = 1:nScen
                scenData{i,1} = presets{i,1};
                shockVec = presets{i,2};
                for j = 1:numel(names)
                    dIdx = find(strcmp(defaultNames, names{j}), 1);
                    if ~isempty(dIdx) && dIdx <= numel(shockVec)
                        scenData{i,1+j} = shockVec(dIdx);
                    else
                        scenData{i,1+j} = 0;
                    end
                end
            end
            S = cell2table(scenData, 'VariableNames', varNames);
            app.Scenarios = S;
            refreshScenarioDisplay(app);
            updateSummary(app);
            updateSAAAnalytics(app);
            updateScenarioStats(app);
            app.StatusLabel.Text = 'Historical stress scenarios loaded.';
        end

        function onScenarioDropDownChanged(app, val)
            % Load a single historical scenario or all of them
            if strcmp(val, '(Select episode)'), return; end
            if strcmp(val, 'All Historical')
                loadHistoricalStresses(app); return;
            end
            if isempty(app.AssetNames)
                uialert(app.UIFigure,'Load data first.','No Data'); return;
            end
            names = app.AssetNames;
            defaultNames = {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds','Equity_US','Equity_Europe','Equity_Japan','Equity_EM','Commodities','HedgeFunds','Gold', ...
                            'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};
            presets = app.getStressPresets();
            % Find matching scenario
            matchIdx = [];
            for i = 1:size(presets,1)
                if contains(val, presets{i,1}) || contains(presets{i,1}, erase(val, {'(',')',''''}))
                    matchIdx = i; break;
                end
            end
            if isempty(matchIdx)
                app.StatusLabel.Text = 'Scenario not found.'; return;
            end
            varNames = [{'Scenario'}, names];
            scenData = cell(1, 1+numel(names));
            scenData{1} = presets{matchIdx,1};
            shockVec = presets{matchIdx,2};
            for j = 1:numel(names)
                dIdx = find(strcmp(defaultNames, names{j}), 1);
                if ~isempty(dIdx) && dIdx <= numel(shockVec)
                    scenData{1+j} = shockVec(dIdx);
                else
                    scenData{1+j} = 0;
                end
            end
            % Append to existing or replace
            if isempty(app.Scenarios) || width(app.Scenarios)==0
                S = cell2table(scenData, 'VariableNames', varNames);
            else
                newRow = cell2table(scenData, 'VariableNames', varNames);
                % Remove if already exists
                existing = app.Scenarios;
                keep = ~strcmp(string(existing.Scenario), presets{matchIdx,1});
                existing = existing(keep,:);
                S = [existing; newRow];
            end
            app.Scenarios = S;
            refreshScenarioDisplay(app);
            updateSummary(app);
            updateSAAAnalytics(app);
            updateScenarioStats(app);
            app.StatusLabel.Text = sprintf('Loaded scenario: %s', presets{matchIdx,1});
        end

        function presets = getStressPresets(~)
            % Central repository of stress scenario data (approx monthly ETF returns)
            %                    Cash    3Y      7Y      HY      EqUS    EqEU    EqJP    EqEM    Cmdy    HF      Gold    EUR     JPY     GBP     CHF     AUD     CAD
            presets = {
                'GFC Oct 2008',     [0.001, 0.003, 0.025,-0.084,-0.168,-0.205,-0.203,-0.275,-0.240,-0.060,-0.178,-0.097, 0.078,-0.120, 0.020,-0.170,-0.120]
                'COVID Mar 2020',   [0.001, 0.011, 0.034,-0.112,-0.124,-0.151,-0.065,-0.154,-0.245,-0.025,-0.005, 0.002, 0.013,-0.054, 0.015,-0.076,-0.053]
                'Rate Shock 2022',  [0.001,-0.012,-0.035,-0.067,-0.083,-0.098,-0.057,-0.078,-0.035,-0.015,-0.016,-0.027,-0.053,-0.032,-0.021,-0.042,-0.024]
                'EM Crisis 1998',   [0.004, 0.008, 0.025,-0.030,-0.145,-0.140,-0.035,-0.290,-0.080,-0.070,-0.065, 0.020,-0.030, 0.010, 0.030,-0.080,-0.030]
                'Inflation Spike',  [0.000,-0.010,-0.050,-0.030,-0.050,-0.060,-0.040,-0.070, 0.080,-0.020, 0.060,-0.030,-0.020,-0.030, 0.020,-0.040,-0.020]
                'USD Surge',        [0.010, 0.000, 0.000,-0.020, 0.000,-0.080,-0.060,-0.120,-0.080,-0.030,-0.030,-0.100,-0.080,-0.070,-0.050,-0.090,-0.060]
            };
        end

        %----- Bootstrap condition builder callbacks
        function onBootAddCondition(app)
            % Add a new condition row to the bootstrap condition table
            current = app.BootCondTable.Data;
            if isempty(current)
                newRow = {'GDP Growth (YoY)', '> above', 0};
            else
                newRow = {'VIX Level', '> above', 20};
            end
            if iscell(current)
                app.BootCondTable.Data = [current; newRow];
            else
                app.BootCondTable.Data = newRow;
            end
        end

        function onBootRemoveCondition(app)
            % Remove last condition row
            current = app.BootCondTable.Data;
            if iscell(current) && size(current,1) > 1
                app.BootCondTable.Data = current(1:end-1,:);
            elseif iscell(current) && size(current,1) == 1
                app.BootCondTable.Data = cell(0,3);
            end
        end

        function expr = buildConditionExpr(app)
            % Build a MATLAB-evaluable condition expression from the condition table
            data = app.BootCondTable.Data;
            if isempty(data) || (iscell(data) && size(data,1)==0)
                expr = 'true(height(T),1)'; return;
            end
            % Map display labels to measure column names
            labelMap = {
                'GDP Growth (YoY)',            'GDP_YoY'
                'Inflation (CPI YoY)',         'CPI_YoY'
                'Inflation (CPI MoM)',         'CPI_MoM'
                'Nonfarm Payrolls (MoM chg)',  'NFP_MoM'
                'Retail Sales (YoY)',          'RetailSales_YoY'
                'USD Momentum (DXY 3m)',       'DXY_3m_return'
                'VIX Level',                   'VIX'
                'Fed Funds Rate',              'FedFunds'
                '2Y Treasury Yield',           'TwoYr'
                '10Y Treasury Yield',          'TenYr'
                'Yield Curve Slope (10Y-2Y)',  'YieldSlope'
                'HY Credit Spread',            'HY_Spread'
                'IG Credit Spread',            'IG_Spread'
                'Oil Price (WTI 3m)',          'Oil_3m_return'
            };
            % Map condition labels to operators
            condMap = {
                '> above',        '>'
                '< below',        '<'
                '>= at or above', '>='
                '<= at or below', '<='
            };
            % Determine combiner
            logicVal = app.BootCondLogicDrop.Value;
            if contains(logicVal, 'AND'), combiner = ' & ';
            else, combiner = ' | '; end

            parts = {};
            for i = 1:size(data,1)
                measureLabel = data{i,1};
                condLabel = data{i,2};
                val = data{i,3};
                if ischar(val) || isstring(val), val = str2double(val); end
                % Lookup measure name
                mIdx = find(strcmp(labelMap(:,1), measureLabel),1);
                if ~isempty(mIdx), mName = labelMap{mIdx,2};
                else, mName = strrep(measureLabel,' ','_'); end
                % Lookup operator
                cIdx = find(strcmp(condMap(:,1), condLabel),1);
                if ~isempty(cIdx), op = condMap{cIdx,2};
                else, op = '>'; end
                % Wrap in NaN guard so NaN values don't silently fail
                parts{end+1} = sprintf('(~isnan(%s) & %s %s %.6g)', mName, mName, op, val); %#ok<AGROW>
            end
            expr = strjoin(parts, combiner);
        end

        %----- Black-Litterman view builder
        function [P, Q] = buildBLViews(app, optNames)
            % Extract views from TAA deltas: assets with non-zero DeltaPct express views
            P = []; Q = [];
            if isempty(app.TAA) || height(app.TAA)==0, return; end
            T = app.TAA;
            if ~ismember('Asset', T.Properties.VariableNames) || ~ismember('DeltaPct', T.Properties.VariableNames)
                return;
            end
            nOpt = numel(optNames);
            viewRows = {};
            for i = 1:height(T)
                delta = T.DeltaPct(i);
                if abs(delta) < 1e-10, continue; end
                a = string(T.Asset(i));
                aIdx = find(strcmp(optNames, a), 1);
                if isempty(aIdx), continue; end
                pRow = zeros(1, nOpt);
                pRow(aIdx) = 1;
                viewRows{end+1} = struct('p', pRow, 'q', delta/100 * 0.25); %#ok<AGROW> % scale: delta% -> annualized expected excess view
            end
            if isempty(viewRows), return; end
            P = zeros(numel(viewRows), nOpt);
            Q = zeros(numel(viewRows), 1);
            for i = 1:numel(viewRows)
                P(i,:) = viewRows{i}.p;
                Q(i) = viewRows{i}.q;
            end
        end

        %----- Utils
        function tf = isFXOverlay(~, name)
            % FX pairs are unfunded overlays — they don't consume cash in SAA
            fxNames = {'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};
            tf = any(strcmp(name, fxNames));
        end

        function k = annFactor(app)
            switch lower(app.Freq)
                case 'daily',   k=252;
                case 'weekly',  k=52;
                case 'monthly', k=12;
                otherwise,      k=252;
            end
        end

        function idx = evalConditionVector(app, T, expr) %#ok<INUSL>
            if isempty(expr) || all(isspace(expr))
                idx = true(height(T),1);
                return;
            end
            vars = T.Properties.VariableNames;
            vars(strcmpi(vars,'Date')) = [];
            expr_rew = expr;
            for i=1:numel(vars)
                v = vars{i};
                if ~isvarname(v)
                    error('Measure column "%s" is not a valid MATLAB identifier. Rename it (e.g., matlab.lang.makeValidName).', v);
                end
                expr_rew = regexprep(expr_rew, ['\<', v, '\>'], ['T.(''', v, ''')']);
            end
            idx = eval(expr_rew);
            if ~islogical(idx) || numel(idx)~=height(T)
                error('Expression must return a logical vector of length %d.', height(T));
            end
            % Exclude rows where any referenced measure column is NaN
            for i=1:numel(vars)
                v = vars{i};
                if contains(expr, v) && isnumeric(T.(v))
                    idx(isnan(T.(v))) = false;
                end
            end
        end

        function seq = sampleBlocks(~, validIdx, Tn, block)
            m = numel(validIdx);
            if m==0, error('No valid indices to sample.'); end
            nb = ceil(Tn / block);
            seq = zeros(nb*block,1);
            for b=1:nb
                startPos = randi(m);
                idxs = mod((startPos-1):(startPos+block-2), m) + 1;
                seq((b-1)*block+1:b*block) = validIdx(idxs);
            end
            seq = seq(1:Tn);
        end

        %----- Realistic sample generator
        function [R, names, RawOut] = generateRealisticSample(app, Tn)
            names = {'USD_Cash','HG_Bonds_3Y','HG_Bonds_7Y','HY_Bonds', ...
                     'Equity_US','Equity_Europe','Equity_Japan','Equity_EM', ...
                     'Commodities','HedgeFunds','Gold', ...
                     'EUR_USD','JPY_USD','GBP_USD','CHF_USD','AUD_USD','CAD_USD'};

            %        Cash   3Y     7Y     HY     EqUS   EqEU   EqJP   EqEM   Cmdy   HF     Gold   EUR    JPY    GBP    CHF    AUD    CAD
            mu_ann = [0.020; 0.025; 0.030; 0.050; 0.070; 0.065; 0.055; 0.075; 0.030; 0.060; 0.040; 0.005; 0.005; 0.005; 0.003; 0.005; 0.005];
            vol_ann= [0.002; 0.030; 0.060; 0.080; 0.160; 0.180; 0.170; 0.220; 0.200; 0.090; 0.150; 0.080; 0.090; 0.080; 0.090; 0.100; 0.080];

            %  17x17 correlation matrix
            %  Rows/cols: Cash 3Y 7Y HY EqUS EqEU EqJP EqEM Cmdy HF Gold EUR JPY GBP CHF AUD CAD
            Corr = [ ...
             1.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00  0.00;
             0.00  1.00  0.85  0.40 -0.20 -0.22 -0.20 -0.15 -0.10  0.20  0.15  0.05  0.10  0.05  0.10  0.00  0.00;
             0.00  0.85  1.00  0.50 -0.25 -0.27 -0.25 -0.20 -0.10  0.20  0.15  0.05  0.10  0.05  0.10  0.00  0.00;
             0.00  0.40  0.50  1.00  0.60  0.58  0.55  0.50  0.25  0.50  0.05  0.10  0.00  0.10  0.00  0.15  0.15;
             0.00 -0.20 -0.25  0.60  1.00  0.85  0.75  0.70  0.20  0.50  0.05  0.10 -0.15  0.15 -0.10  0.25  0.25;
             0.00 -0.22 -0.27  0.58  0.85  1.00  0.75  0.70  0.20  0.50  0.05  0.30 -0.10  0.25 -0.05  0.20  0.15;
             0.00 -0.20 -0.25  0.55  0.75  0.75  1.00  0.65  0.15  0.45  0.05  0.05  0.10  0.05  0.05  0.15  0.10;
             0.00 -0.15 -0.20  0.50  0.70  0.70  0.65  1.00  0.20  0.45  0.05  0.25 -0.05  0.15  0.00  0.35  0.20;
             0.00 -0.10 -0.10  0.25  0.20  0.20  0.15  0.20  1.00  0.30  0.35  0.10  0.00  0.05  0.00  0.25  0.30;
             0.00  0.20  0.20  0.50  0.50  0.50  0.45  0.45  0.30  1.00  0.10  0.10 -0.05  0.10 -0.05  0.15  0.15;
             0.00  0.15  0.15  0.05  0.05  0.05  0.05  0.05  0.35  0.10  1.00  0.15  0.10  0.05  0.20  0.10  0.05;
             0.00  0.05  0.05  0.10  0.10  0.30  0.05  0.25  0.10  0.10  0.15  1.00  0.30  0.60  0.55  0.30  0.20;
             0.00  0.10  0.10  0.00 -0.15 -0.10  0.10 -0.05  0.00 -0.05  0.10  0.30  1.00  0.15  0.55  0.00 -0.05;
             0.00  0.05  0.05  0.10  0.15  0.25  0.05  0.15  0.05  0.10  0.05  0.60  0.15  1.00  0.35  0.35  0.25;
             0.00  0.10  0.10  0.00 -0.10 -0.05  0.05  0.00  0.00 -0.05  0.20  0.55  0.55  0.35  1.00  0.10  0.00;
             0.00  0.00  0.00  0.15  0.25  0.20  0.15  0.35  0.25  0.15  0.10  0.30  0.00  0.35  0.10  1.00  0.50;
             0.00  0.00  0.00  0.15  0.25  0.15  0.10  0.20  0.30  0.15  0.05  0.20 -0.05  0.25  0.00  0.50  1.00];
            Corr = (Corr + Corr.')/2;

            k = 252;
            mu_d  = mu_ann  / k;
            vol_d = vol_ann / sqrt(k);

            S = diag(vol_d);
            Sigma = S * Corr * S;
            Sigma = (Sigma + Sigma.')/2;
            [V,D] = eig(Sigma); d = diag(D); d(d < 1e-10) = 1e-10;
            Sigma = V*diag(d)*V.'; Sigma = (Sigma + Sigma.')/2;

            jitters = [0, 1e-10, 1e-8, 1e-6];
            L = [];
            for ji = 1:numel(jitters)
                [L,p] = chol(Sigma + jitters(ji)*mean(diag(Sigma))*eye(size(Sigma)),'lower');
                if p == 0, break; end
            end
            if p > 0
                error('Covariance matrix is not positive definite even after regularization.');
            end
            if ji > 1
                warning('PortfolioRiskOptimizerApp:cholJitter', ...
                    'Cholesky required regularization (jitter=%.1e).', jitters(ji)*mean(diag(Sigma)));
            end
            Z = randn(Tn, numel(names));
            R = repmat(mu_d', Tn, 1) + Z*L.';

            RawOut = array2table(R,'VariableNames',names);
        end

        %----- Populate split asset/currency listboxes
        function populateAssetLists(app)
            names = app.AssetNames;
            if isempty(names), return; end
            isFX = false(numel(names), 1);
            for ii = 1:numel(names)
                isFX(ii) = app.isFXOverlay(names{ii});
            end
            funded = names(~isFX);
            fx = names(isFX);
            app.AssetsList.Items = funded;
            app.AssetsList.Value = funded;
            app.CurrenciesList.Items = fx;
            app.CurrenciesList.Value = fx;
        end

        %----- UI validity helper
        function ok = uiValid(~, component)
            % Check if a UI component exists and is valid for property assignment
            ok = ~isempty(component) && isvalid(component);
        end

        function w = initEqualWeights(app)
            % Equal weight funded assets; overlays get 0
            N = numel(app.AssetNames);
            w = zeros(N, 1);
            for ii = 1:N
                if ~app.isFXOverlay(app.AssetNames{ii}), w(ii) = 1; end
            end
            nFunded = sum(w > 0);
            if nFunded > 0, w = w / nFunded; end
        end

        %----- FX Overlay Display Methods
        function updateFXOverlayDisplay(app)
            % Split SAA data into funded/FX sub-tables for display
            if isempty(app.SAA) || ~istable(app.SAA) || height(app.SAA) == 0, return; end
            if ~ismember('Asset', app.SAA.Properties.VariableNames), return; end
            S = app.SAA;
            isFX = false(height(S), 1);
            for ii = 1:height(S)
                isFX(ii) = app.isFXOverlay(char(S.Asset(ii)));
            end
            % Funded assets table
            funded = S(~isFX, :);
            if app.uiValid(app.SAATable), app.SAATable.Data = funded; end
            % FX assets table
            fxData = S(isFX, :);
            if app.uiValid(app.SAAFXTable), app.SAAFXTable.Data = fxData; end
            % FX exposure summary
            if app.uiValid(app.FXExposureText)
                if any(isFX)
                    fxWeights = S.WeightPct(isFX);
                    grossFX = sum(abs(fxWeights));
                    netFX = sum(fxWeights);
                    detail = '';
                    for ii = find(isFX)'
                        detail = [detail, sprintf('  %s: %.1f%%', char(S.Asset(ii)), S.WeightPct(ii))]; %#ok<AGROW>
                    end
                    app.FXExposureText.Value = {sprintf('Gross FX: %.1f%%  Net FX: %.1f%%', grossFX, netFX), detail};
                else
                    app.FXExposureText.Value = {'Gross FX: 0.0%  Net FX: 0.0%'};
                end
            end
        end

        function onSAATableEdited(app)
            % Merge funded table edits back into master app.SAA
            if ~app.uiValid(app.SAATable), return; end
            funded = app.SAATable.Data;
            if isempty(funded), return; end
            S = app.SAA;
            if isempty(S) || ~istable(S) || height(S) == 0
                app.SAA = funded;
                updateFXOverlayDisplay(app); updateSAAAnalytics(app);
                return;
            end
            isFX = false(height(S), 1);
            for ii = 1:height(S)
                isFX(ii) = app.isFXOverlay(char(S.Asset(ii)));
            end
            fxData = S(isFX, :);
            app.SAA = [funded; fxData];
            updateFXOverlayDisplay(app);
            updateSAAAnalytics(app);
        end

        function onSAAFXTableEdited(app)
            % Merge FX table edits back into master app.SAA
            if ~app.uiValid(app.SAAFXTable), return; end
            fxData = app.SAAFXTable.Data;
            if isempty(fxData), return; end
            S = app.SAA;
            if isempty(S) || ~istable(S) || height(S) == 0
                app.SAA = fxData;
                updateFXOverlayDisplay(app); updateSAAAnalytics(app);
                return;
            end
            isFX = false(height(S), 1);
            for ii = 1:height(S)
                isFX(ii) = app.isFXOverlay(char(S.Asset(ii)));
            end
            funded = S(~isFX, :);
            app.SAA = [funded; fxData];
            updateFXOverlayDisplay(app);
            updateSAAAnalytics(app);
        end

        function updateCombinedFXSplit(app)
            % Split Combined weights table into funded/FX views
            if isempty(app.W) || isempty(app.AssetNames) || isempty(app.R), return; end
            if numel(app.W) ~= size(app.R,2), return; end
            names = app.AssetNames;
            Sigma = cov(app.R);
            w = app.W;
            contrib = Sigma * w;
            RC = w .* contrib;
            isFX = false(numel(names), 1);
            for ii = 1:numel(names)
                isFX(ii) = app.isFXOverlay(names{ii});
            end
            Tall = table(names(:), w(:), RC(:), 'VariableNames', {'Asset','Weight','RiskContribution'});
            if app.uiValid(app.CombinedTable), app.CombinedTable.Data = Tall(~isFX, :); end
            if app.uiValid(app.CombFXTable), app.CombFXTable.Data = Tall(isFX, :); end
        end

        function updateCombinedAnalytics(app)
            % Compute IR, Hit Rate, ETL, CDaR for Combined vs SAA
            if isempty(app.R) || isempty(app.W), return; end
            if numel(app.W) ~= size(app.R,2), return; end
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa) ~= size(app.R,2), return; end
            R = app.R;
            rpComb = R * app.W;
            rpSAA = R * w_saa;
            activeRet = rpComb - rpSAA;
            k = app.annFactor();
            muActive = mean(activeRet) * k;
            teActive = std(activeRet) * sqrt(k);
            IR = muActive / max(1e-12, teActive);
            hitRate = mean(activeRet > 0) * 100;
            ETL = app.CVaR_hist(activeRet, 0.95);
            eqActive = cumprod(1 + activeRet);
            ddActive = 1 - eqActive ./ cummax(eqActive);
            if ~isempty(ddActive)
                CDaR = quantile(ddActive, 0.95);
            else
                CDaR = NaN;
            end
            lines = {
                sprintf('Information Ratio: %.3f   Hit Rate: %.1f%%', IR, hitRate)
                sprintf('Active Return (ann): %.2f%%   Tracking Error (ann): %.2f%%', muActive*100, teActive*100)
                sprintf('ETL (CVaR95 on active): %.4f   CDaR (95%%): %.2f%%', ETL, CDaR*100)
            };
            if app.uiValid(app.CombAnalyticsText), app.CombAnalyticsText.Value = lines; end
        end

        %----- Risk Decomposition Methods
        function updateRiskDecomp(app)
            if isempty(app.R) || isempty(app.W), return; end
            if numel(app.W) ~= size(app.R,2), return; end
            w = app.W; names = app.AssetNames;
            N = numel(names);
            Sigma = cov(app.R);
            k = app.annFactor();
            sigp2 = max(1e-20, w' * Sigma * w);
            sigp = sqrt(sigp2);
            sigp_ann = sigp * sqrt(k);
            MCR = (Sigma * w) / sigp;
            CR = w .* MCR;
            pctRisk = CR / sigp;
            MCR_ann = MCR * sqrt(k);
            CR_ann = CR * sqrt(k);
            % Decompose weights into SAA and TAA components
            w_saa = app.getSAAWeightsVector();
            if isempty(w_saa) || numel(w_saa) ~= N
                w_saa = w; % fallback: all SAA
            end
            w_taa = w - w_saa;
            % Compute SAA and TAA component risk separately
            CR_saa = w_saa .* MCR;
            CR_taa = w_taa .* MCR;
            CR_saa_ann = CR_saa * sqrt(k);
            CR_taa_ann = CR_taa * sqrt(k);
            % Source label per asset
            srcLabel = repmat("SAA", N, 1);
            for ii = 1:N
                if abs(w_taa(ii)) > 1e-8 && abs(w_saa(ii)) < 1e-8
                    srcLabel(ii) = "TAA";
                elseif abs(w_taa(ii)) > 1e-8
                    srcLabel(ii) = "SAA+TAA";
                end
            end
            % Display MCR and CR in bps (x10000) for readability
            T = table(string(names(:)), srcLabel, w_saa(:)*100, w_taa(:)*100, w(:)*100, ...
                MCR_ann(:)*10000, CR_saa_ann(:)*10000, CR_taa_ann(:)*10000, CR_ann(:)*10000, pctRisk(:)*100, ...
                'VariableNames',{'Asset','Source','SAA_Wt','TAA_Wt','TotalWt', ...
                'MCR_bps','CR_SAA_bps','CR_TAA_bps','CR_Total_bps','PctRisk'});
            if app.uiValid(app.RiskBudgetTable), app.RiskBudgetTable.Data = T; end
            % Waterfall chart
            [sortedCR, sortIdx] = sort(CR_ann, 'descend');
            sortedNames = names(sortIdx);
            colors = zeros(numel(sortedCR), 3);
            for ii = 1:numel(sortedCR)
                if sortedCR(ii) >= 0
                    colors(ii,:) = [0.85 0.33 0.33];
                else
                    colors(ii,:) = [0.33 0.75 0.33];
                end
            end
            if app.uiValid(app.RiskWaterfallAxes)
                cla(app.RiskWaterfallAxes);
                sortedCR_bps = sortedCR * 10000; % convert to bps
                bh = barh(app.RiskWaterfallAxes, sortedCR_bps);
                bh.FaceColor = 'flat';
                bh.CData = colors;
                app.RiskWaterfallAxes.YTick = 1:numel(sortedNames);
                app.RiskWaterfallAxes.YTickLabel = sortedNames;
                xlabel(app.RiskWaterfallAxes, 'bps');
                title(app.RiskWaterfallAxes, sprintf('Risk Contributions (Total Vol: %.0f bps)', sigp_ann*10000));
                % Add % risk labels on bars
                sortedPctRisk = pctRisk(sortIdx) * 100;
                hold(app.RiskWaterfallAxes, 'on');
                for ii = 1:numel(sortedCR_bps)
                    xPos = sortedCR_bps(ii);
                    if xPos >= 0
                        text(app.RiskWaterfallAxes, xPos + max(abs(sortedCR_bps))*0.02, ii, ...
                            sprintf('%.1f%%', sortedPctRisk(ii)), ...
                            'FontSize', 8, 'VerticalAlignment', 'middle');
                    else
                        text(app.RiskWaterfallAxes, xPos - max(abs(sortedCR_bps))*0.02, ii, ...
                            sprintf('%.1f%%', sortedPctRisk(ii)), ...
                            'FontSize', 8, 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right');
                    end
                end
                hold(app.RiskWaterfallAxes, 'off');
            end
            % Concentration metrics
            wAbs = abs(w(:));
            wNorm = wAbs / max(1e-12, sum(wAbs));
            HHI_w = sum(wNorm.^2);
            rcAbs = abs(pctRisk(:));
            rcNorm = rcAbs / max(1e-12, sum(rcAbs));
            HHI_rc = sum(rcNorm.^2);
            ENB = 1 / max(1e-12, HHI_rc);
            indVols = sqrt(diag(Sigma));
            DR = sum(abs(w(:)) .* indVols) / max(1e-12, sigp);
            maxRC = max(abs(pctRisk)) * 100;
            concLines = {
                sprintf('HHI (weights): %.4f   HHI (risk): %.4f   Effective Bets: %.1f', HHI_w, HHI_rc, ENB)
                sprintf('Diversification Ratio: %.2f   Max Risk Contrib: %.1f%%', DR, maxRC)
            };
            if app.uiValid(app.ConcentrationText), app.ConcentrationText.Value = concLines; end
            % Factor decomposition
            updateFactorDecomp(app);
        end

        function updateFactorDecomp(app)
            if isempty(app.R) || isempty(app.W) || isempty(app.AssetNames), return; end
            if numel(app.W) ~= size(app.R,2), return; end
            R = app.R; names = app.AssetNames;
            factorMap = {
                'Equity_US',    'Equity'
                'HG_Bonds_7Y',  'Rates'
                'HY_Bonds',     'Credit'
                'EUR_USD',      'FX'
                'Commodities',  'Commodities'
                'Gold',         'Gold'
            };
            factorIdx = []; factorLabels = {};
            for ii = 1:size(factorMap, 1)
                idx = find(strcmp(names, factorMap{ii,1}), 1);
                if ~isempty(idx)
                    factorIdx(end+1) = idx; %#ok<AGROW>
                    factorLabels{end+1} = factorMap{ii,2}; %#ok<AGROW>
                end
            end
            if isempty(factorIdx)
                if app.uiValid(app.FactorExposureTable), app.FactorExposureTable.Data = table(); end
                if app.uiValid(app.FactorVsSpecificText), app.FactorVsSpecificText.Value = {'No factor proxies found in universe.'}; end
                return;
            end
            rp = R * app.W;
            F = R(:, factorIdx);
            nF = size(F, 2);
            Tn = size(F, 1);
            X = [ones(Tn, 1), F];
            b = X \ rp;
            alpha = b(1);
            betas = b(2:end);
            residuals = rp - X * b;
            SSres = sum(residuals.^2);
            SStot = sum((rp - mean(rp)).^2);
            R2 = 1 - SSres / max(1e-12, SStot);
            mse = SSres / max(1, Tn - nF - 1);
            XtXinv = inv(X' * X); %#ok<MINV>
            se = sqrt(mse * diag(XtXinv));
            tStats = b ./ max(1e-12, se);
            betaTStats = tStats(2:end);
            app.FactorBetas = betas;
            app.FactorR2 = R2;
            app.FactorNames = factorLabels;
            app.FactorResidVar = var(residuals);
            k = app.annFactor();
            factorContrib = betas .* std(F)' * sqrt(k);
            Tf = table(string(factorLabels(:)), betas(:), betaTStats(:), factorContrib(:), ...
                'VariableNames',{'Factor','Beta','tStat','Contribution'});
            if app.uiValid(app.FactorExposureTable), app.FactorExposureTable.Data = Tf; end
            factorVar = var(F * betas);
            specificVar = var(residuals);
            totalVar = var(rp);
            fvLines = {
                sprintf('R² = %.3f   Alpha(per) = %.6f   Factor Var: %.2f%%   Specific Var: %.2f%%   Total Var: %.6f', ...
                    R2, alpha, factorVar/max(1e-12,totalVar)*100, specificVar/max(1e-12,totalVar)*100, totalVar)
            };
            if app.uiValid(app.FactorVsSpecificText), app.FactorVsSpecificText.Value = fvLines; end
            updateFactorSensitivityChart(app, betas, factorLabels);
            updateRollingFactorExposure(app);
        end

        function updateFactorSensitivityChart(app, betas, factorLabels)
            % Show portfolio PnL impact of +1% move in each factor
            if isempty(app.FactorSensAxes) || ~isvalid(app.FactorSensAxes), return; end
            cla(app.FactorSensAxes);
            pnlImpact = betas * 0.01; % +1% factor move
            bh = bar(app.FactorSensAxes, pnlImpact);
            bh.FaceColor = 'flat';
            for ii = 1:numel(pnlImpact)
                if pnlImpact(ii) >= 0
                    bh.CData(ii,:) = [0.2 0.6 0.9];
                else
                    bh.CData(ii,:) = [0.9 0.3 0.3];
                end
            end
            app.FactorSensAxes.XTick = 1:numel(factorLabels);
            app.FactorSensAxes.XTickLabel = factorLabels;
            app.FactorSensAxes.XTickLabelRotation = 45;
            title(app.FactorSensAxes, 'Portfolio PnL Impact: +1% Factor Move');
            ylabel(app.FactorSensAxes, 'PnL Impact');
        end

        function updateRollingFactorExposure(app)
            % Rolling window factor beta chart
            if isempty(app.R) || isempty(app.W) || isempty(app.AssetNames), return; end
            if isempty(app.RollingFactorAxes) || ~isvalid(app.RollingFactorAxes), return; end
            R = app.R; names = app.AssetNames;
            factorMap = {
                'Equity_US','Equity'; 'HG_Bonds_7Y','Rates'; 'HY_Bonds','Credit';
                'EUR_USD','FX'; 'Commodities','Commodities'; 'Gold','Gold'
            };
            factorIdx = []; factorLabels = {};
            for ii = 1:size(factorMap, 1)
                idx = find(strcmp(names, factorMap{ii,1}), 1);
                if ~isempty(idx)
                    factorIdx(end+1) = idx; %#ok<AGROW>
                    factorLabels{end+1} = factorMap{ii,2}; %#ok<AGROW>
                end
            end
            if isempty(factorIdx), return; end
            rp = R * app.W;
            F = R(:, factorIdx);
            nF = size(F, 2);
            Tn = size(R, 1);
            L = max(20, round(app.FactorWindowField.Value));
            rollingBetas = NaN(Tn, nF);
            for t = L:Tn
                seg_rp = rp(t-L+1:t);
                seg_F = F(t-L+1:t, :);
                X = [ones(L,1), seg_F];
                b = X \ seg_rp;
                rollingBetas(t, :) = b(2:end)';
            end
            x = app.Dates;
            if isempty(x) || numel(x) ~= Tn, x = (1:Tn)'; end
            cla(app.RollingFactorAxes);
            hold(app.RollingFactorAxes, 'on');
            for ii = 1:nF
                plot(app.RollingFactorAxes, x, rollingBetas(:,ii), 'DisplayName', factorLabels{ii});
            end
            hold(app.RollingFactorAxes, 'off');
            legend(app.RollingFactorAxes, 'show', 'Location', 'best', 'FontSize', 7);
            title(app.RollingFactorAxes, sprintf('Rolling %d-period Factor Betas', L));
        end

        function updateEigenDecomp(app)
            if isempty(app.R) || size(app.R,2) < 2, return; end
            if ~app.uiValid(app.EigenTable), return; end
            C = corrcoef(app.R);
            [~, D] = eig(C);
            eigenvals = sort(diag(D), 'descend');
            N = numel(eigenvals);
            pctVar = eigenvals / sum(eigenvals) * 100;
            cumPct = cumsum(pctVar);
            pcNums = (1:N)';
            T = table(pcNums, eigenvals, pctVar, cumPct, ...
                'VariableNames', {'PC','Eigenvalue','PctVariance','CumulativePct'});
            app.EigenTable.Data = T;
        end

        function computeDurationProxy(app)
            % Bond duration from rate sensitivity
            if isempty(app.R) || isempty(app.Measures), return; end
            if ~ismember('TenYr', app.Measures.Properties.VariableNames), return; end
            M = app.Measures;
            rateChg = diff(M.TenYr);
            if numel(rateChg) < 10, return; end
            names = app.AssetNames;
            bondIdx = [];
            for ii = 1:numel(names)
                if contains(names{ii}, 'Bond') || contains(names{ii}, 'HG_') || contains(names{ii}, 'HY_')
                    bondIdx(end+1) = ii; %#ok<AGROW>
                end
            end
            if isempty(bondIdx), return; end
            % Align lengths
            nR = size(app.R, 1);
            nM = numel(rateChg);
            nUse = min(nR, nM);
            rateChgUse = rateChg(end-nUse+1:end);
            for ii = 1:numel(bondIdx)
                bi = bondIdx(ii);
                bondRet = app.R(end-nUse+1:end, bi);
                X = [ones(nUse, 1), rateChgUse];
                b = X \ bondRet;
                % Duration = -beta, DV01 = duration * weight * 0.0001
                % Store as tooltip on the risk budget table
            end
        end

        %----- Asset ETF map
        function initAssetETFMap(app)
            masterMap = {
                'USD_Cash',       'BIL (1-3M T-Bills)'
                'HG_Bonds_3Y',    'SHY (1-3Y Treasury)'
                'HG_Bonds_7Y',    'IEF (7-10Y Treasury)'
                'HY_Bonds',       'HYG (High Yield Corp)'
                'Equity_US',      'SPY (S&P 500)'
                'Equity_Europe',  'VGK (FTSE Europe)'
                'Equity_Japan',   'EWJ (MSCI Japan)'
                'Equity_EM',      'EEM (MSCI EM)'
                'Commodities',    'DBC (Commodity Index)'
                'HedgeFunds',     'QAI (HF Multi-Strat)'
                'Gold',           'GLD (Gold SPDR)'
                'EUR_USD',        'FXE (Euro/USD) [Overlay]'
                'JPY_USD',        'FXY (Yen/USD) [Overlay]'
                'GBP_USD',        'FXB (GBP/USD) [Overlay]'
                'CHF_USD',        'FXF (CHF/USD) [Overlay]'
                'AUD_USD',        'FXA (AUD/USD) [Overlay]'
                'CAD_USD',        'FXC (CAD/USD) [Overlay]'
            };
            app.AssetETFMap = masterMap;
            % Build split tooltips for assets vs currencies
            tipAssets = ''; tipFX = '';
            for i = 1:numel(app.AssetNames)
                lbl = getETFLabel(app, app.AssetNames{i});
                line = [app.AssetNames{i}, ' = ', lbl, newline];
                if app.isFXOverlay(app.AssetNames{i})
                    tipFX = [tipFX, line]; %#ok<AGROW>
                else
                    tipAssets = [tipAssets, line]; %#ok<AGROW>
                end
            end
            app.AssetsList.Tooltip = strtrim(tipAssets);
            app.CurrenciesList.Tooltip = strtrim(tipFX);
        end

        function lbl = getETFLabel(app, assetName)
            lbl = assetName;
            if isempty(app.AssetETFMap), return; end
            idx = find(strcmp(app.AssetETFMap(:,1), assetName), 1);
            if ~isempty(idx)
                lbl = app.AssetETFMap{idx, 2};
            end
        end

        %----- CMA methods
        function computeCMA(app)
            if isempty(app.R) || isempty(app.AssetNames)
                uialert(app.UIFigure,'Load data first.','No Data'); return;
            end
            try
                method = app.CMAMethodDropDown.Value;
                switch method
                    case 'Historical'
                        computeCMA_Historical(app);
                    case 'Building-Block'
                        computeCMA_BuildingBlock(app);
                    case 'BL-Equilibrium'
                        computeCMA_BLEquilibrium(app);
                    otherwise
                        computeCMA_Historical(app);
                end
                app.StatusLabel.Text = sprintf('CMA computed (%s).', method);
            catch ME
                uialert(app.UIFigure, ME.message, 'CMA Error');
            end
        end

        function computeCMA_Historical(app)
            R = app.R;
            k = app.annFactor();
            lookback = round(app.CMALookbackField.Value);
            if lookback > 0 && lookback < size(R,1)
                R = R(end-lookback+1:end, :);
            end
            mu_ann = mean(R,1)' * k;
            vol_ann = std(R,0,1)' * sqrt(k);
            Corr = corrcoef(R);
            populateCMATables(app, mu_ann, vol_ann, Corr);
        end

        function computeCMA_BuildingBlock(app)
            % Research Affiliates-style Building-Block CMA
            % Equities: Dividend Yield + Real Earnings Growth + Inflation + Valuation Change
            % Bonds:    Yield - Expected Default Loss + Rolldown Return
            % Cash:     Short-term rate
            % Commodities: Inflation + Convenience Yield - Storage
            % Gold:     Inflation + Real Price Appreciation
            % FX:       Interest rate differential (carry)
            % HF:       Cash + Alpha premium + Beta drag
            R = app.R;
            k = app.annFactor();
            names = app.AssetNames;
            N = numel(names);
            lookback = round(app.CMALookbackField.Value);
            if lookback > 0 && lookback < size(R,1)
                Rsub = R(end-lookback+1:end, :);
            else
                Rsub = R;
            end
            vol_ann = std(Rsub,0,1)' * sqrt(k);
            Corr = corrcoef(Rsub);

            % ---- Macro building blocks (defaults, overridden by FRED data) ----
            inflation   = 0.025;   % CPI YoY
            realGrowth  = 0.020;   % real GDP growth
            tenYr       = 0.040;   % 10Y Treasury yield
            twoYr       = 0.035;   % 2Y Treasury yield (proxy for short-rate expectations)
            fedFunds    = 0.050;   % Fed Funds rate
            creditSpread= 0.040;   % HY OAS spread
            divYield_US = 0.015;   % S&P 500 dividend yield
            divYield_DM = 0.025;   % developed markets dividend yield
            divYield_EM = 0.030;   % EM dividend yield
            cape_US     = 30;      % Shiller CAPE ratio (for valuation adjustment)
            cape_avg    = 20;      % long-run average CAPE

            if ~isempty(app.Measures) && height(app.Measures) > 0
                M = app.Measures;
                if ismember('CPI_YoY', M.Properties.VariableNames)
                    v = M.CPI_YoY(end); if isfinite(v), inflation = v; end
                end
                if ismember('GDP_YoY', M.Properties.VariableNames)
                    v = M.GDP_YoY(end); if isfinite(v), realGrowth = v - inflation; end
                end
                if ismember('TenYr', M.Properties.VariableNames)
                    v = M.TenYr(end); if isfinite(v), tenYr = v; end
                end
                if ismember('TwoYr', M.Properties.VariableNames)
                    v = M.TwoYr(end); if isfinite(v), twoYr = v; end
                end
                if ismember('FedFunds', M.Properties.VariableNames)
                    v = M.FedFunds(end); if isfinite(v), fedFunds = v; end
                end
                if ismember('HY_Spread', M.Properties.VariableNames)
                    v = M.HY_Spread(end); if isfinite(v), creditSpread = v; end
                elseif ismember('CreditSpread', M.Properties.VariableNames)
                    v = M.CreditSpread(end); if isfinite(v), creditSpread = v; end
                end
            end

            % ---- Derived building blocks ----
            % Valuation adjustment: 10Y mean reversion of CAPE toward long-run average
            % Annual valuation drag/boost = (1/10) * ln(CAPE_avg / CAPE_current)
            valuationAdj = (1/10) * log(cape_avg / cape_US);  % ~-4% if CAPE=30 vs avg=20

            % Bond rolldown: approx slope of yield curve * average duration / maturity
            rolldown_3Y = max(0, (twoYr - fedFunds)) * 0.5;   % ~rolldown for 1-3Y
            rolldown_7Y = max(0, (tenYr - twoYr)) * 0.7;      % ~rolldown for 7-10Y

            % Default loss for HY: ~3% annual default rate * 60% loss given default
            hyDefaultLoss = 0.03 * 0.60;  % ~1.8%

            % FX carry: differential between foreign and domestic short rates
            % Approximate with spread vs US Fed Funds
            fxCarry = struct('EUR_USD', -0.010, 'JPY_USD', -0.040, ...
                             'GBP_USD', -0.005, 'CHF_USD', -0.035, ...
                             'AUD_USD',  0.005, 'CAD_USD', -0.005);

            mu_ann = zeros(N, 1);
            for i = 1:N
                nm = names{i};
                if contains(nm, 'Cash')
                    % Cash = short-term rate
                    mu_ann(i) = fedFunds;

                elseif strcmp(nm, 'HG_Bonds_3Y')
                    % Short govt bonds: yield + rolldown
                    mu_ann(i) = twoYr + rolldown_3Y;

                elseif strcmp(nm, 'HG_Bonds_7Y')
                    % Intermediate govt bonds: yield + rolldown
                    mu_ann(i) = tenYr + rolldown_7Y;

                elseif contains(nm, 'HY_')
                    % HY: Treasury yield + credit spread - default loss
                    mu_ann(i) = tenYr + creditSpread - hyDefaultLoss;

                elseif strcmp(nm, 'Equity_US')
                    % US Equity: div yield + real earnings growth + inflation + valuation
                    mu_ann(i) = divYield_US + realGrowth + inflation + valuationAdj;

                elseif strcmp(nm, 'Equity_Europe')
                    % Europe: higher yield, lower growth, neutral valuation
                    mu_ann(i) = divYield_DM + realGrowth * 0.7 + inflation + valuationAdj * 0.3;

                elseif strcmp(nm, 'Equity_Japan')
                    % Japan: moderate yield, low growth, mild valuation tailwind
                    mu_ann(i) = 0.020 + realGrowth * 0.4 + inflation * 0.5 + valuationAdj * 0.2;

                elseif strcmp(nm, 'Equity_EM')
                    % EM: high yield, high growth, cheap valuations
                    mu_ann(i) = divYield_EM + realGrowth * 1.5 + inflation + 0.005;

                elseif contains(nm, 'Commodities')
                    % Commodities: inflation + convenience yield - storage
                    convenienceYield = 0.005; storageCost = 0.003;
                    mu_ann(i) = inflation + convenienceYield - storageCost;

                elseif contains(nm, 'Gold')
                    % Gold: inflation + real price appreciation (monetary debasement hedge)
                    realGoldAppreciation = 0.005;
                    mu_ann(i) = inflation + realGoldAppreciation;

                elseif app.isFXOverlay(nm)
                    % FX: carry (interest rate differential)
                    if isfield(fxCarry, nm)
                        mu_ann(i) = fxCarry.(nm);
                    else
                        mu_ann(i) = 0;
                    end

                elseif contains(nm, 'HedgeFunds')
                    % HF: cash + alpha premium + beta drag
                    alphaPremium = 0.020; betaDrag = -0.005;
                    mu_ann(i) = fedFunds + alphaPremium + betaDrag;

                else
                    mu_ann(i) = mean(Rsub(:,i)) * k; % fallback to historical
                end
            end
            populateCMATables(app, mu_ann, vol_ann, Corr);
        end

        function computeCMA_BLEquilibrium(app)
            R = app.R;
            k = app.annFactor();
            names = app.AssetNames;
            N = numel(names);
            lookback = round(app.CMALookbackField.Value);
            if lookback > 0 && lookback < size(R,1)
                Rsub = R(end-lookback+1:end, :);
            else
                Rsub = R;
            end
            Sigma = cov(Rsub);
            vol_ann = std(Rsub,0,1)' * sqrt(k);
            Corr = corrcoef(Rsub);

            % Market weights from SAA
            w_mkt = app.getSAAWeightsVector();
            if isempty(w_mkt) || numel(w_mkt) ~= N
                w_mkt = ones(N,1) / N;
            end

            % Reverse-optimize implied returns
            delta_ra = 2.5;
            pi_eq = delta_ra * Sigma * w_mkt;
            mu_ann = pi_eq * k;

            populateCMATables(app, mu_ann, vol_ann, Corr);
        end

        function populateCMATables(app, mu_ann, vol_ann, Corr)
            names = app.AssetNames(:);
            N = numel(names);
            sharpe = mu_ann ./ max(1e-12, vol_ann);

            % Build ETF column
            etfLabels = cell(N, 1);
            for i = 1:N
                etfLabels{i} = getETFLabel(app, names{i});
            end

            T = table(string(names), string(etfLabels), mu_ann, vol_ann, sharpe, ...
                'VariableNames', {'Asset','ETF','Exp_Return_Ann','Vol_Ann','Sharpe'});
            app.CMARetVolTable.Data = T;
            app.CMARetVolTable.ColumnEditable = [false false true true false];

            % Correlation table
            corrT = array2table(Corr, 'VariableNames', names, 'RowNames', names);
            app.CMACorrTable.Data = corrT;
        end

        function onUseCMAInputs(app)
            % Feed CMA returns/vol into the next optimization via BL pathway
            T = app.CMARetVolTable.Data;
            if isempty(T)
                uialert(app.UIFigure, 'Compute CMA first.', 'No CMA'); return;
            end
            app.StatusLabel.Text = 'CMA assumptions ready — select Black-Litterman objective to use them.';
        end

        %% ============ SESSION SAVE / LOAD ============

        function onSaveSession(app)
            % Save all data, settings, and portfolio state to a .mat file
            [f, p] = uiputfile({'*.mat','MATLAB Session (*.mat)'}, 'Save Session', ...
                fullfile(pwd, 'RiskToolSession.mat'));
            if isequal(f, 0), return; end
            filepath = fullfile(p, f);
            try
                session = struct();
                % Data
                session.R = app.R;
                session.Dates = app.Dates;
                session.AssetNames = app.AssetNames;
                session.W = app.W;
                session.Measures = app.Measures;
                session.AssetETFMap = app.AssetETFMap;
                % Portfolios
                session.SAA = app.SAA;
                session.TAA = app.TAA;
                % Settings
                session.Freq = app.Freq;
                session.DataType = app.DataType;
                session.Alpha = app.Alpha;
                session.Horizon = app.Horizon;
                session.RF = app.RF;
                session.LongOnly = app.LongOnly;
                session.LB = app.LB;
                session.UB = app.UB;
                session.Optimizer = app.Optimizer;
                session.Objective = app.Objective;
                session.TargetRet = app.TargetRet;
                session.NormalizeCombined = app.NormalizeCombined;
                session.RandSeed = app.RandSeed;
                session.MCPaths = app.MCPaths;
                % Bootstrap conditions
                session.BootCondData = app.BootCondTable.Data;
                session.BootCondLogic = app.BootCondLogicDrop.Value;
                session.BlockLen = app.BlockLenField.Value;
                session.BootPaths = app.PathsField.Value;
                % Date range
                session.StartDate = app.StartDateField.Value;
                session.EndDate = app.EndDateField.Value;
                % Scenarios
                session.Scenarios = app.Scenarios;

                save(filepath, 'session', '-v7.3');
                app.StatusLabel.Text = sprintf('Session saved: %s', filepath);
            catch ME
                uialert(app.UIFigure, sprintf('Save failed: %s', ME.message), 'Save Error');
            end
        end

        function onLoadSession(app)
            % Load a previously saved session
            [f, p] = uigetfile({'*.mat','MATLAB Session (*.mat)'}, 'Load Session');
            if isequal(f, 0), return; end
            filepath = fullfile(p, f);
            try
                loaded = load(filepath, 'session');
                s = loaded.session;

                % Restore data
                app.R = s.R;
                app.Dates = s.Dates;
                app.AssetNames = s.AssetNames;
                app.W = s.W;
                if isfield(s, 'Measures'), app.Measures = s.Measures; end
                if isfield(s, 'AssetETFMap'), app.AssetETFMap = s.AssetETFMap; end

                % Restore portfolios
                app.SAA = s.SAA;
                if isfield(s, 'TAA'), app.TAA = s.TAA; end

                % Restore settings
                app.Freq = s.Freq;
                app.DataType = s.DataType;
                app.Alpha = s.Alpha;
                app.Horizon = s.Horizon;
                app.RF = s.RF;
                app.LongOnly = s.LongOnly;
                app.LB = s.LB;
                app.UB = s.UB;
                app.Optimizer = s.Optimizer;
                app.Objective = s.Objective;
                if isfield(s, 'TargetRet'), app.TargetRet = s.TargetRet; end
                if isfield(s, 'NormalizeCombined'), app.NormalizeCombined = s.NormalizeCombined; end
                if isfield(s, 'RandSeed'), app.RandSeed = s.RandSeed; end
                if isfield(s, 'MCPaths'), app.MCPaths = s.MCPaths; end
                if isfield(s, 'Scenarios'), app.Scenarios = s.Scenarios; end

                % Update UI controls to match restored settings
                app.FreqDropDown.Value = app.Freq;
                app.DataTypeDropDown.Value = app.DataType;
                app.AlphaField.Value = app.Alpha;
                app.HorizonField.Value = app.Horizon;
                app.RiskFreeField.Value = app.RF;
                app.LongOnlyCheck.Value = app.LongOnly;
                app.LBField.Value = app.LB;
                app.UBField.Value = app.UB;
                app.OptimizerDropDown.Value = app.Optimizer;
                app.ObjectiveDropDown.Value = app.Objective;
                if isfinite(app.TargetRet)
                    app.TargetRetField.Value = app.TargetRet;
                end
                if isfield(s, 'StartDate'), app.StartDateField.Value = s.StartDate; end
                if isfield(s, 'EndDate'), app.EndDateField.Value = s.EndDate; end

                % Restore bootstrap settings
                if isfield(s, 'BootCondData') && ~isempty(s.BootCondData)
                    app.BootCondTable.Data = s.BootCondData;
                end
                if isfield(s, 'BootCondLogic')
                    app.BootCondLogicDrop.Value = s.BootCondLogic;
                end
                if isfield(s, 'BlockLen'), app.BlockLenField.Value = s.BlockLen; end
                if isfield(s, 'BootPaths'), app.PathsField.Value = s.BootPaths; end

                % Restore measures info label
                if ~isempty(app.Measures) && istable(app.Measures) && height(app.Measures) > 0
                    app.MeasuresInfoLabel.Text = sprintf('Measures: %d rows, %d columns (from session).', ...
                        height(app.Measures), width(app.Measures)-1);
                end

                % Update all UI displays
                populateAssetLists(app);
                app.TAAAssetsList.Items = app.AssetNames;
                app.DataTable.Data = array2table(app.R, 'VariableNames', app.AssetNames);
                app.TAATable.Data = app.TAA;
                updateFXOverlayDisplay(app);
                refreshScenariosTable(app);

                % Run analytics
                try updateSummary(app); catch; end
                try plotDistribution(app); catch; end
                try plotSensitivity(app); catch; end
                try updateTrackingError(app); catch; end
                try updatePerformanceTable(app); catch; end
                try updateCorrelation(app); catch; end
                try updateSAAAnalytics(app); catch; end
                try updateRiskDecomp(app); catch; end
                try updateCombinedAnalytics(app); catch; end
                try updateCombinedFXSplit(app); catch; end
                try updateEigenDecomp(app); catch; end

                app.StatusLabel.Text = sprintf('Session loaded: %s (%d assets, %d obs)', ...
                    f, numel(app.AssetNames), size(app.R,1));
            catch ME
                uialert(app.UIFigure, sprintf('Load failed: %s', ME.message), 'Load Error');
            end
        end

        %% ============ PDF REPORT GENERATION ============

        function onGenerateReport(app)
            % Orchestrate PDF report generation via LaTeX
            if isempty(app.R)
                uialert(app.UIFigure, 'Load data first before generating a report.', 'No Data');
                return;
            end
            prog = uiprogressdlg(app.UIFigure, 'Title', 'Generating Report', ...
                'Message', 'Setting up...', 'Indeterminate', 'off', 'Value', 0);
            try
                % Create temp directory
                tmpDir = fullfile(tempdir, ['report_' datestr(now,'yyyymmdd_HHMMSS')]); %#ok<TNOW1,DATST>
                mkdir(tmpDir);

                prog.Value = 0.05; prog.Message = 'Exporting charts...';

                % Export all available charts
                chartList = {
                    'DistAxes',         'distribution'
                    'SensAxes',         'sensitivity'
                    'FactorSensAxes',   'factor_sensitivity'
                    'CorrAxes',         'correlation_heatmap'
                    'CorrRollAxes',     'rolling_correlation'
                    'FrontierAxes',     'frontier'
                    'PerfAxesCum',      'perf_cumulative'
                    'PerfAxesVol',      'perf_rolling_vol'
                    'PerfAxesDD',       'perf_drawdown'
                    'RiskWaterfallAxes','risk_waterfall'
                    'RollingFactorAxes','rolling_factor'
                    'BootstrapAxes',    'bootstrap_dist'
                    'BootCondAxes',     'bootstrap_cond'
                };
                for ci = 1:size(chartList,1)
                    propName = chartList{ci,1};
                    fname = chartList{ci,2};
                    try
                        ax = app.(propName);
                        if app.uiValid(ax) && ~isempty(ax.Children)
                            exportChartImage(app, ax, tmpDir, fname);
                        end
                    catch
                        % skip if chart not available
                    end
                    prog.Value = 0.05 + 0.35 * (ci / size(chartList,1));
                end

                prog.Value = 0.45; prog.Message = 'Building LaTeX document...';
                texFile = buildReportLaTeX(app, tmpDir);

                prog.Value = 0.65; prog.Message = 'Compiling PDF (pdflatex)...';
                pdflatexCmd = sprintf('"%s" -interaction=nonstopmode -output-directory="%s" "%s"', ...
                    'C:\Program Files\MiKTeX\miktex\bin\x64\pdflatex.exe', tmpDir, texFile);
                [status, cmdout] = system(pdflatexCmd);

                % Run twice for cross-references
                if status == 0
                    system(pdflatexCmd);
                end

                [~, texName] = fileparts(texFile);
                pdfPath = fullfile(tmpDir, [texName '.pdf']);

                prog.Value = 0.90; prog.Message = 'Opening PDF...';

                if exist(pdfPath, 'file')
                    % Ask user where to save
                    [f, p] = uiputfile({'*.pdf','PDF Files'}, 'Save Report As', ...
                        fullfile(pwd, 'PortfolioReport.pdf'));
                    if ~isequal(f, 0)
                        copyfile(pdfPath, fullfile(p, f));
                        winopen(fullfile(p, f));
                        app.StatusLabel.Text = sprintf('Report saved: %s', fullfile(p, f));
                    else
                        winopen(pdfPath);
                        app.StatusLabel.Text = sprintf('Report: %s', pdfPath);
                    end
                else
                    % Compilation failed
                    uialert(app.UIFigure, ...
                        sprintf('pdflatex failed (exit %d).\n\nOutput:\n%s', status, cmdout), ...
                        'PDF Error');
                end

                prog.Value = 1.0; prog.Message = 'Done.';
                pause(0.3);
                close(prog);

            catch ME
                try close(prog); catch; end
                uialert(app.UIFigure, sprintf('Report generation failed:\n%s', ME.message), 'Report Error');
            end
        end

        function exportChartImage(~, ax, tmpDir, name)
            % Export a UIAxes to PNG
            pngPath = fullfile(tmpDir, [name '.png']);
            exportgraphics(ax, pngPath, 'Resolution', 150);
        end

        function texStr = tableToLaTeX(~, T, caption)
            % Convert MATLAB table to LaTeX tabular string with booktabs
            if nargin < 3, caption = ''; end
            varNames = T.Properties.VariableNames;
            nCols = width(T);

            % Escape special LaTeX chars in a string
            esc = @(s) strrep(strrep(strrep(strrep(string(s),'_','\_'),'%','\%'),'&','\&'),'#','\#');

            lines = {};
            if ~isempty(caption)
                lines{end+1} = sprintf('\\subsection*{%s}', char(esc(caption)));
            end

            % Determine column alignment
            colSpec = repmat('l', 1, nCols);
            % Check for numeric columns and right-align them
            for j = 1:nCols
                col = T.(varNames{j});
                if isnumeric(col)
                    colSpec(j) = 'r';
                end
            end

            lines{end+1} = '\begingroup\small';
            lines{end+1} = sprintf('\\begin{tabular}{%s}', colSpec);
            lines{end+1} = '\toprule';

            % Header row
            hdrs = cellfun(@(v) char(esc(v)), varNames, 'UniformOutput', false);
            lines{end+1} = [strjoin(hdrs, ' & ') ' \\'];
            lines{end+1} = '\midrule';

            % Data rows
            nRows = height(T);
            maxRows = min(nRows, 50); % cap at 50 rows
            for i = 1:maxRows
                cells = cell(1, nCols);
                for j = 1:nCols
                    val = T{i,j};
                    if isnumeric(val)
                        if abs(val) < 0.01 && val ~= 0
                            cells{j} = sprintf('%.6f', val);
                        elseif abs(val) > 100
                            cells{j} = sprintf('%.1f', val);
                        else
                            cells{j} = sprintf('%.4f', val);
                        end
                    elseif iscell(val)
                        cells{j} = char(esc(val{1}));
                    elseif isstring(val) || ischar(val)
                        cells{j} = char(esc(val));
                    else
                        cells{j} = char(esc(string(val)));
                    end
                end
                lines{end+1} = [strjoin(cells, ' & ') ' \\']; %#ok<AGROW>
            end
            if nRows > maxRows
                lines{end+1} = sprintf('\\multicolumn{%d}{c}{\\textit{... %d more rows ...}} \\\\', nCols, nRows - maxRows);
            end

            lines{end+1} = '\bottomrule';
            lines{end+1} = '\end{tabular}';
            lines{end+1} = '\endgroup';
            lines{end+1} = '';

            texStr = strjoin(lines, newline);
        end

        function texFile = buildReportLaTeX(app, tmpDir)
            % Build the complete LaTeX document for the portfolio report

            esc = @(s) strrep(strrep(strrep(strrep(string(s),'_','\_'),'%','\%'),'&','\&'),'#','\#');

            L = {};  % collect lines

            % Preamble
            L{end+1} = '\documentclass[11pt,a4paper]{article}';
            L{end+1} = '\usepackage[margin=2cm]{geometry}';
            L{end+1} = '\setlength{\headheight}{13.6pt}';
            L{end+1} = '\usepackage{graphicx,booktabs,float,xcolor,fancyhdr,longtable}';
            L{end+1} = '\usepackage[T1]{fontenc}';
            L{end+1} = '\usepackage{lmodern}';
            L{end+1} = '\pagestyle{fancy}';
            L{end+1} = '\fancyhead[L]{\textbf{Portfolio Risk Report}}';
            L{end+1} = sprintf('\\fancyhead[R]{%s}', datestr(now, 'dd-mmm-yyyy')); %#ok<TNOW1,DATST>
            L{end+1} = '\fancyfoot[C]{\thepage}';
            L{end+1} = '\setlength{\parindent}{0pt}';
            L{end+1} = '\setlength{\parskip}{6pt}';
            L{end+1} = '\begin{document}';

            % Title
            L{end+1} = '\begin{center}';
            L{end+1} = '{\LARGE\bfseries Portfolio Risk Report}\\[8pt]';
            L{end+1} = sprintf('{\\large Generated: %s}\\\\[4pt]', datestr(now, 'dd-mmm-yyyy HH:MM')); %#ok<TNOW1,DATST>
            L{end+1} = sprintf('{Assets: %d \\quad Observations: %d \\quad Frequency: %s}', ...
                size(app.R,2), size(app.R,1), char(esc(app.Freq)));
            L{end+1} = '\end{center}';
            L{end+1} = '\vspace{6pt}\hrule\vspace{12pt}';

            % === Section 1: Summary ===
            L{end+1} = '\section{Portfolio Summary}';
            if app.uiValid(app.SummaryText) && ~isempty(app.SummaryText.Value)
                summLines = app.SummaryText.Value;
                L{end+1} = '{\small\begin{verbatim}';
                for si = 1:numel(summLines)
                    L{end+1} = char(summLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end

            % Weights table
            if app.uiValid(app.WeightsTable) && ~isempty(app.WeightsTable.Data)
                L{end+1} = tableToLaTeX(app, app.WeightsTable.Data, 'Portfolio Weights & Risk Contribution');
            end

            % === Section 2: SAA ===
            L{end+1} = '\section{Strategic Asset Allocation}';

            % Funded allocations
            if ~isempty(app.SAA) && istable(app.SAA) && height(app.SAA) > 0
                isFX = false(height(app.SAA), 1);
                for i = 1:height(app.SAA)
                    isFX(i) = app.isFXOverlay(app.SAA.Asset{i});
                end
                funded = app.SAA(~isFX, :);
                overlays = app.SAA(isFX, :);

                if height(funded) > 0
                    L{end+1} = tableToLaTeX(app, funded, 'Funded Allocations');
                end
                if height(overlays) > 0
                    L{end+1} = tableToLaTeX(app, overlays, 'Overlay Positions');
                end
            end

            % FX exposure text
            if app.uiValid(app.FXExposureText) && ~isempty(app.FXExposureText.Value)
                L{end+1} = '\textbf{FX Exposure:}';
                L{end+1} = '{\small\begin{verbatim}';
                fxLines = app.FXExposureText.Value;
                for si = 1:numel(fxLines)
                    L{end+1} = char(fxLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end

            % SAA analytics
            if app.uiValid(app.SAAMetricsText) && ~isempty(app.SAAMetricsText.Value)
                L{end+1} = '\subsection*{SAA Analytics}';
                L{end+1} = '{\small\begin{verbatim}';
                mLines = app.SAAMetricsText.Value;
                for si = 1:numel(mLines)
                    L{end+1} = char(mLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end

            % === Section 3: Combined Weights ===
            L{end+1} = '\section{Combined Weights (SAA + TAA)}';
            if app.uiValid(app.CombinedTable) && ~isempty(app.CombinedTable.Data)
                L{end+1} = tableToLaTeX(app, app.CombinedTable.Data, 'Funded Positions');
            end
            if app.uiValid(app.CombFXTable) && ~isempty(app.CombFXTable.Data)
                L{end+1} = tableToLaTeX(app, app.CombFXTable.Data, 'Overlay Positions');
            end
            % Tracking error
            if app.uiValid(app.TETable) && ~isempty(app.TETable.Data)
                L{end+1} = tableToLaTeX(app, app.TETable.Data, 'Tracking Error vs SAA');
            end
            % Combined analytics
            if app.uiValid(app.CombAnalyticsText) && ~isempty(app.CombAnalyticsText.Value)
                L{end+1} = '{\small\begin{verbatim}';
                caLines = app.CombAnalyticsText.Value;
                for si = 1:numel(caLines)
                    L{end+1} = char(caLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end

            % === Section 4: Risk Decomposition ===
            L{end+1} = '\section{Risk Decomposition}';
            if app.uiValid(app.RiskBudgetTable) && ~isempty(app.RiskBudgetTable.Data)
                L{end+1} = tableToLaTeX(app, app.RiskBudgetTable.Data, 'Risk Budget');
            end
            if app.uiValid(app.ConcentrationText) && ~isempty(app.ConcentrationText.Value)
                L{end+1} = '\subsection*{Concentration Metrics}';
                L{end+1} = '{\small\begin{verbatim}';
                cLines = app.ConcentrationText.Value;
                for si = 1:numel(cLines)
                    L{end+1} = char(cLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end
            imgPath = fullfile(tmpDir, 'risk_waterfall.png');
            if exist(imgPath, 'file')
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Risk Contribution Waterfall}';
                L{end+1} = '\end{figure}';
            end
            % Factor decomposition
            if app.uiValid(app.FactorExposureTable) && ~isempty(app.FactorExposureTable.Data)
                L{end+1} = tableToLaTeX(app, app.FactorExposureTable.Data, 'Factor Exposures');
            end
            if app.uiValid(app.FactorVsSpecificText) && ~isempty(app.FactorVsSpecificText.Value)
                L{end+1} = '{\small\begin{verbatim}';
                fvLines = app.FactorVsSpecificText.Value;
                for si = 1:numel(fvLines)
                    L{end+1} = char(fvLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end
            imgPath = fullfile(tmpDir, 'rolling_factor.png');
            if exist(imgPath, 'file')
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Rolling Factor Betas}';
                L{end+1} = '\end{figure}';
            end

            % === Section 5: Distribution ===
            imgPath = fullfile(tmpDir, 'distribution.png');
            if exist(imgPath, 'file')
                L{end+1} = '\section{Return Distribution}';
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Portfolio Return Distribution with VaR/CVaR}';
                L{end+1} = '\end{figure}';
            end

            % === Section 6: Sensitivity ===
            imgPath = fullfile(tmpDir, 'sensitivity.png');
            if exist(imgPath, 'file')
                L{end+1} = '\section{Sensitivity Analysis}';
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Per-Asset Sensitivity (+1\% Shock)}';
                L{end+1} = '\end{figure}';
            end
            imgPath = fullfile(tmpDir, 'factor_sensitivity.png');
            if exist(imgPath, 'file')
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Factor Sensitivity}';
                L{end+1} = '\end{figure}';
            end

            % === Section 7: Correlation ===
            imgPath = fullfile(tmpDir, 'correlation_heatmap.png');
            if exist(imgPath, 'file')
                L{end+1} = '\section{Correlation Analysis}';
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Correlation Heatmap}';
                L{end+1} = '\end{figure}';
            end
            imgPath = fullfile(tmpDir, 'rolling_correlation.png');
            if exist(imgPath, 'file')
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Rolling Pairwise Correlation}';
                L{end+1} = '\end{figure}';
            end
            % PCA eigenvalue table
            if app.uiValid(app.EigenTable) && ~isempty(app.EigenTable.Data)
                L{end+1} = tableToLaTeX(app, app.EigenTable.Data, 'PCA Eigenvalue Decomposition');
            end

            % === Section 8: Performance ===
            hasPerf = false;
            imgPath = fullfile(tmpDir, 'perf_cumulative.png');
            if exist(imgPath, 'file')
                if ~hasPerf; L{end+1} = '\section{Performance}'; hasPerf = true; end
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Cumulative Returns}';
                L{end+1} = '\end{figure}';
            end
            imgPath = fullfile(tmpDir, 'perf_rolling_vol.png');
            if exist(imgPath, 'file')
                if ~hasPerf; L{end+1} = '\section{Performance}'; hasPerf = true; end
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Rolling Volatility}';
                L{end+1} = '\end{figure}';
            end
            imgPath = fullfile(tmpDir, 'perf_drawdown.png');
            if exist(imgPath, 'file')
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Drawdown}';
                L{end+1} = '\end{figure}';
            end
            % Performance stats table
            if app.uiValid(app.PerfTable) && ~isempty(app.PerfTable.Data)
                if ~hasPerf; L{end+1} = '\section{Performance}'; end
                L{end+1} = tableToLaTeX(app, app.PerfTable.Data, 'Performance Statistics');
            end

            % === Section 9: Efficient Frontier ===
            imgPath = fullfile(tmpDir, 'frontier.png');
            if exist(imgPath, 'file')
                L{end+1} = '\section{Efficient Frontier}';
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Mean-Variance Efficient Frontier}';
                L{end+1} = '\end{figure}';
            end
            if app.uiValid(app.FrontierDistLabel) && ~isempty(app.FrontierDistLabel.Text) ...
                    && ~strcmp(app.FrontierDistLabel.Text, '')
                L{end+1} = sprintf('\\textbf{%s}', char(esc(app.FrontierDistLabel.Text)));
            end

            % === Section 10: Bootstrap ===
            hasBoot = false;
            if app.uiValid(app.BootstrapSummary) && ~isempty(app.BootstrapSummary.Value) ...
                    && ~all(cellfun(@isempty, app.BootstrapSummary.Value))
                L{end+1} = '\section{Conditional Bootstrap}';
                hasBoot = true;
                L{end+1} = '{\small\begin{verbatim}';
                bsLines = app.BootstrapSummary.Value;
                for si = 1:numel(bsLines)
                    L{end+1} = char(bsLines{si}); %#ok<AGROW>
                end
                L{end+1} = '\end{verbatim}}';
            end
            imgPath = fullfile(tmpDir, 'bootstrap_dist.png');
            if exist(imgPath, 'file')
                if ~hasBoot; L{end+1} = '\section{Conditional Bootstrap}'; hasBoot = true; end
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.9\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Bootstrap Return Distribution}';
                L{end+1} = '\end{figure}';
            end
            imgPath = fullfile(tmpDir, 'bootstrap_cond.png');
            if exist(imgPath, 'file')
                if ~hasBoot; L{end+1} = '\section{Conditional Bootstrap}'; end
                L{end+1} = '\begin{figure}[H]\centering';
                L{end+1} = sprintf('\\includegraphics[width=0.85\\textwidth]{%s}', strrep(imgPath,'\','/'));
                L{end+1} = '\caption{Condition Match Timeline}';
                L{end+1} = '\end{figure}';
            end

            % === Section 11: Stress Scenarios ===
            if app.uiValid(app.SAAStressTable) && ~isempty(app.SAAStressTable.Data)
                L{end+1} = '\section{Stress Scenarios}';
                L{end+1} = tableToLaTeX(app, app.SAAStressTable.Data, 'SAA Stress Performance');
            end
            if app.uiValid(app.ScenTable) && ~isempty(app.ScenTable.Data)
                if ~app.uiValid(app.SAAStressTable) || isempty(app.SAAStressTable.Data)
                    L{end+1} = '\section{Stress Scenarios}';
                end
                L{end+1} = tableToLaTeX(app, app.ScenTable.Data, 'Scenario Analysis');
            end

            % End document
            L{end+1} = '';
            L{end+1} = '\end{document}';

            % Write to file
            texFile = fullfile(tmpDir, 'PortfolioReport.tex');
            fid = fopen(texFile, 'w', 'n', 'UTF-8');
            fprintf(fid, '%s\n', L{:});
            fclose(fid);
        end
    end
end
