%% MAIN SCRIPT: Two-Tranche Decision Tree Optimization
clear; clc; close all;

%% STEP 1: Load Real Data & Synchronize
% -------------------------------------------------------------------------
filename = 'Signals.xlsx';
disp('Loading data from Excel...');

% 1. Detect import options
opts_signals = detectImportOptions(filename, 'Sheet', 'Signals');
opts_markets = detectImportOptions(filename, 'Sheet', 'Markets');

% 2. CRITICAL FIX: Force all columns (except the first Date column) to be numeric
% This automatically converts Bloomberg '#N/A N/A' strings into NaNs!
opts_signals = setvartype(opts_signals, opts_signals.VariableNames(2:end), 'double');
opts_markets = setvartype(opts_markets, opts_markets.VariableNames(2:end), 'double');

% 3. Read both tabs
signals_data = readtimetable(filename, opts_signals);
markets_data = readtimetable(filename, opts_markets);

% 4. Synchronize data
data = synchronize(markets_data, signals_data, 'intersection');

% 5. Define the date array
data.dates = data.Properties.RowTimes; 

% -------------------------------------------------------------------------
% ACTION REQUIRED: Map your exact Excel column headers below
% -------------------------------------------------------------------------
try
    data.equity_index       = data.SPXIndex;            % From your screenshot
    
    % Update the following three to match your 'Signals' tab headers
    data.overall_signal     = data.Overall_Signal;      
    data.macro_signal       = data.Macro_Signal;        
    data.vol_term_structure = data.VIX_VIX3M_Ratio;     
    
    % Calculate daily returns dynamically
    data.daily_returns = [0; diff(data.equity_index) ./ data.equity_index(1:end-1)];
catch ME
    disp(ME.message);
    error('Column mapping failed. Please check your exact Excel headers.');
end

% Handle missing data (Forward fill to prevent look-ahead bias)
if any(ismissing(data))
    data = fillmissing(data, 'previous');
end

disp('Step 1 Complete: Data loaded, cleaned, and synchronized.');

%% STEP 2: Identify Subzero Regimes & Baseline Analysis
% -------------------------------------------------------------------------
disp('Analyzing baseline subzero regimes...');
is_subzero = data.overall_signal < 0;
starts = find(diff([0; is_subzero]) == 1);
ends = find(diff([is_subzero; 0]) == -1);

num_events = length(starts);
Duration = zeros(num_events, 1);
Realized_Return = zeros(num_events, 1);
Max_Drawdown = zeros(num_events, 1);

for i = 1:num_events
    idx_start = starts(i);
    idx_end = ends(i);
    
    period_prices = data.equity_index(idx_start:idx_end);
    Duration(i) = idx_end - idx_start + 1;
    Realized_Return(i) = (period_prices(end) / period_prices(1)) - 1;
    
    cum_max = cummax(period_prices);
    drawdowns = (period_prices - cum_max) ./ cum_max;
    Max_Drawdown(i) = min(drawdowns);
end

Regime_Start = data.dates(starts);
Regime_End = data.dates(ends);
Regime_Analysis = table(Regime_Start, Regime_End, Duration, Realized_Return, Max_Drawdown);
disp(sortrows(Regime_Analysis, 'Max_Drawdown', 'ascend')); % Shows worst drawdowns first

%% STEP 3 & 4: Optimize Decision Tree Thresholds
% -------------------------------------------------------------------------
disp('Optimizing decision tree thresholds...');

% Define initial guess for [tau_vol, tau_z]
% tau_vol: ~1.05 (backwardation threshold)
% tau_z: ~ -1.0 (macro deterioration threshold)
initial_params = [1.05, -1.0];

% Define bounds to prevent absurd curve-fitting
% Vol ratio bounded between 0.9 and 1.3
% Z-score bounded between -3.0 and 0.0
lb = [0.9, -3.0];
ub = [1.3, 0.0];

% Objective function wrapper (minimizes negative Calmar ratio)
obj_func = @(params) strategy_objective(params, data);

