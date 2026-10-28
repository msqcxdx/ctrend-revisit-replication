function [rOptions,rLedger,vLedgerWeekRow] = ...
    fAttachEconomicLedgerOptions( ...
    rOptions,sDataPath,rData,vAssetID,vWeekDate,sTiming)
% Authenticate a weekly input's ledger reference and attach sort options.

arguments
    rOptions (1,1) struct
    sDataPath {mustBeTextScalar}
    rData (1,1) struct
    vAssetID (:,1) {mustBeNumeric}
    vWeekDate (:,1) {mustBeNumeric}
    sTiming {mustBeMember(sTiming,{'ordinary','lead1'})}
end
assert(isfield(rData,'rEconomicReinvestmentLedgerReference'), ...
    'Weekly input predates the same-leg reinvestment ledger');
[rLedger,vLedgerWeekRow] = fLoadEconomicReinvestmentLedger( ...
    sDataPath,rData.rEconomicReinvestmentLedgerReference, ...
    vAssetID,vWeekDate);
rOptions.rReinvestmentLedger = rLedger;
rOptions.vLedgerWeekRow = vLedgerWeekRow;
rOptions.sPayoffTiming = char(sTiming);
end
