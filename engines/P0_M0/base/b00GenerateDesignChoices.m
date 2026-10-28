% Script for creating all design choices
%
% Note that some design choices will be added later. This is because these
% choices do not need a full recalculation of the CTREND characteristic.
% Saves time

% Clear console
clear; clc; close all;

%% Create data settings
% === Threshold for winsorization or truncation
vThreshold              = [0.005, 0.01]';

% === Winsorization or truncation
cOutlierTreatment       = {'trunc'; 'win'};

% Create settings
tDataCombos                   = combinations(vThreshold, cOutlierTreatment);
iNumDataCombos                = size(tDataCombos,1);
tDataCombos.data_setting      = (1:iNumDataCombos)';

%% Other settings that are design choices. These include various data 
%% filters and settings relevant for the estimation of the CTREND factor
% === Exclude stable coins
vExclStable = [false, true];

% === Minimum market capitalization
vMinMCAP    = [0, 1e6, 2e6];

% === Minimum price
vMinPRC     = [0, 1];

% === Return lag/implementation lag
vRetLead    = [0, 1];

% === Estimation window
vRoll           = [true; false];

% === Number of in-sample periods
vNumIn          = [26, 52, 78, 104]; 

% === Value-weighted or equal-weighted estimation
vUseValueWts    = [true; false];

% === Use volume indicators
vUseVolume      = [true; false];

% Create factor settings
tCombos         = combinations(vExclStable, vMinMCAP, vMinPRC, vRetLead,...
    vRoll, vNumIn, vUseValueWts, vUseVolume);

% Merge data settings and filter choices
[ii,jj] = meshgrid(1:height(tDataCombos),1:height(tCombos));
tCombos = [tDataCombos(ii,:) tCombos(jj,:)];
tCombos.setting = (1:height(tCombos))';
iNumCombos = size(tCombos,1);

% Save
save('DesignChoices.mat', 'tDataCombos','tCombos');