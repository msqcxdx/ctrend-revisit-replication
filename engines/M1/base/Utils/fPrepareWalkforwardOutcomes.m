function [vYtrain, vYvalidation, vYout, vYoutPnl, rOutlierFit, ...
        vYoutLabel] = ...
    fPrepareWalkforwardOutcomes(vYtrainRaw, vYvalidationRaw, vYoutRaw, ...
    mIDtrain, mIDvalidation, mIDout, sMethod, dThreshold, lDemean, ...
    vYoutEvaluationRaw, vYfitRaw, mIDfitRaw)
% Clean each already-realized historical week on its own cross-section.
%
% This is the v2 "minimal" repair of the paper/old outlier convention.
% Cutoffs for historical week s use only formation-eligible returns observed
% in week s. Training and validation weeks are both historical at the target
% formation date, so their own cross-sections may be transformed without
% look-ahead. The target/OOS week is never used to fit or apply an outlier
% rule: its statistical label and its endpoint portfolio payoff remain raw.
%
% vYfitRaw/mIDfitRaw provide the formation-universe reference cross-section.
% They may contain more rows than the estimator panel so missing predictors
% cannot change a return-cleaning cutoff.

if nargin < 7 || isempty(sMethod)
    sMethod = 'none';
end
if nargin < 8 || isempty(dThreshold)
    dThreshold = 0;
end
if nargin < 9 || isempty(lDemean)
    lDemean = false;
end
if nargin < 10 || isempty(vYoutEvaluationRaw)
    vYoutEvaluationRaw = vYoutRaw;
end
lUsedPanelFallback = nargin < 11 || isempty(vYfitRaw);
if lUsedPanelFallback
    vYfitRaw = [vYtrainRaw;vYvalidationRaw];
    mIDfitRaw = [mIDtrain;mIDvalidation];
elseif nargin < 12 || isempty(mIDfitRaw)
    error(['Historical-week outlier fitting requires time IDs for every ' ...
        'formation-universe reference outcome']);
end

assert(size(mIDtrain,1) == numel(vYtrainRaw), ...
    'Training outcomes and IDs must have equal length');
assert(size(mIDvalidation,1) == numel(vYvalidationRaw), ...
    'Validation outcomes and IDs must have equal length');
assert(size(mIDout,1) == numel(vYoutRaw), ...
    'OOS outcomes and IDs must have equal length');
assert(numel(vYoutEvaluationRaw) == numel(vYoutRaw), ...
    'OOS evaluation outcomes and IDs must have equal length');
assert(size(mIDfitRaw,1) == numel(vYfitRaw) && size(mIDfitRaw,2) == 2, ...
    'Outlier reference outcomes require matching time/asset IDs');

sMethod = lower(strtrim(sMethod));
assert(ismember(sMethod, {'none','trunc','win'}), ...
    'Outlier treatment must be none, trunc, or win');
if strcmp(sMethod, 'none')
    assert(dThreshold == 0, ...
        'The none outlier method requires a zero threshold');
else
    assert(dThreshold > 0 && dThreshold < 0.5, ...
        'The outlier threshold must lie in (0,0.5)');
    assert(~lUsedPanelFallback, ...
        ['A nontrivial outlier rule requires the independent formation-' ...
         'universe weekly return reference']);
end

vHistoricalTime = unique([mIDtrain(:,1);mIDvalidation(:,1)]);
vOutTime = unique(mIDout(:,1));
if ~isempty(vHistoricalTime) && ~isempty(vOutTime)
    assert(max(vHistoricalTime) < min(vOutTime), ...
        'Every outlier-cleaned week must strictly precede the OOS target');
end
assert(all(ismember(mIDfitRaw(:,1),vHistoricalTime)), ...
    ['The outlier reference may contain only current training/validation ' ...
     'weeks, never an OOS or future week']);

rOutlierFit = iFitHistoricalWeeks( ...
    vYfitRaw,mIDfitRaw,sMethod,dThreshold);
if ~strcmp(sMethod,'none')
    vRequiredFitTime = unique([ ...
        mIDtrain(isfinite(vYtrainRaw),1); ...
        mIDvalidation(isfinite(vYvalidationRaw),1)]);
    assert(all(ismember(vRequiredFitTime,rOutlierFit.vTimeID)), ...
        ['Every finite historical estimator label must have an independent ' ...
         'formation-universe weekly cutoff']);
end

