function [vIdxInSample,vIdxOutOfSample] = ...
    fCreateIndices(iNumObs,iIdxT,iNumIn,iNumOut,lRoll,lInSample,lDisplay)
% Function to generate in-sample and out-of-sample indices
%
% Input:
%   iNumObs:        Scalar, integer, number of all observations
%   iIdxT:          Scalar, integer, current time step in loop
%   iNumIn:         Scalar, integer, number of initial in-sample
%                   observations
%   iNumOut:        Scalar, integer, number of out-of-sample observations
%                   (default = 1)
%   lRoll:          Logical, specifies whether to use rolling (true, default) 
%                   or expanding (false) time window
%   lInSample:      Logical, specifies whether estimation is full in-sample
%                   (default = false)
%   lDisplay:       Logical, whether to print progress on console 
%                   (default = true)
%
% Output:
%   vIdxInSample:   1 x M vector of current in-sample indices
%       	        M: number of in-sample observations
%   vIdxOutOfSample:1 x L vector of current out-of-sample indices
%       	        L: number of out-of-sample observations

% Check input arguments
arguments
    iNumObs (1,1) {mustBeNumeric, mustBeNonnegative}
    iIdxT (1,1) {mustBeNumeric, mustBeNonnegative}
    iNumIn (1,1) {mustBeNumeric, mustBeNonnegative}
    iNumOut (1,1) {mustBeNumeric, mustBeNonnegative} = 1
    lRoll (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true
    lInSample (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = false
    lDisplay (1,1) {mustBeNumericOrLogical, mustBeNonnegative} = true
end

% Create indices
if lInSample
    % Full in-sample estimation and validation
    vIdxInSample    = 1:iNumObs;
    vIdxOutOfSample = 1:iNumObs;
elseif lRoll
    % Rolling time window
    vIdxInSample = (iIdxT - iNumIn + 1):iIdxT;
    vIdxOutOfSample = (iIdxT + 1):min(iNumObs, (iIdxT + iNumOut));
else
    % Expanding time window
    vIdxInSample = 1:iIdxT;
    vIdxOutOfSample = (iIdxT + 1):min(iNumObs, (iIdxT + iNumOut));
end

% Print progress
if lDisplay
    fprintf('Start in-sample: %d, End in-sample %d \n', vIdxInSample(1), ...
        vIdxInSample(end));
end
end

