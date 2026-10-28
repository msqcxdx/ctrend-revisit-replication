#!/usr/bin/env python3
# CTREND_REVISIT_FILE_PURPOSE: Generate eighteen byte-exact review mirrors with P/M/D lineage and exhaustive changed-block annotations.
"""Create all 18 review mirrors with a byte-exact body and every diff opcode.

The percent-sign hierarchy follows the earlier release. Each block records
its immediate parent, owner, exact line range, defect/convention, replacement
and scientific effect. Production never imports a review mirror.
"""
from pathlib import Path
import ast,csv,hashlib,importlib.util,shutil,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('v4',ROOT/'scripts/build_annotated_source_mirrors.py')
v4=importlib.util.module_from_spec(spec);spec.loader.exec_module(v4)
OUT=ROOT/'annotated_sources'
BEGIN='CTREND_REVISIT_ANNOTATION_HEADER_V4_BEGIN'
END='CTREND_REVISIT_ANNOTATION_HEADER_V4_END'

# Ordinary reading notes explain selected, unchanged Dataverse code.  They are
# deliberately separate from the change annotations below: a line is eligible
# only when the exact anchor also occurs in the immutable Dataverse file.
# This makes it impossible to present a repaired line as ordinary inherited
# code merely because it happens to look familiar.
ORDINARY_GUIDES = {
    'Utils/characteristics.m': [
        ('classdef characteristics', 'This class groups the daily cross-sectional characteristics; construction stores aligned inputs, while individual methods derive one characteristic family.'),
        ('methods', 'The methods block is the ordinary calculation surface. Review %%/%>>> entries separately wherever a formula or support rule changed.'),
    ],
    'Utils/technical_indicators.m': [
        ('classdef technical_indicators', 'This class owns the OHLCV technical-indicator formulas. Its input matrices share the same date-by-asset axes.'),
        ('methods', 'Each method returns a date-by-asset indicator matrix; unchanged methods retain the Dataverse calculation unless a %% change group says otherwise.'),
    ],
    'Utils/fResampleDay2Week.m': [
        ('function', 'This helper converts daily observations to the requested weekly aggregation; callers determine which economic or statistical layer is supplied.'),
    ],
    'Utils/fPanel2Matrix.m': [
        ('function', 'This is a shape conversion helper: panel rows are mapped back to a date-by-asset matrix without defining portfolio membership.'),
    ],
    'Utils/fCreateIndices.m': [
        ('function', 'This helper creates date/asset index arrays used to preserve panel identity through estimation and prediction.'),
    ],
    'Utils/fSingleSortMulti.m': [
        ('function', 'This is the central univariate-sort consumer. Quantile assignment, leg returns, hedge construction and reporting are distinct stages inside the function.'),
    ],
    'Utils/fWalkforwardCSENET.m': [
        ('function', 'This walk-forward entry point maps historical panels into out-of-sample forecasts; its unchanged arguments define the stable caller contract.'),
    ],
    'Utils/fWalkforwardCENET.m': [
        ('function', 'This walk-forward entry point is the combined elastic-net path; the function signature preserves the identity of inputs and returned forecasts.'),
    ],
    'b01ReadData.m': [
        ('clear;', 'The data stage starts from a clean MATLAB workspace before loading and aligning the raw daily matrices.'),
        ('mReturns = [NaN', 'Daily close-to-close returns are formed only after the price matrices have been aligned; method-specific changes are marked separately.'),
    ],
    'b02CalculateIndicators.m': [
        ("load('DATA/b0DataOLHC.mat')", 'The indicator stage consumes the sealed b01 checkpoint rather than reopening raw CSV inputs.'),
    ],
    'b05CreateCTREND.m': [
        ('clear;', 'The CTREND stage reloads its declared weekly checkpoint and does not inherit interactive workspace variables.'),
    ],
    'b06Table3_UnivariatePortfolioSorts.m': [
        ('clear;', 'The Table 3/Figure 1 stage begins from saved CTREND outputs; it is a downstream consumer rather than a model-training entry point.'),
    ],
}

