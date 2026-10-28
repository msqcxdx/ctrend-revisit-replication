function analyze_e10_holding(sRunRoot,sOutput)
% E10: all fixed-member, nonoverlapping 1--6-week cohort phases.
% This reads an accepted M1 run without changing its DATA, source or results.
% One comparator repeats formation caps for fixed members (a proxy); another
% calls the actual original sorter every week on repeated signals/caps, as
% original b17 does. Both use M1 signals and payoffs, so neither re-estimates
% the original M0 predictive model. Their names deliberately remain distinct.
arguments
    sRunRoot (1,:) char
    sOutput (1,:) char
end
assert(isfile(fullfile(sRunRoot,'RUN_COMPLETE')), ...
    'E10 requires a completed accepted M1 run');
sResult = fullfile(sRunRoot,'results');
if ~isfolder(sResult)
    sResult = fullfile(sRunRoot,'results.staging');
end
sEngine = fullfile(sRunRoot,'runtime','cttrend_corrected_pipeline');
sData = fullfile(sRunRoot,'data');
if ~isfolder(sData)
    sData = fullfile(sRunRoot,'data.staging');
end
assert(isfolder(sEngine) && isfolder(sData) && isfolder(sResult), ...
    'E10 input run is missing source, DATA or result tree');
addpath(fullfile(sEngine,'Utils'));
S = load(fullfile(sData,'bCharacteristicsOLHC_Combo1.mat'), ...
    'rData','rMetaData');
C = load(fullfile(sResult,'CTREND','CTREND_Base.mat'), ...
    'mYhat','vDates','vAssetID','cResults');
assert(isequal(C.vAssetID(:),S.rMetaData.vID(:)), ...
    'E10 asset identity and order disagree');
rData = S.rData;
vAllDates = rData.yrmoda(:);
lSample = vAllDates >= 201416 & vAllDates <= 202222;
vDates = vAllDates(lSample);
assert(isequal(vDates,C.vDates(:)) && ...
    size(C.mYhat,2)==numel(vDates),'E10 week axes disagree');
mPnl = double(rData.mPnlReturns(lSample,:))';
mME = double(rData.mME);
mClose = double(rData.mClose);
mMELag = [NaN(1,size(mME,2));mME(1:end-1,:)];
mCloseLag = [NaN(1,size(mClose,2));mClose(1:end-1,:)];
mMELag = mMELag(lSample,:);
mCloseLag = mCloseLag(lSample,:);
lRemove = ~isfinite(mMELag) | ~isfinite(mCloseLag) | ...
    mMELag <= 0 | mMELag < 1e6 | mCloseLag < 0;
