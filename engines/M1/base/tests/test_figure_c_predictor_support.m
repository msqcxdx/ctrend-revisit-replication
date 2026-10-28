function test_figure_c_predictor_support()
% Lock Appendix C's predictor-specific N_j and univariate-PDV definition.

sTestDir = fileparts(mfilename('fullpath'));
sCodeDir = fileparts(sTestDir);
sOldPath = path;
addpath(fullfile(sCodeDir,'Utils'));
rCleanup = onCleanup(@() path(sOldPath)); %#ok<NASGU>

iNumAssets = 4;
iNumTimes = 4;
iNumPredictors = 3;
mX = reshape(1:(iNumAssets*iNumTimes*iNumPredictors), ...
    iNumAssets,iNumTimes,iNumPredictors) / 100;
mRawPredictorObserved = true(size(mX));
mRawOutcomeObserved = true(iNumAssets,iNumTimes);

% Model row 1 failed. Row 2 selects j=1,2 while an unselected j=3 is
% missing for asset 1. Row 3 selects j=1,3; j=3 is missing for asset 1 and
% the subsequent return is missing for asset 2. Row 4 is a successfully
% estimated all-zero selection.
mBeta = NaN(iNumTimes,iNumPredictors,2);
mBeta(2:end,:,1) = 0.1;
mBeta(2:end,:,2) = repmat([2,3,4],iNumTimes-1,1);
mSelected = logical([ ...
    0,0,0; ...
    1,1,0; ...
    1,0,1; ...
    0,0,0]);
mRawPredictorObserved(1,2,3) = false;
mX(1,2,3) = NaN;
mRawPredictorObserved(1,3,3) = false;
mX(1,3,3) = NaN;
mRawOutcomeObserved(2,3) = false;
vModelStatusCode = [ ...
    "expected_no_admissible_lambda"; ...
    "estimated"; ...
    "estimated"; ...
    "estimated"];

[vImportance,rDiag] = fImportanceCS_ENetPredictorSupport( ...
    mX,mRawPredictorObserved,mRawOutcomeObserved, ...
    mBeta,mSelected,(1:iNumTimes)',vModelStatusCode);

% Missing an unselected predictor cannot remove an asset from j=1's N_j.
assert(rDiag.mSupportCount(2,1) == iNumAssets, ...
    'Appendix-C N_j incorrectly depends on an unselected predictor');

% At row 3, j=1 loses only the asset with missing future return (N=3);
% j=3 loses that asset plus its own missing-predictor asset (N=2).
assert(rDiag.mSupportCount(3,1) == 3 && ...
    rDiag.mSupportCount(3,3) == 2, ...
    'Appendix-C N_j must use only j and raw future-return availability');

% Other selected forecasts contribute no variation with respect to j, but
% equation (11)'s fixed 1/J_selected denominator remains:
% sigma_j = |beta_j|/J_selected*std(unique(z_j)).
vUnique = unique(mX(:,2,1));
dExpected = abs(mBeta(2,1,2))*std(vUnique)/2;
iAssertClose(rDiag.mImportance(2,1),dExpected,1e-14, ...
    'equation-(11)-scaled Appendix-C PDV');

% Holding beta and support fixed, reducing the selected set from two
% forecasts to one must double j's importance.
mSelectedSingle = mSelected;
mSelectedSingle(2,:) = [1,0,0];
[~,rDiagSingle] = fImportanceCS_ENetPredictorSupport( ...
    mX,mRawPredictorObserved,mRawOutcomeObserved, ...
    mBeta,mSelectedSingle,(1:iNumTimes)',vModelStatusCode);
iAssertClose(rDiagSingle.mImportance(2,1),2*dExpected,1e-14, ...
    'time-varying selected-forecast denominator');

% A failed model week stays missing, while a valid all-zero selection is a
% genuine zero-importance week. An unselected j is zero even if N_j exists.
assert(all(isnan(rDiag.mImportance(1,:))) && ...
    all(isnan(rDiag.mSupportCount(1,:))) && ...
    all(rDiag.mImportance(4,:) == 0) && ...
    rDiag.mImportance(2,3) == 0 && ...
    rDiag.mFailureCode(2,3) == 2, ...
    'Failed, selected, and valid-zero model states were conflated');
assert(all(isfinite(vImportance)), ...
    'Time-averaged importance should be defined in this deterministic test');
assert(contains(rDiag.sSupportRule,'no other predictor enters') && ...
    contains(rDiag.sPDVRule,'univariate'), ...
    'Saved Figure-C diagnostics do not state the paper support/PDV rule');

fprintf('FIGURE_C_PREDICTOR_SUPPORT_TEST_OK\n');
end

function iAssertClose(dActual,dExpected,dTolerance,sName)
assert(isfinite(dActual) && isfinite(dExpected) && ...
    abs(dActual-dExpected) <= dTolerance, ...
    '%s differs from its deterministic reference',sName);
end
