function mMatrix = fPanel2Matrix(vPanel,vRowIDin, vColIDin, vRowIDOut, vColIDout)
% Function for transforming a stacked vector into a 2D matrix
%
% Input:
%   vPanel:         (M * N) x 1 vector
%                   M: size of first dimension
%                   N: size of second dimension
%   vRowIDin:       (M * N) index refering to the first dimension
%   vColIDin:       (M * N) index refering to the second dimension
%   vRowIDOut:      M x 1 vector, desired index of first dimension
%   vColIDOut:      N x 1 vector, desired index of second dimension
%
% Output:
%   mMatrix:        M x N matrix

% If no output indices passed as input, create some based on the unique
% values of the input indices
if nargin < 4 || (isempty(vRowIDOut) && isempty(vColIDout))
    vRowIDOut = unique(vRowIDin);
    vColIDout = unique(vColIDin);
end

% Determine dimensions
iNumRows = length(vRowIDOut);
iNumCols = length(vColIDout);

% Create matrix
mMatrix = NaN(iNumRows,iNumCols);
[~, vRowIdx] = ismember(vRowIDin,vRowIDOut);
[~, vColIdx] = ismember(vColIDin,vColIDout);
vIndices = sub2ind([iNumRows, iNumCols],vRowIdx, vColIdx);
mMatrix(vIndices) = vPanel;
end

