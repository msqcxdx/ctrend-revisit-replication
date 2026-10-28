function[FGRS, pGRS] = fGRS(alpha, eps, mu)
%   [FGRS, pGRS] = fGRS(alpha, eps, mu) returns the GRS test statistic
%       and its corresponding p-Value proposed in 
%       Gibbons, Ross, Shanken (1989), to test the hypothesis:
%       alpha1 = alpha2 = ... = alphaN = 0. That is if the alphas from a
%       time series Regression on N Test Assets are cummulativly zero.
%       Used e.g. in Artmann/Finter/Kempf/Koch/Theissen (2012), p. 33ff.
%   
%   Input:
%       alpha       := Nx1 Vector of intercepts from TS-Rergression
%       eps         := TxN Matrix of Residuals from TS-Regression
%       mu          := TxL Matrix of Excess Factor Returns
%
%   Output:
%       FGRS        := 1x1 Scalar of GRS Test-Value
%       pGRS        := 1x1 Scalar of P-Value from an F-Distribution.
%
%%% Sven Thies 24/02/2014 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Copyright (c) 2014, Sven Thies
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
% 
% * Redistributions of source code must retain the above copyright notice, this
%   list of conditions and the following disclaimer.
% 
% * Redistributions in binary form must reproduce the above copyright notice,
%   this list of conditions and the following disclaimer in the documentation
%   and/or other materials provided with the distribution
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
% FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
% DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
% OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

% https://de.mathworks.com/matlabcentral/fileexchange/45898-grs-test-statistic

FGRS = NaN;
pGRS = NaN;

% Adjustment of code @Liedtke: Remove missing values
alpha = alpha(:);
if length(alpha) ~= size(eps,2)
    return
end
lValidAsset = isfinite(alpha) & any(isfinite(eps), 1)';
alpha = alpha(lValidAsset);
eps = eps(:, lValidAsset);

lInvalid = any(~isfinite(eps), 2) | any(~isfinite(mu), 2);
mu(lInvalid,:) = [];
eps(lInvalid,:) = [];

% Now this is the code from Sven Thies:
[T,N] = size(eps);
L = size(mu,2);
if N == 0 || T <= N + L || T <= L + 1
    return
end
% Mean Excess Factor Returns
mu_mean = mean(mu)';
% Unbiased residual covariance from the N time-series regressions.  With
% this (T-L-1) denominator, the finite-sample multiplier below is the GRS
% form stated in Gibbons, Ross, and Shanken (1989).
COV_e = eps'*eps / (T-L-1);
% GRS uses the factor second central moment with denominator T. This pairs
% with the unbiased residual covariance above and the finite-sample
% multiplier below; using MATLAB's usual T-1 sample covariance changes the
% exact GRS statistic.
COV_f = ((mu - repmat(mu_mean',T,1))' * (mu - repmat(mu_mean',T,1))) / T;
if any(~isfinite(COV_e), 'all') || rcond(COV_e) < 1e-12
    return
end
if L > 0
    if any(~isfinite(COV_f), 'all') || rcond(COV_f) < 1e-12
        return
    end
    dFactorAdj = 1 + (mu_mean' * (COV_f \ mu_mean));
else
    dFactorAdj = 1;
end
% Compute GRS statistic
FGRS = (T/N) * ((T-N-L)/(T-L-1)) * ((alpha' * (COV_e \ alpha)) / dFactorAdj);
% p-Value for GRS statistic: GRS ~ F(N,T-N-L)
pGRS = 1-fcdf(FGRS, N, (T-N-L));
end
