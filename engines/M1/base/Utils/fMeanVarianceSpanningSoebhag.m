function rResults = fMeanVarianceSpanningSoebhag(mY, mX, options)
% OOS mean-variance frontier expansion on fixed calendar windows.
%
% The paper specifies weights estimated from the previous 52 weeks and
% applied to the following week.  Missing weeks therefore remain calendar
% positions.  For a given null-plus-alternative test, listwise deletion is
% performed only inside the already selected calendar window; an older
% observation is never pulled in to replace a missing week.

arguments
    mY (:,:) {mustBeNumeric}
    mX (:,:) {mustBeNumeric}
    options.iNumIn (1,1) {mustBeInteger, mustBePositive} = 52
    options.lRoll (1,1) {mustBeNumericOrLogical} = true
    options.dTargetVol (1,1) {mustBeNumeric} = NaN
    options.iIdxFirstOut (1,1) {mustBeInteger, mustBePositive} = 1
    options.dMinRcond (1,1) {mustBeNumeric, mustBePositive} = 1e-12
end

[iNumObs, iNumFactY] = size(mY);
iNumFactX = size(mX,2);
assert(iNumObs == size(mX,1), ...
    'Number of time-series observations must agree');
assert(options.iNumIn < iNumObs, ...
    'The estimation window must leave at least one OOS week');

vTangPortY  = NaN(iNumObs, 1);
vTangPortX  = NaN(iNumObs, 1);
vTangPortXY = NaN(iNumObs, 1);
vNumInComplete = NaN(iNumObs, 1);

% Columns are null, alternative, and combined systems.  Code 1 denotes a
% date before the explicitly scheduled Table-7 OOS start.
cSystemNames = {'null','alternative','combined'};
mNumFactors = NaN(iNumObs,3);
mCovRank = NaN(iNumObs,3);
mCovRcond = NaN(iNumObs,3);
mFailureCode = repmat(uint8(1),iNumObs,3);
cFailureReason = repmat({"not_scheduled"},iNumObs,3);

iIdxLoopFirst = max(options.iNumIn + 1, options.iIdxFirstOut);
for iIdxOut = iIdxLoopFirst:iNumObs
    iIdxT = iIdxOut - 1;
    if logical(options.lRoll)
        % Exactly the preceding iNumIn calendar positions.
        vIdxInSample = (iIdxT-options.iNumIn+1):iIdxT;
    else
        vIdxInSample = 1:iIdxT;
    end

    mYin = mY(vIdxInSample,:);
    mXin = mX(vIdxInSample,:);
    mYout = mY(iIdxOut,:);
    mXout = mX(iIdxOut,:);

    % Listwise deletion is local to this already-fixed calendar window and
    % uses only the factors in this null-plus-alternative comparison.
    lCompleteIn = all(isfinite([mYin,mXin]),2);
    vNumInComplete(iIdxOut) = nnz(lCompleteIn);
    mYin = mYin(lCompleteIn,:);
    mXin = mXin(lCompleteIn,:);

    cIn = {mYin,mXin,[mYin,mXin]};
    cOut = {mYout,mXout,[mYout,mXout]};
    vReturn = NaN(1,3);
    % All three portfolio systems are ultimately compared on the same OOS
    % date.  Still calculate window N/rank/rcond when that current payoff is
    % missing, so the diagnostic distinguishes sample support from payoff
    % availability.
    lMatchedOOSMissing = any(~isfinite([mYout,mXout]),'all');
    for iIdxSystem = 1:3
        [mInUse,vOutUse,rIdentification] = iPrepareSystem( ...
            cIn{iIdxSystem},cOut{iIdxSystem},options.dMinRcond);
        mNumFactors(iIdxOut,iIdxSystem) = ...
            rIdentification.iNumFactors;
        mCovRank(iIdxOut,iIdxSystem) = ...
            rIdentification.iCovRank;
        mCovRcond(iIdxOut,iIdxSystem) = ...
            rIdentification.dCovRcond;
        mFailureCode(iIdxOut,iIdxSystem) = ...
            rIdentification.iFailureCode;
        cFailureReason{iIdxOut,iIdxSystem} = ...
            rIdentification.sFailureReason;
        if ~rIdentification.lIdentified
            continue
        end
        if lMatchedOOSMissing
            mFailureCode(iIdxOut,iIdxSystem) = uint8(2);
            cFailureReason{iIdxOut,iIdxSystem} = ...
                'oos_return_missing';
            continue
        end

        vReturn(iIdxSystem) = fEstEvalTangPort( ...
            mInUse,vOutUse,options.dTargetVol);
        if ~isfinite(vReturn(iIdxSystem))
            mFailureCode(iIdxOut,iIdxSystem) = uint8(8);
            cFailureReason{iIdxOut,iIdxSystem} = ...
                'invalid_tangency_variance_or_scale';
        end
    end

    vTangPortY(iIdxOut) = vReturn(1);
    vTangPortX(iIdxOut) = vReturn(2);
    vTangPortXY(iIdxOut) = vReturn(3);