# These one-percent notes are deliberately modest: they orient a reader inside
# inherited author code, while the two/three/four-percent layers remain reserved
# for modifications and lineage.  Every anchor is checked against both the
# materialized experiment and the immutable Dataverse source before emission.
STAGE_READ_GUIDES = {
    'b00GenerateDesignChoices.m': 'This stage enumerates the research-design grid consumed downstream; it does not estimate CTREND.',
    'b02CalculateIndicators.m': 'This stage creates weekly returns, characteristics and technical indicators used by later estimation and sorts.',
    'b03Table1_ResearchSample.m': 'This reporting stage summarizes the screened research sample and does not train a forecasting model.',
    'b04Table2_TechnicalIndicatorStrategyReturns.m': 'This stage evaluates the stand-alone technical-indicator strategies used in Table 2.',
    'b05CreateCTREND.m': 'This stage estimates the headline CTREND signal from the saved predictor and target panels.',
    'b06Table3_UnivariatePortfolioSorts.m': 'This stage maps saved characteristics into univariate portfolios and headline factor returns.',
    'b07Table4_CrossSectionalRegressions.m': 'This stage runs the cross-sectional regressions after CTREND has already been constructed.',
    'b08Table5_PerformanceInSubperiodsAndDifferentMarketStates.m': 'This stage partitions saved factor performance by subperiod and market state.',
    'b09RunResearchDesigns.m': 'This stage evaluates the frozen research-design combinations; it is the expensive design-grid computation.',
    'b10Table6_FactorPerformanceAcrossResearchDesignChoices.m': 'This stage summarizes completed b09 design cells rather than re-estimating them.',
    'b11Figure3_AnomalyAlphas.m': 'This stage evaluates anomaly-portfolio pricing errors using already constructed factors.',
    'b12Table7_FrontierExpansionTest.m': 'This stage performs the mean-variance spanning test on saved return series.',
    'b13Table8_TheCTRENDFactorPerformanceInBigAndLiquidCryptos.m': 'This stage applies the author-defined large/liquid-asset robustness universe.',
    'b14Table9_CTRENDPortfoliosAndTransactionCosts.m': 'This stage applies the author-defined turnover and transaction-cost analysis.',
    'b15TableB3_BivariatePortfolioSorts.m': 'This stage forms the appendix bivariate portfolios from saved characteristics.',
    'b16TableB4_CTRENDPerformanceDependingOnCryptocurrencyType.m': 'This stage reports CTREND performance by the saved cryptocurrency-type labels.',
    'b17TableB10_ExtendedPortfolioHoldingPeriod.m': 'This stage evaluates longer holding periods from the saved formation signals.',
    'b18FigureC3_C4_AverageVariableImportance.m': 'This stage aggregates saved elastic-net importance measures for the appendix figures.',
}
for _file, _explanation in STAGE_READ_GUIDES.items():
    ORDINARY_GUIDES.setdefault(_file, []).insert(
        0, ('clear; clc; close all;', _explanation))

ORDINARY_GUIDES.update({
    'Utils/fCreatePanelFast.m': [
        ('function', 'This unchanged helper converts aligned matrices into a long panel while retaining date and asset identity.'),
    ],
    'Utils/fRemoveOutlier.m': [
        ('function', 'This unchanged entry routes the requested author outlier convention; method-specific changes to its inputs are annotated separately.'),
    ],
    'Utils/fWinsorize.m': [
        ('function', 'This helper implements the author winsorization operator on the array supplied by its caller.'),
    ],
    'Utils/fTruncate.m': [
        ('function', 'This helper implements the author truncation operator on the array supplied by its caller.'),
    ],
    'Utils/fAnalyzeReturns.m': [
        ('function', 'This reporting helper converts a supplied return series into performance statistics; it does not choose the investable universe.'),
    ],
    'Utils/fEvaluateResearchDesigns.m': [
        ('function', 'This helper summarizes completed design-level factor returns; it does not construct the upstream predictors.'),
    ],
})
def sha(x):return hashlib.sha256(x).hexdigest()
def source(p,m,d,dest):
    if p==0:
        subprocess.run([str(ROOT/'p0_extension/scripts/materialize_experiment_source.sh'),
            f'P0_M{m}_D{d}',str(dest)],check=True,stdout=subprocess.DEVNULL)
    else:v4.copy_materialized_source(ROOT,f'M{m}',f'D{d}',dest)
def manifest(root,name):
    paths=sorted(p for p in root.rglob('*') if p.is_file() and p.name!=name and '__pycache__' not in p.parts)
    (root/name).write_text(''.join(f'{sha(p.read_bytes())}  {p.relative_to(root)}\n' for p in paths))
