% Create paper research-design choices.  Baseline-only runs keep the single
% published baseline row; full runs keep the complete Table 6 grid.

% Clear console
clear; clc; close all;

sPipelineScope = lower(strtrim(getenv('PIPELINE_SCOPE')));
if isempty(sPipelineScope)
    sPipelineScope = 'full';
end
assert(ismember(sPipelineScope,{'full','baseline','table6'}), ...
    'PIPELINE_SCOPE must be full, baseline, or table6');
lFullScope = ~strcmp(sPipelineScope,'baseline');

%% Create data settings
% === Threshold for winsorization or truncation
if lFullScope
    vThreshold          = [0.005, 0.01]';
else
    vThreshold          = 0.005;
end

% === Winsorization or truncation
if lFullScope
    cOutlierTreatment   = {'trunc'; 'win'};
else
    cOutlierTreatment   = {'trunc'};
end

% Create settings
tDataCombos                   = combinations(vThreshold, cOutlierTreatment);
iNumDataCombos                = size(tDataCombos,1);
tDataCombos.data_setting      = (1:iNumDataCombos)';

%% Other settings that are design choices. These include various data 
%% filters and settings relevant for the estimation of the CTREND factor
% === Exclude stable coins
if lFullScope
    vExclStable = [false, true];
else
    vExclStable = true;
end

% === Minimum market capitalization
if lFullScope
    vMinMCAP    = [0, 1e6, 2e6];
else
    vMinMCAP    = 1e6;
end

% === Minimum price
if lFullScope
    vMinPRC     = [0, 1];
else
    vMinPRC     = 0;
end

% === Return lag/implementation lag
if lFullScope
    vRetLead    = [0, 1];
else
    vRetLead    = 0;
end

% === Estimation window
if lFullScope
    vRoll       = [true; false];
else
    vRoll       = true;
end

% === Number of in-sample periods
if lFullScope
    vNumIn      = [26, 52, 78, 104];
else
    vNumIn      = 52;
end

% === Value-weighted or equal-weighted factor portfolios.  The predictive
% regressions themselves always use the paper's market-cap WLS objective;
% this design switch changes only factor portfolio accounting.
if lFullScope
    vUseValueWts = [true; false];
else
    vUseValueWts = true;
end

% === Use volume indicators
if lFullScope
    vUseVolume  = [true; false];
else
    vUseVolume  = true;
end

% Create factor settings
tCombos         = combinations(vExclStable, vMinMCAP, vMinPRC, vRetLead,...
    vRoll, vNumIn, vUseValueWts, vUseVolume);

% Merge data settings and filter choices
[ii,jj] = meshgrid(1:height(tDataCombos),1:height(tCombos));
tCombos = [tDataCombos(ii,:) tCombos(jj,:)];
tCombos.setting = (1:height(tCombos))';
iNumCombos = size(tCombos,1);

% Save an explicit mode marker so downstream provenance cannot be mistaken
% for a different run scope.
if lFullScope
    sPipelineMode = 'full';
else
    sPipelineMode = 'baseline-only';
end
sOutputFile = 'DesignChoices.mat';
sTemporary = [tempname(pwd),'.mat'];
rCleanup = onCleanup(@() iDeleteIfExists(sTemporary));
save(sTemporary,'tDataCombos','tCombos','sPipelineMode');
[lMoved,sMoveMessage] = movefile(sTemporary,sOutputFile,'f');
assert(lMoved,'Could not atomically publish %s: %s', ...
    sOutputFile,sMoveMessage);
clear rCleanup

function iDeleteIfExists(sFilename)
if exist(sFilename,'file') == 2
    delete(sFilename);
end
end
