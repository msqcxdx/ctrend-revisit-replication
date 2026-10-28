function rSummary = fSummarizeResearchDesignEstimatorAudit(rAudit)
% Compact explicit ENet window statuses for per-combo provenance.

arguments
    rAudit (1,1) struct
end

rSummary = struct();
rSummary.cStatusCodebook = { ...
    'not_exposed','estimated','expected_insufficient_observations', ...
    'expected_no_predictors','expected_nonpositive_weight_sum', ...
    'expected_no_admissible_lambda', ...
    'expected_no_complete_validation_support','other_expected', ...
    'unexpected_nonestimated'};
if ~isfield(rAudit,'cSelectionStatus')
    rSummary.vWindowStatus = zeros(0,1,'uint8');
    rSummary.lEmptySelection = false(0,1);
    rSummary.iExpectedFailureWindows = 0;
    rSummary.iUnexpectedFailureWindows = 0;
    return
end

cStatus = rAudit.cSelectionStatus(:);
vStatus = zeros(numel(cStatus),1,'uint8');
lEmptySelection = false(numel(cStatus),1);
for iIdx = 1:numel(cStatus)
    rStatus = cStatus{iIdx};
    assert(isstruct(rStatus) && isfield(rStatus,'sCode'), ...
        'Estimator audit status entry %d is malformed',iIdx);
    sCode = string(rStatus.sCode);
    switch sCode
        case "estimated"
            vStatus(iIdx) = uint8(1);
        case "expected_insufficient_observations"
            vStatus(iIdx) = uint8(2);
        case "expected_no_predictors"
            vStatus(iIdx) = uint8(3);
        case "expected_nonpositive_weight_sum"
            vStatus(iIdx) = uint8(4);
        case "expected_no_admissible_lambda"
            vStatus(iIdx) = uint8(5);
        case "expected_no_complete_validation_support"
            vStatus(iIdx) = uint8(6);
        otherwise
            if startsWith(sCode,"expected_")
                vStatus(iIdx) = uint8(7);
            else
                vStatus(iIdx) = uint8(8);
            end
    end
    if isfield(rAudit,'cSelected') && vStatus(iIdx) == 1
        lEmptySelection(iIdx) = ...
            ~any(logical(rAudit.cSelected{iIdx}));
    end
end

rSummary.vWindowStatus = vStatus;
rSummary.lEmptySelection = lEmptySelection;
rSummary.iExpectedFailureWindows = nnz(vStatus >= 2 & vStatus <= 7);
rSummary.iUnexpectedFailureWindows = nnz(vStatus == 8);
end
