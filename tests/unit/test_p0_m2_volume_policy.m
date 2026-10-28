function test_p0_m2_volume_policy(root)
% CTREND_REVISIT_FILE_PURPOSE: Execute the P0/M0 and P0/M2 volume blocks on edge-case panels and check exact equivalence.
% Extract and execute only the bounded volume-cleaning blocks. P0/M2 must be
% behaviorally identical to Dataverse-derived P0/M0: explicit zero becomes
% missing, while returns, closes, and valid positive volume stay unchanged.
original = fileread(fullfile(root,'engines','P0_M0','base','b02CalculateIndicators.m'));
fixed = fileread(fullfile(root,'p0_extension','overlays','M2','b02CalculateIndicators.m'));
original = volumeBlock(original); fixed = volumeBlock(fixed);
v = [0,0.1,1e-8,NaN,-1,1e-6,Inf; zeros(1,7); NaN(1,7); ...
     2,0,0,NaN,3,1e-5,4];
y = [0,0.1,-0.2,NaN,1,0,-1; ones(1,7); zeros(1,7); zeros(1,7)];
rData = struct('mVolume',v,'mReturns',y,'mClose',ones(size(v)));
before = rData;
% Evaluate both source blocks against the same edge-case fixture.
eval(original); expected = rData;
rData = before; eval(fixed);
assert(isequaln(rData,expected));
assert(~any(rData.mVolume==0,'all'));
assert(isequaln(rData.mReturns,before.mReturns));
assert(isequaln(rData.mClose,before.mClose));
assert(rData.mVolume(1,2)==0.1 && rData.mVolume(4,6)==1e-5);
assert(all(isnan(rData.mVolume(2,:))));
fprintf('P0_M2_VOLUME_BEHAVIOR_OK original_block_equivalence=1 zero_to_nan=1 other_fields_unchanged=1\n');
end
function result = volumeBlock(text)
% Locate the policy using stable semantic boundary comments, not line numbers.
a = strfind(text,'    % Set volume to missing if zero for all assets');
b = strfind(text,'    % Calculate value-weighted market return');
assert(numel(a)==1 && numel(b)==1 && a<b);
result = text(a:b-1);
end
