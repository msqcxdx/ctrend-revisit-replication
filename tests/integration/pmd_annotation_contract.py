#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Independently verify eighteen source bodies, exhaustive diff opcodes and comment hierarchy.
# Inputs: canonical M0/M1/M2 sources, P0 overlays, Dataverse reference code,
# and the generated annotated_sources tree.  The verifier rebuilds expected
# experiment trees independently of the annotation generator.
# Output: no files; a mismatch in bytes, diff coverage, ownership, hierarchy,
# or ordinary-reading annotations raises immediately and blocks release.
from pathlib import Path
import csv,difflib,hashlib
from collections import Counter
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'annotated_sources'
SUFFIX={'.m','.sh','.py','.bat'}
BEGIN=b'CTREND_REVISIT_ANNOTATION_HEADER_V4_BEGIN'
END=b'CTREND_REVISIT_ANNOTATION_HEADER_V4_END'
def sha(x):return hashlib.sha256(x).hexdigest()
def files(root):return {p.relative_to(root).as_posix():p.read_bytes() for p in root.rglob('*') if p.is_file() and p.suffix in SUFFIX}
def expected(id):
 # Reconstruct the exact source composition for one P×M×D cell.
 p,m,d=id.split('_');engine='P0_M0' if p=='P0' and m=='M0' else m
 base=ROOT/'engines'/engine;src=files(base/'base')
 if d!='D0':src.update(files(base/'overlays/exclusion'))
 if p=='P0' and m!='M0':src['b01ReadData.m']=(ROOT/'p0_extension/overlays'/m/('D0' if d=='D0' else 'exclusion')/'b01ReadData.m').read_bytes()
 if p=='P0' and m=='M2':src['b02CalculateIndicators.m']=(ROOT/'p0_extension/overlays/M2/b02CalculateIndicators.m').read_bytes()
 return src
def strip(body):
 # Remove only the generated annotation header, retaining the shebang byte-for-byte.
 lines=body.splitlines(keepends=True);off=1 if body.startswith(b'#!') else 0
 assert BEGIN in lines[off]
 end=next(i for i,line in enumerate(lines) if END in line)
 return b''.join(lines[:off]+lines[end+1:]),b''.join(lines[off:end+1])
