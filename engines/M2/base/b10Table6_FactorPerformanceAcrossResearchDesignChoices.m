% Script for evaluating the Sharpe ratio of the CTREND and benchmark factors
% across all possible combinations of research designs.
%
% Requires that b09RunResearchDesigns was executed
%
% This script produces:
%   Figure 2:   Distribution of Sharpe Ratios under Alternative Research Designs
%   Table 6:    Factor Performance across Research Design Choices
%   Figure B1:  Distribution of Sharpe Ratios under Alternative Research Designs
%               (Value-Weighted Portfolios Only)
%   Table B6:   Factor Performance Depending on Research Design Choices 
%               without Equal-Weighting

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Load design choices
load('DesignChoices.mat','tCombos');

% Remove all combinations with equally weighted factors (Figure B1, Table B6)
lDropEW = false;
if lDropEW
    tCombos(~tCombos.vUseValueWts,:) = [];
end
iNumCombos      = size(tCombos,1);

% Load any combo to get some info
sFilename   = sprintf('./Results/CTREND/CTREND_Combo%i.mat', 1);
rInfo       = load(sFilename);
cTrendNames = rInfo.cTrendNames;
iNumMethods = length(cTrendNames);

% Initialize memory
mShp3        = NaN(iNumCombos, iNumMethods); % Sharpe ratios of tertile portfolios
mShp5        = NaN(iNumCombos, iNumMethods); % Sharpe ratios of quintile portfolios
mShp3_T      = NaN(iNumCombos, iNumMethods); % t-stats of Sharpe ratios of tertile portfolios
mShp5_T      = NaN(iNumCombos, iNumMethods); % t-stats of Sharpe ratios of quintile portfolios
mShpLTW      = NaN(iNumCombos, 2);           % Sharpe ratios of LTW factors
mShpLTW_T    = NaN(iNumCombos, 2);           % t-stats of Sharpe ratios of LTW factors

% Loop over combos to calculate the Sharpe ratios
for iIdxC = 1:iNumCombos
    % Print progress
    fprintf('Load combo %i of %i \n', iIdxC, iNumCombos);

    % Create filename for combination
    sFilename = sprintf('./Results/CTREND/CTREND_Combo%i.mat', tCombos.setting(iIdxC));

    % Load combination (tertile and quintile CTREND factors and LTW factors)
    try
        load(sFilename,'mTrend_3','mTrend_5','mLTW', ...
            'iFirstFormationForecast');
    catch
        warning('%s does not exist', sFilename);
        continue
    end

    % Match LTW to the scheduled CTREND forecast start.  The first realized
    % CTREND return may be missing for payoff reasons and therefore cannot
    % define this comparison boundary.
    assert(exist('iFirstFormationForecast','var') == 1 && ...
        isscalar(iFirstFormationForecast) && ...
        iFirstFormationForecast >= 1 && ...
        iFirstFormationForecast <= size(mTrend_5,1), ...
        'Research-design output lacks a valid formation forecast boundary');
    iIdxFirst = iFirstFormationForecast;
    mLTW(1:iIdxFirst-1,:) = NaN;
    clear iFirstFormationForecast

    % Calculate Sharpe ratio
    [mShp3(iIdxC,:), mShp3_T(iIdxC,:)]      = fSharpeRatio(mTrend_3,0,1,2);
    [mShp5(iIdxC,:), mShp5_T(iIdxC,:)]      = fSharpeRatio(mTrend_5,0,1,2);
    [mShpLTW(iIdxC,:), mShpLTW_T(iIdxC,:)]  = fSharpeRatio(mLTW,0,1,2);
end

% So far, the breakpoints for portfolio sorts have not been part of the
% tCombos table because both tertiles and quintiles were calculated (to
% save computation time). To evaluate the combinations, we now need to add
% them to tCombos

% Define breakpoints to consider
cBreakpoints    = {'tertile';'quintile'};
iNumBreakpoints = length(cBreakpoints);

% Repeat tCombos and add breakpoints 
tCombosAll              = repmat(tCombos,iNumBreakpoints,1); 
tCombosAll.cBreakpoints = repelem(cBreakpoints,iNumCombos,1);

% Adjust number of combinations, including choice of breakpoints
iNumCombosAll       = size(tCombosAll,1);
tCombosAll.setting  = (1:iNumCombosAll)'; % Update index of combination

% Merge the Sharpe ratios for different breakpoints
mShp        = [mShp3; mShp5]; 
mShpT       = [mShp3_T; mShp5_T];

% Note that we did not change the breakpoints of LTW factors. Since
% 'tertile' is the alternative setting compared to the baseline, we add
% missing values at the position where tertiles were used.
mShpLTW     = [NaN(iNumCombos,2); mShpLTW];      
mShpLTW_T   = [NaN(iNumCombos,2); mShpLTW_T]; 

% So far, we treated the design choice to use a validation sample during 
% the estimation and the choice to theta-weight the predictions as separate 
% models. Now we merge the combos with this design choice. This implies 
% that we need to insert missing values for all methods for which these 
% two choices are irrelevant. 

