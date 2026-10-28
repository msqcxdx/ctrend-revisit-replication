function p = fEnsureParallelPoolExact(iWorkers,sJobStorage)
% Start and verify an exact-size local process pool.

arguments
    iWorkers (1,1) {mustBeNumeric,mustBeInteger,mustBePositive}
    sJobStorage {mustBeTextScalar} = ""
end

fprintf('parallel_workers_requested=%i\n',iWorkers);
p = gcp('nocreate');
if ~isempty(p) && p.NumWorkers ~= iWorkers
    delete(p);
    p = [];
end
if isempty(p)
    c = parcluster('local');
    fprintf('parallel_cluster_default_limit=%i\n',c.NumWorkers);
    if c.NumWorkers < iWorkers
        c.NumWorkers = iWorkers;
        fprintf('parallel_cluster_adjusted_limit=%i\n',c.NumWorkers);
    end
    if ~isempty(char(sJobStorage))
        sJobStorage = char(sJobStorage);
        if exist(sJobStorage,'dir') ~= 7
            mkdir(sJobStorage);
        end
        c.JobStorageLocation = sJobStorage;
        fprintf('parallel_job_storage=%s\n',sJobStorage);
    end
    p = parpool(c,iWorkers);
end
assert(p.NumWorkers == iWorkers, ...
    'Requested %i workers but active pool has %i',iWorkers,p.NumWorkers);
fprintf('parallel_workers_active=%i\n',p.NumWorkers);
end
