classdef SignalBuilderDialog < handle
    %SIGNALBUILDERDIALOG Modal dialog for building individual custom signals.
    %   Opens a dialog where the user picks a signal type, sets parameters,
    %   previews the result, and adds it to the app.

    properties (Access = private)
        Fig              matlab.ui.Figure
        MainGrid         matlab.ui.container.GridLayout

        % Type selector
        TypeDropDown     matlab.ui.control.DropDown

        % Dynamic parameter panel
        ParamPanel       matlab.ui.container.Panel
        ParamGrid        matlab.ui.container.GridLayout

        % Preview
        PreviewAxes      matlab.ui.control.UIAxes
        StatsLabel       matlab.ui.control.Label

        % Buttons
        PreviewButton    matlab.ui.control.Button
        AddButton        matlab.ui.control.Button
        CancelButton     matlab.ui.control.Button

        % Name field
        NameField        matlab.ui.control.EditField

        % Dynamic parameter controls (recreated per type)
        LookbackField    matlab.ui.control.NumericEditField
        MinHistField     matlab.ui.control.NumericEditField
        TanhScaleField   matlab.ui.control.NumericEditField
        VariableDrop     matlab.ui.control.DropDown
        NegateCheck      matlab.ui.control.CheckBox
        MinWindowField   matlab.ui.control.NumericEditField
        CompositeTable   matlab.ui.control.Table

        % Momentum-family controls
        VolHalflifeField matlab.ui.control.NumericEditField
        VolFloorField    matlab.ui.control.NumericEditField
        ActivationDrop   matlab.ui.control.DropDown
        SkipDaysField    matlab.ui.control.NumericEditField

        % EWMAC controls
        FastSpanField    matlab.ui.control.NumericEditField
        SlowSpanField    matlab.ui.control.NumericEditField

        % Ensemble controls
        LookbacksField   matlab.ui.control.EditField
        MethodDrop       matlab.ui.control.DropDown

        % Data
        MktData          struct
        MacroData        table
        ExistingNames    cell

        % Result
        ResultSignal     double
        ResultMeta       struct
        Accepted         logical = false

        % Available macro variables
        MacroVarNames    cell
    end

    methods (Access = public)
        function app = SignalBuilderDialog(mkt, macro, existingNames)
            if nargin < 3, existingNames = {}; end
            app.MktData = mkt;
            app.MacroData = macro;
            app.ExistingNames = existingNames;

            % Determine available macro variable names
            if istable(macro) && height(macro) > 0
                vn = macro.Properties.VariableNames;
                app.MacroVarNames = vn(~strcmpi(vn, 'Date'));
            else
                app.MacroVarNames = {};
            end

            createComponents(app);
            onTypeChanged(app);
        end

        function [signal, metadata] = waitForUser(app)
            uiwait(app.Fig);
            if app.Accepted && ~isempty(app.ResultSignal)
                signal = app.ResultSignal;
                metadata = app.ResultMeta;
            else
                signal = [];
                metadata = struct();
            end
            if isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.Fig = uifigure('Name', 'Signal Builder', ...
                'Position', [300 150 480 680], ...
                'CloseRequestFcn', @(~,~) onCancel(app), ...
                'Resize', 'off');

            app.MainGrid = uigridlayout(app.Fig, [7 1]);
            app.MainGrid.RowHeight = {'fit', 'fit', '1x', 'fit', '0.6x', 'fit', 'fit'};
            app.MainGrid.Padding = [10 10 10 10];
            app.MainGrid.RowSpacing = 6;

            % Row 1: Signal type selector
            typeRow = uigridlayout(app.MainGrid, [1 2]);
            typeRow.ColumnWidth = {'fit', '1x'};
            typeRow.Padding = [0 0 0 0];
            uilabel(typeRow, 'Text', 'Signal Type:', 'FontWeight', 'bold');
            app.TypeDropDown = uidropdown(typeRow, ...
                'Items', {'Momentum', 'EWMAC', 'Ensemble', 'MacroZ', 'MeanReversion', 'Composite'}, ...
                'Value', 'Momentum', ...
                'ValueChangedFcn', @(~,~) onTypeChanged(app));

            % Row 2: Signal name
            nameRow = uigridlayout(app.MainGrid, [1 2]);
            nameRow.ColumnWidth = {'fit', '1x'};
            nameRow.Padding = [0 0 0 0];
            uilabel(nameRow, 'Text', 'Signal Name:', 'FontWeight', 'bold');
            app.NameField = uieditfield(nameRow, 'text', 'Value', 'SPX_Mom_126d');

            % Row 3: Dynamic parameter panel
            app.ParamPanel = uipanel(app.MainGrid, 'Title', 'Parameters');

            % Row 4: Stats label
            app.StatsLabel = uilabel(app.MainGrid, 'Text', 'Preview signal to see statistics.', ...
                'FontColor', [0.4 0.4 0.4]);

            % Row 5: Preview axes
            app.PreviewAxes = uiaxes(app.MainGrid);
            title(app.PreviewAxes, 'Signal Preview');
            ylabel(app.PreviewAxes, 'Signal Value');
            app.PreviewAxes.YLim = [-1.1 1.1];

            % Row 6: Buttons
            btnRow = uigridlayout(app.MainGrid, [1 3]);
            btnRow.ColumnWidth = {'1x', '1x', '1x'};
            btnRow.Padding = [0 0 0 0];
            app.PreviewButton = uibutton(btnRow, 'Text', 'Preview', ...
                'ButtonPushedFcn', @(~,~) onPreview(app));
            app.AddButton = uibutton(btnRow, 'Text', 'Add Signal', ...
                'BackgroundColor', [0.3 0.75 0.4], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~,~) onAdd(app));
            app.CancelButton = uibutton(btnRow, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) onCancel(app));

            % Row 7: spacer
            uilabel(app.MainGrid, 'Text', '');
        end

        %% ---- Type Changed: rebuild parameter panel ----
        function onTypeChanged(app)
            % Clear existing param panel contents
            delete(app.ParamPanel.Children);

            sigType = app.TypeDropDown.Value;

            switch sigType
                case 'Momentum'
                    buildMomentumParams(app);
                    app.NameField.Value = 'SPX_Mom_126d';
                case 'EWMAC'
                    buildEWMACParams(app);
                    app.NameField.Value = 'EWMAC_16_64';
                case 'Ensemble'
                    buildEnsembleParams(app);
                    app.NameField.Value = 'Ensemble_4lb';
                case 'MacroZ'
                    buildMacroZParams(app);
                    if ~isempty(app.MacroVarNames)
                        app.NameField.Value = sprintf('%s_Z', app.MacroVarNames{1});
                    else
                        app.NameField.Value = 'MacroZ';
                    end
                case 'MeanReversion'
                    buildMeanRevParams(app);
                    app.NameField.Value = 'MeanRev_63d';
                case 'Composite'
                    buildCompositeParams(app);
                    app.NameField.Value = 'Composite_2vars';
            end

            % Reset preview
            cla(app.PreviewAxes);
            app.StatsLabel.Text = 'Preview signal to see statistics.';
        end

        %% ---- Parameter Panels ----
        function buildMomentumParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [7 2]);
            app.ParamGrid.ColumnWidth = {'fit', '1x'};
            app.ParamGrid.RowHeight = repmat({'fit'}, 1, 7);

            uilabel(app.ParamGrid, 'Text', 'Lookback (days):');
            app.LookbackField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 126, 'Limits', [21 504]);

            uilabel(app.ParamGrid, 'Text', 'Min History:');
            app.MinHistField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 252, 'Limits', [42 1008]);

            uilabel(app.ParamGrid, 'Text', 'Vol Halflife:');
            app.VolHalflifeField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 32, 'Limits', [10 120]);

            uilabel(app.ParamGrid, 'Text', 'Skip Days:');
            app.SkipDaysField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 0, 'Limits', [0 21]);

            uilabel(app.ParamGrid, 'Text', 'Vol Floor (0=auto):');
            app.VolFloorField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 0, 'Limits', [0 Inf]);

            uilabel(app.ParamGrid, 'Text', 'Activation:');
            app.ActivationDrop = uidropdown(app.ParamGrid, ...
                'Items', {'tanh', 'sigmoid', 'revertSigmoid'}, ...
                'Value', 'tanh');

            uilabel(app.ParamGrid, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        function buildEWMACParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [6 2]);
            app.ParamGrid.ColumnWidth = {'fit', '1x'};
            app.ParamGrid.RowHeight = repmat({'fit'}, 1, 6);

            uilabel(app.ParamGrid, 'Text', 'Fast Span:');
            app.FastSpanField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 16, 'Limits', [2 128]);

            uilabel(app.ParamGrid, 'Text', 'Slow Span:');
            app.SlowSpanField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 64, 'Limits', [8 512]);

            uilabel(app.ParamGrid, 'Text', 'Vol Halflife:');
            app.VolHalflifeField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 32, 'Limits', [10 120]);

            uilabel(app.ParamGrid, 'Text', 'Vol Floor (0=auto):');
            app.VolFloorField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 0, 'Limits', [0 Inf]);

            uilabel(app.ParamGrid, 'Text', 'Activation:');
            app.ActivationDrop = uidropdown(app.ParamGrid, ...
                'Items', {'tanh', 'sigmoid', 'revertSigmoid'}, ...
                'Value', 'tanh');

            uilabel(app.ParamGrid, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        function buildEnsembleParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [7 2]);
            app.ParamGrid.ColumnWidth = {'fit', '1x'};
            app.ParamGrid.RowHeight = repmat({'fit'}, 1, 7);

            uilabel(app.ParamGrid, 'Text', 'Lookbacks:');
            app.LookbacksField = uieditfield(app.ParamGrid, 'text', ...
                'Value', '21,63,126,252');

            uilabel(app.ParamGrid, 'Text', 'Method:');
            app.MethodDrop = uidropdown(app.ParamGrid, ...
                'Items', {'Equal Weight', 'Risk Parity'}, ...
                'Value', 'Equal Weight');

            uilabel(app.ParamGrid, 'Text', 'Vol Halflife:');
            app.VolHalflifeField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 32, 'Limits', [10 120]);

            uilabel(app.ParamGrid, 'Text', 'Skip Days:');
            app.SkipDaysField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 0, 'Limits', [0 21]);

            uilabel(app.ParamGrid, 'Text', 'Vol Floor (0=auto):');
            app.VolFloorField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 0, 'Limits', [0 Inf]);

            uilabel(app.ParamGrid, 'Text', 'Activation:');
            app.ActivationDrop = uidropdown(app.ParamGrid, ...
                'Items', {'tanh', 'sigmoid', 'revertSigmoid'}, ...
                'Value', 'tanh');

            uilabel(app.ParamGrid, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        function buildMacroZParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [4 2]);
            app.ParamGrid.ColumnWidth = {'fit', '1x'};
            app.ParamGrid.RowHeight = {'fit', 'fit', 'fit', 'fit'};

            uilabel(app.ParamGrid, 'Text', 'Variable:');
            if ~isempty(app.MacroVarNames)
                items = app.MacroVarNames;
            else
                items = {'(none)'};
            end
            app.VariableDrop = uidropdown(app.ParamGrid, ...
                'Items', items, 'Value', items{1});

            uilabel(app.ParamGrid, 'Text', 'Min Window:');
            app.MinWindowField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 126, 'Limits', [20 504]);

            uilabel(app.ParamGrid, 'Text', 'Negate:');
            app.NegateCheck = uicheckbox(app.ParamGrid, 'Text', 'Invert signal', 'Value', false);

            uilabel(app.ParamGrid, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        function buildMeanRevParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [3 2]);
            app.ParamGrid.ColumnWidth = {'fit', '1x'};
            app.ParamGrid.RowHeight = {'fit', 'fit', 'fit'};

            uilabel(app.ParamGrid, 'Text', 'MA Lookback (days):');
            app.LookbackField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 63, 'Limits', [21 504]);

            uilabel(app.ParamGrid, 'Text', 'Min History:');
            app.MinHistField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 126, 'Limits', [42 1008]);

            uilabel(app.ParamGrid, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        function buildCompositeParams(app)
            app.ParamGrid = uigridlayout(app.ParamPanel, [3 1]);
            app.ParamGrid.RowHeight = {'1x', 'fit', 'fit'};

            % Editable table for variables, weights, negate
            if ~isempty(app.MacroVarNames) && numel(app.MacroVarNames) >= 2
                defaultVars = app.MacroVarNames(1:min(2, numel(app.MacroVarNames)));
            else
                defaultVars = {'VIX', 'HY_Spread'};
            end
            nDef = numel(defaultVars);
            tData = [defaultVars(:), num2cell(ones(nDef,1)), num2cell(false(nDef,1))];
            app.CompositeTable = uitable(app.ParamGrid, ...
                'Data', tData, ...
                'ColumnName', {'Variable', 'Weight', 'Negate'}, ...
                'ColumnEditable', [true true true], ...
                'ColumnFormat', {app.MacroVarNames, 'numeric', 'logical'});

            % Min window row
            mwRow = uigridlayout(app.ParamGrid, [1 2]);
            mwRow.ColumnWidth = {'fit', '1x'};
            mwRow.Padding = [0 0 0 0];
            uilabel(mwRow, 'Text', 'Min Window:');
            app.MinWindowField = uieditfield(mwRow, 'numeric', ...
                'Value', 126, 'Limits', [20 504]);

            % Tanh scale row
            tsRow = uigridlayout(app.ParamGrid, [1 2]);
            tsRow.ColumnWidth = {'fit', '1x'};
            tsRow.Padding = [0 0 0 0];
            uilabel(tsRow, 'Text', 'Tanh Scale:');
            app.TanhScaleField = uieditfield(app.ParamGrid, 'numeric', ...
                'Value', 2, 'Limits', [0.1 10]);
        end

        %% ---- Collect params from UI ----
        function params = collectParams(app)
            sigType = app.TypeDropDown.Value;
            params = struct();
            params.tanhScale = app.TanhScaleField.Value;

            switch sigType
                case 'Momentum'
                    params.lookback = app.LookbackField.Value;
                    params.minHistory = app.MinHistField.Value;
                    params.volHalflife = app.VolHalflifeField.Value;
                    params.skipDays = app.SkipDaysField.Value;
                    params.volFloor = app.VolFloorField.Value;
                    params.activation = app.ActivationDrop.Value;
                case 'EWMAC'
                    params.fastSpan = app.FastSpanField.Value;
                    params.slowSpan = app.SlowSpanField.Value;
                    params.volHalflife = app.VolHalflifeField.Value;
                    params.volFloor = app.VolFloorField.Value;
                    params.activation = app.ActivationDrop.Value;
                case 'Ensemble'
                    lbText = app.LookbacksField.Value;
                    params.lookbacks = str2num(lbText); %#ok<ST2NM>
                    if isempty(params.lookbacks)
                        params.lookbacks = [21 63 126 252];
                    end
                    methodStr = app.MethodDrop.Value;
                    if strcmp(methodStr, 'Risk Parity')
                        params.method = 'riskparity';
                    else
                        params.method = 'equal';
                    end
                    params.volHalflife = app.VolHalflifeField.Value;
                    params.skipDays = app.SkipDaysField.Value;
                    params.volFloor = app.VolFloorField.Value;
                    params.activation = app.ActivationDrop.Value;
                case 'MacroZ'
                    params.variable = app.VariableDrop.Value;
                    params.minWindow = app.MinWindowField.Value;
                    params.negate = app.NegateCheck.Value;
                case 'MeanReversion'
                    params.lookback = app.LookbackField.Value;
                    params.minHistory = app.MinHistField.Value;
                case 'Composite'
                    tData = app.CompositeTable.Data;
                    params.variables = tData(:,1)';
                    params.weights = cell2mat(tData(:,2))';
                    params.negate = cell2mat(tData(:,3))';
                    params.minWindow = app.MinWindowField.Value;
            end
        end

        %% ---- Preview ----
        function onPreview(app)
            try
                params = collectParams(app);
                sigType = app.TypeDropDown.Value;
                [sig, meta] = sigstrat.buildSignal(sigType, params, app.MktData, app.MacroData);

                app.ResultSignal = sig;
                app.ResultMeta = meta;
                app.ResultMeta.name = app.NameField.Value;

                % Plot
                cla(app.PreviewAxes);
                plot(app.PreviewAxes, app.MktData.retDates, sig, 'LineWidth', 0.8);
                yline(app.PreviewAxes, 0, '--', 'Color', [0.5 0.5 0.5]);
                app.PreviewAxes.YLim = [-1.1 1.1];
                title(app.PreviewAxes, app.NameField.Value);
                ylabel(app.PreviewAxes, 'Signal');

                % Stats
                valid = sig(isfinite(sig));
                if isempty(valid)
                    app.StatsLabel.Text = 'No valid signal values produced.';
                else
                    app.StatsLabel.Text = sprintf('Mean=%.3f  Std=%.3f  Min=%.3f  Max=%.3f  Valid=%d/%d', ...
                        mean(valid), std(valid), min(valid), max(valid), numel(valid), numel(sig));
                end
            catch ME
                app.StatsLabel.Text = ['Error: ' ME.message];
            end
        end

        %% ---- Add Signal ----
        function onAdd(app)
            % Validate name
            name = strtrim(app.NameField.Value);
            if isempty(name)
                uialert(app.Fig, 'Signal name cannot be empty.', 'Validation Error');
                return;
            end
            if any(strcmp(name, app.ExistingNames))
                uialert(app.Fig, sprintf('Signal name "%s" already exists. Choose a unique name.', name), ...
                    'Duplicate Name');
                return;
            end

            % Build signal if not already previewed
            if isempty(app.ResultSignal)
                onPreview(app);
            end
            if isempty(app.ResultSignal)
                uialert(app.Fig, 'Could not build signal. Check parameters.', 'Build Error');
                return;
            end

            app.ResultMeta.name = name;
            app.Accepted = true;
            uiresume(app.Fig);
        end

        %% ---- Cancel ----
        function onCancel(app)
            app.Accepted = false;
            uiresume(app.Fig);
        end
    end
end
