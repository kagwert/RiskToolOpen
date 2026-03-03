classdef BaseController < handle
% BaseController  Abstract base for all +Controller classes.
%
%   A controller:
%     - Instantiates Model and View objects.
%     - Wires event listeners between them.
%     - Provides a uniform lifecycle (init, run, shutdown).
%
%   Subclass example:
%       classdef StrategyController < Controller.BaseController

    % ------------------------------------------------------------------ %
    properties (SetAccess = protected)
        % Human-readable name for logging / debugging.
        Name (1,1) string = "BaseController"
    end

    properties (Access = protected)
        % Active listener handles stored so they can be cleaned up.
        Listeners event.listener = event.listener.empty
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = BaseController(name)
        % BaseController  Constructor.
            arguments
                name (1,1) string = "BaseController"
            end
            obj.Name = name;
        end

        % -------------------------------------------------------------- %
        function shutdown(obj)
        % shutdown  Release all listeners and close all views.
        %   Subclasses should call shutdown@Controller.BaseController(obj)
        %   after their own cleanup.
            delete(obj.Listeners);
            obj.Listeners = event.listener.empty;
        end

        % -------------------------------------------------------------- %
        function delete(obj)
        % delete  Destructor — always shut down cleanly.
            obj.shutdown();
        end
    end

    % ------------------------------------------------------------------ %
    methods (Abstract)
        % init  Build models, views and wire listeners.
        init(obj)

        % run  Start the primary workflow (load data, compute, render).
        run(obj)
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function addManagedListener(obj, source, eventName, callback)
        % addManagedListener  Register a listener that is tracked for cleanup.
            lh = addlistener(source, eventName, callback);
            obj.Listeners(end+1) = lh;
        end

        function logInfo(obj, msg, varargin)
        % logInfo  Print a timestamped info message.
            fprintf('[%s] [%s] INFO: %s\n', ...
                datestr(now, 'HH:MM:SS'), obj.Name, ...
                sprintf(msg, varargin{:}));
        end

        function logWarn(obj, msg, varargin)
        % logWarn  Print a timestamped warning.
            fprintf('[%s] [%s] WARN: %s\n', ...
                datestr(now, 'HH:MM:SS'), obj.Name, ...
                sprintf(msg, varargin{:}));
        end
    end
end
