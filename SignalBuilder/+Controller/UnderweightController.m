classdef UnderweightController < Controller.BaseController
% UnderweightController  Mediates DataManager ↔ UnderweightApp for the
%                        equity underweight strategy GUI.
%
%   Owns the DataManager and UnderweightApp. Implements the three button
%   callbacks: Build Signals, Optimize Params, Run Strategy.
%
%   USAGE:
%       ctrl = Controller.UnderweightController();
%       ctrl.init();
%       ctrl.run();

    % ------------------------------------------------------------------ %
    properties (Access = private)
        App         View.UnderweightApp
        DM          Model.DataManager

        % Cached state (populated by onBuildSignals)
        Features    timetable = timetable.empty
        Labels      timetable = timetable.empty
        EqPrices    timetable = timetable.empty
        MonthClose  double    = []

        % Best PayrollsMom PrefilterWindow from optimizer (default 3)
        OptPrefilter double = 3
    end

    % ------------------------------------------------------------------ %
    methods
        function obj = UnderweightController()
            obj = obj@Controller.BaseController('UnderweightController');
        end

        % -------------------------------------------------------------- %
        function init(obj)
        % init  Create DataManager, build App, wire callbacks.
            obj.logInfo('Initialising DataManager...');
            obj.DM = Model.DataManager();
            obj.DM.init();

            obj.logInfo('Creating UnderweightApp...');
            obj.App = View.UnderweightApp();
            obj.App.render();

            obj.App.wireBuildCallback(@obj.onBuildSignals);
            obj.App.wireOptimizeCallback(@obj.onOptimize);
            obj.App.wireRunCallback(@obj.onRunStrategy);

            obj.logInfo('Ready.');
        end

        % -------------------------------------------------------------- %
        function run(obj)
        % run  Bring the app window to front.
            if ~isempty(obj.App) && obj.App.hasFigure()
                figure(obj.App.Figure);
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)
        % -------------------------------------------------------------- %
        function onBuildSignals(obj)
        % onBuildSignals  Fetch data, build signals, label regimes, update tab.
            try
                obj.App.setStatus('Building signals... (may take 20-30 s on first run)');
                drawnow;

                p = obj.App.getParams();

                % Build feature timetable
                features = buildSignals(obj.DM, p.EquityTicker, ...
                    StartDate                = p.StartDate, ...
                    MAWindow                 = p.MAWindow, ...
                    TrendScale               = p.TrendScale, ...
                    PayrollsPrefilterWindow  = p.OptPrefilterWindow, ...
                    PayrollsSmoothHalfLife   = p.PayrollsSmoothHL, ...
                    YieldZScoreWindow        = p.YieldZWin, ...
                    YieldSmoothHalfLife      = p.YieldSmoothHL, ...
                    CreditZScoreWindow       = p.CreditZWin, ...
                    CreditSmoothHalfLife     = p.CreditSmoothHL);

                % Fetch equity prices for labelling (try Yahoo → Stooq → FRED)
                tt_eq = timetable.empty;
                try
                    tt_eq = obj.DM.fetch_yahoo(p.EquityTicker, p.StartDate, "");
                catch
                end
                if height(tt_eq) < 252 * 25
                    try
                        tt_st = obj.DM.fetch_stooq(p.EquityTicker, p.StartDate, "");
                        if height(tt_st) > height(tt_eq)
                            tt_eq = tt_st;
                        end
                    catch
                    end
                end
                if height(tt_eq) < 252 * 25
                    tt_eq = obj.fetchFredSp500(p.StartDate);
                end

                md = Model.MarketData(p.EquityTicker);
                md.loadFromTimetable(tt_eq, 'Yahoo');

                labels = labelEquityRegimes(md.Prices, features.Time, ...
                    SevereRetThresh = p.SevereRetThresh, ...
                    SevereVolThresh = p.SevereVolThresh, ...
                    MildRetThresh   = p.MildRetThresh);

                % Cache state
                obj.Features  = features;
                obj.Labels    = labels;
                obj.EqPrices  = md.Prices;

                % Build monthly close cache
                monthGrid = features.Time;
                monthYM   = year(monthGrid)*100 + month(monthGrid);
                dailyYM   = year(md.Prices.Time)*100 + month(md.Prices.Time);
                closeP    = md.Prices.Close;
                mc        = nan(numel(monthGrid), 1);
                for k = 1 : numel(monthGrid)
                    idx = find(dailyYM == monthYM(k), 1, 'last');
                    if ~isempty(idx); mc(k) = closeP(idx); end
                end
                obj.MonthClose = mc;

                % Compute aligned valid subset for chart
                [~, iF, iL] = intersect(features.Time, labels.Time);
                lbl_all  = labels(iL, :);
                validMask = ~isnan(lbl_all.Label);
                T         = features.Time(iF(validMask));
                lbl_v     = lbl_all.Label(validMask);

                % Update Signals tab
                obj.App.updateSignalsTab(features, labels, T, lbl_v);
                obj.App.selectTab('Signals');

                nMo = height(features);
                nLbl = sum(validMask);
                obj.App.setStatus(sprintf('Built: %d months, %d labelled. Click Optimize or Run Strategy.', nMo, nLbl));

            catch ME
                obj.App.setStatus(['ERROR (Build): ' ME.message]);
                obj.logWarn('onBuildSignals failed: %s', ME.message);
            end
        end

        % -------------------------------------------------------------- %
        function onOptimize(obj)
        % onOptimize  Grid-search signal params; apply best to spinners.
            if isempty(obj.Features)
                obj.App.setStatus('Run "Build Signals" first.');
                return;
            end
            try
                obj.App.setStatus('Optimising signal parameters (85 combos × 4 signals)...');
                drawnow;

                p = obj.App.getParams();

                optResult = optimizeSignalParams(obj.DM, p.EquityTicker, p.StartDate, ...
                    obj.Labels, obj.Features.Time, obj.EqPrices);

                obj.App.applyOptimizedParams(optResult);

                % Build status message with per-signal best accuracy
                sigNames  = {'PayrollsMom','YieldCurve','CreditSpread','EquityTrend'};
                statusParts = {};
                for k = 1 : numel(sigNames)
                    sn = sigNames{k};
                    if isfield(optResult, sn)
                        acc = optResult.(sn).BestBalAcc;
                        statusParts{end+1} = sprintf('%s: %.3f', sn, acc); %#ok<AGROW>
                    end
                end
                obj.App.setStatus(['Optimised. Best BalAcc — ' strjoin(statusParts, ' | ')]);

            catch ME
                obj.App.setStatus(['ERROR (Optimize): ' ME.message]);
                obj.logWarn('onOptimize failed: %s', ME.message);
            end
        end

        % -------------------------------------------------------------- %
        function onRunStrategy(obj)
        % onRunStrategy  Run threshold + tree approaches; update all result tabs.
            if isempty(obj.Features)
                obj.App.setStatus('Run "Build Signals" first.');
                return;
            end
            try
                p = obj.App.getParams();

                % Validate allocation weights
                if p.SevereWeight >= p.MildWeight || p.MildWeight >= p.BaseWeight
                    obj.App.setStatus(sprintf( ...
                        'ERROR: Weights must satisfy Severe (%.0f%%) < Mild (%.0f%%) < Base (%.0f%%).' , ...
                        p.SevereWeight*100, p.MildWeight*100, p.BaseWeight*100));
                    return;
                end

                obj.App.setStatus('Running threshold approach...');
                drawnow;

                thresh = thresholdApproach(obj.Features, obj.Labels, ...
                    BaseWeight   = p.BaseWeight, ...
                    MildWeight   = p.MildWeight, ...
                    SevereWeight = p.SevereWeight);

                % Decision tree (optional — requires Stat+ML Toolbox)
                dtree = [];
                obj.App.setStatus('Running decision tree...');
                drawnow;
                try
                    dtree = decisionTreeApproach(obj.Features, obj.Labels, ...
                        MaxNumSplits = p.TreeMaxSplits, ...
                        CostSevere   = p.CostSevere, ...
                        CostMild     = p.CostMild, ...
                        BaseWeight   = p.BaseWeight, ...
                        MildWeight   = p.MildWeight, ...
                        SevereWeight = p.SevereWeight);
                catch ME_tree
                    obj.App.setStatus(['Decision tree skipped: ' ME_tree.message]);
                    drawnow;
                end

                % Aligned valid subset
                [~, iF, iL] = intersect(obj.Features.Time, obj.Labels.Time);
                lbl_all   = obj.Labels(iL, :);
                validMask = ~isnan(lbl_all.Label);
                T         = obj.Features.Time(iF(validMask));
                lbl_v     = lbl_all.Label(validMask);

                % Monthly equity returns
                equityMonthRet = [NaN; diff(obj.MonthClose) ./ obj.MonthClose(1:end-1)];
                eqRet_v        = equityMonthRet(iF(validMask));
                bondRet        = (1 + 0.04)^(1/12) - 1;

                % Build allocation series and equity curves
                variantNames = {'Benchmark50pct', 'Composite', 'MacroComposite', ...
                                'MarketComposite'};
                allocSeries  = { repmat(p.BaseWeight, sum(validMask), 1), ...
                                 thresh.Composite.BestAlloc, ...
                                 thresh.MacroComposite.BestAlloc, ...
                                 thresh.MarketComposite.BestAlloc };

                if ~isempty(dtree)
                    variantNames{end+1} = 'DecisionTree';
                    allocSeries{end+1}  = dtree.Allocation;
                end

                nVariants   = numel(variantNames);
                perfRows    = cell(nVariants, 1);
                equityCurves = cell(nVariants, 1);

                for v = 1 : nVariants
                    alloc_v = allocSeries{v};
                    m = evalPortfolio(alloc_v, eqRet_v, bondRet);
                    perfRows{v} = {variantNames{v}, m.TotalReturn, m.AnnReturn, ...
                        m.SharpeRatio, m.MaxDrawdown, m.AvgEquityAlloc};
                    portRet = alloc_v .* eqRet_v + (1 - alloc_v) .* bondRet;
                    portRet(isnan(portRet)) = 0;
                    equityCurves{v} = cumprod(1 + portRet);
                end

                perfTable = table( ...
                    variantNames(:), ...
                    cellfun(@(r) r{2}, perfRows), ...
                    cellfun(@(r) r{3}, perfRows), ...
                    cellfun(@(r) r{4}, perfRows), ...
                    cellfun(@(r) r{5}, perfRows), ...
                    cellfun(@(r) r{6}, perfRows), ...
                    'VariableNames', {'Variant','TotalReturn','AnnReturn', ...
                                      'SharpeRatio','MaxDrawdown','AvgEquityAlloc'});

                % --- Update tabs ---
                comp_v      = obj.Features.Composite(iF(validMask));
                thresholds  = thresh.Composite.BestThresholds;

                obj.App.updateCompositeTab(T, comp_v, thresholds, lbl_v);
                obj.App.updateAllocationTab(T, allocSeries, variantNames, lbl_v);
                obj.App.updatePerformanceTab(perfTable, equityCurves, T);

                % Tree tab
                if ~isempty(dtree)
                    treeText = evalc('view(dtree.Tree)');
                    obj.App.updateTreeTab(treeText);
                else
                    obj.App.updateTreeTab({'Decision tree not available (Stat+ML Toolbox required).'});
                end

                obj.App.selectTab('Performance');
                obj.App.setStatus('Strategy run complete. Review tabs.');

            catch ME
                obj.App.setStatus(['ERROR (Run): ' ME.message]);
                obj.logWarn('onRunStrategy failed: %s\n%s', ME.message, ME.getReport('extended'));
            end
        end

        % -------------------------------------------------------------- %
        function tt = fetchFredSp500(obj, startDate)
        % Stooq ^SPX fallback (FRED SP500 only starts 2016-01-04).
            tt = obj.DM.fetch_stooq('^SPX', startDate, "");
        end
    end
end
