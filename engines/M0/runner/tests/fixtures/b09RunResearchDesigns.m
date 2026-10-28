% CTREND_REVISIT_FILE_PURPOSE: Provide a minimal deterministic b09 fixture used only by runner smoke and fault tests.
% Minimal execution fixture for the old-v2 b09 shard runner. The initial
% clear matches the archived old script and the parfor verifies that the
% runner-created exact pool is usable from the base workspace.
clear; clc;
iFirst = str2double(getenv('OLD_V1_B09_FIRST_COMBO'));
iLast = str2double(getenv('OLD_V1_B09_LAST_COMBO'));
iFirstV2 = str2double(getenv('OLD_V2_B09_FIRST_COMBO'));
iLastV2 = str2double(getenv('OLD_V2_B09_LAST_COMBO'));
assert(iFirst == iFirstV2 && iLast == iLastV2, ...
    'Published-method v1/v2 range adapters disagree');
assert(iFirst == iLast && isfinite(iFirst),'Fixture expects one combo');
vWorkerOutput = zeros(1,4);
parfor iIdx = 1:4
    vWorkerOutput(iIdx) = iIdx^2;
end
assert(isequal(vWorkerOutput,[1 4 9 16]),'Fixture parfor output mismatch');
save(fullfile('Results','CTREND',sprintf('CTREND_Combo%d.mat',iFirst)), ...
    'iFirst','vWorkerOutput');
