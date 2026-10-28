function [mXReduced,cNamesReduced,rAlias] = ...
        fReduceKnownUnpenalizedAliases(mX,cNames)
% Remove the documented exact sma_20d/boll_mid alias for joint, unpenalized
% regressions.  The two columns are identical by construction, so their
% separate coefficients are not identified, while the fitted values are.
% Penalized and one-characteristic estimators must not call this function.

arguments
    mX (:,:) {mustBeNumeric}
    cNames (:,1) cell
end

assert(size(mX,2) == numel(cNames), ...
    'Predictor names must match the columns of the design matrix.');
iSMA = find(strcmp(cNames,'sma_20d'));
iBoll = find(strcmp(cNames,'boll_mid'));
assert(isscalar(iSMA) && isscalar(iBoll), ...
    'Expected exactly one sma_20d and one boll_mid predictor.');
assert(isequaln(mX(:,iSMA),mX(:,iBoll)), ...
    ['The documented sma_20d/boll_mid alias is no longer exact. ', ...
     'Do not choose a replacement identification rule silently.']);

lKeep = true(1,size(mX,2));
lKeep(iBoll) = false;
mXReduced = mX(:,lKeep);
cNamesReduced = cNames(lKeep);
rAlias = struct('sKept','sma_20d','sDropped','boll_mid', ...
    'sScope','joint_unpenalized_FM_and_POLS','lExact',true, ...
    'lKeep',lKeep);
end
