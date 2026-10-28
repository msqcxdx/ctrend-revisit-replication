% CTREND_REVISIT_FILE_PURPOSE: Resolve relocatable package paths, resources, and the eighteen public P/M/D experiment IDs.
function c = project_config()
% Relocatable public configuration; environment variables override defaults.
root = fileparts(fileparts(mfilename('fullpath')));
c.packageRoot = root;
c.rawData = fullfile(root,'data','raw','common');
c.runBase = getenv('RUN_BASE');
if isempty(c.runBase), c.runBase = fullfile(root,'outputs','runs'); end
c.workBase = getenv('WORK_BASE');
if isempty(c.workBase), c.workBase = fullfile(root,'runtime'); end
c.matlabBin = getenv('MATLAB_BIN');
if isempty(c.matlabBin), c.matlabBin = 'matlab'; end
c.parallelWorkers = str2double(getenv('PARALLEL_WORKERS'));
if isnan(c.parallelWorkers), c.parallelWorkers = max(1,feature('numcores')-1); end
c.experimentIDs = cell(1,18);
i = 0;
for p = 0:1
    for m = [0 2 1]
        for d = 0:2
            i = i+1;
            c.experimentIDs{i} = sprintf('P%d_M%d_D%d',p,m,d);
        end
    end
end
c.rawAdjustmentMode = 'none';
c.useDerivedCache = false;
end
