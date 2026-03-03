classdef BaseView < handle
% BaseView  Base class for all +View rendering classes.
%
%   Provides a shared figure handle, a title string, and lifecycle methods
%   (show, hide, close) that all concrete views can rely on.
%
%   Subclass example:
%       classdef ChartView < View.BaseView

    % ------------------------------------------------------------------ %
    properties (SetAccess = protected)
        % Main figure handle created by the view.
        Figure matlab.ui.Figure = gobjects(0)

        % Window title shown in the figure title bar.
        Title (1,1) string = "SignalBuilder"
    end

    properties (Access = protected)
        % Flag set to true once render() has been called at least once.
        IsRendered (1,1) logical = false
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = BaseView(title)
        % BaseView  Constructor.
        %   v = View.BaseView('My Chart')
            arguments
                title (1,1) string = "SignalBuilder"
            end
            obj.Title = title;
        end

        % -------------------------------------------------------------- %
        function show(obj)
        % show  Make the view's figure visible (creates it if needed).
            if ~obj.hasFigure()
                obj.createFigure();
            end
            obj.Figure.Visible = 'on';
            figure(obj.Figure);   % bring to front
        end

        % -------------------------------------------------------------- %
        function hide(obj)
        % hide  Hide the figure without destroying it.
            if obj.hasFigure()
                obj.Figure.Visible = 'off';
            end
        end

        % -------------------------------------------------------------- %
        function close(obj)
        % close  Destroy the figure handle.
            if obj.hasFigure()
                delete(obj.Figure);
            end
        end

        % -------------------------------------------------------------- %
        function tf = hasFigure(obj)
        % hasFigure  Returns true if the figure exists and is valid.
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        % -------------------------------------------------------------- %
        function delete(obj)
        % delete  Destructor — clean up figure on object destruction.
            obj.close();
        end
    end

    % ------------------------------------------------------------------ %
    methods (Abstract)
        % render  Draw/update the view's content.
        %   Subclasses must implement this method.
        render(obj)
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function createFigure(obj)
        % createFigure  Instantiate a uifigure for this view.
            obj.Figure = uifigure( ...
                'Name',    obj.Title, ...
                'Visible', 'off');
        end

        function clearAxes(obj)
        % clearAxes  Delete all axes children inside the figure.
            if obj.hasFigure()
                delete(obj.Figure.Children);
            end
        end
    end
end
