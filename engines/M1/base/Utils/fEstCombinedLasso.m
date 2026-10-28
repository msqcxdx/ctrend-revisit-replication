function rModel = fEstCombinedLasso(vY, mX, mID, vW, rModel)
% Function for implementing the combined lasso method in Han et al. (2024)
%
% rModel:
%   .lEstAlpha:     Logical, specifies whether to estimate an intercept
%                   (true, default) or not (false)
%   .iMinNumObsReg: Scalar, integer, minimum number of non-missing
%                   observations for a cross-sectional regression (default
%                   = 10)
%   .lGammaOnly:    Logical, specifies whether to return only the gamma
%                   estimates (true) or gamma estimates and additional
%                   statistics (false, default)
%   .iNumLagsNW:    Scalar, integer, number of lags for Newey-West standard
%                   error correction (default = 12)

arguments
    vY
    mX
    mID
    vW
    rModel.lEstAlpha = true;
    rModel.dAlpha    = 0.5;
end

% Step 1:
% For each characteristic, estimate a month-(t − 1) cross-sectional univariate regression via WLS:
%
% Step 2:
% For each characteristic, compute a month-t univariate regression forecast:
%
% Step 3:
% Estimate a month-t cross-sectional Granger and Ramanathan (1984) multiple regression 
% via the weighted LASSO
%
% Step 4:
% For each characteristic, estimate a month-t cross-sectional univariate regression via WLS:

% Determine dimensions
iNumPanelObs                    = length(vY);
[iNumPanelObsX, iNumIndepVars]  = size(mX);
iNumPanelObsID                  = size(mID,1);
iNumPanelObsW                   = length(vW);
vUniqueTimeID                   = unique(mID(:,1));
iNumObs                         = length(vUniqueTimeID);
iNumResp                        = max(mID(:,2));

% Check dimensions
assert(iNumPanelObs == iNumPanelObsX, 'Number of panel observations must agree (vY, mX)');
assert(iNumPanelObs == iNumPanelObsID, 'Number of panel observations must agree (vY, mID)');
if ~isempty(vW)
    assert(iNumPanelObs == iNumPanelObsW, 'Number of panel observations must agree (vY, vW)');
    lValueWeightedLS = true;
else
    lValueWeightedLS = false;
end

% Initialize memory
iNumIndepVars   = iNumIndepVars;
mGamma          = NaN(iNumObs, iNumIndepVars);
vR2             = NaN(iNumObs, 1);

%% Step 1
% Get t-1 data (returns in t-1) and characteristics in (t-2)
iIdxTime        = vUniqueTimeID(end-1);

% Get data index
lIsSampleData   = mID(:,1) == iIdxTime;

% Get data
vYtemp          = vY(lIsSampleData);
mXtemp          = mX(lIsSampleData,:);
mIDtemp         = mID(lIsSampleData,:);
if lValueWeightedLS
    vWtemp      = vW(lIsSampleData);
end

% % Remove missing values
% lIsNaN = isnan(vYtemp) | any(isnan(mXtemp),2);
% vYtemp(lIsNaN) = [];
% mXtemp(lIsNaN,:) = [];
% if lValueWeightedLS
%     vWtemp(lIsNaN) = [];
% end
iNumObsStep1 = size(vYtemp,1);

% For each characteristic, estimate a month-(t − 1) cross-sectional univariate regression via WLS:
mGammaStep1 = NaN(iNumIndepVars, 2);
for iIdxI = 1:iNumIndepVars
    % Estimate cross-sectional regression
    rModelFM = fEstFamaMacBethPanel(vYtemp, mXtemp(:,iIdxI), mIDtemp, vWtemp, ...
        'lEstAlpha', rModel.lEstAlpha, 'lGammaOnly', true);

    % Save gamma
    mGammaStep1(iIdxI,:) = rModelFM.vGamma;
end

%% Step 2
% For each characteristic, compute a month-t univariate regression forecast
% Get t data (returns in t) and characteristics in (t-1)
iIdxTime        = vUniqueTimeID(end);

% Get data index
lIsSampleData   = mID(:,1) == iIdxTime;

% Get data
vYtemp          = vY(lIsSampleData);
mXtemp          = mX(lIsSampleData,:);
mIDtemp         = mID(lIsSampleData,:);
if lValueWeightedLS
    vWtemp      = vW(lIsSampleData);
end
iNumObsStep2 = size(vYtemp,1);

mYhatStep2 = NaN(iNumObsStep2, iNumIndepVars);
for iIdxI = 1:iNumIndepVars
    % Add constant to the independent variable
    mXtrain = [ones(iNumObsStep2, rModel.lEstAlpha), mXtemp(:,iIdxI)];

    % Get prediction
    mYhatStep2(:,iIdxI) = mXtrain * mGammaStep1(iIdxI,:)';
end

% Check availability of characteristic (this is true if available at t and
% t-1)
lAvail = ~all(isnan(mYhatStep2),1);

%% Step 3
% Estimate lasso
rLasso = fEstRegPanelRegression(vYtemp, mYhatStep2(:,lAvail), mIDtemp, vWtemp, "dAlpha",rModel.dAlpha);

% Drop the alpha
if rLasso.lEstAlpha
    rLasso.vBeta(1) = [];
end

% Get coefficients
vBeta           = zeros(1, iNumIndepVars);
vBeta(lAvail)   = rLasso.vBeta;

% Find coefficients > 0
lKeepPred = vBeta > 0;

%% Step 4
% For each characteristic, estimate a month-t cross-sectional univariate regression via WLS:
mGammaStep4 = NaN(iNumIndepVars, 2);
for iIdxI = 1:iNumIndepVars
    if ~lAvail(iIdxI)
        continue
    end
    
    % Estimate cross-sectional regression
    rModelFM = fEstFamaMacBethPanel(vYtemp, mXtemp(:,iIdxI), mIDtemp, vWtemp, ...
        'lEstAlpha', rModel.lEstAlpha, 'lGammaOnly', true);

    % Save gamma
    mGammaStep4(iIdxI,:) = rModelFM.vGamma;
end

% Save model
rModel.mGamma           = mGammaStep4;
rModel.lKeepPred        = lKeepPred;
end
