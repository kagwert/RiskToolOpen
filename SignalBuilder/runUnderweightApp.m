%% runUnderweightApp.m
% Entry point for the Underweight Strategy GUI.
%
%   Adds required paths, creates the UnderweightController, and opens the
%   interactive uifigure application.
%
% USAGE
% -----
%   Run from the SignalBuilder root directory:
%       cd('C:\CIO\ClaudeCode\SignalBuilder')
%       run('Underweight\runUnderweightApp.m')
%
%   Or run directly from the Underweight folder — the script auto-detects
%   its own location and adds the parent (SignalBuilder root) to the path.
%
% INTERACTION
% -----------
%   1. Adjust parameters in the left panel if desired.
%   2. Click "Build Signals"   → fetches data, populates Signals tab.
%   3. Click "Optimize Params" → grid-searches signal construction params,
%                                updates spinners with optimal values.
%   4. Click "Run Strategy"    → runs threshold + decision tree approaches,
%                                populates all result tabs.

scriptDir = fileparts(mfilename('fullpath'));
rootDir   = fileparts(scriptDir);   % SignalBuilder root

addpath(rootDir);
addpath(scriptDir);

ctrl = Controller.UnderweightController();
ctrl.init();
ctrl.run();