if strcmp(sMethod,'none')
    vYtrainCleanRaw = vYtrainRaw;
    vYvalidationCleanRaw = vYvalidationRaw;
else
    vYtrainCleanRaw = iTransformHistoricalWeeks( ...
        vYtrainRaw,mIDtrain,rOutlierFit);
    vYvalidationCleanRaw = iTransformHistoricalWeeks( ...
        vYvalidationRaw,mIDvalidation,rOutlierFit);
end

% The target week is never cross-sectionally cleaned. It is an outcome
% observed only after formation. The strict statistical layer and the raw
% endpoint P&L layer may differ in support, but neither is capped/deleted by
% the historical label transform.
vYoutLabel = vYoutRaw;
vYoutPnl = vYoutEvaluationRaw;
vYtrain = vYtrainCleanRaw;
vYvalidation = vYvalidationCleanRaw;
vYout = vYoutRaw;

if logical(lDemean)
    vYtrain = iDemeanByTime(vYtrain,mIDtrain);
    vYvalidation = iDemeanByTime(vYvalidation,mIDvalidation);
    vYout = iDemeanByTime(vYout,mIDout);
end
end

function rFit = iFitHistoricalWeeks(vRaw,mID,sMethod,dThreshold)
vTime = unique(mID(:,1));
iNumTime = numel(vTime);
vLower = NaN(iNumTime,1);
vUpper = NaN(iNumTime,1);
vNumFit = zeros(iNumTime,1);
for iIdxT = 1:iNumTime
    lTime = mID(:,1) == vTime(iIdxT);
    vFinite = vRaw(lTime & isfinite(vRaw));
    vNumFit(iIdxT) = numel(vFinite);
    if isempty(vFinite) || strcmp(sMethod,'none')
        continue
    end
    vLower(iIdxT) = quantile(vFinite,dThreshold);
    vUpper(iIdxT) = quantile(vFinite,1-dThreshold);
    assert(isfinite(vLower(iIdxT)) && isfinite(vUpper(iIdxT)) && ...
        vLower(iIdxT) <= vUpper(iIdxT), ...
        'Historical-week outlier cutoffs are not identified');
end
rFit = struct();
rFit.sMethod = sMethod;
rFit.dThreshold = dThreshold;
rFit.sFitRule = 'own_cross_section_for_each_historical_week';
rFit.vTimeID = vTime;
rFit.vLower = vLower;
rFit.vUpper = vUpper;
rFit.vNumFit = vNumFit;
rFit.iNumHistoricalWeeks = iNumTime;
rFit.iNumReferenceRows = numel(vRaw);
rFit.lTransformsOOS = false;
end

function vClean = iTransformHistoricalWeeks(vRaw,mID,rFit)
vClean = NaN(size(vRaw));
for iIdxT = 1:numel(rFit.vTimeID)
    lTime = mID(:,1) == rFit.vTimeID(iIdxT);
    if ~any(lTime)
        continue
    end
    vThis = vRaw(lTime);
    lFinite = isfinite(vThis);
    if rFit.vNumFit(iIdxT) == 0 || ...
            ~isfinite(rFit.vLower(iIdxT)) || ...
            ~isfinite(rFit.vUpper(iIdxT))
        vClean(lTime) = NaN;
        continue
    end
    switch rFit.sMethod
        case 'trunc'
            vThis(lFinite & (vThis < rFit.vLower(iIdxT) | ...
                vThis > rFit.vUpper(iIdxT))) = NaN;
        case 'win'
            vThis(lFinite & vThis < rFit.vLower(iIdxT)) = ...
                rFit.vLower(iIdxT);
            vThis(lFinite & vThis > rFit.vUpper(iIdxT)) = ...
                rFit.vUpper(iIdxT);
        otherwise
            error('Unknown historical-week outlier method: %s', ...
                rFit.sMethod);
    end
    vClean(lTime) = vThis;
end
end

function vY = iDemeanByTime(vY,mID)
if isempty(vY)
    return
end
vTime = unique(mID(:,1));
for iIdxT = 1:numel(vTime)
    lThisTime = mID(:,1) == vTime(iIdxT);
    vThisTime = vY(lThisTime);
    dMean = mean(vThisTime(isfinite(vThisTime)));
    if isfinite(dMean)
        vY(lThisTime) = vThisTime-dMean;
    else
        vY(lThisTime) = NaN;
    end
end
end
