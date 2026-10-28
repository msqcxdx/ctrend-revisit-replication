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

% Adjustment of code @Liedtke: Remove missing values
lIsNaN = any(isnan(eps), 2) | any(isnan(mu), 2);
mu(lIsNaN,:) = [];
eps(lIsNaN,:) = [];

% Now this is the code from Sven Thies:
[T,N] = size(eps);
L = size(mu,2);
% Mean Excess Factor Returns
mu_mean = mean(mu)';
% Compute Covariance Matrix of eps
COV_e = eps'*eps / (T-L-1);
% Compute Covariance Matrix of Factor Returns
COV_f = ((mu - repmat(mu_mean',T,1))' * (mu - repmat(mu_mean',T,1))) / (T-1);
% Compute GRS statistic
FGRS = (T/N) * ((T-N-L)/(T-L-1)) * ((alpha' * inv(COV_e) * alpha) / (1 + (mu_mean' * inv(COV_f) * mu_mean))); 
% p-Value for GRS statistic: GRS ~ F(N,T-N-L)
pGRS = 1-fcdf(FGRS, N, (T-N-L));
end