def lookup(tree,rel):
    p=tree/rel
    return p.read_bytes() if p.is_file() else None


def shared_file_purpose(path,body):
    """Extract one concise purpose without dumping shebangs or partial headers."""
    text=body.decode(errors='replace')
    for line in text.splitlines()[:30]:
        if 'CTREND_REVISIT_FILE_PURPOSE:' in line:
            return line.split('CTREND_REVISIT_FILE_PURPOSE:',1)[1].strip()
    if path.suffix=='.py':
        try:
            doc=ast.get_docstring(ast.parse(text),clean=True)
        except SyntaxError:
            doc=None
        if doc:
            return ' '.join(doc.split('\n\n',1)[0].split())
    comment_prefixes=('%','#','REM ')
    for line in text.splitlines()[:30]:
        stripped=line.strip()
        if not stripped or stripped.startswith('#!'):
            continue
        if stripped.startswith(comment_prefixes):
            value=stripped.lstrip('%#').strip()
            if value.upper().startswith('REM '):value=value[4:].strip()
            if value:return value
    return f'Package engineering file {path.as_posix()}; inspect its canonical body and callers for the exact role.'
def reason(p,method,d,rel,new,old,stage,owner):
    if rel.name=='b02CalculateIndicators.m' and method=='M2':
        cat,why,effect=v4.reason_for(method,f'D{d}',str(rel),new.decode(errors='replace').splitlines(),old.decode(errors='replace').splitlines() if old is not None else [],stage,old is not None)
        return (cat,why+' Volume cleaning is held equal to the same-P M0 parent: P0 maps volume <= 1e-6 (including zero) to NaN and preserves the original all-zero-row and zero/nonzero-return rules; P1 preserves explicit zero and screens only small positive volume. This P convention is not a look-ahead correction.',effect+' Zero and missing have different meanings for volume indicators and support; no blanket zero-preservation rule is transferred from P1 into P0.')
    if method=='M2' and rel.name=='b01ReadData.m':
        return ('raw-endpoint-layer','Retain raw prices and volume before the published outlier/synchronization path so formation eligibility and terminal settlement need not use future cleaned-return availability. P0 does not invoke the optional common fill.','M2 retains the published feature/outlier path while adding a separately stored economic endpoint layer for the declared exit/reinvestment convention.')
    if owner=='P':return ('preprocessing-sensitivity',
        'P0 leaves original missing cells; P1 fills internal OHLC from a strictly earlier valid close and invalid volume/turnover with zero. It also preserves those explicit zeros in downstream synchronization.',
        'An explicit P-axis convention, not a correction silently attributed to M. Leading and post-terminal prices stay missing.')
    if owner=='D':return ('whole-history-universe-sensitivity',
        'Apply the frozen CMCID exclusion list before market aggregates, screening, features, ranks and training. D1 removes 3787; D2 additionally removes the event-asset set.',
        'Changes the data-universe estimand. No individual price is adjusted; different IDs are not spliced.')
    if p == 0 and rel.name=='fApplyUnifiedMissingDataPreprocessing.m' and old is None:
        return ('inactive-preprocessing-helper',
            'The helper is distributed in this source tree for a uniform package interface, but P0 b01 never calls it. P0 therefore performs no unified OHLC forward fill; its volume convention is enforced separately in b01/b02.',
            'No P0 array is transformed merely because this dormant helper is present. P1, not M1/M2, owns activation of the common preprocessing rule.')
    if (method in ('M1','M2') and
            rel.name=='fBuildAndFreezeMechanicalExitCalendar.m' and old is None):
        return ('pre-model-mechanical-exit-calendar',
            f'{method} needs one immutable replacement for unavailable listing announcements before any model or portfolio stage. This helper records each asset\'s final positive close/date and distinguishes sample-end right censoring from an earlier terminal exit.',
            'The frozen calendar supplies settlement timing only: it does not alter predictors, historical estimation labels, formation ranks, or raw endpoint prices, and M0 does not inherit this accounting rule.')
    if method=='M2' and str(rel) not in v4.M2_REASONS and old is None:
        if rel.name=='fApplyUnifiedMissingDataPreprocessing.m':
            return ('inactive-preprocessing-helper','This helper is distributed with the shared current engine but P0 b01 does not call it. Only P1 enables its strictly backward OHLC fill and zero-volume rule.','No P0 array is filled by the presence of an unused function; do not count this as an M2 scientific repair.')
        return v4.default_added_reason(str(rel))
    cat,why,effect=v4.reason_for(method,f'D{d}',str(rel),new.decode(errors='replace').splitlines(),
        old.decode(errors='replace').splitlines() if old is not None else [],stage,old is not None)
    if method=='M0' and rel.name=='b01ReadData.m':
        return ('published-runability','Repair case-sensitive Utils lookup and raw input routing; the P0 parent does not fill prices or replace its scientific return/screen definitions.','Runability and publication adapters only. P1 changes are documented in the separate P lineage step.')
    if method=='M0' and rel.name=='b02CalculateIndicators.m':
        return ('equivalence-gated-parallelism','Select the empirical input and schedule asset-separable published calculations in chunks; preserve the original column order, formulas and outlier/synchronization path.','The P0 M0 scientific baseline is preserved; common zero-volume preservation belongs to the separate P1 step.')
    return cat,why,effect


