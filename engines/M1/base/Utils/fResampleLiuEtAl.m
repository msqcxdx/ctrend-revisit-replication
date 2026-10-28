function [mDataWeek, vDatesWeek, vNumDaysWeek] = fResampleLiuEtAl(mDataDay, vDates, options)
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
%                       'last': scheduled last observation (default)
%                       'first': scheduled first observation
%                       'sum': sum of all observations during past week
%                       'prod': product of all observations during past week
%                       'mean': average of all observations during past week
%                       'std': standard deviation of observations during
%                              past week
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
%   vNumDaysWeek:   T x 1 number of calendar days in each weekly block

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
assert(iNumDailyObs > 0, 'Daily data and dates must be nonempty');

% Change format of date vector. Change yyyyMMdd to actual dates
if isnumeric(vDates)
    assert(all(isfinite(vDates)), 'Numeric dates must be finite');
    dtDates     = datetime(cellstr(num2str(vDates)),'InputFormat','yyyyMMdd');
elseif isdatetime(vDates)
    dtDates     = vDates;
else
    error('Unknown type');
end

% The Liu et al. schedule below partitions each calendar year by row count.
% A duplicate, unsorted date, or a missing calendar day would silently move
% every subsequent weekly boundary. Require a unique, strictly increasing,
% uninterrupted daily calendar before forming seven-row weeks.
assert(all(~isnat(dtDates)), 'Dates must be valid');
assert(all(dtDates(2:end) == dtDates(1:end-1) + caldays(1)), ...
    'Dates must be unique, strictly increasing, and daily-contiguous');

% Validate the minimum-observation rule explicitly. The only textual rule
% is 'all'; numeric rules must be positive integer scalars.
if ischar(options.iMinNumObs)
    assert(strcmpi(options.iMinNumObs, 'all'), ...
        'Text iMinNumObs must equal ''all''');
else
    assert(isnumeric(options.iMinNumObs) && isscalar(options.iMinNumObs) && ...
        isfinite(options.iMinNumObs) && options.iMinNumObs >= 1 && ...
        options.iMinNumObs == fix(options.iMinNumObs), ...
        'Numeric iMinNumObs must be a positive integer scalar');
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
vNumDaysWeek                = NaN(iNumObsWeek, 1);

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
        vNumDaysWeek(iCounter)  = numel(vIdxInSample);
        mDataDailyTemp          = mDataTemp(vIdxInSample,:);
        % All nonfinite values are missing observations. Aggregators with
        % 'omitmissing' ignore NaN but not Inf, so canonicalize before both
        % support counting and arithmetic.
        mDataDailyTemp(~isfinite(mDataDailyTemp)) = NaN;

        % Find non valid observations
        if ischar(options.iMinNumObs) && strcmpi(options.iMinNumObs, 'all')
            % Require all observations
            lNonValid = any(~isfinite(mDataDailyTemp),1);
        else           
            % Require specified number of observations
            lNonValid = sum(isfinite(mDataDailyTemp),1) < options.iMinNumObs;
        end
        mDataDailyTemp(:,lNonValid) = NaN;

        % Resample data
        switch upper(options.sMethod)
            case 'LAST'
                % Use the observation at the scheduled weekly boundary.
                % A missing boundary value is economically different from
                % an earlier observation and must therefore remain NaN.
                % In particular, do not carry an earlier value forward
                % across an intra-week data gap.
                mDataWeek(iCounter, :) = mDataDailyTemp(end, :);

            case 'FIRST'
                % Formation-day snapshot used by the one-day implementation
                % lag. As with LAST, do not replace a missing scheduled cell
                % with another observation from inside the week.
                mDataWeek(iCounter, :) = mDataDailyTemp(1, :);

            case 'SUM'
                % Use sum
                mDataWeek(iCounter,~lNonValid) = sum(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            case 'PROD'
                % Use product
                mDataWeek(iCounter,~lNonValid) = prod(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            case {'MEAN','AVG'}
                % Use mean
                mDataWeek(iCounter,~lNonValid) = mean(mDataDailyTemp(:,~lNonValid),1,'omitmissing');

            case 'STD'
                % Use the sample standard deviation
                mDataWeek(iCounter,~lNonValid) = std(mDataDailyTemp(:,~lNonValid),0,1,'omitmissing');

            otherwise
                error('Unknown aggregation method');
        end

        % Increase counter
        iCounter = iCounter + 1;
    end
end
end
