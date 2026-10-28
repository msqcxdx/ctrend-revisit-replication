function test_same_leg_reinvestment(sRoot)
% CTREND_REVISIT_FILE_PURPOSE: Verify frozen terminal settlement, immediate same-leg EW/VW reinvestment, and the no-cash rule.
% Synthetic prices cover ordinary terminal exits, entry-day exits, EW and VW
% redistribution, and missing-state guards. Proceeds must be marked at the
% frozen last tradable price and immediately reinvested within the same leg;
% no post-exit cash balance or external event source is allowed.

arguments
    sRoot {mustBeTextScalar}
end
sUtils = fullfile(char(sRoot),'engines','M1','base','Utils');
addpath(sUtils);
rPathCleanup = onCleanup(@() rmpath(sUtils));

dt = datetime(2020,1,1)+caldays(0:13)';
vDates = year(dt)*10000+month(dt)*100+day(dt);
vAssetID = (1:5)';
mClose = NaN(14,5);
mClose(:,2) = linspace(14,27,14)';       % B: day 7=20, 10=23, 14=27
mClose(:,3) = [linspace(24,30,7),31:37]';% C: day 7=30, 10=33, 14=37
mClose(1:10,1) = (4:13)';               % A: day 7=10, exits day 10=13
mClose(1:7,4) = (44:50)';               % D: exits exactly at entry day 7
mClose(1:12,5) = (54:65)';              % E: day 7=60, exits day 12=65
mME = ones(size(mClose));
mME(10,2) = 100;
mME(10,3) = 300;

sTemp = tempname;
mkdir(sTemp);
rTempCleanup = onCleanup(@() rmdir(sTemp,'s'));
[tExit,~] = fBuildAndFreezeMechanicalExitCalendar( ...
    mClose,vDates,vAssetID,["A";"B";"C";"D";"E"], ...
    fullfile(sTemp,'exit.csv'));
% First prove the calendar/ledger classifies each synthetic exit as intended.
[rLedger,mPnl,~,rBuild] = fBuildWeeklyReinvestmentLedger( ...
    mClose,mME,vDates,vAssetID,tExit);
assert(rBuild.iNumWeeks == 2 && ~rLedger.lUsesExternalSource && ...
    ~rLedger.lAllowsCashAfterExit);
assert(abs(mPnl(2,1)-0.3) <= 1e-12 && ...
    abs(mPnl(2,4)) <= 1e-12 && ...
    rLedger.lOrdinaryEarlyExit(2,1) && ...
    rLedger.lOrdinaryEarlyExit(2,4));

% EW: A exits day 10.  Its entire marked proceeds are reinvested in B.
vEW = [0.5;0.5;0;0;0];
[dEW,vEndEW,dL1EW,rEWAudit] = fApplySameLegReinvestment( ...
    vEW,rLedger,2,'ordinary','EW');
dExpectedEW = (0.5*(13/10)+0.5*(23/20))*(27/23)-1;
assert(abs(dEW-dExpectedEW) <= 1e-12 && ...
    abs(dL1EW-1.3) <= 1e-12 && ...
    isequal(vEndEW > 0,[false;true;false;false;false]) && ...
    abs(sum(vEndEW)-1) <= 1e-12 && ...
    rEWAudit.vExitedHoldingCount == 1 && ...
    rEWAudit.lEndCashAlwaysZero && ~rEWAudit.lCrossLegTransfer);

% VW: released A proceeds use event-day B:C market-cap ratio 1:3.  Existing
% B/C wealth is not otherwise rebalanced.
vVW = [0.4;0.3;0.3;0;0];
[dVW,vEndVW,dL1VW,rVWAudit] = fApplySameLegReinvestment( ...
    vVW,rLedger,2,'ordinary','VW');
dA = 0.4*(13/10);
dB = 0.3*(23/20)+0.25*dA;
dC = 0.3*(33/30)+0.75*dA;
dExpectedVW = dB*(27/23)+dC*(37/33)-1;
assert(abs(dVW-dExpectedVW) <= 1e-12 && ...
    abs(dL1VW-2*dA) <= 1e-12 && ...
    abs(sum(vEndVW)-1) <= 1e-12 && ...
    rVWAudit.vExitedHoldingCount == 1 && ...
    abs(rVWAudit.vReinvestedProceeds-dA) <= 1e-12);

% Sequential EW events: A exits on day 10 and its proceeds are divided
% between the then-surviving B and E.  E exits on day 12; its complete
% marked position (initial wealth plus the day-10 reinvestment) is then
% invested in B.  This locks event ordering and prevents each event from
% being evaluated independently from stale formation weights.
vSequential = [1/3;1/3;0;0;1/3];
[dSequential,vEndSequential,dL1Sequential,rSequentialAudit] = ...
    fApplySameLegReinvestment( ...
    vSequential,rLedger,2,'ordinary','EW');
dAEvent1 = (1/3)*(13/10);
dBAfterEvent1 = (1/3)*(23/20)+0.5*dAEvent1;
dEAfterEvent1 = (1/3)*(63/60)+0.5*dAEvent1;
dBEvent2 = dBAfterEvent1*(25/23);
dEEvent2 = dEAfterEvent1*(65/63);
dExpectedSequential = (dBEvent2+dEEvent2)*(27/25)-1;
dExpectedSequentialL1 = 2*(dAEvent1+dEEvent2);
assert(abs(dSequential-dExpectedSequential) <= 1e-12 && ...
    abs(dL1Sequential-dExpectedSequentialL1) <= 1e-12 && ...
    isequal(vEndSequential > 0,[false;true;false;false;false]) && ...
    abs(sum(vEndSequential)-1) <= 1e-12 && ...
    rSequentialAudit.vEventDateCount == 2 && ...
    rSequentialAudit.vExitedHoldingCount == 2 && ...
    abs(rSequentialAudit.vReinvestedProceeds- ...
        (dAEvent1+dEEvent2)) <= 1e-12);

% A terminal quote equal to the entry date earns zero before immediate
% reinvestment; the released wealth is not parked in cash.
vEntryExit = [0;0.5;0;0.5;0];
[dEntryExit,vEndEntryExit,dEntryL1] = fApplySameLegReinvestment( ...
    vEntryExit,rLedger,2,'ordinary','EW');
assert(abs(dEntryExit-(27/20-1)) <= 1e-12 && ...
    abs(dEntryL1-1) <= 1e-12 && ...
    isequal(vEndEntryExit > 0,[false;true;false;false;false]));

% Positive proceeds without any surviving same-leg recipient fail closed;
% they are never reported as cash or transferred to another leg.
[dNoRecipient,vNoRecipient,~,rNoRecipient] = ...
    fApplySameLegReinvestment([1;0;0;0;0],rLedger,2,'ordinary','VW');
assert(isnan(dNoRecipient) && all(isnan(vNoRecipient)) && ...
    rNoRecipient.lNoEligibleRecipient);

clear rTempCleanup rPathCleanup
fprintf('SAME_LEG_REINVESTMENT_TEST_OK\n');
end
