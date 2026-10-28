#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Bind the P0/M2 volume block to Dataverse/P0-M0 and exclude any other b02 scientific change.
# Scope contract: P0/M2 must retain the original zero-volume→missing rule,
# while P1/M2 may preserve explicit zero after unified preprocessing.  The
# surrounding b02 bytes must remain identical to the P1 parent implementation.
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]
parent = (ROOT/'engines/M2/base/b02CalculateIndicators.m').read_text()
fixed = (ROOT/'p0_extension/overlays/M2/b02CalculateIndicators.m').read_text()
end = '    % Calculate value-weighted market return'
before, tail = parent.split('    % Preserve explicit zero volume from the shared raw preprocessing.', 1)
_, after = tail.split(end, 1)
new_before, tail = fixed.split('    %%%% P0/M2 VOLUME-POLICY REPAIR', 1)
_, new_after = tail.split(end, 1)
assert before == new_before and after == new_after, 'Undeclared change outside volume block'
def block(text):
    # Extract the semantically bounded volume-policy block from each source.
    return text.split('    % Set volume to missing if zero for all assets', 1)[1].split(end, 1)[0]
def executable(text):
    # Ignore comments and whitespace only; all executable tokens must agree.
    return re.sub(r'\s+', '', '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('%')))
with zipfile.ZipFile(ROOT/'reference/dataverse_files.zip') as archive:
    original = archive.read('b02CalculateIndicators.m').decode()
m0 = (ROOT/'engines/P0_M0/base/b02CalculateIndicators.m').read_text()
assert executable(block(fixed)) == executable(block(m0)) == executable(block(original))
assert 'rData.mVolume > 0 & rData.mVolume <= 1e-6' in parent
assert 'overlays/M2/b02CalculateIndicators.m' in (ROOT/'p0_extension/scripts/materialize_experiment_source.sh').read_text()
print('P0_M2_VOLUME_SCOPE_OK dataverse_equivalent=1 outside_block_unchanged=1 P1_zero_preserved=1')
