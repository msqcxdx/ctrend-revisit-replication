function [mPortRet,rDiagnostics] = fBuildTable5PortfolioReturns( ...
        mYhat,mRetPnlOOS,mFormationME,rSavedResults,vQuantiles,rOptions)
% Build the complete Table-5 quintile-return matrix without weakening H-L.
%
% b05 deliberately estimates the baseline factor with lHedgeOnly=true so
% that the economic H-L payoff depends only on the low and high legs.  The
% middle quintiles are therefore not present in b05's saved cResults.  Table
% 5 nevertheless reports all five quintiles.  Reconstruct those middle
% portfolios from the saved OOS signal and raw endpoint P&L, then restore
% the low, high, and H-L rows byte-for-byte from b05's hedge-only result.

arguments
    mYhat (:,:) {mustBeNumeric}
    mRetPnlOOS (:,:) {mustBeNumeric}
    mFormationME (:,:) {mustBeNumeric}
    rSavedResults struct
    vQuantiles (:,1) {mustBeNumeric,mustBeNonnegative}
    rOptions struct
end

assert(isequal(size(mYhat),size(mRetPnlOOS),size(mFormationME)), ...
    'Table-5 signal, endpoint P&L, and formation-cap matrices must align');
assert(isfield(rSavedResults,'VW') && ...
       isfield(rSavedResults.VW,'mPortRet'), ...
    'Table 5 requires b05 value-weighted hedge-only portfolio returns');

rFullOptions = rOptions;
rFullOptions.lHedgeOnly = false;
rFullResults = fSingleSortMulti(mYhat,mRetPnlOOS,vQuantiles,[], ...
    mFormationME,rFullOptions);

mPortRet = rFullResults.VW.mPortRet;
mSavedPortRet = rSavedResults.VW.mPortRet;
assert(isequal(size(mPortRet),size(mSavedPortRet)), ...
    'Full and hedge-only Table-5 portfolio matrices must align');

iNumLegs = numel(vQuantiles)-1;
assert(iNumLegs >= 2 && size(mPortRet,1) == iNumLegs+1, ...
    'Unexpected Table-5 quantile layout');
vOuterRows = [1,iNumLegs,iNumLegs+1];
vMiddleRows = 2:(iNumLegs-1);

% Preserve the exact b05 availability rule and economic accounting for the
% two traded legs and H-L.  Only the otherwise absent middle portfolios
% come from the complete sort.
mPortRet(vOuterRows,:) = mSavedPortRet(vOuterRows,:);

rDiagnostics = struct();
rDiagnostics.vOuterRowsFromB05 = vOuterRows;
rDiagnostics.vMiddleRowsReconstructed = vMiddleRows;
rDiagnostics.vFiniteWeeksByPortfolio = sum(isfinite(mPortRet),2);
rDiagnostics.lOuterRowsExact = ...
    isequaln(mPortRet(vOuterRows,:),mSavedPortRet(vOuterRows,:));
rDiagnostics.sAccountingRule = [ ...
    'Middle quintiles are reconstructed from the saved formation-time ' ...
    'OOS signal and raw endpoint P&L; low, high, and H-L retain the exact ' ...
    'b05 hedge-only accounting and availability rule'];

assert(rDiagnostics.lOuterRowsExact, ...
    'Table-5 reconstruction changed a b05 low, high, or H-L payoff');
end
