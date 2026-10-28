function cCell = fMatrix2Cell(mMatrix, iNumDigits, lReplaceNaN)

% Check input arguments
arguments
    mMatrix {mustBeNumeric}
    iNumDigits (1,1) = 2
    lReplaceNaN (1,1) = true
end

% Round data
mMatrix = round(mMatrix, iNumDigits);

% Find missing values
lIsNaN = isnan(mMatrix);

% To cell
cCell = sprintfc(['%.',num2str(iNumDigits),'f'], mMatrix);

% Replace missing values
if lReplaceNaN
    cCell(lIsNaN) = {''};
end


end