end

[rResults.dShp_Y, rResults.dShpT_Y] = ...
    fSharpeRatio(vTangPortY, 0, 1, 0);
[rResults.dShp_X, rResults.dShpT_X] = ...
    fSharpeRatio(vTangPortX, 0, 1, 0);
[rResults.dShp_XY, rResults.dShpT_XY] = ...
    fSharpeRatio(vTangPortXY, 0, 1, 0);

[rResults.vBeta, rResults.vBetaT, rResults.vBetaT_hac, ...
    rResults.vBetaP, rResults.vBetaP_hac, rRegressionY] = ...
    iSafeHACRegression(vTangPortXY, vTangPortY);
[rResults.vTheta, rResults.vThetaT, rResults.vThetaT_hac, ...
    rResults.vThetaP, rResults.vThetaP_hac, rRegressionX] = ...
    iSafeHACRegression(vTangPortXY, vTangPortX);

% Calendar-indexed estimates and complete identification diagnostics.
rResults.vTangPortY = vTangPortY;
rResults.vTangPortX = vTangPortX;
rResults.vTangPortXY = vTangPortXY;
rResults.vNumInComplete = vNumInComplete;
rResults.iNumFactY = iNumFactY;
rResults.iNumFactX = iNumFactX;
rResults.iIdxFirstOut = iIdxLoopFirst;
rResults.rRegressionY = rRegressionY;
rResults.rRegressionX = rRegressionX;
rResults.rWindowDiagnostics = struct( ...
    'cSystemNames',{cSystemNames}, ...
    'mNumFactors',mNumFactors, ...
    'mCovRank',mCovRank, ...
    'mCovRcond',mCovRcond, ...
    'mFailureCode',mFailureCode, ...
    'cFailureReason',{cFailureReason}, ...
    'dMinRcond',options.dMinRcond);
end

function [mInUse,vOutUse,rDiag] = ...
        iPrepareSystem(mIn,vOut,dMinRcond)
% Every named factor is required.  In particular, do not delete a factor
% merely because it is identically zero in this window: that is rank
% deficiency and the specified system must fail closed.

mInUse = mIn;
vOutUse = vOut;
iNumIn = size(mInUse,1);
iNumFactors = size(mInUse,2);

rDiag = struct('lIdentified',false,'iNumFactors',iNumFactors, ...
    'iCovRank',NaN,'dCovRcond',NaN,'iFailureCode',uint8(0), ...
    'sFailureReason','ok');

if iNumIn == 0
    rDiag.iFailureCode = uint8(3);
    rDiag.sFailureReason = 'no_complete_in_window_observations';
    return
end
if iNumFactors == 0
    rDiag.iFailureCode = uint8(4);
    rDiag.sFailureReason = 'no_required_factors';
    return
end
if iNumIn <= iNumFactors
    rDiag.iFailureCode = uint8(5);
    rDiag.sFailureReason = 'N_not_greater_than_K';
    return
end

mCov = cov(mInUse);
if any(~isfinite(mCov),'all')
    rDiag.iFailureCode = uint8(6);
    rDiag.sFailureReason = 'covariance_nonfinite';
    return
end
rDiag.iCovRank = rank(mCov);
rDiag.dCovRcond = rcond(mCov);
if rDiag.iCovRank < iNumFactors
    rDiag.iFailureCode = uint8(7);
    rDiag.sFailureReason = 'covariance_rank_deficient';
    return
end
if ~isfinite(rDiag.dCovRcond) || rDiag.dCovRcond < dMinRcond
    rDiag.iFailureCode = uint8(9);
    rDiag.sFailureReason = 'covariance_ill_conditioned';
    return
end

rDiag.lIdentified = true;
end

function [vBeta,vT,vTHAC,vP,vPHAC,rReg] = ...
        iSafeHACRegression(vY,vX)
rReg = fOLSNeweyWestCalendar(vY,vX);
vBeta = rReg.vBeta;
vT = rReg.vT;
vTHAC = rReg.vTHAC;
vP = rReg.vP;
vPHAC = rReg.vPHAC;
end
