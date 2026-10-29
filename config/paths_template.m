% CTREND_REVISIT_FILE_PURPOSE: Show portable site-local environment variables without embedding an actual host path.
% Site-local example only. Copy these values into environment variables;
% never edit a frozen engine or commit an actual host path.
setenv('MATLAB_BIN','/absolute/path/to/R2023b/bin/matlab');
setenv('RUN_BASE','/absolute/large/disk/ctrend_nine_runs');
setenv('WORK_BASE','/absolute/large/disk/ctrend_nine_work');
setenv('JOB_STORAGE_ROOT','/absolute/large/disk/ctrend_matlab_jobs');
setenv('PARALLEL_WORKERS','127');
