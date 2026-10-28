#!/usr/bin/env python3
"""Materialize observation-only copies of accepted holding/reinvestment helpers.

Only function names, logging fields and audit arrays are added. No arithmetic
assignment of the production ledger is removed or changed. The caller compares
every output return against the uninstrumented helper before exporting flows.
The source/destination hashes and exact added blocks are saved for inspection.
"""
import json
from pathlib import Path
from run_e06_upstream_hybrids import ROOT,REPO,sha


def replace(text,old,new):
    if text.count(old)!=1:raise ValueError('Audit insertion anchor not unique: '+old)
    return text.replace(old,new)


def prepare():
    source=REPO/'engines/M1/base/Utils';out=ROOT/'outputs/E10/reference_sort';out.mkdir(exist_ok=True)
    p=source/'fApplySameLegReinvestment.m';s=p.read_text()
    s=replace(s,'    fApplySameLegReinvestment( ...','    fE10ReinvestmentObserved( ...')
    s=replace(s,'lNoRecipient = false(1,iNumObs);','lNoRecipient = false(1,iNumObs);\ncObservedTransactions=cell(iNumObs,1);')
    anchor='        vDollar(lExit) = 0;'
    s=replace(s,anchor,"""        % E10 observer: transaction dollars per unit of week-opening LEG capital.
        vRows=find(lExit);
        for iAudit=reshape(vRows,1,[])
            cObservedTransactions{iIdxT}(end+1,:)=[rLedger.vEventDate(iEventRow), ...
                rLedger.vAssetID(iAudit),-vDollar(iAudit),vEventPrice(iAudit)];
        end
"""+anchor)
    anchor='            vDollar = vDollar + ...'
    s=replace(s,anchor,"""            % Observer only: preserve the original vDollar addition below.
            vBuyAudit=dProceeds*(vRecipientWeight/dRecipientTotal);
            for iAudit=reshape(find(vBuyAudit>0),1,[])
                cObservedTransactions{iIdxT}(end+1,:)=[rLedger.vEventDate(iEventRow), ...
                    rLedger.vAssetID(iAudit),vBuyAudit(iAudit),vEventPrice(iAudit)];
            end
"""+anchor)
    s=replace(s,'rAudit = struct();','rAudit = struct();\nrAudit.cObservedTransactions=cObservedTransactions;')
    target=out/'fE10ReinvestmentObserved.m';target.write_text(s)
    entries=[dict(source=str(p.relative_to(REPO)),source_sha256=sha(p),output_sha256=sha(target))]
    p=source/'fExtendedHoldingPeriodVW.m';s=p.read_text()
    s=replace(s,'function [vHedgeRet,rCoverage] = fExtendedHoldingPeriodVW( ...',
                'function [vHedgeRet,rCoverage] = fE10HoldingObserved( ...')
    if s.count('fApplySameLegReinvestment(')!=2:raise ValueError('Expected two leg calls')
    s=s.replace('fApplySameLegReinvestment(','fE10ReinvestmentObserved(')
    s=replace(s,'rCoverage.lPartialTailBlock = false(iNumObs,1);',
        'rCoverage.lPartialTailBlock = false(iNumObs,1);\n'+
        'rCoverage.cObservedAssets=cell(iNumObs,1);\n'+
        'rCoverage.cObservedLowTrades=cell(iNumObs,1);\n'+
        'rCoverage.cObservedHighTrades=cell(iNumObs,1);')
    anchor='        rCoverage.vExitHoldingCount(iIdxT) = ...'
    s=replace(s,anchor,"""        % E10 observer: record original-member weights before/after this week.
        vAuditAsset=find(vWtsLow>0 | vWtsHigh>0);
        rCoverage.cObservedAssets{iIdxT}=[rLedger.vAssetID(vAuditAsset), ...
            vWtsLow(vAuditAsset),vWtsHigh(vAuditAsset), ...
            vEndLow(vAuditAsset),vEndHigh(vAuditAsset)];
        rCoverage.cObservedLowTrades{iIdxT}=rAuditLow.cObservedTransactions{1};
        rCoverage.cObservedHighTrades{iIdxT}=rAuditHigh.cObservedTransactions{1};
"""+anchor)
    target=out/'fE10HoldingObserved.m';target.write_text(s)
    entries.append(dict(source=str(p.relative_to(REPO)),source_sha256=sha(p),output_sha256=sha(target)))
    (out/'AUDIT_HELPERS_MANIFEST.json').write_text(json.dumps(entries,indent=2)+'\n')


if __name__=='__main__':prepare()