def span(a,b):return str(a+1) if b-a==1 else f'{a+1}-{b}' if b>a else f'insertion-point-{a+1}'
def check(mode):
 # First prove executable-body identity, then prove every real diff opcode is explained.
 ids=[f'P{p}_M{m}_D{d}' for p in range(2) for m in range(3) for d in range(3)]
 trees={id:expected(id) for id in ids};orig=files(ROOT/'reference/dataverse_original_3d0959b1')
 rows=list(csv.DictReader((OUT/'ANNOTATION_INDEX.csv').open()))
 bodies=list(csv.DictReader((OUT/'BODY_IDENTITIES.csv').open()))
 ordinary=list(csv.DictReader((OUT/'ORDINARY_ANNOTATIONS.csv').open()))
 assert {x['experiment_id'] for x in bodies}==set(ids)
 for id,src in trees.items():
  actual=files(OUT/id/'source');assert set(actual)==set(src),(id,set(src)^set(actual))
  for rel,body in actual.items():
   plain,header=strip(body);assert plain==src[rel],(id,rel,'executable bytes changed')
   assert b'%%%%' in header
   ownrows=[r for r in rows if r['experiment_id']==id and r['relative_path']==rel]
   if ownrows:
    assert b'%%%' in header and b'%>>>' in header,(id,rel,'hierarchy')
    assert b'Reason / design need:' in header,(id,rel,'missing reason label')
    assert b'Result / boundary:' in header,(id,rel,'missing boundary label')
    assert b'Implementation in this exact block:' in header,(id,rel,'missing implementation label')
    for r in ownrows:assert f"[{r['owner']}]".encode() in header,(id,rel,'owner')
  p,m,d=id.split('_');chain=[('Dataverse','P0_M0_D0',orig,trees['P0_M0_D0'],'M0')]
  if d!='D0':chain.append(('P0_M0_D0',f'P0_M0_{d}',trees['P0_M0_D0'],trees[f'P0_M0_{d}'],'D'))
  if p=='P1':chain.append((f'P0_M0_{d}',f'P1_M0_{d}',trees[f'P0_M0_{d}'],trees[f'P1_M0_{d}'],'P'))
  if m!='M0':chain.append((f'{p}_M0_{d}',id,trees[f'{p}_M0_{d}'],src,m))
  want=[]
  for a,b,old,new,owner in chain:
   for rel in set(old)|set(new):
    x,y=old.get(rel),new.get(rel)
    if x==y:continue
    xl=(x or b'').decode(errors='replace').splitlines();yl=(y or b'').decode(errors='replace').splitlines()
    if x is None:ops=[('added-file','NA',span(0,len(yl)))]
    else:ops=[(op,span(i,j),span(k,l)) for op,i,j,k,l in difflib.SequenceMatcher(None,xl,yl,autojunk=False).get_opcodes() if op!='equal']
    for op,si,sj in ops:want.append((rel,a,b,owner,op,si,sj,sha(x) if x is not None else 'NA',sha(y or b'')))
  got=[(r['relative_path'],r['from_id'],r['to_id'],r['owner'],r['operation'],r['parent_lines'],r['child_lines'],r['parent_sha256'],r['child_sha256']) for r in rows if r['experiment_id']==id]
  if mode=='coverage':assert Counter(want)==Counter(got),(id,(Counter(want)-Counter(got)).most_common(4),(Counter(got)-Counter(want)).most_common(4))
 for r in bodies:
  assert sha(trees[r['experiment_id']][r['relative_path']])==r['canonical_sha256']
  assert sha((OUT/r['experiment_id']/'source'/r['relative_path']).read_bytes())==r['annotated_sha256']
 for r in rows:
  assert r['why'].strip() and r['scientific_effect'].strip()
  assert r['block_note'].strip(),(r['experiment_id'],r['relative_path'],r['block'])
  assert 'Adds ``' not in r['block_note'],(r['experiment_id'],r['relative_path'],r['block'])
  assert 'Removes ``' not in r['block_note'],(r['experiment_id'],r['relative_path'],r['block'])
  assert "See the file's own function contract" not in r['scientific_effect'],(
      r['experiment_id'],r['relative_path'],r['block'])
 # Ordinary notes must point to an exact final-body line that also occurs
 # verbatim in the immutable Dataverse source.  They can explain inherited
 # code, but can never be used to relabel a modification as "ordinary".
 assert ordinary
 assert len(ordinary)==len({(r['experiment_id'],r['relative_path'],r['canonical_line']) for r in ordinary})
 for r in ordinary:
  body=trees[r['experiment_id']][r['relative_path']].decode(errors='replace').splitlines()
  line=int(r['canonical_line']);assert body[line-1].strip()==r['anchor'],r
  assert r['anchor'] in [x.strip() for x in orig[r['relative_path']].decode(errors='replace').splitlines()],r
  assert r['explanation'].strip(),r
  annotated=(OUT/r['experiment_id']/'source'/r['relative_path']).read_bytes()
  assert f"[READ-{int(r['note']):02d}]".encode() in annotated,r
 # The dormant preprocessing helper must not imply that P0 executes P1 fill.
 for d in range(3):
  helper=OUT/f'P0_M1_D{d}'/'source/Utils/fApplyUnifiedMissingDataPreprocessing.m'
  assert helper.is_file(),helper
  helper_rows=[r for r in rows if r['experiment_id']==f'P0_M1_D{d}'
               and r['relative_path']=='Utils/fApplyUnifiedMissingDataPreprocessing.m']
  assert any('P0 b01 never calls it' in r['why'] for r in helper_rows),helper
 for p in (OUT/'shared_engineering').rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(OUT/'shared_engineering');body,header=strip(p.read_bytes())
  assert body==(ROOT/rel).read_bytes(),rel
  assert b'[PKG]' in header and b'%>>>' in header
  assert b'Reason / design need:' in header,rel
  assert b'Result / boundary:' in header,rel
  assert b'Implementation in this exact block:' in header,rel
  assert b'Canonical file purpose: #!' not in header,rel
 for p in (ROOT/'cmc_acquisition').rglob('*'):
  if p.is_file() and p.suffix in SUFFIX:
   assert (OUT/'shared_engineering'/p.relative_to(ROOT)).is_file(),p
 print('PMD_ANNOTATION_'+mode.upper()+'_OK',len(ids),len(bodies),len(rows))