% Define methods
cMethods    = {'FM','CFM','C_ENET_SCS','POLS','CPOLS','C_ENET'};
iNumMethods = length(cMethods);

% Initialize memory
mShpAll     = NaN(iNumCombosAll * 4, iNumMethods);
mShpAll_T   = NaN(iNumCombosAll * 4, iNumMethods);

% Create combos for that
cWts        = {'equally weighted','$\theta$-weighted'};
cValSample  = {'no','yes'};
tCombosAdd  = combinations(cWts, cValSample);

% Merge combos
[ii,jj]     = meshgrid(1:height(tCombosAdd),1:height(tCombosAll));
tCombosAll  = [tCombosAdd(ii,:) tCombosAll(jj,:)];

% Adjust number of combinations, including validation sample and
% theta-weighting
tCombosAll.setting  = (1:height(tCombosAll))';
iNumCombos          = size(tCombosAll,1);

% Loop over methods
for iIdxM = 1:iNumMethods
    % Get method
    sMethodTemp = cMethods{iIdxM};

    switch sMethodTemp
        case {'FM','CFM','POLS','CPOLS','C_ENET'}
            % These models do not have the option of having a validation
            % sample or theta weights

            % Get Sharpe ratios
            iIdxTemp = find(strcmpi(cTrendNames,sMethodTemp));

            % Add missing values
            vShpTemp    = [mShp(:,iIdxTemp); NaN(iNumCombosAll*3,1)];
            vShpTempT   = [mShpT(:,iIdxTemp); NaN(iNumCombosAll*3,1)];

        case {'C_ENET_SCS'}
            % Find indices of models
            iIdxTemp        = find(strcmpi(cTrendNames,sMethodTemp));               % Method, equal, no validation
            iIdxTemp_T      = find(strcmpi(cTrendNames,[sMethodTemp,'_T']));        % Method, theta, no validation
            iIdxTemp_VAL    = find(strcmpi(cTrendNames,[sMethodTemp,'_VAL']));      % Method, equal, validation
            iIdxTemp_VAL_T  = find(strcmpi(cTrendNames,[sMethodTemp,'_VAL_T']));    % Method, theta, validation

            % Merge
            vShpTemp        = [mShp(:,iIdxTemp);mShp(:,iIdxTemp_VAL);mShp(:,iIdxTemp_T);mShp(:,iIdxTemp_VAL_T)];
            vShpTempT       = [mShpT(:,iIdxTemp);mShpT(:,iIdxTemp_VAL);mShpT(:,iIdxTemp_T);mShpT(:,iIdxTemp_VAL_T)];
    end
    % Save
    mShpAll(:,iIdxM)    = vShpTemp;
    mShpAll_T(:,iIdxM)  = vShpTempT;
end

% Add missing values to LTW combos
mShpLTW    = [mShpLTW; NaN(size(mShpLTW,1)*3,2)];
mShpLTW_T  = [mShpLTW_T; NaN(size(mShpLTW,1)*3,2)];

% Print total number of combos
fprintf('Total number of combinations: %i \n', sum(~isnan(mShpAll),'all'));

%% Find base setting in all combinations to extract Sharpe ratios
iIdxBaseSetting = find(tCombosAll.vThreshold == 0.005 & ...
    strcmpi(tCombosAll.cOutlierTreatment,'trunc') & ...
    tCombosAll.vExclStable & ...
    tCombosAll.vMinMCAP == 1e6 & ...
    tCombosAll.vMinPRC == 0 & ...
    tCombosAll.vRetLead == 0 & ...
    tCombosAll.vRoll == 1 & ...
    tCombosAll.vNumIn == 52 & ...
    tCombosAll.vUseValueWts & ...
    tCombosAll.vUseVolume & ...
    strcmpi(tCombosAll.cBreakpoints,'quintile') & ...
    strcmpi(tCombosAll.cWts,'equally weighted') & ...
    strcmpi(tCombosAll.cValSample,'no'));
dShpBaseCTREND = mShpAll(iIdxBaseSetting, strcmpi(cMethods,'C_ENET_SCS'));
dShpBaseCSMB   = mShpLTW(iIdxBaseSetting,1);
dShpBaseCMOM   = mShpLTW(iIdxBaseSetting,2);

%% Figure 2a: Density plot Sharpe ratio CTREND
h1 = figure(1);
fDensityPlot(mShpAll(:), 'FaceColor','black');
xline(dShpBaseCTREND,'--','','Color','black','LineWidth',1.5)
xlabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12)
ylabel('Density', 'Interpreter','latex','FontSize',12)

%% Figure 2b: Density plot Sharpe ratio CSMB
h2 = figure(2);
fDensityPlot(mShpLTW(:,1), 'FaceColor','black');
xline(dShpBaseCSMB,'--','','Color','black','LineWidth',1.5)
xlabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12)
ylabel('Density', 'Interpreter','latex','FontSize',12);