% Run optimization using patternsearch (requires Global Optimization Toolbox)
% If you don't have this toolbox, you can replace patternsearch with fminsearch
options = optimoptions('patternsearch', 'Display', 'iter', 'UseParallel', false);
[opt_params, ~] = patternsearch(obj_func, initial_params, [], [], [], [], lb, ub, [], options);

opt_tau_vol = opt_params(1);
opt_tau_z = opt_params(2);

fprintf('\nOptimization Complete.\n');
fprintf('Optimal Volatility Panic Threshold (tau_vol): %.3f\n', opt_tau_vol);
fprintf('Optimal Macro Deterioration Threshold (tau_z): %.3f\n', opt_tau_z);

%% STEP 5: Apply Optimized Parameters & Plot Results
% -------------------------------------------------------------------------
% Recalculate weights with optimal parameters
[~, final_weights, strategy_returns] = strategy_objective(opt_params, data);

data.Portfolio_Weight = final_weights;
data.Strategy_Index = 100 * cumprod(1 + strategy_returns);
benchmark_index = 100 * cumprod(1 + data.daily_returns);

% Plotting
figure('Name', 'Optimized Two-Tranche Strategy', 'Position', [100, 100, 1000, 600]);

ax1 = subplot(3,1,[1 2]);
plot(data.dates, benchmark_index, 'k', 'DisplayName', 'Buy & Hold Equity');
hold on;
plot(data.dates, data.Strategy_Index, 'b', 'LineWidth', 1.5, 'DisplayName', 'Optimized Strategy');
title('Strategy Performance vs. Benchmark');
ylabel('Cumulative Return');
legend('Location', 'NorthWest');
grid on;

ax2 = subplot(3,1,3);
area(data.dates, data.Portfolio_Weight, 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none');
title('Portfolio Exposure (1.0 = Fully Invested, 0.0 = Full Underweight)');
ylim([-0.1 1.1]);
ylabel('Weight');
grid on;
linkaxes([ax1, ax2], 'x');


%% --- HELPER FUNCTION: STRATEGY OBJECTIVE ---
function [neg_calmar, weights, strat_rets] = strategy_objective(params, data)
    % Unpack parameters
    tau_vol = params(1);
    tau_z = params(2);
    
    % Constants
    W_base = 1.0;
    W_half_uw = 0.5;
    W_full_uw = 0.0;
    
    % 1. Calculate Macro Z-score (rolling 60 days)
    roll_mean = movmean(data.macro_signal, [59 0]);
    roll_std = movstd(data.macro_signal, [59 0]);
    roll_std(roll_std == 0) = 1e-6; 
    macro_z_score = (data.macro_signal - roll_mean) ./ roll_std;
    macro_change = [0; diff(data.macro_signal)];
    
    % 2. Evaluate Nodes
    node0_trigger = data.overall_signal < 0;
    node1_pass = data.vol_term_structure <= tau_vol;
    node2_pass = (macro_change < 0) & (macro_z_score < tau_z);
    
    % 3. Build Weight Vector
    weights = ones(height(data), 1) * W_base;
    weights(node0_trigger) = W_half_uw; % Tranche 1
    
    trigger_full_uw = node0_trigger & node1_pass & node2_pass;
    weights(trigger_full_uw) = W_full_uw; % Tranche 2
    
    % 4. Calculate Performance
    % Shift weights by 1 day to prevent look-ahead bias (execute at next open/close)
    exec_weights = [1; weights(1:end-1)]; 
    strat_rets = exec_weights .* data.daily_returns;
    
    % 5. Calculate Calmar Ratio for Optimization
    cum_ret = cumprod(1 + strat_rets);
    ann_ret = (cum_ret(end)^(252/height(data))) - 1;
    
    cum_max = cummax(cum_ret);
    drawdowns = (cum_ret - cum_max) ./ cum_max;
    max_dd = abs(min(drawdowns));
    
    % Avoid division by zero
    if max_dd == 0
        max_dd = 1e-6; 
    end
    
    calmar = ann_ret / max_dd;
    
    % We return negative calmar because MATLAB optimizers minimize the objective function
    neg_calmar = -calmar; 
end