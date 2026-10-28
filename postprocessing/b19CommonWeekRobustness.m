function b19CommonWeekRobustness()
% CTREND_REVISIT_FILE_PURPOSE: Run the numbered post-b18 identical-week robustness analysis without changing any experiment.
%B19COMMONWEEKROBUSTNESS Compare M0, M2, and M1 on explicitly shared weeks.
%
% This is deliberately outside engines/M0, engines/M1, and engines/M2. It
% consumes nine completed CTREND_Base.mat files through environment variables
% and delegates the numerical work to the tested path-free analysis function.
% It never re-estimates a model, rewrites a run root, or imputes a missing
% return.

sRoot = fileparts(fileparts(mfilename('fullpath')));
sAnalysis = fullfile(sRoot,'analysis');
sOldPath = path;
addpath(sAnalysis,'-begin');
rCleanup = onCleanup(@() path(sOldPath)); %#ok<NASGU>
run_nine_method_common_week_comparison();
end
