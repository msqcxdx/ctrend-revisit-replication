function [mDataWeek, vDatesWeek] = fResampleDay2Week(mDataDay, vDates, options)
% Function for resampling daily observations to weekly data
%
% Input:
%   mDataDay:       T* x N matrix of daily data
%                   T*: number of daily time-series observations
%                   N: number of assets
%   vDates:         T* x 1 vector of daily dates
%                   T*: number of daily time-series observations
%   options:        Name-Value pair arguments for controlling options
%       'iStartDay':    Scalar, integer, specifies the day to start according
%                       to MATLABs "weekday" function
%                       1: sunday (default), 2: monday, 3: tuesday, 4: wednesday,
%                       5: thursday, 6: friday, 7: saturday
%       'sMethod':      String, specifies the aggregation method
%                       'last': last observation during past week (default)
%                       'sum': sum of all observations during past week
%                       'prod': product of all observations during past week
%                       'mean': average of all observations during past week
%       'iMinNumObs':   Scalar, integer, minimum number of observations
%                       required for resampling (default = 1)
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
    options.iStartDay (1,1) {mustBeNumeric, mustBeNonnegative} = 1
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

% Find index of day
vIdxDay     = weekday(dtDates);

% Find days to resample (e.g., every Sunday)
vUnique     = find(vIdxDay == options.iStartDay);
iNumPeriods = length(vUnique);

% Preallocate memory
mDataWeek   = NaN(iNumPeriods-1, iNumAssets);
vDatesWeek  = NaN(iNumPeriods-1, 1);
for iIdxT = 1:iNumPeriods-1
    % Get start and end indices 
    iIdxStart   = vUnique(iIdxT)+1;   % This is now e.g. Monday
    iIdxEnd     = vUnique(iIdxT+1);   % This is now e.g. Sunday

    % Extract data
    mDataTemp           = mDataDay(iIdxStart:iIdxEnd,:);
    vDatesWeek(iIdxT)   = vDates(vUnique(iIdxT+1));

    % Find valid assets
    lValid = sum(~isnan(mDataTemp),1) >= min(options.iMinNumObs, size(mDataTemp,1));

    % Skip if no valid assets exist
    if ~any(lValid)
        continue
    end

    % Resample data
    switch upper(options.sMethod)
        case {'LAST','FIRST'}
            if strcmpi(options.sMethod, 'LAST')
                % Use last value
                vUseThisObs = mDataTemp(end, :);
            else
                % Use first value
                vUseThisObs = mDataTemp(1, :);
            end

            % If there is no valid observation in last/first row, find the next most
            % recent observation
            vIdxLoop = find(isnan(vUseThisObs) & lValid);

            % Loop over those observations
            for iIdxA = 1:length(vIdxLoop)
                % Find index
                idx = vIdxLoop(iIdxA);
    
                % Find last valid observation
                vUseThisObs(idx) = mDataTemp(find(~isnan(mDataTemp(:,idx)),1,options.sMethod), idx);
            end

            % Save first observation
            mDataWeek(iIdxT,:) = vUseThisObs;

        case 'SUM'
            % Use sum
            mDataWeek(iIdxT,lValid) = sum(mDataTemp(:,lValid),1,'omitnan');

        case 'PROD'
            % Use product
            mDataWeek(iIdxT,lValid) = prod(mDataTemp(:,lValid),1,'omitnan');

        case {'MEAN','AVG'}
            % Use mean
            mDataWeek(iIdxT,lValid) = mean(mDataTemp(:,lValid),1,'omitnan');

        otherwise
            error('Unknown aggregation method');
    end
end
end