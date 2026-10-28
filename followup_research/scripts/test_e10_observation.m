function test_e10_observation(sRepo,sHelpers)
% Verify observation-only E10 hooks on actual terminal exits, not empty logs.
% Synthetic VW proceeds must use EVENT-day capitalization, and every sale
% must be balanced by purchases of surviving members in that same leg.
addpath(fullfile(sRepo,'engines','M1','base','Utils'));
addpath(sHelpers);
dt=datetime(2020,1,1)+caldays(0:27)';
dates=year(dt)*10000+month(dt)*100+day(dt);
prices=ones(28,4);prices(15:18,4)=(1.1:.1:1.4)';prices(19:end,4)=NaN;
me=ones(size(prices));ids=(1:4)';
folder=tempname;mkdir(folder);cleanup=onCleanup(@()rmdir(folder,'s'));
[exits,~]=fBuildAndFreezeMechanicalExitCalendar(prices,dates,ids,["A";"B";"C";"D"],fullfile(folder,'exits.csv'));
[ledger,ret]=fBuildWeeklyReinvestmentLedger(prices,me,dates,ids,exits);
signal=repmat((1:4)',1,4);cap=ones(4,4);
[a,ca]=fExtendedHoldingPeriodVW(signal,ret',cap,[0;.5;1],2,1,4,1,ledger,(1:4)');
[b,cb]=fE10HoldingObserved(signal,ret',cap,[0;.5;1],2,1,4,1,ledger,(1:4)');
assert(isequaln(a,b) && isequal(ca.vExitHoldingCount,cb.vExitHoldingCount));
trades=cb.cObservedHighTrades{3};
assert(size(trades,1)==2 && trades(1,1)==20200118 && trades(1,2)==4 && trades(2,2)==3);
assert(abs(trades(1,3)+.7)<1e-12 && abs(trades(2,3)-.7)<1e-12 && abs(sum(trades(:,3)))<1e-12);
assert(all(trades(:,4)>0) && isempty(cb.cObservedLowTrades{3}));
assert(isequal(cb.cObservedAssets{3}(:,1),ids));
fprintf('E10_OBSERVATION_TEST_OK actual_synthetic_exit=1 flow_balance=1 no_return_change=1\n');
end
