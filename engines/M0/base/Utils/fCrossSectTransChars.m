function mCharsZ = fCrossSectTransChars(mChars, sMethod)
% Function for cross-sectional standardization of characteristics
%
% Input:
%   mChars:         N x M x T matrix of characteristics
%                   N: number of response variables
%                   M: number of characteristics
%                   T: number of time-series variables
%   sMethod:        Char or String, specifies the method
%                   'none': no standardization
%                   'rank': rank transformation
%                   'z':    z-transformation
%
% Output:
%   mCharsZ:        N x M x T matrix of standardized characteristics
%                   N: number of response variables
%                   M: number of characteristics
%                   T: number of time-series variables

% Check input arguments
arguments
    mChars (:,:,:) {mustBeNumeric}
    sMethod char = 'rank'
end

% Return if no standardization
if strcmpi(sMethod,'none')
    mCharsZ = mChars;
    return
end

% Determine dimension
[iNumResp, iNumChars, iNumObs] = size(mChars);

% Initialize memory
mCharsZ = NaN(iNumResp, iNumChars, iNumObs);

% Loop over characteristic
for iIdxC = 1:iNumChars
    % Extract characteristic
    mCharTemp = squeeze(mChars(:,iIdxC,:));
    
    % Choose method
    switch upper(sMethod)
        case 'RANK'
            % Rank transformation

            mCharTemp = tiedrank(mCharTemp); % , 0,1);
            mCharTemp = (mCharTemp-1)./(max(mCharTemp)-1);
            mCharTemp = mCharTemp - 0.5;

        case 'Z'
            % z-transformation
            vMean       = mean(mCharTemp,1,'omitnan');   % Cross-sectional mean
            vStd        = std(mCharTemp,[],1,'omitnan');  % Cross-sectional sd
            mCharTemp   = (mCharTemp - vMean)./vStd; % Standardization

        otherwise   
            error('Unknown method');
    end
    % Save characteristic
    mCharsZ(:,iIdxC,:) = mCharTemp;
end
end

