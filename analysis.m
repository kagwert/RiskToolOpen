%% STEP 1: Load Data & Signal Components
% -------------------------------------------------------------------------
% Note: Swap this synthetic generation block with your actual data import.
% Example: data = readtimetable('my_strategy_data.csv');
% -------------------------------------------------------------------------
rng(42); % For reproducibility
num_days = 2000;
dates = datetime(2018, 1, 1) + caldays(1:num_days)';

% Simulate Equity Index (with some V-shape drops and prolonged drawdowns)
daily_returns = 0.0005 + 0.01 * randn(num_days, 1);
equity_index = 100 * cumprod(1 + daily_returns);

% Simulate Signals (Bounded -1 to 1)
overall_signal = smoothdata(randn(num_days, 1), 'gaussian', 50);
overall_signal = max(min(overall_signal / max(abs(overall_signal)), 1), -1);

macro_signal = smoothdata(overall_signal + 0.5*randn(num_days, 1), 'gaussian', 100);
macro_signal = max(min(macro_signal / max(abs(macro_signal)), 1), -1);

market_signal = smoothdata(overall_signal + 0.5*randn(num_days, 1), 'gaussian', 20);

% Simulate Volatility Term Structure Proxy (e.g., VIX/VIX3M ratio)
% > 1.05 implies panic/backwardation (V-shape bottom)
vol_term_structure = 0.95 + 0.05 * randn(num_days, 1);
vol_term_structure(daily_returns < -0.02) = 1.1; % Spike vol on bad days

data = timetable(dates, equity_index, daily_returns, overall_signal, ...
    macro_signal, market_signal, vol_term_structure);

%% STEP 2: Identify Subzero Regimes & Calculate Performance Table
% -------------------------------------------------------------------------
% Find continuous blocks where overall_signal < 0
is_subzero = data.overall_signal < 0;

% Identify start and end indices of these periods
starts = find(diff([0; is_subzero]) == 1);
ends = find(diff([is_subzero; 0]) == -1);

% Initialize arrays to store metrics
num_events = length(starts);
Duration = zeros(num_events, 1);
Realized_Return = zeros(num_events, 1);
Volatility = zeros(num_events, 1);
Max_Drawdown = zeros(num_events, 1);

for i = 1:num_events
    idx_start = starts(i);
    idx_end = ends(i);
    
    % Slice the data for the current regime
    period_returns = data.daily_returns(idx_start:idx_end);
    period_prices = data.equity_index(idx_start:idx_end);
    
    % Calculate Metrics
    Duration(i) = idx_end - idx_start + 1;
    Realized_Return(i) = (period_prices(end) / period_prices(1)) - 1;
    Volatility(i) = std(period_returns) * sqrt(252); % Annualized
    
    % Calculate Max Drawdown for the period (Base MATLAB approach)
    cum_max = cummax(period_prices);
    drawdowns = (period_prices - cum_max) ./ cum_max;
    Max_Drawdown(i) = min(drawdowns);
end

% Construct and display the table
Regime_Start = data.dates(starts);
Regime_End = data.dates(ends);
Regime_Analysis = table(Regime_Start, Regime_End, Duration, ...
    Realized_Return, Volatility, Max_Drawdown);

disp('--- Subzero Signal Regime Analysis ---');
disp(Regime_Analysis);

%% STEP 3: The Robust Decision Tree (Two-Tranche Execution)
% -------------------------------------------------------------------------
% Base weights: 1.0 = Fully Invested, 0.5 = Half Underweight, 0.0 = Full Underweight
W_base = 1.0;
W_half_uw = 0.5;
W_full_uw = 0.0;

% Parameters (To be calibrated later)
tau_vol = 1.05; % Volatility panic threshold
tau_z = -1.0;   % Macro deterioration Z-score threshold

% Calculate Z-score of Macro Signal (rolling 60-day window)
% Using movmean and movstd for base MATLAB compatibility
rolling_mean = movmean(data.macro_signal, [59 0]);
rolling_std = movstd(data.macro_signal, [59 0]);
% Avoid division by zero
rolling_std(rolling_std == 0) = 1e-6; 
macro_z_score = (data.macro_signal - rolling_mean) ./ rolling_std;

% Node 0: Base Trigger (Is overall signal negative?)
node0_trigger = data.overall_signal < 0;

% Node 1: Volatility Capitulation Filter (Is the market orderly?)
% We want vol term structure to be <= tau_vol (Not in backwardation panic)
node1_pass = data.vol_term_structure <= tau_vol;

% Node 2: Macro Divergence Filter (Is macro confirming the drop?)
% Macro signal must be deteriorating (change < 0) AND severely weak (Z < tau)
macro_change = [0; diff(data.macro_signal)];
node2_pass = (macro_change < 0) & (macro_z_score < tau_z);

% Execute Logic Tree to build the final weight vector
Final_Weights = ones(num_days, 1) * W_base;

% Apply Tranche 1 (Half Underweight) where Node 0 is true
Final_Weights(node0_trigger) = W_half_uw;

% Apply Tranche 2 (Full Underweight) ONLY where Node 0, Node 1, and Node 2 are true
trigger_full_uw = node0_trigger & node1_pass & node2_pass;
Final_Weights(trigger_full_uw) = W_full_uw;

% Add weights to timetable for review
data.Portfolio_Weight = Final_Weights;

% Calculate strategy returns
strategy_returns = [0; data.Portfolio_Weight(1:end-1)] .* data.daily_returns;
data.Strategy_Index = 100 * cumprod(1 + strategy_returns);

% Plot the results to visually verify the decision tree
figure;
ax1 = subplot(2,1,1);
plot(data.dates, data.equity_index, 'k', 'DisplayName', 'Equity Index');
hold on;
plot(data.dates, data.Strategy_Index, 'b', 'LineWidth', 1.5, 'DisplayName', 'Strategy (Two-Tranche)');
title('Equity Index vs. Two-Tranche Strategy');
legend('Location', 'best');
grid on;

ax2 = subplot(2,1,2);
area(data.dates, data.Portfolio_Weight, 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none');
title('Strategy Exposure (1.0 = Invested, 0.5 = Half UW, 0.0 = Full UW)');
ylim([-0.1 1.1]);
grid on;
linkaxes([ax1, ax2], 'x');