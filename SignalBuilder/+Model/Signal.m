classdef Signal < Model.BaseModel
% Signal  Handle class that computes and stores trading signals.
%
%   A Signal is built from a MarketData handle.  Computed signals are
%   appended to a timetable (SignalTable) as columns, keeping them
%   time-aligned with the source price data.
%
%   Usage:
%       md  = Model.MarketData('SPY');
%       md.loadFromFile('SPY.csv');
%       sig = Model.Signal(md);
%       sig.addSMA(20);
%       sig.addRSI(14);
%       sig.addCrossoverSignal('SMA_20', 'SMA_50');
%       tt  = sig.SignalTable;

    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        % Handle reference to the source MarketData object (not a copy).
        MarketDataRef Model.MarketData

        % Timetable of computed signal columns.
        % RowTimes mirror MarketDataRef.Prices.Time.
        SignalTable timetable = timetable.empty
    end

    properties (Dependent)
        % Names of all computed signal columns.
        SignalNames (1,:) string
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = Signal(marketDataObj)
        % Signal  Constructor.
        %   sig = Model.Signal(md)  where md is a Model.MarketData handle.
            arguments
                marketDataObj (1,1) Model.MarketData
            end
            obj = obj@Model.BaseModel("Signal:" + marketDataObj.Ticker);
            obj.MarketDataRef = marketDataObj;
            % Initialise empty timetable aligned to price times
            if marketDataObj.NumBars > 0
                obj.SignalTable = timetable(marketDataObj.Prices.Time);
            end
            % Auto-refresh when source data changes
            addlistener(marketDataObj, 'Changed', @(~,~) obj.onDataChanged());
        end

        % -------------------------------------------------------------- %
        function addSMA(obj, period)
        % addSMA  Add a Simple Moving Average column to SignalTable.
        %
        %   sig.addSMA(20)   % adds column SMA_20
            arguments
                obj
                period (1,1) {mustBePositive, mustBeInteger} = 20
            end
            obj.requireData();
            close = obj.MarketDataRef.Prices.Close;
            sma   = movmean(close, period, 'Endpoints', 'discard');
            % Pad NaNs at the front so lengths match
            values = [nan(period - 1, 1); sma];
            colName = sprintf('SMA_%d', period);
            obj.upsertColumn(colName, values);
        end

        % -------------------------------------------------------------- %
        function addEMA(obj, period)
        % addEMA  Add an Exponential Moving Average column to SignalTable.
        %
        %   sig.addEMA(12)   % adds column EMA_12
            arguments
                obj
                period (1,1) {mustBePositive, mustBeInteger} = 12
            end
            obj.requireData();
            close  = obj.MarketDataRef.Prices.Close;
            k      = 2 / (period + 1);
            values = nan(numel(close), 1);
            values(period) = mean(close(1:period));
            for i = period + 1 : numel(close)
                values(i) = close(i) * k + values(i-1) * (1 - k);
            end
            colName = sprintf('EMA_%d', period);
            obj.upsertColumn(colName, values);
        end

        % -------------------------------------------------------------- %
        function addRSI(obj, period)
        % addRSI  Add Relative Strength Index column to SignalTable.
        %
        %   sig.addRSI(14)   % adds column RSI_14
            arguments
                obj
                period (1,1) {mustBePositive, mustBeInteger} = 14
            end
            obj.requireData();
            close  = obj.MarketDataRef.Prices.Close;
            delta  = diff(close);
            gains  = max(delta, 0);
            losses = abs(min(delta, 0));
            n      = numel(close);
            values = nan(n, 1);
            if n > period
                avgGain = mean(gains(1:period));
                avgLoss = mean(losses(1:period));
                for i = period + 1 : n - 1
                    avgGain = (avgGain * (period - 1) + gains(i)) / period;
                    avgLoss = (avgLoss * (period - 1) + losses(i)) / period;
                    rs = avgGain / max(avgLoss, eps);
                    values(i + 1) = 100 - (100 / (1 + rs));
                end
            end
            colName = sprintf('RSI_%d', period);
            obj.upsertColumn(colName, values);
        end

        % -------------------------------------------------------------- %
        function addCrossoverSignal(obj, fastCol, slowCol)
        % addCrossoverSignal  Long/flat signal based on two column crossover.
        %
        %   Produces a column named '<fastCol>_X_<slowCol>' with values:
        %       +1  = fast above slow (long)
        %        0  = signal not yet valid (NaN input)
        %       -1  = fast below slow (short / flat, depending on strategy)
        %
        %   sig.addCrossoverSignal('EMA_12', 'EMA_26')
            arguments
                obj
                fastCol (1,1) string
                slowCol (1,1) string
            end
            obj.requireSignalCols([fastCol, slowCol]);
            fast   = obj.SignalTable.(fastCol);
            slow   = obj.SignalTable.(slowCol);
            values = double(fast > slow) - double(fast < slow);
            values(isnan(fast) | isnan(slow)) = 0;
            colName = fastCol + "_X_" + slowCol;
            obj.upsertColumn(colName, values);
        end

        % -------------------------------------------------------------- %
        function tt = getSignals(obj, colNames)
        % getSignals  Return a subset of SignalTable by column names.
        %
        %   tt = sig.getSignals()               % all columns
        %   tt = sig.getSignals(["SMA_20","RSI_14"])
            arguments
                obj
                colNames (1,:) string = string.empty
            end
            if isempty(colNames)
                tt = obj.SignalTable;
            else
                obj.requireSignalCols(colNames);
                tt = obj.SignalTable(:, colNames);
            end
        end

        % -------------------------------------------------------------- %
        % Dependent getter
        function names = get.SignalNames(obj)
            if isempty(obj.SignalTable)
                names = string.empty;
            else
                names = string(obj.SignalTable.Properties.VariableNames);
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function upsertColumn(obj, colName, values)
            cName = char(colName);   % R2021b: VariableNames needs char, not string
            if isempty(obj.SignalTable)
                obj.SignalTable = timetable( ...
                    obj.MarketDataRef.Prices.Time, values, ...
                    'VariableNames', {cName});
            elseif ismember(cName, obj.SignalTable.Properties.VariableNames)
                obj.SignalTable.(cName) = values;
            else
                newCol = timetable( ...
                    obj.MarketDataRef.Prices.Time, values, ...
                    'VariableNames', {cName});
                obj.SignalTable = synchronize(obj.SignalTable, newCol);
            end
            obj.notifyChanged();
        end

        function requireData(obj)
            if obj.MarketDataRef.NumBars == 0
                error('SignalBuilder:Signal:noData', ...
                    'MarketData reference holds no price data.');
            end
        end

        function requireSignalCols(obj, colNames)
            missing = colNames(~ismember(colNames, ...
                obj.SignalTable.Properties.VariableNames));
            if ~isempty(missing)
                error('SignalBuilder:Signal:missingColumn', ...
                    'Signal columns not found: %s', strjoin(missing, ', '));
            end
        end

        function onDataChanged(obj)
            % Source data was reloaded — clear all derived signals.
            obj.SignalTable = timetable(obj.MarketDataRef.Prices.Time);
            obj.notifyChanged();
        end
    end
end
