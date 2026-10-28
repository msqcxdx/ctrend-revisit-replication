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
mChars(~isfinite(mChars)) = NaN;

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

            lFinite = isfinite(mCharTemp);
            vRawMin = min(mCharTemp,[],1,'omitnan');
            vRawMax = max(mCharTemp,[],1,'omitnan');
            lNoVariation = isfinite(vRawMin) & vRawMax == vRawMin;
            mCharTemp = tiedrank(mCharTemp); % , 0,1);
            vDenom = max(mCharTemp,[],1,'omitnan') - 1;
            lNoVariation = lNoVariation | vDenom == 0;
            vDenom(lNoVariation) = NaN;
            mCharTemp = (mCharTemp-1)./vDenom;
            mCharTemp = mCharTemp - 0.5;

            % A one-point or all-tied cross-section contains no signal.
            % Map its observed values to the neutral rank (zero), while
            % retaining genuinely missing observations as NaN.
            if any(lNoVariation)
                mNoVariation = lFinite(:,lNoVariation);
                mTemp = mCharTemp(:,lNoVariation);
                mTemp(mNoVariation) = 0;
                mCharTemp(:,lNoVariation) = mTemp;
            end

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

