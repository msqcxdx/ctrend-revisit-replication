#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Verify reading, lineage, ownership and changed-block comment levels.
# In addition to structural annotation checks, this test targets large real
# production opcodes whose purpose could be misdescribed by a generic header.
from pmd_annotation_contract import check
from pathlib import Path
import importlib.util

# A truncated preview can hide the computation after a progress message.
# Exercise real production opcodes so annotation cannot call these numeric
# changes diagnostic-only or a mere expansion of the NaN predicate.
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('annotation_builder',root/'scripts/build_pmd_annotated_sources.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
checks=0
for rel,needle,required in [
    ('b02CalculateIndicators.m','fComputeCharacteristicChunk(','characteristic matrices'),
    ('b02CalculateIndicators.m','fComputeTechnicalIndicatorChunk(','technical indicators'),
    ('Utils/characteristics.m','mAge = cumsum(isfinite(self.mReturns),1)','observed returns rather than observed closes'),
]:
    old=(root/'engines/M0/base'/rel).read_bytes()
    new=(root/'engines/M1/base'/rel).read_bytes()
    blocks=builder.v4.diff_rows('M0','D0',rel,new,old,
        stage='m0-to-m1',reference_name='M0',target_name='M1')
    matching=[row for row in blocks if needle in row['target_block']]
    assert matching,rel
    for row in matching:
        note=builder.block_note(Path(rel),row)
        assert required in note,(rel,note)
        assert 'diagnostics only' not in note,(rel,note)
        checks+=1
print('ANNOTATION_LOCAL_SEMANTICS_OK cases='+str(checks))
check('readability')
# ``readability`` also requires ordinary annotations on unchanged code, so the
# mirror remains useful to a reader rather than merely serving as a diff log.