lRemove = lRemove | repmat(logical(S.rMetaData.lIsStable(:)'), ...
    size(lRemove,1),1);
mMELag(lRemove) = NaN;
mSort = double(C.mYhat);
mSort(:,1:min(52,size(mSort,2))) = NaN;
[~,rLedger,vLedgerWeekRow] = fAttachEconomicLedgerOptions( ...
    struct(),[sData,filesep],rData,S.rMetaData.vID(:),vDates,'ordinary');
assert(size(mPnl,2)==numel(vDates) && ...
    isequal(size(mSort),size(mPnl)) && ...
    isequal(size(mMELag'),size(mPnl)), ...
    'E10 arrays must share asset-week axes');
vQuantiles = 0:0.2:1;
nRows = 0;
for H = 1:6
    for phase = 1:H
        nRows = nRows+numel(vDates)-phase+1;
    end
end
cNames = {'year_week','holding_weeks','phase','cohort_formation_week', ...
    'fixed_cohort_hl_return','legacy_style_repeated_cap_hl_return', ...
    'published_repeated_signal_sort_hl_return', ...
    'formation_valid','payoff_complete','exit_holding_count', ...
    'reinvestment_event_count','no_recipient','partial_tail_block'};
R = table('Size',[nRows,numel(cNames)], ...
    'VariableTypes',repmat({'double'},1,numel(cNames)), ...
    'VariableNames',cNames);
iRow = 0;
sAssets=strrep(sOutput,'_weekly_holding.csv','_cohort_asset_weights.csv');
sTrades=strrep(sOutput,'_weekly_holding.csv','_cohort_reinvestment_trades.csv');
iAssets=fopen(sAssets,'w');iTrades=fopen(sTrades,'w');
assert(iAssets>0 && iTrades>0,'E10 cannot create isolated audit output');
cAssetClose=onCleanup(@()fclose(iAssets));cTradeClose=onCleanup(@()fclose(iTrades));
fprintf(iAssets,'holding_weeks,phase,cohort_formation_week,year_week,cmcid,low_opening_weight,high_opening_weight,low_end_weight,high_end_weight,payoff_complete\n');
fprintf(iTrades,'holding_weeks,phase,cohort_formation_week,year_week,leg,event_date,cmcid,signed_trade_value,price,payoff_complete\n');
for H = 1:6
    for phase = 1:H
        t = phase:numel(vDates);
        iFirst = find(any(isfinite(mSort(:,t)),1),1,'first');
        if isempty(iFirst)
            iFirst = numel(t)+1;
        end
        [vFixed,rCoverage] = fExtendedHoldingPeriodVW( ...
            mSort(:,t),mPnl(:,t),mMELag(t,:)', ...
            vQuantiles,H,iFirst,25,5,rLedger,vLedgerWeekRow(t));
        [vObserved,rObserved]=fE10HoldingObserved(mSort(:,t),mPnl(:,t), ...
            mMELag(t,:)',vQuantiles,H,iFirst,25,5,rLedger,vLedgerWeekRow(t));
        assert(isequaln(vFixed,vObserved),'E10 audit instrumentation altered returns');
        vLegacy = iLegacyRepeatedCap(mSort(:,t),mPnl(:,t), ...
            mMELag(t,:)',H,vQuantiles);
        % Reproduce the actual b17 convention: repeat the original block's
        % signal/cap, but let original fSingleSortMulti run again EACH week.
        % Unlike a fixed cohort, missing payoffs can change quantile cutoffs
        % and even move surviving assets between groups. This distinction
        % must not be hidden in a supposedly "fixed-members" comparator.
        vStart=1:H:numel(t);
        vLength=diff([vStart,numel(t)+1]);
        mRepeatSort=repelem(mSort(:,t(vStart))',vLength,1)';
        mRepeatCap=repelem(mMELag(t(vStart),:),vLength,1)';
        rLegacyOptions=struct('sFreq','weekly','lHedgeOnly',false, ...
            'iMinNumCS',25,'iMinNumAssets',5,'lEnsureAllObs',true);
        rPublished=fE10PublishedSingleSort(mRepeatSort,mPnl(:,t), ...
            vQuantiles,[],mRepeatCap,rLegacyOptions);
        vPublished=rPublished.VW.mPortRet(end,:)';
        for j = 1:numel(t)
            iRow = iRow+1;
            R.year_week(iRow,1) = vDates(t(j));
            R.holding_weeks(iRow,1) = H;
            R.phase(iRow,1) = phase;
            R.cohort_formation_week(iRow,1) = vDates(t(vStart(ceil(j/H))));
            R.fixed_cohort_hl_return(iRow,1) = vFixed(j);
            R.legacy_style_repeated_cap_hl_return(iRow,1) = vLegacy(j);
            R.published_repeated_signal_sort_hl_return(iRow,1) = vPublished(j);
            R.formation_valid(iRow,1) = rCoverage.lFormationValid(j);
            R.payoff_complete(iRow,1) = rCoverage.lPayoffComplete(j);
            R.exit_holding_count(iRow,1) = ...
                rCoverage.vExitHoldingCount(j);
            R.reinvestment_event_count(iRow,1) = ...
                rCoverage.vReinvestmentEventCount(j);
            R.no_recipient(iRow,1) = rCoverage.lNoEligibleRecipient(j);
            R.partial_tail_block(iRow,1) = ...
                rCoverage.lPartialTailBlock(j);
            mAsset=rObserved.cObservedAssets{j};
            for a=1:size(mAsset,1)
                fprintf(iAssets,'%d,%d,%d,%d,%d,%.17g,%.17g,%.17g,%.17g,%d\n', ...
                    H,phase,R.cohort_formation_week(iRow),vDates(t(j)),mAsset(a,:),rCoverage.lPayoffComplete(j));
            end
            cTrade={rObserved.cObservedLowTrades{j},rObserved.cObservedHighTrades{j}};
            for leg=1:2
                mTrade=cTrade{leg};
                if ~isempty(mTrade) && rCoverage.lPayoffComplete(j)
                    assert(abs(sum(mTrade(:,3)))<1e-8*max(1,sum(abs(mTrade(:,3)))), ...
                        'E10 sale proceeds and recipient purchases do not balance');
                end
                for a=1:size(mTrade,1)
                    fprintf(iTrades,'%d,%d,%d,%d,%d,%d,%d,%.17g,%.17g,%d\n', ...
                        H,phase,R.cohort_formation_week(iRow),vDates(t(j)),leg,mTrade(a,:),rCoverage.lPayoffComplete(j));
                end
            end
        end
        fprintf('E10_PROGRESS H=%d phase=%d/%d finite_fixed=%d\n', ...
            H,phase,H,nnz(isfinite(vFixed)));
    end
end
lH1 = R.holding_weeks==1;
vOriginal = C.cResults.VW.mPortRet(end,:)';
vH1 = R.fixed_cohort_hl_return(lH1);
assert(isequal(isfinite(vH1),isfinite(vOriginal)) && ...
    all(abs(vH1(isfinite(vOriginal)) - ...
    vOriginal(isfinite(vOriginal))) <= 1e-10), ...
    'E10 one-week fixed cohort must equal accepted baseline');
assert(iRow==nRows,'E10 output row count mismatch');
sParent = fileparts(sOutput);
if ~isfolder(sParent)
    mkdir(sParent);
end
writetable(R,sOutput);
fprintf('E10_HOLDING_OK rows=%d H1_equal_baseline=1\n',height(R));
end

function vResult = iLegacyRepeatedCap(mSort,mRet,mCap,H,vQ)
% Legacy-style weekly reset to the *same* block-formation cap vector.
% Target-week unpriced assets are dropped and the survivors renormalized.
[~,T] = size(mSort);
vResult = NaN(T,1);
for first = 1:H:T
    last = min(first+H-1,T);
    lAvail = isfinite(mSort(:,first)) & ...
        isfinite(mCap(:,first)) & mCap(:,first)>0 & ...
        isfinite(mRet(:,first));
    if nnz(lAvail)<25
        continue
    end
    vBreak = quantile(mSort(lAvail,first),vQ,1,'Method','exact');
    % Match the fixed-cohort formation gate across ALL five groups, not
    % merely the extreme legs. No gate difference may masquerade as drift.
    validGroups=true;
    for k=1:5
        member=lAvail & mSort(:,first)<=vBreak(k+1);
        if k==1
            member=member & mSort(:,first)>=vBreak(k);
        else
            member=member & mSort(:,first)>vBreak(k);
        end
        validGroups=validGroups && nnz(member)>=5;
    end
    if ~validGroups, continue, end
    lLow = lAvail & mSort(:,first)>=vBreak(1) & ...
        mSort(:,first)<=vBreak(2);
    lHigh = lAvail & mSort(:,first)>vBreak(end-1) & ...
        mSort(:,first)<=vBreak(end);
    if nnz(lLow)<5 || nnz(lHigh)<5
        continue
    end
    vCap = mCap(:,first);
    for t = first:last
        a = lLow & isfinite(mRet(:,t));
        b = lHigh & isfinite(mRet(:,t));
        if nnz(a)<5 || nnz(b)<5
            continue
        end
        rLow = sum(vCap(a).*mRet(a,t))/sum(vCap(a));
        rHigh = sum(vCap(b).*mRet(b,t))/sum(vCap(b));
        vResult(t) = rHigh-rLow;
    end
end
end
