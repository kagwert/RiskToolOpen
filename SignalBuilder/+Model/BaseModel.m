classdef BaseModel < handle
% BaseModel  Abstract base for all +Model Handle Classes.
%
%   All domain model classes in the SignalBuilder project inherit from
%   BaseModel.  It provides:
%     - A standard 'Changed' event that subclasses notify when their
%       state mutates, so Controllers can react via addlistener.
%     - A read-only Name property for identification/logging.
%     - Abstract lifecycle stubs that subclasses may override.
%
%   Example subclass declaration:
%       classdef MarketData < Model.BaseModel

    % ------------------------------------------------------------------ %
    events
        % Fired by subclasses via notify(obj, 'Changed') whenever any
        % meaningful state has been updated.
        Changed
    end

    % ------------------------------------------------------------------ %
    properties (SetAccess = protected)
        % Human-readable identifier set at construction.
        Name (1,1) string = "BaseModel"
    end

    properties (Access = protected)
        % Subclasses may store initialisation metadata here.
        CreatedAt (1,1) datetime = datetime('now', 'TimeZone', 'local')
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = BaseModel(name)
        % BaseModel  Constructor.
        %   obj = BaseModel(name) sets the Name property.
            arguments
                name (1,1) string = "BaseModel"
            end
            obj.Name = name;
        end

        function tf = isReady(obj) %#ok<MANU>
        % isReady  Returns true when the model holds valid data.
        %   Subclasses should override this to reflect their own state.
            tf = true;
        end

        function reset(obj)
        % reset  Clears all computed state back to defaults.
        %   Subclasses should override and call reset@Model.BaseModel(obj)
        %   at the end of their own implementation.
            notify(obj, 'Changed');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function notifyChanged(obj)
        % notifyChanged  Convenience wrapper to fire the Changed event.
            notify(obj, 'Changed');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = protected, Static)
        function validateTimetable(tt, requiredVars)
        % validateTimetable  Assert tt is a timetable with required columns.
        %
        %   Model.BaseModel.validateTimetable(tt, ["Close","Volume"])
            arguments
                tt timetable
                requiredVars (1,:) string = string.empty
            end
            missing = requiredVars(~ismember(requiredVars, tt.Properties.VariableNames));
            if ~isempty(missing)
                error('SignalBuilder:BaseModel:missingColumns', ...
                    'Timetable is missing required columns: %s', ...
                    strjoin(missing, ', '));
            end
        end
    end
end
