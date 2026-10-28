function [vImportance,rDiagnostics] = ...
        fImportanceCS_ENetPredictorSupport( ...
        mX,mRawPredictorObserved,mRawOutcomeObserved, ...
        mBeta,mSelected,vModelTimeIndex,vModelStatusCode)
% Figure-C variable importance with predictor-specific asset support.
%
% Appendix C defines N_{j,t+1} using only assets for which predictor j at t
% and the subsequent return at t+1 are observed.  For each unique z_j, the
% univariate intercept/slope from equation (8) generates the PDV.  Other
% selected or unselected predictors never enter j's support or forecast.
% The outcome is an availability mask only; its numerical value is not used.

arguments
    mX (:,:,:) {mustBeNumeric}
    mRawPredictorObserved (:,:,:) {mustBeNumericOrLogical}
    mRawOutcomeObserved (:,:) {mustBeNumericOrLogical}
    mBeta (:,:,:) {mustBeNumeric}
    mSelected (:,:) {mustBeNumericOrLogical}
    vModelTimeIndex (:,1) {mustBeInteger, mustBePositive}
    vModelStatusCode (:,1) string
end

[iNumAssets,iNumTimes,iNumPredictors] = size(mX);
assert(isequal(size(mRawPredictorObserved),size(mX)), ...
    'Raw-predictor availability must be asset by time by predictor');
assert(isequal(size(mRawOutcomeObserved),[iNumAssets,iNumTimes]), ...
    'Raw-outcome availability must be asset by time');
assert(size(mBeta,1) == numel(vModelTimeIndex) && ...
    size(mBeta,2) == iNumPredictors && size(mBeta,3) == 2, ...
    'Coefficients must be model-date by predictor by intercept/slope');
assert(isequal(size(mSelected), ...
    [numel(vModelTimeIndex),iNumPredictors]), ...
    'Selection must be model-date by predictor');
assert(numel(vModelStatusCode) == numel(vModelTimeIndex) && ...
    all(strlength(vModelStatusCode) > 0), ...
    'Every model date must have an explicit nonempty ENet status code');
assert(all(vModelTimeIndex <= iNumTimes) && ...
    numel(unique(vModelTimeIndex)) == numel(vModelTimeIndex) && ...
    all(diff(vModelTimeIndex) > 0), ...
    'Model dates must map uniquely and monotonically to the data calendar');
assert(all(isfinite(double(mRawPredictorObserved)),'all') && ...
    all(ismember(double(mRawPredictorObserved(:)),[0,1])), ...
    'Raw-predictor availability must contain only true/false values');
assert(all(isfinite(double(mRawOutcomeObserved)),'all') && ...
    all(ismember(double(mRawOutcomeObserved(:)),[0,1])), ...
    'Raw-outcome availability must contain only true/false values');

mRawPredictorObserved = logical(mRawPredictorObserved);
mRawOutcomeObserved = logical(mRawOutcomeObserved);
mSelected = logical(mSelected);
iNumModelDates = numel(vModelTimeIndex);

