function [mCoskew, mIskew, mSkew] = fCoskewness(mY, vX, iLength, iOffset, iMinNumIn)

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
mSkew   = NaN(iNumObs, iNumAssets);
mIskew  = NaN(iNumObs, iNumAssets);
mCoskew = NaN(iNumObs, iNumAssets);

% Loop over time
for iIdxT = iLength:iNumObs-1
    % Get data
    vIdxInSample = (iIdxT-iLength+1):(iIdxT-iOffset);
    mYin         = mY(vIdxInSample,:);
    vXin         = vX(vIdxInSample);
    mXin         = [vXin, vXin.^2];

    % Get number of nonmissing observations
    vNumNonMissing = sum(~isnan(mYin),1);

    % Find assets that have all observations nonmissing
    lAllAvail = vNumNonMissing == size(mYin,1);

    % Fast regression
    mBeta = mXin\mYin(:,lAllAvail);
    mCoskew(iIdxT,lAllAvail) = mBeta(2,:);

    % Get idiosyncratic skewness
    vBeta = vXin\mYin(:,lAllAvail);
    mIskew(iIdxT,lAllAvail) = skewness( mYin(:,lAllAvail) - vBeta .* vXin);

    % Do not use regressions for assets that already have a measure
    % of skewness
    vNumNonMissing(lAllAvail) = 0;

    % Check missing values
    vIdxValid = find(vNumNonMissing >= iMinNumIn);
    iNumAssetsTemp = length(vIdxValid);

    % Loop over available assets
    for iIdxA = 1:iNumAssetsTemp
        % Get asset
        iIdxTemp = vIdxValid(iIdxA);

        % Get data
        vYtemp  = mYin(:,iIdxTemp);
        vXtemp  = vXin;
        mXtemp  = mXin;

        % Remove missing
        lIsNaN = any(isnan([vYtemp, mXtemp]),2);
        vYtemp(lIsNaN)      = [];
        vXtemp(lIsNaN)      = [];
        mXtemp(lIsNaN,:)    = [];

        % Regression to get coskewness
        vBeta = mXtemp\vYtemp;
        mCoskew(iIdxT, iIdxA) = vBeta(2);

        % Regression to get idiosyncratic skewness
        dBeta = vXtemp\vYtemp;
        mIskew(iIdxT, iIdxA) = skewness(vYtemp - dBeta * vXtemp);
    end

    % Calculate skewness
    vSkew = skewness(mYin,[],1);
    vSkew(sum(~isnan(mYin),1) < iMinNumIn) = NaN;
    mSkew(iIdxT,:) = vSkew;
end
end