%% Figure 2c: Density plot Sharpe ratio CMOM
h3 = figure(3);
fDensityPlot(mShpLTW(:,2), 'FaceColor','black');
xline(dShpBaseCMOM,'--','','Color','black','LineWidth',1.5)
xlabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12)
ylabel('Density', 'Interpreter','latex','FontSize',12)

%% Figure 2d: Box Plot
% Change order
vOrder = [3,1,2,4:iNumMethods];

% Merge factor Sharpe ratios for plotting
mX = [mShpLTW, mShpAll(:,vOrder)];
h4 = figure(4);
boxplot(mX, 'Colors', [0.5, 0.5, 0.5;...
    0.5, 0.5, 0.5;...
    0,0,0; 0,0,0; 0,0,0; 0,0,0; 0,0,0; 0,0,0],...
    'Labels',...
    {'CSMB', 'CMOM', 'CS-C-ENet','FM', 'CFM','POLS', 'CPOLS', 'C-ENet'},...
    'Whisker',20,...
    'BoxStyle','outline');
box off
ax = gca;
ax.XColor = [0, 0, 0];
ylabel('Sharpe Ratio (Annualized)','Interpreter','latex','FontSize',12);

%% Create table 6 /B6
% Create a cleaner combination table
tCombosClean         = tCombosAll;
tCombosClean.setting = [];
iNumCombosClean      = height(tCombosClean);

% Rename datasets
cDatasets = cell(iNumCombosClean,1);
cDatasets(tCombosClean.data_setting == 1) = {'Truncation at 0.5\%'};
cDatasets(tCombosClean.data_setting == 2) = {'Winsorization at 0.5\%'};
cDatasets(tCombosClean.data_setting == 3) = {'Truncation at 1\%'};
cDatasets(tCombosClean.data_setting == 4) = {'Winsorization at 1\%'};
tCombosClean.data_setting = cDatasets;

% Move columns
tCombosClean = tCombosClean(:,{'data_setting',...
    'vExclStable','vMinMCAP','vMinPRC','vRoll','vNumIn','vRetLead','cBreakpoints',...
    'vUseValueWts','vUseVolume','cValSample','cWts'});

% Rename columns
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'data_setting')) = {'Outlier treatment'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vExclStable')) = {'Stablecoins'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vMinMCAP')) = {'MCAP filter'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vMinPRC')) = {'Price filter'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vRoll')) = {'Estimation window'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vNumIn')) = {'In-sample observations'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vRetLead')) = {'Implementation lag'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'cBreakpoints')) = {'Breakpoints'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vUseValueWts')) = {'Weighting'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'vUseVolume')) = {'Volume indicators'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'cValSample')) = {'Validation sample'};
tCombosClean.Properties.VariableNames(strcmpi(tCombosClean.Properties.VariableNames,'cWts')) = {'Forecast weight'};

% Rename design choices
    % Stablecoins
    cStablecoins = cell(iNumCombosClean,1);
    cStablecoins(tCombosClean.Stablecoins)  = {'exclude'};
    cStablecoins(~tCombosClean.Stablecoins) = {'include'};
    tCombosClean.Stablecoins = cStablecoins;

    % MCAP filter
    cMCAP = cell(iNumCombosClean,1);
    cMCAP(tCombosClean.("MCAP filter")==0)   = {'$\geq \$0 mio'};
    cMCAP(tCombosClean.("MCAP filter")==1e6) = {'$\geq \$1 mio'};
    cMCAP(tCombosClean.("MCAP filter")==2e6) = {'$\geq \$2 mio'};
    tCombosClean.("MCAP filter") = cMCAP;

    % Price filter
    cPriceFilter = cell(iNumCombosClean,1);
    cPriceFilter(tCombosClean.("Price filter")==0)   = {'$\geq \$0'};
    cPriceFilter(tCombosClean.("Price filter")==1)   = {'$\geq \$1'};
    tCombosClean.("Price filter") = cPriceFilter;

    % Type of estimation window
    cEstWindow = cell(iNumCombosClean,1);
    cEstWindow(tCombosClean.("Estimation window")==1) = {'rolling'};
    cEstWindow(tCombosClean.("Estimation window")==0) = {'expanding'};
    tCombosClean.("Estimation window") = cEstWindow;

    % Weighting
    cWeighting = cell(iNumCombosClean,1);
    cWeighting(tCombosClean.Weighting == 1) = {'value-weighted'};
    cWeighting(tCombosClean.Weighting == 0) = {'equally weighted'};
    tCombosClean.Weighting = cWeighting;

    % Volume indicators
    cUseVolume = cell(iNumCombosClean,1);
    cUseVolume(tCombosClean.("Volume indicators")==1) = {'include'};
    cUseVolume(tCombosClean.("Volume indicators")==0) = {'exclude'};
    tCombosClean.("Volume indicators") = cUseVolume;
    
% Create table 6 /B6
cTable6 = [[{'',''},cMethods,{'CSMB','CMOM'}];...
    fEvaluateResearchDesigns(tCombosClean, [mShpAll, mShpLTW])];% 
rInput.table = cTable6;
rInput.tableCaption = 'Factor Performance Across Research Design Choices';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);
