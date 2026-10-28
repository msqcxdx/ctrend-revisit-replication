function t = extract_confirmed_event_windows()
% Export auditable raw windows around every suspected unit/event break.
% This function is read-only with respect to the source CMC directory.

sRawDir = getenv('CTREND_RAW_DATA_DIR');
if isempty(sRawDir)
    sRawDir = fullfile(fileparts(mfilename('fullpath')),'..','DATA');
end
sOutputDir = getenv('CTREND_EVENT_AUDIT_DIR');
if isempty(sOutputDir)
    sOutputDir = fullfile(fileparts(mfilename('fullpath')),'output');
end
if ~exist(sOutputDir,'dir')
    mkdir(sOutputDir);
end

[mClose,vID,dtDate] = iReadPanel(sRawDir,'close_cmc.csv');
[mOpen,vIDOpen,dtOpen] = iReadPanel(sRawDir,'open_cmc.csv');
[mHigh,vIDHigh,dtHigh] = iReadPanel(sRawDir,'high_cmc.csv');
[mLow,vIDLow,dtLow] = iReadPanel(sRawDir,'low_cmc.csv');
[mCap,vIDCap,dtCap] = iReadPanel(sRawDir,'market_cap_cmc.csv');
[mVolume,vIDVolume,dtVolume] = iReadPanel(sRawDir,'volume_cmc.csv');
assert(isequal(vID,vIDOpen,vIDHigh,vIDLow,vIDCap,vIDVolume) && ...
    isequal(dtDate,dtOpen,dtHigh,dtLow,dtCap,dtVolume), ...
    'Event-window panels do not have identical keys');
r = load(fullfile(sRawDir,'MetaData.mat'),'rMetaData');
assert(isequal(vID(:),r.rMetaData.vID(:)), ...
    'Event-window metadata asset IDs do not agree');

vEventID = [184;624;638;895;1209;1902;3468;4069; ...
    4172;4275;5834;7497];
dtStart = [datetime(2018,4,20); datetime(2015,10,25); ...
    datetime(2015,11,20); datetime(2016,8,10); ...
    datetime(2016,4,1); datetime(2018,5,25); ...
    datetime(2019,2,15); datetime(2020,2,15); ...
    datetime(2022,5,1); datetime(2021,1,10); ...
    datetime(2021,2,20); datetime(2020,12,15)];
dtEnd = [datetime(2018,5,20); datetime(2016,2,10); ...
    datetime(2015,12,20); datetime(2016,9,5); ...
    datetime(2016,4,20); datetime(2018,6,20); ...
    datetime(2019,5,15); datetime(2020,3,20); ...
    datetime(2022,5,31); datetime(2021,1,31); ...
    datetime(2021,3,25); datetime(2021,1,10)];

cParts = cell(numel(vEventID),1);
for iEvent = 1:numel(vEventID)
    iColumn = find(vID == vEventID(iEvent),1);
    assert(~isempty(iColumn),'Event asset ID %d is absent',vEventID(iEvent));
    vRows = find(dtDate >= dtStart(iEvent) & dtDate <= dtEnd(iEvent));
    iN = numel(vRows);
    tPart = table();
    tPart.AssetID = repmat(vEventID(iEvent),iN,1);
    tPart.Name = repmat(string(r.rMetaData.cName{iColumn}),iN,1);
    tPart.Symbol = repmat(string(r.rMetaData.cSymbol{iColumn}),iN,1);
    tPart.Date = dtDate(vRows);
    tPart.Open = mOpen(vRows,iColumn);
    tPart.High = mHigh(vRows,iColumn);
    tPart.Low = mLow(vRows,iColumn);
    tPart.Close = mClose(vRows,iColumn);
    tPart.MarketCap = mCap(vRows,iColumn);
    tPart.ImpliedSupply = tPart.MarketCap./tPart.Close;
    tPart.Volume = mVolume(vRows,iColumn);
    tPart.CloseGrossRatio = [NaN; ...
        tPart.Close(2:end)./tPart.Close(1:end-1)];
    tPart.SupplyGrossRatio = [NaN; ...
        tPart.ImpliedSupply(2:end)./tPart.ImpliedSupply(1:end-1)];
    cParts{iEvent} = tPart;
end
t = vertcat(cParts{:});
writetable(t,fullfile(sOutputDir,'confirmed_event_raw_windows.csv'));
save(fullfile(sOutputDir,'confirmed_event_raw_windows.mat'),'t','sRawDir');
fprintf('confirmed_event_window_rows=%d assets=%d\n', ...
    height(t),numel(vEventID));
end

function [mPanel,vID,dtDate] = iReadPanel(sRawDir,sFile)
sPath = fullfile(sRawDir,sFile);
mRaw = readmatrix(sPath);
vID = mRaw(1,2:end);
mPanel = mRaw(2:end,2:end);
fid = fopen(sPath,'r');
assert(fid >= 0,'Could not open %s',sPath);
rCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fgetl(fid);
cDate = strings(size(mPanel,1),1);
for iRow = 1:size(mPanel,1)
    sLine = fgetl(fid);
    assert(ischar(sLine) && numel(sLine) >= 10, ...
        'Malformed date row in %s',sPath);
    cDate(iRow) = string(sLine(1:10));
end
dtDate = datetime(cDate,'InputFormat','yyyy-MM-dd');
end
