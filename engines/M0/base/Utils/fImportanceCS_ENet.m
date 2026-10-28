function vImportance = fImportanceCS_ENet(vY, mX, mID, mBeta, mSelected)
% Function for calculating the variable importance using the
% cross-sectional combined elastic net
%
% Input:
%   vY:             (T * N) x 1 vector of the response variable
%   mX:             (T * N) x L matrix of independent variables
%                   T: number of time-series observations
%                   N: number of assets
%                   L: number of independent variables
%   mBeta:          T x L x 2 matrix of estimated beta coefficients
%                   T: number of time-series observations
%                   L: number of independent variables
%   mSelected       T x L matrix, indicating whether a prediction was
%                   selected by the elastic net or not
%
% Output:
%   vImportance:    L x 1 vector of importance scores

% Determine dimensions
[iNumPanelObs, iNumIndepVars] = size(mX);
vUniqueTime     = unique(mID(:,1));
vUniqueAsset    = unique(mID(:,2));
iNumObs         = length(vUniqueTime);
iNumAssets      = length(vUniqueAsset);

% Find first valid estimate for which any regression coefficient is nonmissing
iIdxFirst   = find(any(~isnan(mBeta),2),1,'first');

% 1. Step: Generate univariate forecasts using the actual observations for
% the variables
mYhat           = NaN(iNumObs, iNumAssets, iNumIndepVars);
for iIdxOOS = iIdxFirst:iNumObs
    % Get data
    lIsDataOut = mID(:,1) == iIdxOOS;

    % Get data 
    mXout       = mX(lIsDataOut, :);
    mIDout      = mID(lIsDataOut, :);
    vIdxAsset   = mIDout(:,2);

    % Determine dimension
    [iNumObsTemp, iNumIndepVars]    = size(mXout);

    % Get individual oos predictions
    mYhatTemp   = NaN(iNumObsTemp, iNumIndepVars);
    for iIdxI = 1:iNumIndepVars 
        mYhatTemp(:,iIdxI) = mBeta(iIdxOOS,iIdxI,1) + mXout(:,iIdxI) * mBeta(iIdxOOS,iIdxI,2);
    end

    % Keep only selected predictions
    lSelected               = logical(mSelected(iIdxOOS,:));
    mYhatTemp(:,~lSelected) = NaN; 

    % Save
    mYhat(iIdxOOS,vIdxAsset,:) = mYhatTemp;
end

% 2. Step: Generate univariate forecasts and replace the actual 
% observations with a constant for the predictor

% Initialize memory for the periodically variable importance measures
mImportance = NaN(iNumObs, iNumIndepVars);

% Loop over time
for iIdxOOS = iIdxFirst:iNumObs
    % Get index for extracting the out-of-sample data
    lIsOutOfSample   = mID(:,1) == vUniqueTime(iIdxOOS);

    % Get data
    mXin            = mX(lIsOutOfSample,:);                 % Predictors
    mYhatIn         = permute(mYhat(iIdxOOS,:,:),[2,3,1]);  % Actual estimates (remove time diomension)
    mIDout          = mID(lIsOutOfSample, :);
    vIdxAsset       = mIDout(:,2);
    iNumObsTemp     = size(mXin,1);
    lIsSelected     = logical(mSelected(iIdxOOS,:)); 
    
    % Loop over predictors
    for iIdxP = 1:iNumIndepVars
        % Copy predictor and estimated returns
        vXtemp      = mXin(:,iIdxP);                        % Predictor
        mYhatTemp   = mYhatIn(vIdxAsset,:);                 % Actual estimates

        % Skip if not selected
        if ~lIsSelected(iIdxP)
            mImportance(iIdxOOS,iIdxP) = 0;
            continue
        end

        % Get unique values of predictor
        vUniqueX        = unique(vXtemp(~isnan(vXtemp)));
        iNumUnique      = length(vUniqueX);

        % Now we obtain the prediction by replacing the actual observation
        % of the predictor with a constant. We do this for each unique value
        mYhatPerm = NaN(iNumObsTemp, iNumUnique);
        for iIdxI = 1:iNumUnique
            % Get oos predictions, which is equal for each asset
            dYhatConst = mBeta(iIdxOOS,iIdxP,1) + vUniqueX(iIdxI) * mBeta(iIdxOOS,iIdxP,2);

            % Replace actual prediction with constant prediction
            mYhatTemp(:,iIdxP) = dYhatConst;

            % Average over all predictions selected by elastic net
            mYhatPerm(:,iIdxI) = mean(mYhatTemp(:,lIsSelected),2,'omitmissing');
        end

        % Now mYhatPerm contains predictions (N x U, where U is the number
        % of unique values in the predictor variable) if the actual
        % observations are replaced with constant values. A large variation
        % indicates that the prediction strongly depends on that predictor,
        % i.e., it has high importance.
        
        % Calculate average prediction in the cross-section and then take
        % the standard deviation of the predictions (PDV)
        mImportance(iIdxOOS,iIdxP) = std(mean(mYhatPerm,1),[],2);
    end
end

% Calculate time-series average
vImportance = mean(mImportance, 1, 'omitmissing');
end
