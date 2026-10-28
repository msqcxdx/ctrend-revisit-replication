function cTableNew = fAddStatistics(cTable,cStats,lBold)
% Function for adding t-statistics to estimated coefficients

% Check input arguments
[iNumRows, iNumCols, iNumThird] = size(cTable);
assert(iNumRows == size(cStats, 1), 'Number of rows must agree');
assert(iNumCols == size(cStats, 2), 'Number of columns must agree');
if nargin < 3 || isempty(lBold)
    lBold = false(iNumRows, iNumCols);
else
    assert(iNumRows == size(lBold, 1), 'Number of rows must agree');
    assert(iNumCols == size(lBold, 2), 'Number of columns must agree');
end

cTableNew = cell(iNumRows, iNumCols, iNumThird);
for iIdxT = 1:iNumThird
for iIdxR = 1:iNumRows
    for iIdxC = 1:iNumCols
        % Get cell
        sCellTemp = cTable{iIdxR, iIdxC, iIdxT};
        sStatTemp = cStats{iIdxR, iIdxC, iIdxT};
        lBoldTemp = lBold(iIdxR, iIdxC, iIdxT);

        % Make bold
        if lBoldTemp
            sCellTemp = ['\textbf{', sCellTemp, '}'];
        end

        % Add statistic
        cTableNew{iIdxR, iIdxC, iIdxT} = ['\makecell[c]{', sCellTemp, '\\ (',...
            sStatTemp, ')}'];
    end
end
end
end
