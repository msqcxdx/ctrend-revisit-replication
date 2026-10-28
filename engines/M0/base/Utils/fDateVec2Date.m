function dtDates = fDateVec2Date(vDates)
% To strings
cDates = num2cell(vDates);
cDates = cellfun(@(x)num2str(x),cDates,'UniformOutput',false);

% To datetime
dtDates = datetime(cDates,'InputFormat','yyyyMMdd');
end