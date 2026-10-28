function [vIdxTrain, vIdxValidation] = fSplitTrainValidation(vIdxInSample, iNumVal)
% Reserve the fixed most-recent validation weeks from one in-sample window.

arguments
    vIdxInSample (:,1) {mustBeNumeric}
    iNumVal (1,1) {mustBeInteger, mustBeNonnegative}
end

vIdxInSample = vIdxInSample(:);
assert(numel(unique(vIdxInSample)) == numel(vIdxInSample) && ...
    all(diff(vIdxInSample) > 0), ...
    'In-sample time IDs must be unique and strictly increasing');
if iNumVal == 0
    % Paper baseline estimates and selects forecasts on the same in-sample
    % observations; no separate validation block is used.
    vIdxTrain = vIdxInSample;
    vIdxValidation = vIdxInSample;
    return
end
assert(iNumVal < numel(vIdxInSample), ...
    'Validation window must be shorter than the in-sample window');
iNumTrain = numel(vIdxInSample) - iNumVal;
vIdxTrain = vIdxInSample(1:iNumTrain);
vIdxValidation = vIdxInSample(iNumTrain+1:end);
end
