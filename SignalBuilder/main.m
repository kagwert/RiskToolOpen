%% main.m  —  Quantitative Strategy Designer  (entry point)
%
%   Launches the full MVC pipeline for a single ticker using the default
%   SMA-20/50 crossover strategy.
%
%   Quick start (synthetic data, no CSV needed):
%       run main
%
%   With real data:
%       sc = Controller.StrategyController('SPY', 'data/SPY_daily.csv');
%       sc.init();
%       sc.run();
%
%   See CLAUDE.md for full architecture documentation.

%% 0. Add the project root to MATLAB path (idempotent)
projectRoot = fileparts(mfilename('fullpath'));
if ~contains(path, projectRoot)
    addpath(projectRoot);
end

%% 1. Create and run the Strategy Controller
%   Pass an empty file path to use built-in synthetic data for the demo.
ticker = 'DEMO';

fprintf('\n=== Quantitative Strategy Designer ===\n');
fprintf('Ticker : %s\n', ticker);
fprintf('Mode   : synthetic (no CSV required)\n\n');

sc = Controller.StrategyController(ticker);
sc.init();
sc.run();

fprintf('\nDone.  Close the chart windows or call sc.shutdown() when finished.\n');
