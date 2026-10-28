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
        for iIdxSlash = fliplr(vIdx)
            sString = [sString(1:iIdxSlash-1),'\',sString(iIdxSlash:end)];
        end
        cCell{iIdxC} = sString;
    end
end
end
