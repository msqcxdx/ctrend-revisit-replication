function run_full_pipeline_corrected()
% Run the corrected CTREND pipeline in one MATLAB session.

codeDir = fileparts(mfilename('fullpath'));
cd(codeDir);
restoredefaultpath;
rehash toolboxcache;

logDir = getenv('PIPELINE_LOG_DIR');
if isempty(logDir)
    runID = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    logDir = fullfile(codeDir, 'logs', ['corrected_pipeline_', runID]);
end
if ~exist(logDir, 'dir')
    mkdir(logDir);
end

statusFile = getenv('PIPELINE_STATUS_FILE');
if isempty(statusFile)
    statusFile = fullfile(logDir, 'status.tsv');
end
logFile = getenv('PIPELINE_LOG_FILE');
if isempty(logFile)
    logFile = fullfile(logDir, 'pipeline.log');
end

if isempty(getenv('PIPELINE_STDOUT_REDIRECTED'))
    diary(logFile);
    cleanupDiary = onCleanup(@() diary('off'));
else
    cleanupDiary = [];
end

fprintf('run_full_pipeline_corrected started_at=%s\n', char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')));
fprintf('code_dir=%s\n', codeDir);
fprintf('log_dir=%s\n', logDir);
fprintf('pipeline_run_id=%s\n',getenv('PIPELINE_RUN_ID'));
fprintf('results_dir=%s\n',char(java.io.File( ...
    fullfile(codeDir,'Results')).getCanonicalPath()));
fprintf('matlab_version=%s\n',version);
fprintf('matlab_release=%s\n',version('-release'));
fprintf('computer=%s\n',computer);
rProductVersions = ver;
for iIdxProduct = 1:numel(rProductVersions)
    fprintf('matlab_product=%s|%s|%s\n', ...
        rProductVersions(iIdxProduct).Name, ...
        rProductVersions(iIdxProduct).Version, ...
        rProductVersions(iIdxProduct).Release);
end

outputVariant = lower(strtrim(getenv('CTREND_OUTPUT_VARIANT')));
assert(isempty(outputVariant) || strcmp(outputVariant,'main'), ...
    ['The full pipeline only accepts CTREND_OUTPUT_VARIANT=main. ' ...
     'Run supplementary variants explicitly after the main outputs.']);
setenv('CTREND_OUTPUT_VARIANT','main');

pipelineScope = lower(strtrim(getenv('PIPELINE_SCOPE')));
if isempty(pipelineScope)
    pipelineScope = 'full';
end
assert(ismember(pipelineScope,{'full','baseline','table6'}), ...
    'PIPELINE_SCOPE must be full, baseline, or table6');

addpath(fullfile(codeDir, 'Utils'));
addpath(fullfile(codeDir, 'LatexTables'));

workers = str2double(getenv('PARALLEL_WORKERS'));
if isnan(workers) || workers < 1
    workers = 12;
end
workers = floor(workers);
configureParallelPool(workers, logDir);
fprintf('pipeline_scope=%s\n',pipelineScope);
fprintf('parallel_workers_requested=%d\n',workers);
fprintf('parallel_workers_active=%d\n',gcp('nocreate').NumWorkers);
fprintf('code_fingerprint=%s\n',fPipelineCodeFingerprint(codeDir));

switch pipelineScope
    case 'full'
        steps = { ...
        'setup', ...
        'b00GenerateDesignChoices', ...
        'b01ReadData', ...
        'b02CalculateIndicators', ...
        'b03Table1_ResearchSample', ...
        'b04Table2_TechnicalIndicatorStrategyReturns', ...
        'b05CreateCTREND', ...
        'b06Table3_UnivariatePortfolioSorts', ...
        'b07Table4_CrossSectionalRegressions', ...
        'b08Table5_PerformanceInSubperiodsAndDifferentMarketStates', ...
        'b09RunResearchDesigns', ...
        'b10Table6_FactorPerformanceAcrossResearchDesignChoices', ...
        'b11Figure3_AnomalyAlphas', ...
        'b12Table7_FrontierExpansionTest', ...
        'b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos', ...
        'b14Table9_CTRENDPortfoliosAndTransactionCosts', ...
        'b15TableB3_BivariatePortfolioSorts', ...
        'b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType', ...
        'b17TableB10_ExtendedPortfolioHoldingPeriod', ...
        'b18FigureC3_C4_AverageVariableImportance' ...
        };
    case 'baseline'
        steps = { ...
        'setup', ...
        'b00GenerateDesignChoices', ...
        'b01ReadData', ...
        'b02CalculateIndicators', ...
        'b03Table1_ResearchSample', ...
        'b04Table2_TechnicalIndicatorStrategyReturns', ...
        'b05CreateCTREND', ...
        'b06Table3_UnivariatePortfolioSorts', ...
        'b07Table4_CrossSectionalRegressions', ...
        'b08Table5_PerformanceInSubperiodsAndDifferentMarketStates', ...
        'b11Figure3_AnomalyAlphas', ...
        'b12Table7_FrontierExpansionTest', ...
        'b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos', ...
        'b14Table9_CTRENDPortfoliosAndTransactionCosts', ...
        'b15TableB3_BivariatePortfolioSorts', ...
        'b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType', ...
        'b17TableB10_ExtendedPortfolioHoldingPeriod', ...
        'b18FigureC3_C4_AverageVariableImportance' ...
        };
    case 'table6'
        % Resume/recompute the published research-design grid from already
        % certified weekly inputs. b09 itself supports explicit combo ranges.
        steps = {'setup','b00GenerateDesignChoices', ...
            'b09RunResearchDesigns', ...
            'b10Table6_FactorPerformanceAcrossResearchDesignChoices'};
end

startStep = getenv('PIPELINE_START_STEP');
endStep = getenv('PIPELINE_END_STEP');
if ~isempty(startStep)
    iStartStep = find(strcmpi(steps, startStep), 1, 'first');
    assert(~isempty(iStartStep), 'Unknown PIPELINE_START_STEP: %s', startStep);
else
    iStartStep = 1;
end
if ~isempty(endStep)
    iEndStep = find(strcmpi(steps, endStep), 1, 'first');
    assert(~isempty(iEndStep), 'Unknown PIPELINE_END_STEP: %s', endStep);
else
    iEndStep = numel(steps);
end
assert(iStartStep <= iEndStep, 'PIPELINE_START_STEP must be before PIPELINE_END_STEP');
fprintf('pipeline_start_step=%s\n', steps{iStartStep});
fprintf('pipeline_end_step=%s\n', steps{iEndStep});
steps = steps(iStartStep:iEndStep);

% A resumed run may skip b00, but it must never inherit the one-row baseline
% design file for a full/Table-6 run (or vice versa).
if any(~strcmp(steps,'setup')) && ...
        ~any(strcmp(steps,'b00GenerateDesignChoices'))
    validateDesignChoices(codeDir,pipelineScope);
end

writeStatusHeader(statusFile);

for iIdxStep = 1:numel(steps)
    step = steps{iIdxStep};
    started = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    appendStatus(statusFile, step, 'START', started, '', '');
    fprintf('\n===== START %s %s =====\n', step, started);
    try
        evalin('base', sprintf("cd('%s'); run('%s.m'); fSaveOpenFigures('%s');", ...
            codeDir, step, step));
        if strcmp(step,'b00GenerateDesignChoices')
            validateDesignChoices(codeDir,pipelineScope);
        end
        ended = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
        appendStatus(statusFile, step, 'END', started, ended, '0');
        fprintf('===== END %s rc=0 %s =====\n', step, ended);
    catch ME
        ended = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
        appendStatus(statusFile, step, 'END', started, ended, '1');
        fprintf('===== END %s rc=1 %s =====\n', step, ended);
        fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
        rethrow(ME);
    end
end

fprintf('completed_at=%s\n', char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')));

clear cleanupDiary
end

function validateDesignChoices(codeDir,pipelineScope)
sFilename = fullfile(codeDir,'DesignChoices.mat');
assert(exist(sFilename,'file') == 2, ...
    'DesignChoices.mat is missing; include b00GenerateDesignChoices');
r = load(sFilename,'tDataCombos','tCombos','sPipelineMode');
assert(isfield(r,'tDataCombos') && isfield(r,'tCombos') && ...
    isfield(r,'sPipelineMode'), 'DesignChoices.mat is incomplete');
if strcmp(pipelineScope,'baseline')
    sExpectedMode = 'baseline-only';
    iExpectedData = 1;
    iExpectedCombos = 1;
else
    sExpectedMode = 'full';
    iExpectedData = 4;
    iExpectedCombos = 3072;
end
assert(strcmp(r.sPipelineMode,sExpectedMode) && ...
    height(r.tDataCombos) == iExpectedData && ...
    height(r.tCombos) == iExpectedCombos && ...
    isequal(r.tCombos.setting(:),(1:iExpectedCombos)'), ...
    ['DesignChoices.mat does not match PIPELINE_SCOPE=%s; rerun ' ...
     'b00GenerateDesignChoices.'],pipelineScope);
end

function configureParallelPool(workers, logDir)
try
    jobStorage = getenv('PIPELINE_JOB_STORAGE');
    if isempty(jobStorage)
        jobStorage = fullfile(logDir, 'parallel_job_storage');
    end
    fEnsureParallelPoolExact(workers,jobStorage);
catch ME
    fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
    error('Could not start requested parallel pool with %d workers.', workers);
end
end

function writeStatusHeader(statusFile)
fid = fopen(statusFile, 'w');
assert(fid > 0, 'Could not open status file');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'step\tstatus\tstarted_at\tended_at\trc\n');
clear cleanup
end

function appendStatus(statusFile, step, status, started, ended, rc)
fid = fopen(statusFile, 'a');
assert(fid > 0, 'Could not open status file');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\t%s\t%s\t%s\t%s\n', step, status, started, ended, rc);
clear cleanup
end
