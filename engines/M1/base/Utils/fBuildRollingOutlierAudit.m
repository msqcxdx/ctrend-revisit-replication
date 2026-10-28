function rAudit = fBuildRollingOutlierAudit(vFitY, mFitID, ...
        vAllTimeID, iNumIn, lRoll, iNumVal, sMethod, dThreshold)
% Reproduce and persist each causal walk-forward outlier fit.

arguments
    vFitY (:,1) {mustBeNumeric}
    mFitID (:,2) {mustBeNumeric, mustBeNonnegative}
    vAllTimeID (:,1) {mustBeNumeric, mustBeNonnegative}
    iNumIn (1,1) {mustBeInteger, mustBePositive}
    lRoll (1,1) {mustBeNumericOrLogical}
    iNumVal (1,1) {mustBeInteger, mustBeNonnegative}
    sMethod char
    dThreshold (1,1) {mustBeNumeric, mustBeNonnegative}
end

assert(numel(vFitY) == size(mFitID,1), ...
    'Outlier audit outcomes and IDs must have equal length');
assert(numel(unique(vAllTimeID)) == numel(vAllTimeID) && ...
       all(diff(vAllTimeID) > 0), ...
    'Outlier audit calendar must be unique and increasing');
assert(all(ismember(mFitID(:,1),vAllTimeID)), ...
    'Outlier-fit IDs must lie on the declared calendar');
sMethod = lower(strtrim(sMethod));
assert(ismember(sMethod,{'none','trunc','win'}), ...
    'Outlier method must be none, trunc, or win');
if strcmp(sMethod,'none')
    assert(dThreshold == 0,'No-treatment audit requires threshold zero');
else
    assert(dThreshold > 0 && dThreshold < 0.5, ...
        'Outlier threshold must lie in (0,0.5)');
end

iNumObs = numel(vAllTimeID);
iNumIter = max(iNumObs-iNumIn,0);
vOOSTimeID = NaN(iNumIter,1);
vTrainFirstTimeID = NaN(iNumIter,1);
vTrainLastTimeID = NaN(iNumIter,1);
vNumTrain = zeros(iNumIter,1);
vLower = NaN(iNumIter,1);
vUpper = NaN(iNumIter,1);

for iIdxI = 1:iNumIter
    iIdxT = iNumIn+iIdxI-1;
    [vIdxInPos,vIdxOutPos] = fCreateIndices(iNumObs,iIdxT, ...
        iNumIn,1,lRoll,false,false);
    vIdxIn = vAllTimeID(vIdxInPos);
    vIdxOut = vAllTimeID(vIdxOutPos);
    [vIdxTrain,~] = fSplitTrainValidation(vIdxIn(:),iNumVal);
    assert(isempty(vIdxTrain) || max(vIdxTrain) < min(vIdxOut), ...
        'Outlier audit training dates must precede OOS dates');
    vOOSTimeID(iIdxI) = vIdxOut(1);
    if isempty(vIdxTrain)
        continue
    end
    vTrainFirstTimeID(iIdxI) = vIdxTrain(1);
    vTrainLastTimeID(iIdxI) = vIdxTrain(end);
    lTrain = ismember(mFitID(:,1),vIdxTrain);
    vFinite = vFitY(lTrain & isfinite(vFitY));
    vNumTrain(iIdxI) = numel(vFinite);
    if isempty(vFinite) || strcmp(sMethod,'none')
        continue
    end
    vLower(iIdxI) = quantile(vFinite,dThreshold);
    vUpper(iIdxI) = quantile(vFinite,1-dThreshold);
end

rAudit = struct();
rAudit.sMethod = sMethod;
rAudit.dThreshold = dThreshold;
rAudit.iNumIn = iNumIn;
rAudit.lRoll = logical(lRoll);
rAudit.iNumVal = iNumVal;
rAudit.vOOSTimeID = vOOSTimeID;
rAudit.vTrainFirstTimeID = vTrainFirstTimeID;
rAudit.vTrainLastTimeID = vTrainLastTimeID;
rAudit.vNumTrain = vNumTrain;
rAudit.vLower = vLower;
rAudit.vUpper = vUpper;
rAudit.lStrictlyCausal = ...
    isnan(vTrainLastTimeID) | vTrainLastTimeID < vOOSTimeID;
assert(all(rAudit.lStrictlyCausal), ...
    'Outlier audit found a noncausal fit window');
end
