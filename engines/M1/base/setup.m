% This script checks whether all required data and code was downloaded to 
% replicate the entire project.

% Clear console
clear; clc; close all;

% Set path
sDataPath  = './DATA/';
sUtilsPath = './Utils/';

addpath(sUtilsPath);

% Download F-F_Research_Data_Factors_daily.CSV
if ~exist([sDataPath,'F-F_Research_Data_Factors_daily.CSV'],'file')
    error('Download daily Fama-French factor from Kenneth R. Frenchs website');
end

% Download LTW_3factor data (https://www.yukunliu.com/research/)
if ~exist([sDataPath,'LTW_3factor.xlsx'],'file')
    error('Download LTW factors from Yukun Lius website');
else
    % Preprocess the data
    tLTW = readtable([sDataPath,'LTW_3factor.xlsx']);
    tLTW = tLTW(tLTW.yyww >= 201404 & tLTW.yyww <= 202252,:);

    % To array
    mLTW        = table2array(tLTW(:, {'cmkt','csize','cmom'}));
    vDatesLiu   = tLTW.yyww;

    % Publish atomically so an interrupted setup cannot leave a truncated
    % factor file for a later resume.
    sLTWFile = [sDataPath,'LTW_3factor.mat'];
    sLTWTemp = [tempname(sDataPath),'.mat'];
    save(sLTWTemp,"vDatesLiu","mLTW");
    [lMoved,sMoveMessage] = movefile(sLTWTemp,sLTWFile,'f');
    assert(lMoved,'Could not publish LTW factor file: %s',sMoveMessage);
end 

% https://sites.google.com/view/cryptocurrency-indices/the-indices/crypto-uncertainty
if ~exist([sDataPath,'UCRY.csv'],'file')
    error('Download UCRY data from DIGITAL ASSET INDICES website');
end

% https://de.mathworks.com/matlabcentral/fileexchange/26169-regstats2
if ~exist([sUtilsPath,'regstats2.m'],'file')
    error('Download regstats2 from fileexchange');
end

% https://de.mathworks.com/matlabcentral/fileexchange/71083-waitbar-for-parfor
if ~exist([sUtilsPath,'parfor_wait.m'],'file')
    error('Download parfor_wait from fileexchange');
end

% Fail before an expensive run if the source was screened before market-wide
% series construction or if it removed internally discontinuous assets.
if exist([sDataPath,'MetaData.mat'],'file')
    rMeta = load([sDataPath,'MetaData.mat'],'rMetaData');
    assert(isfield(rMeta,'rMetaData'), 'MetaData.mat does not contain rMetaData');
    fValidateInputProvenance(sDataPath, rMeta.rMetaData);
end

fprintf('All required files available. Happy coding! \n');
