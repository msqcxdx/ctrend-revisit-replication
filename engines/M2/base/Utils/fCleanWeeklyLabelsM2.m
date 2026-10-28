function [mClean,rAudit] = fCleanWeeklyLabelsM2(mRaw,sMethod,dThreshold)
% Apply M0's outlier rule separately to each already-realized weekly
% cross-section.  No cutoff uses another week and the returned object is a
% training-label layer, never a portfolio-payoff layer.

arguments
    mRaw (:,:) {mustBeNumeric}
    sMethod char
    dThreshold (1,1) {mustBeNumeric,mustBeNonnegative}
end

sMethod = lower(strtrim(sMethod));
assert(ismember(sMethod,{'trunc','win'}), ...
    'M2 preserves M0 outlier methods: trunc or win');
assert(dThreshold > 0 && dThreshold < 0.5, ...
    'Outlier threshold must lie in (0,0.5)');

[iNumWeeks,~] = size(mRaw);
mClean = mRaw;
vLower = NaN(iNumWeeks,1);
vUpper = NaN(iNumWeeks,1);
vNumFit = zeros(iNumWeeks,1);
for iIdxT = 1:iNumWeeks
    vThis = mRaw(iIdxT,:);
    % M0 treats only NaN as missing.  Preserve that numerical convention:
    % very large and infinite observations are not silently reclassified as
    % missing by the M2 look-ahead ablation.
    lObserved = ~isnan(vThis);
    vFit = vThis(lObserved);
    vNumFit(iIdxT) = numel(vFit);
    if isempty(vFit)
        continue
    end
    vLower(iIdxT) = quantile(vFit,dThreshold);
    vUpper(iIdxT) = quantile(vFit,1-dThreshold);
    assert(~isnan(vLower(iIdxT)) && ~isnan(vUpper(iIdxT)) && ...
        vLower(iIdxT) <= vUpper(iIdxT), ...
        'Weekly outlier cutoff is not identified');
    switch sMethod
        case 'trunc'
            vThis(lObserved & (vThis < vLower(iIdxT) | ...
                vThis > vUpper(iIdxT))) = NaN;
        case 'win'
            vThis(lObserved & vThis < vLower(iIdxT)) = vLower(iIdxT);
            vThis(lObserved & vThis > vUpper(iIdxT)) = vUpper(iIdxT);
    end
    mClean(iIdxT,:) = vThis;
end

rAudit = struct();
rAudit.sMethod = sMethod;
rAudit.dThreshold = dThreshold;
rAudit.sRule = 'own_cross_section_for_each_historical_week';
rAudit.sCutoffReference = ...
    'formation_screened_returns_before_predictor_support';
rAudit.lUsesOtherWeeks = false;
rAudit.lUsesPredictorAvailability = false;
rAudit.lTransformsPortfolioPayoff = false;
rAudit.vNumFit = vNumFit;
rAudit.vLower = vLower;
rAudit.vUpper = vUpper;
end