def block_note(rel,r):
    """Explain the local operation without pretending a file-level rationale is line-specific."""
    # Inspect the complete opcode, never a truncated excerpt or neighboring
    # comment. A large calculation block can contain fprintf/save/rank without
    # being merely diagnostic, persistence, or predictor-ranking code.
    new=r.get('target_block',r.get('target_excerpt',''))
    if rel.name=='b02CalculateIndicators.m' and 'fComputeCharacteristicChunk(' in new:
        return ('Computes characteristic matrices in asset-column chunks, merges them in '
                'original order, and retains shared market inputs. The block includes '
                'calculation and scheduling; its progress message is not its only effect.')
    if rel.name=='b02CalculateIndicators.m' and 'fComputeTechnicalIndicatorChunk(' in new:
        return ('Computes OHLCV technical indicators for each asset chunk using the '
                'declared M1 formulas; progress printing is part of this calculation block.')
    if rel.name=='characteristics.m' and 'mAge = cumsum(isfinite(self.mReturns),1)' in new:
        return ('Counts days with observed returns rather than observed closes for asset age. '
                'A listing-day or post-gap close without a calculable return no longer '
                'increments age; this changes the characteristic, not just NaN/Inf handling.')
    # Source comments inside the changed block supply local rationale without
    # attributing a keyword's meaning to all statements in that block.
    comments=[line.strip().lstrip('%').strip() for line in new.splitlines()
              if line.strip().startswith('%')]
    comment_note=(' Local source explanation: '+' '.join(comments[:5])) if comments else ''
    def short(value):
        value=' '.join(value.split())
        return value if len(value)<=135 else value[:132]+'...'
    context=(' in the canonical section "'+short(r['context'])+'"') if r.get('context') else ''
    op=r['operation']
    old_excerpt=short(r.get('reference_excerpt',''))
    new_excerpt=short(r.get('target_excerpt',''))
    # SequenceMatcher legitimately reports blank-line-only opcodes.  Name them
    # as formatting changes instead of rendering the unreadable placeholder
    # `Adds ```, which could be mistaken for a missing annotation.
    if op=='delete' and not old_excerpt:
        return 'Removes a blank separator only; this formatting change deletes no executable statement.'
    if op in ('insert','added-file') and not new_excerpt:
        return 'Adds a blank separator only; this formatting change introduces no executable statement.'
    if op=='replace' and not old_excerpt and not new_excerpt:
        return 'Replaces whitespace only; executable source text is unchanged by this local block.'
    if op=='delete':return f'Removes `{short(r["reference_excerpt"])}`{context}; the parent line range identifies every removed statement.'
    if op in ('insert','added-file'):
        return f'Adds `{short(r["target_excerpt"])}`{context}; the enclosing %% group states the purpose and the child line range identifies the complete block.'+comment_note
    return (f'Replaces `{short(r["reference_excerpt"])}` with '
            f'`{short(r["target_excerpt"])}`{context}; OLD/NEW are abbreviated previews; '
            'the stated parent/child line ranges delimit the full change.'+comment_note)


