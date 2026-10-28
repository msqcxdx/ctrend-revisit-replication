function [mDataWeek, vDatesWeek] = fResampleLiuEtAl(mDataDay, vDates, options)
% Function for resampling daily data to the weekly frequency using the 
% approach in Liu et al.
%
% Input:
%   mDataDay:       T* x N matrix of daily data
%                   T*: number of daily time-series observations
%                   N: number of assets
%   vDates:         T* x 1 vector of daily dates
%                   T*: number of daily time-series observations
%   options:        Name-Value pair arguments for controlling options
%       'sMethod':      String, specifies the aggregation method
%                       'last': last observation during past week (default)
%                       'sum': sum of all observations during past week
%                       'prod': product of all observations during past week
%                       'mean': average of all observations during past week
%       'iMinNumObs':   Scalar, integer, minimum number of observations
%                       required for resampling (default = 1). Note that it
%                       may also be equal to 'all', which means that all
%                       observations within a week need to be nonmissing
%
% Output:
%   mDataWeek:      T x N matrix of weekly data
%                   T: number of weekly time-series observations
%                   N: number of assets
%   vDatesWeek:     T x 1 vector of weekly dates
%                   T: number of weekly time-series observations

% Check inputs
arguments 
    mDataDay (:,:) {mustBeNumeric}
    vDates (:,1) {mustBeNumericOrDatetime}
    options.sMethod char = 'last'
    options.iMinNumObs {mustBeNonempty} = 1
end

% Determine dimensions
[iNumDailyObs, iNumAssets] = size(mDataDay);

% Check dimensions
assert(iNumDailyObs == length(vDates), 'Number of daily time-series observations must agree');

% Change format of date vector. Change yyyyMMdd to actual dates
if isnumeric(vDates)
    dtDates     = datetime(cellstr(num2str(vDates)),'InputFormat','yyyyMMdd');
elseif isdatetime(vDates)
    dtDates     = vDates;
else
    error('Unknown type');
end

% Get years
vYears     = year(dtDates);    

% Count the number of days per year
[vNumDays, vUniqueYears]    = groupcounts(vYears);
iNumYears                   = length(vUniqueYears);

% Count the number of weeks per year. Round to lower integer because in Liu
% et al., all years have at most 52 weeks, with the last week having more
% than seven days
vNumWeeks                   = fix(vNumDays/7);

% Count data points after resampling to weekly frequency
iNumObsWeek                 = sum(vNumWeeks);

% Initialize memory
mDataWeek                   = NaN(iNumObsWeek, iNumAssets);
vDatesWeek                  = NaN(iNumObsWeek, 1);

% Initialize counter 
iCounter = 1;

% Loop over year
for iIdxY = 1:iNumYears
    % Get all data within that year
    mDataTemp = mDataDay( vYears == vUniqueYears(iIdxY), :);

    % Create start and end index. The last index equals the number of days
    % within that year because the last week may contain more than seven
    % days
    vStartIdx = 1:7:(vNumWeeks(iIdxY) * 7);
    vEndIdx   = [vStartIdx(2:end)-1, vNumDays(iIdxY)];

    % Loop over weeks
    for iIdxW = 1:vNumWeeks(iIdxY)
        % Create date in the format yyyyWW, where WW refers to the number 
        % of the week, ranging from 1 to 52
        vDatesWeek(iCounter) = vUniqueYears(iIdxY) * 100 + iIdxW;

        % Get data within that week
        vIdxInSample            = vStartIdx(iIdxW):vEndIdx(iIdxW);
        mDataDailyTemp          = mDataTemp(vIdxInSample,:);

        % Find non valid observations
        if ischar(options.iMinNumObs) && strcmp(options.iMinNumObs, 'all')
            % Require all observations
            lNonValid = any(isnan(mDataDailyTemp),1);
        else           
            % Require specified number of observations
            lNonValid = sum(~isnan(mDataDailyTemp),1) < options.iMinNumObs;
        end
        mDataDailyTemp(:,lNonValid) = NaN;

        % Resample data
        switch upper(options.sMethod)
            case 'LAST'
                % Use last observation
                vUseThisObs = mDataDailyTemp(end, :);
    
                % If the scheduled last row is missing, use the last valid
                % observation from this weekly block only.  M0 searched the
                % entire calendar year and could therefore read a later
                % week.  M2 removes only that future-data path while
                % retaining M0's within-week "last valid" convention.
                vIdxLoop = find(isnan(vUseThisObs) & ~lNonValid);
        
                % Loop over those observations
                for iIdxA = 1:length(vIdxLoop)
                    % Find index
                    idx = vIdxLoop(iIdxA);
        
                    % Find the last valid observation no later than this
                    % week's scheduled boundary.
                    iLast = find(~isnan(mDataDailyTemp(:,idx)),1,'last');
                    if ~isempty(iLast)
                        vUseThisObs(idx) = mDataDailyTemp(iLast,idx);
                    end
                end
    
                % Save resampled data
                mDataWeek(iCounter, :) = vUseThisObs;

            case 'SUM'
                % Use sum
                mDataWeek(iCounter,~lNonValid) = sum(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            case 'PROD'
                % Use product
                mDataWeek(iCounter,~lNonValid) = prod(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            case {'MEAN','AVG'}
                % Use mean
                mDataWeek(iCounter,~lNonValid) = mean(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            otherwise
                error('Unknown aggregation method');
        end

        % Increase counter
        iCounter = iCounter + 1;
    end
end
end
