function [lIsAvail, varargout] = fEnsureAllObs(varargin)
% The function takes a variable number of matrices of equal size as input
% and ensures that every observation i,j is non-missing in any input matrix

% Determine number of input matrices
iNumMatrices = length(varargin);

% Control dimensions
cInputNames = cell(iNumMatrices,1);
for iIdxM = 1:iNumMatrices
    % Get input name
    cInputNames{iIdxM} = inputname(iIdxM);
    if iIdxM == 1
        % Get dimensions of first matrix
        [iNumRows, iNumCols] = size(varargin{iIdxM});

        % Initialize available matrix
        lIsAvail = ~isnan(varargin{iIdxM});
    else
        % Compare dimensions
        [iNumRowsTest, iNumColsTest] = size(varargin{iIdxM});
        assert((iNumRows == iNumRowsTest),sprintf(['Number of rows in ' ...
            '%s (%i) and %s (%i) does not agree'],cInputNames{1},iNumRows,...
            cInputNames{iIdxM},iNumRowsTest));
        assert((iNumCols == iNumColsTest),sprintf(['Number of columns in ' ...
            '%s (%i) and %s (%i) does not agree'],cInputNames{1},iNumCols,...
            cInputNames{iIdxM},iNumColsTest));

        % Update available matrix. The logical lIsAvail will indicate if
        % there are only non-missing observations at position i,j. We will
        % use this later to set observations with any missing value to
        % missing in all other matrices
        lIsAvail = lIsAvail & ~isnan(varargin{iIdxM});
    end
end

% Again loop over input matrices to set values to missing, if a observation 
% i,j is missing in any input matrix
varargout = cell(iNumMatrices,1);
for iIdxM = 1:iNumMatrices
    % Get input matrix
    mMatTemp            = varargin{iIdxM};

    % Set to missing if any missing value at position i,j
    mMatTemp(~lIsAvail) = NaN;

    % Output
    varargout{iIdxM} = mMatTemp;
end
end