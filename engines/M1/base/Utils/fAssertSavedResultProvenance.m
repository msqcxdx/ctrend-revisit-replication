function fAssertSavedResultProvenance(rSaved, sExpectedDataBuildID)
% Reject a saved pipeline dependency produced by stale code or weekly data.

arguments
    rSaved struct
    sExpectedDataBuildID {mustBeTextScalar} = ""
end

cRequired = {'sCodeFingerprint','sDataBuildID'};
assert(all(isfield(rSaved, cRequired)), ...
    ['Saved dependency predates corrected provenance tracking. ' ...
     'Rerun its producing pipeline step.']);
sCurrentFingerprint = fPipelineCodeFingerprint(pwd);
assert(strcmp(char(rSaved.sCodeFingerprint), sCurrentFingerprint), ...
    'Saved dependency was produced by different corrected source; rerun it.');
if ~isempty(char(sExpectedDataBuildID))
    assert(strcmp(char(rSaved.sDataBuildID), char(sExpectedDataBuildID)), ...
        'Saved dependency was produced from a different weekly data build; rerun it.');
end
end
