function rMerged = fMergeAssetChunkStructs(cChunks)
% Concatenate identically shaped per-asset result structs in chunk order.

assert(iscell(cChunks) && ~isempty(cChunks) && ...
    all(cellfun(@isstruct, cChunks)), 'Asset chunks must be nonempty structs');
cFields = fieldnames(cChunks{1});
rMerged = struct();
for iIdxC = 2:numel(cChunks)
    assert(isequal(fieldnames(cChunks{iIdxC}), cFields), ...
        'Parallel asset chunks returned different fields');
end
for iIdxF = 1:numel(cFields)
    sField = cFields{iIdxF};
    cParts = cellfun(@(r) r.(sField), cChunks, 'UniformOutput', false);
    rMerged.(sField) = cat(2, cParts{:});
end
end