def ordinary_notes(rel,body,original_body):
    """Return line-linked reading aids only for exact lines inherited from Dataverse."""
    if original_body is None or str(rel) not in ORDINARY_GUIDES:return []
    current=body.decode(errors='replace').splitlines()
    original=set(original_body.decode(errors='replace').splitlines())
    notes=[];used_lines=set()
    for needle,explanation in ORDINARY_GUIDES[str(rel)]:
        matches=[(i,line) for i,line in enumerate(current,1) if needle in line and line in original]
        if not matches:continue
        line,text=matches[0]
        if line in used_lines:continue
        used_lines.add(line)
        notes.append(dict(line=line,anchor=text.strip(),explanation=explanation))
    return notes

def main():
    # Review output is reproducible; only this generated directory is replaced.
    if OUT.exists():shutil.rmtree(OUT)
    OUT.mkdir();index=[];bodies=[];ordinary_index=[]
    with tempfile.TemporaryDirectory(prefix='cttrend_pmd_annotations_') as tmp:
      temp=Path(tmp);trees={}
      for p in range(2):
       for m in range(3):
        for d in range(3):
         id=f'P{p}_M{m}_D{d}';tree=temp/id;source(p,m,d,tree);trees[id]=tree
      original=ROOT/'reference/dataverse_original_3d0959b1'
      for id,tree in trees.items():
        p,m,d=[int(x[1:]) for x in id.split('_')]
        target=OUT/id/'source';shutil.copytree(tree,target)
        # Compare the actual scientific branch to its same-D M0 parent. The
        # separate P0->P1 chain prevents preprocessing from being called M1-only.
        chain=[('Dataverse','P0_M0_D0',original,trees['P0_M0_D0'],'M0','dataverse-to-m0')]
        if d:chain.append(('P0_M0_D0',f'P0_M0_D{d}',trees['P0_M0_D0'],trees[f'P0_M0_D{d}'],'D','dataverse-to-m0'))
        if p:chain.append((f'P0_M0_D{d}',f'P1_M0_D{d}',trees[f'P0_M0_D{d}'],trees[f'P1_M0_D{d}'],'P','dataverse-to-m0'))
        if m:chain.append((f'P{p}_M0_D{d}',id,trees[f'P{p}_M0_D{d}'],tree,f'M{m}',f'm0-to-m{m}'))
        deleted=[]
        for rel in sorted(set(x.relative_to(t) for _,_,t,u,_,_ in chain for x in t.rglob('*') if x.is_file())):
            if not (tree/rel).exists() and rel.suffix in v4.TEXT_SUFFIXES:deleted.append(str(rel))
        (OUT/id/'DELETED_FILES.md').write_text('# Files absent from this scientific branch\n\n'+
            '\n'.join(f'- `{x}`' for x in deleted)+'\n')
        for reltext in deleted:
          rel=Path(reltext)
          for from_id,to_id,oldtree,newtree,owner,stage in chain:
            old,new=lookup(oldtree,rel),lookup(newtree,rel)
            if old==new:continue
            new=new or b''
            cat,why,effect=reason(p,f'M{m}' if owner not in ('M0','P','D') else 'M0',d,rel,new,old,stage,owner)
            for n,r in enumerate(v4.diff_rows('M0','D0',str(rel),new,old,stage=stage,reference_name=from_id,target_name=to_id),1):
              local_note=('Adds the helper to the packaged source tree, but P0 b01 does not call it; therefore this block does not apply common OHLC/volume filling to P0 data.'
                  if cat=='inactive-preprocessing-helper' else block_note(rel,r))
              index.append(dict(experiment_id=id,section='source-deletion',relative_path=str(rel),block=n,owner=owner,
                from_id=from_id,to_id=to_id,operation=r['operation'],parent_lines=r['reference_lines'],
                child_lines=r['target_lines'],why=why,scientific_effect=effect,block_note=local_note,
                parent_sha256=r['reference_sha256'],child_sha256=r['target_sha256'],final_body_sha256='ABSENT'))
        for file in sorted(target.rglob('*')):
          if not file.is_file() or file.suffix not in v4.TEXT_SUFFIXES:continue
          rel=file.relative_to(target);body=file.read_bytes();rows=[]
          for from_id,to_id,oldtree,newtree,owner,stage in chain:
            old=lookup(oldtree,rel);new=lookup(newtree,rel)
            if old==new:continue
            if new is None:new=b''
            dr=v4.diff_rows('M0','D0',str(rel),new,old,
                stage=stage,reference_name=from_id,target_name=to_id)
            cat,why,effect=reason(p,f'M{m}' if owner not in ('M0','P','D') else 'M0',d,rel,new,old,stage,owner)
            for r in dr:
                local_note=('Adds the helper to the packaged source tree, but P0 b01 does not call it; therefore this block does not apply common OHLC/volume filling to P0 data.'
                    if cat=='inactive-preprocessing-helper' else block_note(rel,r))
                r.update(owner=owner,category=cat,why=why,scientific_effect=effect,
                    block_note=local_note,from_id=from_id,to_id=to_id)
            rows.extend(dr)
          prefix=v4.comment_prefix(file)
          def comment(level,text):
            mark=v4.hierarchy_marker(prefix,level)
            return '\n'.join(v4.textwrap.wrap(text,width=110,initial_indent=mark+' ',subsequent_indent=mark+' ',break_long_words=False,break_on_hyphens=False))+'\n'
          header=comment(4,BEGIN)+comment(4,f'{id} | source/{rel} | REVIEW ONLY; body below is byte-identical to production materialization.')
          header+=comment(4,'%%%% reading guide; %%% parent-to-child lineage; %% owner plus reason and resulting boundary; %>>> exact implementation block; % [READ] ordinary explanation of an unchanged Dataverse line. Parent line numbers and final-body line numbers are not interchangeable.')
          notes=ordinary_notes(rel,body,lookup(original,rel))
          for note_number,note in enumerate(notes,1):
            mark=v4.hierarchy_marker(prefix,1)
            header+='\n'.join(v4.textwrap.wrap(
                f"[READ-{note_number:02d}] Unchanged canonical line {note['line']} ({note['anchor']}): {note['explanation']}",
                width=110,initial_indent=mark+' ',subsequent_indent=mark+' ',
                break_long_words=False,break_on_hyphens=False))+'\n'
            ordinary_index.append(dict(experiment_id=id,relative_path=str(rel),
                note=note_number,canonical_line=note['line'],anchor=note['anchor'],
                explanation=note['explanation'],canonical_sha256=sha(body),
                dataverse_sha256=sha(lookup(original,rel))))
          for n,r in enumerate(rows,1):
            header+=comment(3,f"{r['from_id']} -> {r['to_id']}")
            header+=comment(2,f"[{r['owner']}] {r['category']}")
            header+=comment(2,'Reason / design need: '+r['why'])
            header+=comment(2,'Result / boundary: '+r['scientific_effect'])
            mark=v4.hierarchy_marker(prefix,1,detail=True)
            header+=f"{mark} Block {n}: {r['operation']}; parent {r['reference_lines']} -> child {r['target_lines']}.\n"
            header+=comment(1,'Implementation in this exact block: '+r['block_note'])
            # Entire added-file bodies are one declared block. Existing files
            # get every exact SequenceMatcher opcode, including deletions.
            for tag,key in [('OLD','reference_excerpt'),('NEW','target_excerpt')]:
                header+=comment(1,f'{tag}: {r[key] or "<empty>"}')
            index.append(dict(experiment_id=id,section='source',relative_path=str(rel),block=n,owner=r['owner'],
                from_id=r['from_id'],to_id=r['to_id'],operation=r['operation'],parent_lines=r['reference_lines'],
                child_lines=r['target_lines'],why=r['why'],scientific_effect=r['scientific_effect'],
                block_note=r['block_note'],
                parent_sha256=r['reference_sha256'],child_sha256=r['target_sha256'],final_body_sha256=sha(body)))
          if not rows:header+=comment(4,'No changed block in this file along the declared lineage. Original comments are retained.')
          header+=comment(4,END)
          # Keep interpreter shebang first while preserving exact removable bytes.
          if body.startswith(b'#!'):
              first,rest=body.split(b'\n',1);newbody=first+b'\n'+header.encode()+rest
          else:newbody=header.encode()+body
          file.write_bytes(newbody)
          bodies.append(dict(experiment_id=id,relative_path=str(rel),canonical_sha256=sha(body),annotated_sha256=sha(newbody),blocks=len(rows)))
        (OUT/id/'EXPERIMENT_ANNOTATION.md').write_text(f'# {id}: comment-only review copy\n\nRead the percent-sign legend in ../README.md. Scientific code is in source/. The runnable entry is `./run_all.sh experiment {id} production`. Shared orchestration is described and annotated once under ../../scripts and ../../engines/M*/runner; it does not redefine the estimator.\n')
        manifest(OUT/id,'ANNOTATED_FILES.sha256')
    # Shared package engineering is new relative to the author archive; review
    # it once, not eighteen slightly diverging copies. It never enters b01-b18.
    shared_paths=[]
    for parent in ('scripts','postprocessing','p0_extension/scripts','engines/M0/runner','engines/M1/runner','engines/M2/runner','analysis','cmc_acquisition','release','environment','config'):
      shared_paths.extend((ROOT/parent).rglob('*'))
    shared_paths.extend(p for p in ROOT.iterdir() if p.is_file())
    for path in sorted(set(shared_paths)):
        if not path.is_file() or path.suffix not in v4.TEXT_SUFFIXES:continue
        rel=path.relative_to(ROOT);body=path.read_bytes();prefix=v4.comment_prefix(path)
        purpose=shared_file_purpose(rel,body)
        header=''
        for level,text in [(4,BEGIN),(4,'SHARED ENGINEERING REVIEW ONLY; not an author-source scientific modification.'),
          (3,'Dataverse: no counterpart -> shared package file'),(2,'[PKG] package-only engineering file'),
          (2,'Reason / design need: the Dataverse archive has no portable counterpart for this file. Canonical file purpose: '+purpose),
          (2,'Result / boundary: adds scheduling, entry routing, verification, acquisition, or saved-output reporting. Scientific estimators remain in the named engines; inspect explicit driver calls for scope.'),
          (1,f'Implementation in this exact block: the entire added file, lines 1-{len(body.splitlines())}; canonical SHA256 {sha(body)}.'),(4,END)]:
            mark=v4.hierarchy_marker(prefix,level,detail=(level==1))
            header+='\n'.join(v4.textwrap.wrap(text,width=110,initial_indent=mark+' ',subsequent_indent=mark+' ',break_long_words=False,break_on_hyphens=False))+'\n'
        if body.startswith(b'#!'):
            first,rest=body.split(b'\n',1);annotated=first+b'\n'+header.encode()+rest
        else:annotated=header.encode()+body
        dest=OUT/'shared_engineering'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(annotated)
    for name,rows in [('ANNOTATION_INDEX.csv',index),('BODY_IDENTITIES.csv',bodies),
                      ('ORDINARY_ANNOTATIONS.csv',ordinary_index)]:
      with (OUT/name).open('w',newline='') as f:
        w=csv.DictWriter(f,list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
    (OUT/'README.md').write_text('''# Reading the eighteen annotated scientific mirrors

Every P/M/D cell has a source/ mirror. Production never executes these copies.
The original percent-sign hierarchy is retained:

- `%%%%`: reading aids and review provenance only;
- `%%%`: the explicit parent -> child step;
- `%% [M0]`, `[M1]`, `[M2]`, `[P]`, `[D]`: who owns the change, followed by an
  explicit `Reason / design need` and `Result / boundary`;
- `%>>>`: each exact changed block, including source/target line spans and an
  `Implementation in this exact block` explanation.
- `% [READ]`: an ordinary reading aid for a specifically identified line whose
  exact text is inherited from the immutable Dataverse source. It is not a
  claimed modification and is indexed in `ORDINARY_ANNOTATIONS.csv`.

The lineage starts at Dataverse -> P0 M0, then adds D and P as appropriate,
then the same-P/same-D M0 -> M1 or M2 method changes. P0-M0 is preserved from
the accepted historical unfilled implementation, including its b02 volume
path. A P change is never silently classified as an M correction.

Every insertion/replacement/deletion opcode is indexed, with the parent and
child hashes. The file header gives full block scope; numbers refer to the
named lineage stage. BODY_IDENTITIES.csv records each final scientific body.
Each exact block also has a local explanation instead of relying only on a
repeated file-level summary.
Stripping only the marked review header reproduces materialized source bytes
exactly. New standalone helpers are annotated as complete added-file blocks.
Unmodified original comments remain original comments. Shared engineering
scripts have file-purpose headers and live once in scripts/ and engines/*/runner.
''')
    manifest(OUT,'ANNOTATED_RELEASE.sha256')
    print('PMD_ANNOTATED_MIRRORS_OK',len(trees),len(bodies),len(index))
if __name__=='__main__':main()
