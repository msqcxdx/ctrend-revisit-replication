function test_v2_no_adjustment_mode()
% Prove that the nine-experiment raw-data mode is a bit-exact identity map.

sModeBefore = getenv('CTREND_RAW_ADJUSTMENT_MODE');
sExperimentBefore = getenv('CTREND_CORE_EXPERIMENT_ID');
sRegistryBefore = getenv('CTREND_EVENT_REGISTRY_FILE');
rCleanup = onCleanup(@() iRestoreEnvironment( ...
    sModeBefore,sExperimentBefore,sRegistryBefore)); %#ok<NASGU>
setenv('CTREND_RAW_ADJUSTMENT_MODE','none');
if strlength(strtrim(string(sExperimentBefore))) == 0
    setenv('CTREND_CORE_EXPERIMENT_ID','M1_D0_unit_test');
end
setenv('CTREND_EVENT_REGISTRY_FILE','');

dtDate = (datetime(2020,1,1):days(1):datetime(2020,1,5))';
vAssetID = [1;2603;3787;9040];
rMetaData = struct();
rMetaData.vID = vAssetID;
rMetaData.cSymbol = {'BTC';'NPXS';'INNBCL';'PUNDIX'};
rng(20260811,'twister');
cBefore = arrayfun(@(i)randn(numel(dtDate),numel(vAssetID))+i*100, ...
    1:6,'UniformOutput',false);
cBefore{1}(2,2) = NaN;
cBefore{4}(3,3) = 1e12;
cBefore{6}(4,4) = 0;

[mOpen,mHigh,mLow,mClose,mME,mVolume,rAudit] = ...
    fApplyV2RawDataCorrections(cBefore{:},dtDate,vAssetID,rMetaData);
cAfter = {mOpen,mHigh,mLow,mClose,mME,mVolume};
assert(all(cellfun(@(a,b)isequaln(a,b),cBefore,cAfter)), ...
    'raw_adjustment_mode=none changed a raw panel');
assert(strcmp(rAudit.sMode,'none') && rAudit.iRegistryRows == 0 && ...
    rAudit.iNumAssetsRemoved == 0 && rAudit.iNumMissingPriceDates == 0 && ...
    rAudit.iNumExternalCorruptPriceDates == 0 && ...
    strcmp(rAudit.sRegistrySHA256,'not_consumed'), ...
    'raw_adjustment_mode=none produced the wrong audit identity');
fprintf('V2_NO_ADJUSTMENT_MODE_TEST_OK panels=6 assets=4 registry_rows=0\n');
end

function iRestoreEnvironment(sMode,sExperiment,sRegistry)
setenv('CTREND_RAW_ADJUSTMENT_MODE',sMode);
setenv('CTREND_CORE_EXPERIMENT_ID',sExperiment);
setenv('CTREND_EVENT_REGISTRY_FILE',sRegistry);
end
