function cCell = fAddSlash(cCell,lRemFirst)

% Determine dimensions
iNumCells = length(cCell);

% Iterate over each cell
for iIdxC = 1:iNumCells
    % Find " _ "
    sString = cCell{iIdxC};
    vIdx = strfind(sString, '_');
    
    if ~isempty(vIdx) && lRemFirst
        vIdx(1) = [];
    end
    
    % Add "\"
    if ~isempty(vIdx)
        sString = [sString(1:vIdx(1)-1),'\',sString(vIdx(1):end)];
        cCell{iIdxC} = sString;
    end
end
end