mImportance = NaN(iNumModelDates,iNumPredictors);
mSupportCount = NaN(iNumModelDates,iNumPredictors);
mUniquePredictorValues = NaN(iNumModelDates,iNumPredictors);
% 0=identified (including a constant predictor's defined zero);
% 1=model failure; 2=not selected (defined importance zero);
% 3=selected coefficient invalid; 4=no support;
% 6=counterfactual forecast invalid.
mFailureCode = repmat(uint8(1),iNumModelDates,iNumPredictors);
cFailureReason = repmat({"model_estimation_failed"}, ...
    iNumModelDates,iNumPredictors);
lStatusEstimated = vModelStatusCode == "estimated";
assert(~any(any(mSelected(~lStatusEstimated,:),2)), ...
    'A failed ENet window cannot contain selected predictors');
lHasFiniteComponentModel = squeeze(any(any(isfinite(mBeta),3),2));
lHasFiniteComponentModel = lHasFiniteComponentModel(:);
assert(~any(lStatusEstimated & ~lHasFiniteComponentModel), ...
    ['An ENet window marked estimated must retain finite component-model ' ...
     'coefficients; do not silently recode it as a failed model']);
lSuccessfulModel = lStatusEstimated;

for iIdxModel = 1:iNumModelDates
    if ~lSuccessfulModel(iIdxModel)
        continue
    end

    iIdxTime = vModelTimeIndex(iIdxModel);
    lSelected = mSelected(iIdxModel,:);
    iNumSelected = nnz(lSelected);

    mXThisWeek = permute(mX(:,iIdxTime,:),[1,3,2]);
    mRawObservedThisWeek = permute( ...
        mRawPredictorObserved(:,iIdxTime,:),[1,3,2]);
    lOutcomeObserved = mRawOutcomeObserved(:,iIdxTime);
    mBetaThisWeek = permute(mBeta(iIdxModel,:,:),[2,3,1]);

    for iIdxPredictor = 1:iNumPredictors
        % This is exactly Appendix C's N_{j,t+1}; calculate it even for an
        % unselected j so the zero assigned by selection remains auditable.
        lSupport = lOutcomeObserved & ...
            mRawObservedThisWeek(:,iIdxPredictor) & ...
            isfinite(mXThisWeek(:,iIdxPredictor));
        mSupportCount(iIdxModel,iIdxPredictor) = nnz(lSupport);
        vUniqueXj = unique(mXThisWeek(lSupport,iIdxPredictor));
        mUniquePredictorValues(iIdxModel,iIdxPredictor) = ...
            numel(vUniqueXj);

        if ~lSelected(iIdxPredictor)
            mImportance(iIdxModel,iIdxPredictor) = 0;
            mFailureCode(iIdxModel,iIdxPredictor) = uint8(2);
            cFailureReason{iIdxModel,iIdxPredictor} = 'not_selected';
            continue
        end
        if any(~isfinite(mBetaThisWeek(iIdxPredictor,:)))
            mFailureCode(iIdxModel,iIdxPredictor) = uint8(3);
            cFailureReason{iIdxModel,iIdxPredictor} = ...
                'univariate_coefficient_nonfinite';
            continue
        end

        if ~any(lSupport)
            mFailureCode(iIdxModel,iIdxPredictor) = uint8(4);
            cFailureReason{iIdxModel,iIdxPredictor} = ...
                'no_predictor_specific_support';
            continue
        end

        if numel(vUniqueXj) < 2
            mImportance(iIdxModel,iIdxPredictor) = 0;
            mFailureCode(iIdxModel,iIdxPredictor) = uint8(0);
            cFailureReason{iIdxModel,iIdxPredictor} = ...
                'constant_predictor_zero_importance';
            continue
        end

        vCrossSectionalMean = NaN(numel(vUniqueXj),1);
        for iIdxValue = 1:numel(vUniqueXj)
            % Replace j by a common unique value and retain equation (11)'s
            % fixed 1/J_selected forecast-combination denominator.  Other
            % selected components contribute only a constant with respect
            % to this replacement value, so they do not affect the standard
            % deviation but their denominator must not be dropped.
            vForecastCounterfactual = repmat( ...
                (mBetaThisWeek(iIdxPredictor,1) + ...
                 vUniqueXj(iIdxValue) * ...
                 mBetaThisWeek(iIdxPredictor,2)) / iNumSelected, ...
                nnz(lSupport),1);
            vCrossSectionalMean(iIdxValue) = ...
                mean(vForecastCounterfactual);
        end
        if any(~isfinite(vCrossSectionalMean))
            mFailureCode(iIdxModel,iIdxPredictor) = uint8(6);
            cFailureReason{iIdxModel,iIdxPredictor} = ...
                'counterfactual_forecast_nonfinite';
            continue
        end

        mImportance(iIdxModel,iIdxPredictor) = ...
            std(vCrossSectionalMean);
        mFailureCode(iIdxModel,iIdxPredictor) = uint8(0);
        cFailureReason{iIdxModel,iIdxPredictor} = 'ok';
    end
end

vImportance = mean(mImportance,1,'omitmissing');
rDiagnostics = struct();
rDiagnostics.mImportance = mImportance;
rDiagnostics.mSupportCount = mSupportCount;
rDiagnostics.mUniquePredictorValues = mUniquePredictorValues;
rDiagnostics.mFailureCode = mFailureCode;
rDiagnostics.cFailureReason = cFailureReason;
rDiagnostics.lSuccessfulModel = lSuccessfulModel;
rDiagnostics.vModelStatusCode = vModelStatusCode;
rDiagnostics.lStatusEstimated = lStatusEstimated;
rDiagnostics.vModelTimeIndex = vModelTimeIndex;
rDiagnostics.mSelected = mSelected;
rDiagnostics.vSelectedPredictorCount = sum(mSelected,2);
rDiagnostics.vNumWeeksInAverage = ...
    sum(isfinite(mImportance),1);
rDiagnostics.sSupportRule = ...
    ['Appendix C literal N_j: raw predictor j observed at t AND raw ' ...
     'untransformed return observed at t+1; no other predictor enters'];
rDiagnostics.sPDVRule = ...
    ['For each unique predictor-specific rank z_j, use only j''s saved ' ...
     'univariate intercept/slope divided by the fixed number of selected ' ...
     'forecasts in equation (11); assign sigma=0 iff ENet did not select j'];
end
