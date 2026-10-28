function [mDBeta] = fDownsideBeta(mY, vX, iLength, iOffset, iMinNumIn)

arguments
    mY
    vX 
    iLength = 52
    iOffset = 0
    iMinNumIn = 30
end

% Determine dimensions
[iNumObs, iNumAssets] = size(mY);

% Initialize memory
mDBeta  = NaN(iNumObs, iNumAssets);

% Loop over time
for iIdxT = iLength:iNumObs-1
    % Get data
    vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);
    mYin         = mY(vIdxInSample,:);
    vXin         = vX(vIdxInSample);

    % Include observation only if market return is below average
    lIncludeObs  = vXin <= mean(vXin,'omitmissing');

    % Get number of nonmissing observations
    vNumNonMissing = sum(~isnan(mYin),1);

    % Find assets that have all observations nonmissing
    lAllAvail = vNumNonMissing == size(mYin,1);

    % Fast regression
    mBeta = vXin(lIncludeObs,:)\mYin(lIncludeObs,lAllAvail);
    mDBeta(iIdxT,lAllAvail) = mBeta;

    % Do not use regressions for assets that already have a measure
    % of downside beta
    vNumNonMissing(lAllAvail) = 0;

    % Check missing values
    vIdxValid = find(vNumNonMissing >= iMinNumIn);
    iNumAssetsTemp = length(vIdxValid);

    % Loop over available assets
    for iIdxA = 1:iNumAssetsTemp
        % Get asset
        iIdxTemp = vIdxValid(iIdxA);

        % Get data
        vYtemp          = mYin(:,iIdxTemp);
        vXtemp          = vXin;
        lIncludeObsTemp = lIncludeObs;

        % Remove missing
        lIsNaN = any(isnan([vYtemp, vXtemp]),2);
        vYtemp(lIsNaN)              = [];
        vXtemp(lIsNaN)              = [];
        lIncludeObsTemp(lIsNaN)     = [];

        % Regression to get coskewness
        vBeta = vXtemp(lIncludeObsTemp,:)\vYtemp(lIncludeObsTemp);
        mDBeta(iIdxT, iIdxA) = vBeta;
    end
end
end