% CTREND_REVISIT_FILE_PURPOSE: Validate saved M1 b09 identity, design settings, dimensions, coverage, and payload hashes before reuse.
function validate_b09_resume_state()
% Write the exact set of provenance- and manifest-validated reusable combos.

codeDir = getenv('B09_CANONICAL_CODE_DIR');
shardRoot = getenv('B09_SHARD_RESULTS_ROOT');
runID = getenv('B09_RESEARCH_RUN_ID');
presentFile = getenv('B09_RESUME_PRESENT_FILE');
assert(~isempty(presentFile), 'B09_RESUME_PRESENT_FILE is required');

rAudit = fCollectB09ValidatedSources(codeDir, shardRoot, runID);
present = find(rAudit.lValid);
assert(~isempty(present) && present(1) == 1, ...
    'Canonical combo 1 is not reusable');

outputDir = fileparts(presentFile);
assert(isfolder(outputDir), ...
    'Resume-plan output directory does not exist');
temporary = [tempname(outputDir), '.txt'];
fid = fopen(temporary, 'wt');
assert(fid >= 0, 'Could not create temporary resume audit file');
rClose = onCleanup(@() fclose(fid));
fprintf(fid, '%d\n', present);
fclose(fid);
clear rClose
[ok, message] = movefile(temporary, presentFile, 'f');
assert(ok, 'Could not publish resume audit: %s', message);

rSummary = rmfield(rAudit, {'cSourceStatus', 'tCombos', ...
    'rBaseManifest'});
save(fullfile(outputDir, 'resume_validation_audit.mat'), 'rSummary');
fprintf(['B09_RESUME_AUDIT_OK valid=%d missing=%d invalid=%d ' ...
    'orphan=%d canonical_duplicates=%d moved_rows=%d\n'], ...
    nnz(rAudit.lValid), nnz(~rAudit.lValid), ...
    numel(rAudit.vInvalidCombo), numel(rAudit.cOrphanFile), ...
    numel(rAudit.cDuplicateCanonicalFile), ...
    size(rAudit.mMovedShardRow, 1));
end
