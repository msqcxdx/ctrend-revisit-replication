% CTREND_REVISIT_FILE_PURPOSE: Fail closed unless MATLAB and every required toolbox match the accepted production environment.
function environment_check()
% Fail closed on the production MATLAB/toolbox contract.

sVersion = string(version);
sRelease = string(version('-release'));
fprintf('matlab_version=%s\n',sVersion);
fprintf('matlab_release=%s\n',sRelease);
assert(sRelease == "2023b",'MATLAB R2023b is required');
assert(contains(sVersion,"Update 11"), ...
    'The accepted runtime is MATLAB R2023b Update 11');

cRequired = {'MATLAB','Econometrics Toolbox','Financial Toolbox', ...
    'Optimization Toolbox','Parallel Computing Toolbox', ...
    'Statistics and Machine Learning Toolbox'};
cInstalled = {ver().Name};
for iProduct = 1:numel(cRequired)
    assert(any(strcmp(cInstalled,cRequired{iProduct})), ...
        'Missing product: %s',cRequired{iProduct});
    fprintf('required_product_ok=%s\n',cRequired{iProduct});
end

cFunctions = {'lagmatrix','hac','lasso','tiedrank','parcluster','parpool'};
for iFunction = 1:numel(cFunctions)
    assert(exist(cFunctions{iFunction},'file') == 2, ...
        'Required MATLAB function is unavailable: %s',cFunctions{iFunction});
    fprintf('required_function_ok=%s\n',cFunctions{iFunction});
end
fprintf('ENVIRONMENT_CHECK_OK release=R2023b update=11\n');
end
