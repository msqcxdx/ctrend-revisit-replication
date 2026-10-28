function run_nine_method_common_week_comparison()
% CTREND_REVISIT_FILE_PURPOSE: Run the path-free nine-method common-week robustness comparison from environment variables.
%RUN_NINE_METHOD_COMMON_WEEK_COMPARISON Environment-driven audit entry point.
%
% This wrapper validates environment-provided paths and delegates every
% calculation to compare_nine_methods_common_weeks. It introduces no defaults
% for missing experiment files and writes only to the requested output folder.
%
% Required variables are CTREND_COMMON_WEEK_M0_D0 through M1_D2 and
% CTREND_COMMON_WEEK_OUTPUT_DIR. Each method variable names its final
% CTREND_Base.mat. This wrapper contains no machine-specific path.

cLabels = ["M0_D0","M0_D1","M0_D2", ...
    "M2_D0","M2_D1","M2_D2", ...
    "M1_D0","M1_D1","M1_D2"];
cFiles = strings(1,numel(cLabels));
for iIdx = 1:numel(cLabels)
    sVariable = "CTREND_COMMON_WEEK_"+cLabels(iIdx);
    cFiles(iIdx) = string(getenv(sVariable));
    assert(strlength(cFiles(iIdx))>0, ...
        'Required environment variable is empty: %s',sVariable);
end
sOutputDir = string(getenv('CTREND_COMMON_WEEK_OUTPUT_DIR'));
assert(strlength(sOutputDir)>0, ...
    'CTREND_COMMON_WEEK_OUTPUT_DIR must be nonempty');
compare_nine_methods_common_weeks(cFiles,sOutputDir);
end
