% Script for implementing the mean-variance frontier expansion test
%
% Requires that b05CreateCTREND and b06Table3_UnivariatePortfolioSorts 
% were executed
%
% This script produces:
%   Table 7:    Frontier Expansion Test

% Clear console
clear; clc; close all;

% Set paths
sOldPath    = path;
sDataPath   = './DATA/';
addpath('./Utils/');
addpath('./LatexTables/');

% Define null models
cFactMdls(1,1) = {'CTREND'};                cFactMdls{1,2} = {'CTREND'};
cFactMdls(2,1) = {'CMKT + CTREND'};         cFactMdls{2,2} = {'CMKT', 'CTREND'};
cFactMdls(3,1) = {'CMKT + CSMB + CTREND'};  cFactMdls{3,2} = {'CMKT', 'CSMB', 'CTREND'};
cFactMdls(4,1) = {'LTW'};                   cFactMdls{4,2} = {'CMKT', 'CSMB', 'CMOM'};
iNumNullModels = size(cFactMdls,1);

% Load trend factor
sFilename = sprintf('./Results/CTREND/CTREND_Base.mat');
rCTREND   = load(sFilename,'cResults','vDates','vAssetID');
vCTREND   = rCTREND.cResults.VW.mPortRet(end,:)';
vDates    = rCTREND.vDates;

% Load LTW factors
load('./DATA/LTW_3factor.mat');
lIsSample   = vDatesLiu >= vDates(1) & vDatesLiu <= vDates(end);
mLTW        = mLTW(lIsSample,:);

% Make factors to table
mFactors = [mLTW, vCTREND]; mFactors(any(isnan(mFactors),2),:) = NaN;
tFactors = array2table(mFactors,...
    'VariableNames',{'CMKT', 'CSMB', 'CMOM', 'CTREND'});
iNumFact = size(tFactors,2);

% Initialize memory
mGenAlphas      = NaN(iNumFact, iNumNullModels);
mGenAlphasT     = NaN(iNumFact, iNumNullModels);

% Loop over null models
for iIdxN = 1:iNumNullModels
    % Get factors
    cNullFact = cFactMdls{iIdxN,2};
    mFactNull = table2array(tFactors(:,cNullFact));

    % Loop over factors
    for iIdxA = 1:iNumFact
        % Get factor
        sAltFact = tFactors.Properties.VariableNames{iIdxA};

        % Skip if factor already included in null factor set
        if ismember(sAltFact, cNullFact)
            continue
        end
        vFactAlt = tFactors.(sAltFact);

        % Perform mean-variance frontier expansion test
        rStats = fMeanVarianceSpanningSoebhag(mFactNull, vFactAlt,...
            "iNumIn", 52, 'dTargetVol',0.1);

        % Save generalized alphas
        mGenAlphas(iIdxA, iIdxN)  = rStats.vBeta(1);
        mGenAlphasT(iIdxA,iIdxN)  = rStats.vBetaT_hac(1);
    end
end

% Create table
cTable7 = fAddStatistics( fMatrix2Cell(mGenAlphas*100,2),...
    fMatrix2Cell(mGenAlphasT,2),...
    abs(round(mGenAlphasT,2))>=1.96);
cTable7(isnan(mGenAlphas)) = {''};
cTable7 = [[{''}, cFactMdls(:,1)']; [tFactors.Properties.VariableNames(:), cTable7]];
rInput.table = cTable7;
rInput.tableCaption = 'Frontier Expansion Test';
fCreateLatexTable(rInput);

% Restore path
path(sOldPath);



