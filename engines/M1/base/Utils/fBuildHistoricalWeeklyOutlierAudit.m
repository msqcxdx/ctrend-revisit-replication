function rAudit = fBuildHistoricalWeeklyOutlierAudit(vFitY, mFitID, ...
        vAllTimeID, iNumIn, lRoll, iNumVal, sMethod, dThreshold)
% Audit v2's minimal, historical-week cross-sectional label cleaning.
%
% Each weekly cutoff is estimated once from that week's formation-eligible
% statistical returns.  A walk-forward iteration may use those cutoffs only
% for its already-realized training and validation weeks.  The OOS target
% week is recorded for chronology checks but is never transformed.

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

% Record the formation-universe cutoff for every calendar week.  Missing
% weeks remain explicit rather than being borrowed from an older week.
iNumTime = numel(vAllTimeID);
vNumFitByWeek = zeros(iNumTime,1);
vLowerByWeek = NaN(iNumTime,1);
vUpperByWeek = NaN(iNumTime,1);
for iIdxT = 1:iNumTime
    lWeek = mFitID(:,1) == vAllTimeID(iIdxT) & isfinite(vFitY);
    vFinite = vFitY(lWeek);
    vNumFitByWeek(iIdxT) = numel(vFinite);
    if isempty(vFinite) || strcmp(sMethod,'none')
        continue
    end
    vLowerByWeek(iIdxT) = quantile(vFinite,dThreshold);
    vUpperByWeek(iIdxT) = quantile(vFinite,1-dThreshold);
    assert(isfinite(vLowerByWeek(iIdxT)) && ...
        isfinite(vUpperByWeek(iIdxT)) && ...
        vLowerByWeek(iIdxT) <= vUpperByWeek(iIdxT), ...
        'Historical-week outlier cutoffs are not identified');
end

% Reproduce every walk-forward schedule and prove that every transformed
% train/validation week is strictly earlier than its target week.
iNumIter = max(iNumTime-iNumIn,0);
vOOSTimeID = NaN(iNumIter,1);
vTrainFirstTimeID = NaN(iNumIter,1);
vTrainLastTimeID = NaN(iNumIter,1);
vValidationFirstTimeID = NaN(iNumIter,1);
vValidationLastTimeID = NaN(iNumIter,1);
vNumTrainWeeks = zeros(iNumIter,1);
vNumValidationWeeks = zeros(iNumIter,1);
vNumHistoricalWeeks = zeros(iNumIter,1);
vNumHistoricalRows = zeros(iNumIter,1);
for iIdxI = 1:iNumIter
    iIdxT = iNumIn+iIdxI-1;
    [vIdxInPos,vIdxOutPos] = fCreateIndices(iNumTime,iIdxT, ...
        iNumIn,1,lRoll,false,false);
    vIdxIn = vAllTimeID(vIdxInPos);
    vIdxOut = vAllTimeID(vIdxOutPos);
    [vIdxTrain,vIdxValidation] = ...
        fSplitTrainValidation(vIdxIn(:),iNumVal);
    vIdxHistorical = [vIdxTrain(:);vIdxValidation(:)];

    vOOSTimeID(iIdxI) = vIdxOut(1);
    vNumTrainWeeks(iIdxI) = numel(vIdxTrain);
    vNumValidationWeeks(iIdxI) = numel(vIdxValidation);
    vNumHistoricalWeeks(iIdxI) = numel(vIdxHistorical);
    if ~isempty(vIdxTrain)
        vTrainFirstTimeID(iIdxI) = vIdxTrain(1);
        vTrainLastTimeID(iIdxI) = vIdxTrain(end);
    end
    if ~isempty(vIdxValidation)
        vValidationFirstTimeID(iIdxI) = vIdxValidation(1);
        vValidationLastTimeID(iIdxI) = vIdxValidation(end);
    end
    if ~isempty(vIdxHistorical)
        assert(max(vIdxHistorical) < vIdxOut(1), ...
            'Historical outlier-cleaning dates must precede OOS dates');
        lHistorical = ismember(mFitID(:,1),vIdxHistorical);
        vNumHistoricalRows(iIdxI) = nnz(lHistorical & isfinite(vFitY));
    end
end

rAudit = struct();
rAudit.sMethod = sMethod;
rAudit.dThreshold = dThreshold;
rAudit.sFitRule = 'own_cross_section_for_each_historical_week';
rAudit.lTransformsOOS = false;
rAudit.iNumIn = iNumIn;
rAudit.lRoll = logical(lRoll);
rAudit.iNumVal = iNumVal;
rAudit.vTimeID = vAllTimeID;
rAudit.vNumFitByWeek = vNumFitByWeek;
rAudit.vLowerByWeek = vLowerByWeek;
rAudit.vUpperByWeek = vUpperByWeek;
rAudit.vOOSTimeID = vOOSTimeID;
rAudit.vTrainFirstTimeID = vTrainFirstTimeID;
rAudit.vTrainLastTimeID = vTrainLastTimeID;
rAudit.vValidationFirstTimeID = vValidationFirstTimeID;
rAudit.vValidationLastTimeID = vValidationLastTimeID;
rAudit.vNumTrainWeeks = vNumTrainWeeks;
rAudit.vNumValidationWeeks = vNumValidationWeeks;
rAudit.vNumHistoricalWeeks = vNumHistoricalWeeks;
rAudit.vNumHistoricalRows = vNumHistoricalRows;
rAudit.lStrictlyCausal = ...
    (isnan(vTrainLastTimeID) | vTrainLastTimeID < vOOSTimeID) & ...
    (isnan(vValidationLastTimeID) | ...
        vValidationLastTimeID < vOOSTimeID);
assert(all(rAudit.lStrictlyCausal), ...
    'Outlier audit found a noncausal historical week');
end
