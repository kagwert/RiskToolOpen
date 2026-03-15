classdef UnderweightApp < View.BaseView
% UnderweightApp  Standalone uifigure GUI for the equity underweight strategy.
%
%   Provides a left control panel with all strategy parameters and a
%   right tabgroup with 5 chart tabs: Signals, Composite, Allocation,
%   Performance, and Tree.
%
%   Controller wires callbacks via wireBuildCallback / wireOptimizeCallback /
%   wireRunCallback; results are pushed back via updateXTab() methods.
%
%   USAGE (called by UnderweightController):
%       app = View.UnderweightApp();
%       app.render();
%       app.wireBuildCallback(@ctrl.onBuildSignals);

    % ------------------------------------------------------------------ %
    properties (Access = private)
        % ---- Left panel controls ----
        FldTicker       matlab.ui.control.EditField
        FldStartDate    matlab.ui.control.EditField

        % Signal params
        SpnMAWindow     matlab.ui.control.Spinner
        SpnTrendScale   matlab.ui.control.Spinner
        SpnPayrollsHL   matlab.ui.control.Spinner
        SpnYieldZWin    matlab.ui.control.Spinner
        SpnYieldHL      matlab.ui.control.Spinner
        SpnCreditZWin   matlab.ui.control.Spinner
        SpnCreditHL     matlab.ui.control.Spinner

        % Label params
        SpnSevRet       matlab.ui.control.Spinner
        SpnSevVol       matlab.ui.control.Spinner
        SpnMildRet      matlab.ui.control.Spinner

        % Allocation params
        SpnBase         matlab.ui.control.Spinner
        SpnMild         matlab.ui.control.Spinner
        SpnSevere       matlab.ui.control.Spinner

        % Tree params
        SpnMaxSplits    matlab.ui.control.Spinner
        SpnCostSevere   matlab.ui.control.Spinner
        SpnCostMild     matlab.ui.control.Spinner

        % Buttons
        BtnBuild        matlab.ui.control.Button
        BtnOptimize     matlab.ui.control.Button
        BtnRun          matlab.ui.control.Button

        % Status
        LblStatus       matlab.ui.control.Label

        % ---- Right panel tabs ----
        TabGroup        matlab.ui.container.TabGroup
        TabSignals      matlab.ui.container.Tab
        TabComposite    matlab.ui.container.Tab
        TabAllocation   matlab.ui.container.Tab
        TabPerformance  matlab.ui.container.Tab
        TabTree         matlab.ui.container.Tab

        % Axes on Signals tab (2×2 grid)
        AxSig1          matlab.ui.control.UIAxes
        AxSig2          matlab.ui.control.UIAxes
        AxSig3          matlab.ui.control.UIAxes
        AxSig4          matlab.ui.control.UIAxes

        % Axes on other tabs
        AxComposite     matlab.ui.control.UIAxes
        AxAllocation    matlab.ui.control.UIAxes
        AxEquity        matlab.ui.control.UIAxes
        TblPerf         matlab.ui.control.Table
        TxtTree         matlab.ui.control.TextArea

        % Hidden state: PayrollsMom PrefilterWindow from optimizer
        OptPrefilterWindow  double = 3
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = UnderweightApp()
            obj = obj@View.BaseView('Underweight Strategy');
        end

        % -------------------------------------------------------------- %
        function render(obj)
        % render  Build the uifigure and all controls (idempotent).
            if obj.hasFigure()
                figure(obj.Figure);
                return;
            end
            obj.createFigure();
            obj.buildLayout();
            obj.Figure.Visible = 'on';
        end

        % -------------------------------------------------------------- %
        function p = getParams(obj)
        % getParams  Return a struct of all current control values.
            p.EquityTicker  = strtrim(obj.FldTicker.Value);
            p.StartDate     = strtrim(obj.FldStartDate.Value);

            p.MAWindow      = obj.SpnMAWindow.Value;
            p.TrendScale    = obj.SpnTrendScale.Value;
            p.PayrollsSmoothHL = obj.SpnPayrollsHL.Value;
            p.YieldZWin     = obj.SpnYieldZWin.Value;
            p.YieldSmoothHL = obj.SpnYieldHL.Value;
            p.CreditZWin    = obj.SpnCreditZWin.Value;
            p.CreditSmoothHL = obj.SpnCreditHL.Value;

            p.SevereRetThresh = obj.SpnSevRet.Value / 100;
            p.SevereVolThresh = obj.SpnSevVol.Value / 100;
            p.MildRetThresh   = obj.SpnMildRet.Value / 100;

            p.BaseWeight    = obj.SpnBase.Value   / 100;
            p.MildWeight    = obj.SpnMild.Value   / 100;
            p.SevereWeight  = obj.SpnSevere.Value / 100;

            p.TreeMaxSplits = obj.SpnMaxSplits.Value;
            p.CostSevere    = obj.SpnCostSevere.Value;
            p.CostMild      = obj.SpnCostMild.Value;

            p.OptPrefilterWindow = obj.OptPrefilterWindow;
        end

        % -------------------------------------------------------------- %
        function setStatus(obj, msg)
        % setStatus  Update the status label text.
            if obj.hasFigure()
                obj.LblStatus.Text = msg;
                drawnow limitrate;
            end
        end

        % -------------------------------------------------------------- %
        function wireBuildCallback(obj, fcn)
            obj.BtnBuild.ButtonPushedFcn = @(~,~) fcn();
        end

        function wireOptimizeCallback(obj, fcn)
            obj.BtnOptimize.ButtonPushedFcn = @(~,~) fcn();
        end

        function wireRunCallback(obj, fcn)
            obj.BtnRun.ButtonPushedFcn = @(~,~) fcn();
        end

        % -------------------------------------------------------------- %
        function applyOptimizedParams(obj, optResult)
        % applyOptimizedParams  Push optimizer results back into spinners.
            if isfield(optResult, 'PayrollsMom')
                bp = optResult.PayrollsMom.BestParams;
                obj.SpnPayrollsHL.Value = bp.SmoothHalfLife;
                obj.OptPrefilterWindow  = bp.PrefilterWindow;
            end
            if isfield(optResult, 'YieldCurve')
                bp = optResult.YieldCurve.BestParams;
                obj.SpnYieldZWin.Value = bp.ZScoreWindow;
                obj.SpnYieldHL.Value   = bp.SmoothHalfLife;
            end
            if isfield(optResult, 'CreditSpread')
                bp = optResult.CreditSpread.BestParams;
                obj.SpnCreditZWin.Value = bp.ZScoreWindow;
                obj.SpnCreditHL.Value   = bp.SmoothHalfLife;
            end
            if isfield(optResult, 'EquityTrend')
                bp = optResult.EquityTrend.BestParams;
                obj.SpnMAWindow.Value    = bp.MAWindow;
                obj.SpnTrendScale.Value  = bp.TrendScale;
            end
        end

        % -------------------------------------------------------------- %
        function updateSignalsTab(obj, features, labels, T, lbl_v)
        % updateSignalsTab  Populate the 4-panel signal chart.
        %
        %   features  timetable  – from buildSignals (aligned to T)
        %   labels    timetable  – from labelEquityRegimes (aligned to T)
        %   T         datetime   – common valid time vector
        %   lbl_v     double     – label values (0/1/2) at T

            cN = [0.85, 0.92, 1.00];
            cM = [1.00, 0.93, 0.80];
            cS = [1.00, 0.80, 0.80];

            sigCols   = {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend'};
            sigTitles = {'Payrolls Momentum (PAYEMS)', ...
                         'Yield Curve Slope (T10Y2Y)', ...
                         'HY Credit Spread (BAMLH0A0HYM2)', ...
                         'Equity Price Trend (vs MA)'};
            axList = {obj.AxSig1, obj.AxSig2, obj.AxSig3, obj.AxSig4};

            [~, iF, iL] = intersect(features.Time, labels.Time);
            featA = features(iF, :);
            validM = ~isnan(labels.Label(iL));
            featV  = featA(validM, :);

            for k = 1 : 4
                ax = axList{k};
                cla(ax);
                hold(ax, 'off');
                shadeRegimes(ax, T, lbl_v, cN, cM, cS);
                sigK = featV.(sigCols{k});
                plot(ax, T, sigK, 'Color', [0.1 0.3 0.7], 'LineWidth', 1.5);
                yline(ax, 0, 'k--', 'LineWidth', 0.8);
                ylim(ax, [-1.1 1.1]);
                ylabel(ax, 'Signal');
                title(ax, sigTitles{k}, 'FontSize', 9);
                ax.XGrid = 'on';  ax.YGrid = 'on';
            end
        end

        % -------------------------------------------------------------- %
        function updateCompositeTab(obj, T, comp_v, thresholds, lbl_v)
        % updateCompositeTab  Plot composite signal with threshold lines.
        %
        %   thresholds  [1×2]  [MildThr, SevereThr]

            cN = [0.85, 0.92, 1.00];
            cM = [1.00, 0.93, 0.80];
            cS = [1.00, 0.80, 0.80];
            ax = obj.AxComposite;
            cla(ax);
            hold(ax, 'off');
            shadeRegimes(ax, T, lbl_v, cN, cM, cS);
            plot(ax, T, comp_v, 'Color', [0.1 0.3 0.7], 'LineWidth', 2, ...
                'DisplayName', 'Composite');
            if ~isempty(thresholds)
                yline(ax, thresholds(1), '--', 'Color', [0.9 0.5 0], 'LineWidth', 1.5, ...
                    'Label', sprintf('Mild %.2f', thresholds(1)), ...
                    'LabelHorizontalAlignment', 'right');
                yline(ax, thresholds(2), '--', 'Color', [0.8 0 0], 'LineWidth', 1.5, ...
                    'Label', sprintf('Severe %.2f', thresholds(2)), ...
                    'LabelHorizontalAlignment', 'right');
            end
            yline(ax, 0, 'k:', 'LineWidth', 0.8);
            ylim(ax, [-1.1 1.1]);
            ylabel(ax, 'Composite Signal');
            title(ax, 'Equal-Weighted Composite Signal with Best Threshold Lines');
            ax.XGrid = 'on';  ax.YGrid = 'on';
        end

        % -------------------------------------------------------------- %
        function updateAllocationTab(obj, T, allocSeries, names, lbl_v)
        % updateAllocationTab  Plot equity allocation over time.
        %
        %   allocSeries  cell of double(:,1)  – one series per variant
        %   names        cell of char         – display names

            cN = [0.85, 0.92, 1.00];
            cM = [1.00, 0.93, 0.80];
            cS = [1.00, 0.80, 0.80];
            ax = obj.AxAllocation;
            cla(ax);
            hold(ax, 'off');
            shadeRegimes(ax, T, lbl_v, cN, cM, cS);

            colours = {[0.2 0.5 0.9], [0.1 0.7 0.4], [0.8 0.2 0.2], ...
                       [0.6 0.3 0.7], [0.9 0.6 0.1]};
            styles  = {'-','--','-','--',':'};
            for v = 1 : numel(allocSeries)
                if isempty(allocSeries{v}); continue; end
                clr = colours{mod(v-1, numel(colours))+1};
                sty = styles{mod(v-1, numel(styles))+1};
                plot(ax, T, allocSeries{v}, sty, 'Color', clr, ...
                    'LineWidth', 1.8, 'DisplayName', names{v});
            end
            ylim(ax, [0.15, 0.55]);
            yticks(ax, [0.20 0.35 0.50]);
            yticklabels(ax, {'20% Severe', '35% Mild', '50% Neutral'});
            ylabel(ax, 'Equity Allocation');
            title(ax, 'Equity Allocation Over Time');
            legend(ax, 'Location', 'best');
            ax.XGrid = 'on';  ax.YGrid = 'on';
        end

        % -------------------------------------------------------------- %
        function updatePerformanceTab(obj, perfTable, equityCurves, T)
        % updatePerformanceTab  Populate the metrics table and equity curve chart.
        %
        %   equityCurves  cell of double(:,1)  – cumulative equity per variant

            % Table
            obj.TblPerf.Data = perfTable;

            % Equity curves chart
            ax = obj.AxEquity;
            cla(ax);
            hold(ax, 'on');
            colours = {[0 0 0], [0.2 0.5 0.9], [0.1 0.7 0.4], ...
                       [0.8 0.2 0.2], [0.6 0.3 0.7]};
            names = perfTable.Variant;
            for v = 1 : numel(equityCurves)
                if isempty(equityCurves{v}); continue; end
                clr = colours{mod(v-1, numel(colours))+1};
                plot(ax, T, equityCurves{v}, 'Color', clr, ...
                    'LineWidth', 1.5, 'DisplayName', names{v});
            end
            ylabel(ax, 'Portfolio Value ($1 start)');
            title(ax, 'Cumulative Portfolio Performance');
            legend(ax, 'Location', 'best');
            ax.XGrid = 'on';  ax.YGrid = 'on';
        end

        % -------------------------------------------------------------- %
        function updateTreeTab(obj, treeText)
        % updateTreeTab  Show decision tree text output.
            obj.TxtTree.Value = treeText;
        end

        % -------------------------------------------------------------- %
        function selectTab(obj, name)
        % selectTab  Switch the active tab by name: 'Signals' | 'Composite' |
        %            'Allocation' | 'Performance' | 'Tree'.
            switch lower(name)
                case 'signals';     obj.TabGroup.SelectedTab = obj.TabSignals;
                case 'composite';   obj.TabGroup.SelectedTab = obj.TabComposite;
                case 'allocation';  obj.TabGroup.SelectedTab = obj.TabAllocation;
                case 'performance'; obj.TabGroup.SelectedTab = obj.TabPerformance;
                case 'tree';        obj.TabGroup.SelectedTab = obj.TabTree;
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function createFigure(obj)
            obj.Figure = uifigure( ...
                'Name',     obj.Title, ...
                'Position', [80, 80, 1400, 820], ...
                'Visible',  'off');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function buildLayout(obj)
        % buildLayout  Construct the full UI tree inside obj.Figure.

            % Top-level 1×2 grid
            mainGrid = uigridlayout(obj.Figure, [1, 2]);
            mainGrid.ColumnWidth = {320, '1x'};
            mainGrid.Padding     = [4 4 4 4];
            mainGrid.ColumnSpacing = 6;

            % --- Left panel (scrollable) ---
            leftPanel = uipanel(mainGrid, 'Scrollable', 'on', 'Title', '');
            leftPanel.Layout.Column = 1;

            obj.buildLeftPanel(leftPanel);

            % --- Right tab group ---
            obj.TabGroup = uitabgroup(mainGrid);
            obj.TabGroup.Layout.Column = 2;

            obj.TabSignals    = uitab(obj.TabGroup, 'Title', 'Signals');
            obj.TabComposite  = uitab(obj.TabGroup, 'Title', 'Composite');
            obj.TabAllocation = uitab(obj.TabGroup, 'Title', 'Allocation');
            obj.TabPerformance = uitab(obj.TabGroup, 'Title', 'Performance');
            obj.TabTree       = uitab(obj.TabGroup, 'Title', 'Tree');

            obj.buildSignalsTab();
            obj.buildCompositeTab();
            obj.buildAllocationTab();
            obj.buildPerformanceTab();
            obj.buildTreeTab();
        end

        % -------------------------------------------------------------- %
        function buildLeftPanel(obj, panel)
            g = uigridlayout(panel, [32, 2]);
            g.RowHeight    = repmat({'fit'}, 1, 32);
            g.ColumnWidth  = {'1x', '1x'};
            g.Padding      = [6 6 6 6];
            g.RowSpacing   = 3;

            row = 1;

            % --- DATA section ---
            row = obj.addSectionLabel(g, 'DATA', row);

            lbl_tick = uilabel(g, 'Text', 'Ticker');
            lbl_tick.Layout.Row = row;  lbl_tick.Layout.Column = 1;
            obj.FldTicker = uieditfield(g, 'text', 'Value', 'SPY');
            obj.FldTicker.Layout.Row = row;
            obj.FldTicker.Layout.Column = 2;
            row = row + 1;

            lbl_sd = uilabel(g, 'Text', 'Start Date');
            lbl_sd.Layout.Row = row;  lbl_sd.Layout.Column = 1;
            obj.FldStartDate = uieditfield(g, 'text', 'Value', '1994-01-01');
            obj.FldStartDate.Layout.Row = row;
            obj.FldStartDate.Layout.Column = 2;
            row = row + 1;

            % --- SIGNAL PARAMS section ---
            row = obj.addSectionLabel(g, 'SIGNAL PARAMS', row);

            [obj.SpnMAWindow, row]   = obj.addSpinner(g, 'MA Window (days)', 200, 10, 500, 10, row);
            [obj.SpnTrendScale, row] = obj.addSpinner(g, 'Trend Scale',       10,  1,  50,  1, row);
            [obj.SpnPayrollsHL, row] = obj.addSpinner(g, 'Payrolls Smooth HL', 3,  0.5, 12, 0.5, row);
            [obj.SpnYieldZWin, row]  = obj.addSpinner(g, 'Yield Z-Win (mo)', 60,  12, 180, 12, row);
            [obj.SpnYieldHL, row]    = obj.addSpinner(g, 'Yield Smooth HL',   3,  0.5, 12, 0.5, row);
            [obj.SpnCreditZWin, row] = obj.addSpinner(g, 'Credit Z-Win (mo)',60,  12, 180, 12, row);
            [obj.SpnCreditHL, row]   = obj.addSpinner(g, 'Credit Smooth HL', 1,  0.5, 12, 0.5, row);

            % --- LABEL PARAMS section ---
            row = obj.addSectionLabel(g, 'LABEL PARAMS', row);

            [obj.SpnSevRet, row] = obj.addSpinner(g, 'Sev Ret Thr (%)',  0, -20, 20,  1, row);
            [obj.SpnSevVol, row] = obj.addSpinner(g, 'Sev Vol Thr (%)', 30,   5, 80,  5, row);
            [obj.SpnMildRet, row]= obj.addSpinner(g, 'Mild Ret Thr (%)', 0, -20, 20,  1, row);

            % --- ALLOCATIONS section ---
            row = obj.addSectionLabel(g, 'ALLOCATIONS (%)', row);

            [obj.SpnBase,   row] = obj.addSpinner(g, 'Base (%)',   50, 30, 80, 5, row);
            [obj.SpnMild,   row] = obj.addSpinner(g, 'Mild (%)',   35, 10, 60, 5, row);
            [obj.SpnSevere, row] = obj.addSpinner(g, 'Severe (%)', 20,  5, 50, 5, row);

            % --- TREE PARAMS section ---
            row = obj.addSectionLabel(g, 'TREE PARAMS', row);

            [obj.SpnMaxSplits,  row] = obj.addSpinner(g, 'Max Splits',    4, 1, 10, 1, row);
            [obj.SpnCostSevere, row] = obj.addSpinner(g, 'Cost Severe',   5, 1, 20, 1, row);
            [obj.SpnCostMild,   row] = obj.addSpinner(g, 'Cost Mild',     2, 1, 10, 1, row);

            % --- Buttons ---
            obj.BtnBuild = uibutton(g, 'Text', 'Build Signals', ...
                'BackgroundColor', [0.2 0.5 0.9], 'FontColor', 'w', 'FontWeight', 'bold');
            obj.BtnBuild.Layout.Row = row;
            obj.BtnBuild.Layout.Column = [1 2];
            row = row + 1;

            obj.BtnOptimize = uibutton(g, 'Text', 'Optimize Params', ...
                'BackgroundColor', [0.1 0.65 0.3], 'FontColor', 'w', 'FontWeight', 'bold');
            obj.BtnOptimize.Layout.Row = row;
            obj.BtnOptimize.Layout.Column = [1 2];
            row = row + 1;

            obj.BtnRun = uibutton(g, 'Text', 'Run Strategy', ...
                'BackgroundColor', [0.85 0.2 0.2], 'FontColor', 'w', 'FontWeight', 'bold');
            obj.BtnRun.Layout.Row = row;
            obj.BtnRun.Layout.Column = [1 2];
            row = row + 1;

            % --- Status label ---
            obj.LblStatus = uilabel(g, 'Text', 'Ready.', ...
                'WordWrap', 'on', 'FontAngle', 'italic', ...
                'VerticalAlignment', 'top');
            obj.LblStatus.Layout.Row    = row;
            obj.LblStatus.Layout.Column = [1 2];

            % Update grid row count to match actual rows used
            g.RowHeight = repmat({'fit'}, 1, row);
        end

        % -------------------------------------------------------------- %
        function buildSignalsTab(obj)
            g = uigridlayout(obj.TabSignals, [2, 2]);
            g.Padding = [4 4 4 4];
            g.RowSpacing    = 4;
            g.ColumnSpacing = 4;

            obj.AxSig1 = uiaxes(g); obj.AxSig1.Layout.Row = 1; obj.AxSig1.Layout.Column = 1;
            obj.AxSig2 = uiaxes(g); obj.AxSig2.Layout.Row = 1; obj.AxSig2.Layout.Column = 2;
            obj.AxSig3 = uiaxes(g); obj.AxSig3.Layout.Row = 2; obj.AxSig3.Layout.Column = 1;
            obj.AxSig4 = uiaxes(g); obj.AxSig4.Layout.Row = 2; obj.AxSig4.Layout.Column = 2;
        end

        function buildCompositeTab(obj)
            g = uigridlayout(obj.TabComposite, [1, 1]);
            g.Padding = [4 4 4 4];
            obj.AxComposite = uiaxes(g);
        end

        function buildAllocationTab(obj)
            g = uigridlayout(obj.TabAllocation, [1, 1]);
            g.Padding = [4 4 4 4];
            obj.AxAllocation = uiaxes(g);
        end

        function buildPerformanceTab(obj)
            g = uigridlayout(obj.TabPerformance, [2, 1]);
            g.RowHeight = {'1x', '2x'};
            g.Padding   = [4 4 4 4];

            obj.TblPerf = uitable(g);
            obj.TblPerf.Layout.Row = 1;

            obj.AxEquity = uiaxes(g);
            obj.AxEquity.Layout.Row = 2;
        end

        function buildTreeTab(obj)
            g = uigridlayout(obj.TabTree, [1, 1]);
            g.Padding = [4 4 4 4];
            obj.TxtTree = uitextarea(g, 'Editable', 'off', ...
                'FontName', 'Courier New', 'FontSize', 11);
            obj.TxtTree.Value = {'Run strategy to see decision tree rules.'};
        end

        % -------------------------------------------------------------- %
        function row = addSectionLabel(~, g, txt, row)
            lbl = uilabel(g, 'Text', txt, 'FontWeight', 'bold', ...
                'FontColor', [0.3 0.3 0.3]);
            lbl.Layout.Row    = row;
            lbl.Layout.Column = [1 2];
            row = row + 1;
        end

        function [spn, row] = addSpinner(~, g, labelTxt, defVal, lo, hi, step, row)
            lbl = uilabel(g, 'Text', labelTxt, 'HorizontalAlignment', 'right');
            lbl.Layout.Row    = row;
            lbl.Layout.Column = 1;
            spn = uispinner(g, 'Value', defVal, 'Limits', [lo hi], 'Step', step, ...
                'ValueDisplayFormat', '%.4g');
            spn.Layout.Row    = row;
            spn.Layout.Column = 2;
            row = row + 1;
        end
    end
end
