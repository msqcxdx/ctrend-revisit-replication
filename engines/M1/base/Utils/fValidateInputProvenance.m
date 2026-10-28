function rInputProvenance = fValidateInputProvenance(sDataPath, rMetaData, mMarketCap)
% Reject asset universes screened before market-wide series are constructed.
%
% b02 applies stablecoin and USD-1-million eligibility dynamically at each
% formation date.  The unscreened source is still required: a full-history
% prefilter would use future eligibility and would prevent the Table 6
% alternative universes from being reconstructed. Internal gaps remain NaN.

arguments
    sDataPath {mustBeTextScalar}
    rMetaData struct
    mMarketCap (:,:) {mustBeNumeric} = []
end

% java.io.File resolves a relative path against the operating-system process
% working directory, which MATLAB does not reliably update when `cd` is
% called.  Anchor relative DATA paths to MATLAB's current folder first.  The
% packaged runner starts MATLAB outside its extracted code directory and then
% changes folder in MATLAB, so omitting this step can validate an unrelated
% project-level DATA directory.
sDataPath = char(sDataPath);
rDataPath = java.io.File(sDataPath);
if ~rDataPath.isAbsolute()
    sDataPath = fullfile(pwd,sDataPath);
end
sCanonicalData = char(java.io.File(sDataPath).getCanonicalPath());

% DATA may itself be a symlink, or (as in the current workspace) it may be a
% real directory containing symlinks to each raw input.  Inspect both the
% package location and every raw file's resolved source location.  Otherwise
% a file-by-file linked, pre-screened export would be reported merely as
% "manifest missing" and its actual provenance would never be checked.
cCandidateManifest = { ...
    fullfile(fileparts(sCanonicalData), 'screening_summary.json'), ...
    fullfile(sCanonicalData, 'screening_summary.json')};
cRawFiles = {'close_cmc.csv','low_cmc.csv','high_cmc.csv','open_cmc.csv', ...
    'market_cap_cmc.csv','volume_cmc.csv','MetaData.mat'};
cCanonicalRawDir = cell(numel(cRawFiles), 1);
for iIdxF = 1:numel(cRawFiles)
    sRawFile = fullfile(sCanonicalData, cRawFiles{iIdxF});
    assert(exist(sRawFile, 'file') == 2, ...
        'Required corrected raw input is missing: %s', sRawFile);
    sCanonicalRaw = char(java.io.File(sRawFile).getCanonicalPath());
    cCanonicalRawDir{iIdxF} = fileparts(sCanonicalRaw);
end
cUniqueRawDir = unique(cCanonicalRawDir, 'stable');
assert(numel(cUniqueRawDir) == 1, ...
    ['Raw CMC panels resolve to different source directories. Do not mix ' ...
     'files from separately screened or separately built exports.']);
sCanonicalRawDir = cUniqueRawDir{1};
cSourceManifest = { ...
    fullfile(sCanonicalRawDir, 'screening_summary.json'), ...
    fullfile(fileparts(sCanonicalRawDir), 'screening_summary.json')};
assert(any(cellfun(@(x)exist(x, 'file') == 2, cSourceManifest)), ...
    ['The resolved raw-data source has no screening_summary.json. A local ' ...
     'certificate cannot substitute for missing source provenance.']);
cCandidateManifest = [cCandidateManifest, cSourceManifest];
cCandidateManifest = unique(cCandidateManifest, 'stable');
lExists = cellfun(@(x)exist(x, 'file') == 2, cCandidateManifest);
cManifest = cCandidateManifest(lExists);
assert(~isempty(cManifest), ...
    ['Corrected input provenance is missing. Provide screening_summary.json ' ...
     'beside DATA and certify exclude_stablecoins=false, min_marketcap=0, ' ...
     'and strict_contiguous=false.']);

% Validate every discoverable manifest.  In particular, a local certificate
% must not override a contradictory manifest beside symlinked source files.
cManifestText = cell(size(cManifest));
vExcludeStable = false(numel(cManifest), 1);
vConfiguredMinMarketCap = NaN(numel(cManifest), 1);
vEffectiveMinMarketCap = NaN(numel(cManifest), 1);
vKeepAllAssets = false(numel(cManifest), 1);
for iIdxM = 1:numel(cManifest)
    sManifestText = fileread(cManifest{iIdxM});
    if ~isempty(sManifestText) && double(sManifestText(1)) == 65279
        sManifestText(1) = [];
    end
    cManifestText{iIdxM} = sManifestText;
    rManifest = jsondecode(sManifestText);
    cRequired = {'exclude_stablecoins','min_marketcap','strict_contiguous'};
    for iIdx = 1:numel(cRequired)
        assert(isfield(rManifest, cRequired{iIdx}), ...
            'Input provenance %s is missing field "%s".', ...
            cManifest{iIdxM}, cRequired{iIdx});
    end

    assert((islogical(rManifest.exclude_stablecoins) || ...
            isnumeric(rManifest.exclude_stablecoins)) && ...
           isscalar(rManifest.exclude_stablecoins) && ...
           isfinite(double(rManifest.exclude_stablecoins)) && ...
           ~logical(rManifest.exclude_stablecoins), ...
        ['Invalid corrected input: stablecoins were removed before market-wide ' ...
         'series and characteristics were constructed. Re-export them.']);
    assert(isnumeric(rManifest.min_marketcap) && ...
           isscalar(rManifest.min_marketcap) && ...
           isfinite(rManifest.min_marketcap) && ...
           rManifest.min_marketcap >= 0, ...
        'Input provenance %s has an invalid min_marketcap.', cManifest{iIdxM});

    % A full-universe exporter may retain a configured threshold in the
    % manifest even when an explicit keep-all mode overrides it. Accept that
    % representation only if the manifest proves that every input asset was
    % retained and none was dropped.
    lKeepAllAssets = isfield(rManifest, 'keep_all_assets') && ...
        (islogical(rManifest.keep_all_assets) || ...
         isnumeric(rManifest.keep_all_assets)) && ...
        isscalar(rManifest.keep_all_assets) && ...
        isfinite(double(rManifest.keep_all_assets)) && ...
        logical(rManifest.keep_all_assets);
    cKeepAllCounts = {'input_asset_files_seen','kept_assets','dropped_assets'};
    lHasKeepAllCounts = all(cellfun(@(s)isfield(rManifest,s), cKeepAllCounts));
    if lKeepAllAssets && lHasKeepAllCounts
        vCounts = double([rManifest.input_asset_files_seen, ...
            rManifest.kept_assets, rManifest.dropped_assets]);
        lKeepAllAssets = all(isfinite(vCounts)) && all(vCounts >= 0) && ...
            vCounts(1) == vCounts(2) && vCounts(3) == 0;
    else
        lKeepAllAssets = false;
    end
    lNoEffectiveMarketCapScreen = rManifest.min_marketcap == 0 || ...
        lKeepAllAssets;
    assert(lNoEffectiveMarketCapScreen, ...
        ['Invalid corrected input: an upstream market-cap screen changes the ' ...
         'raw market and characteristics. Require min_marketcap=0, or an ' ...
         'explicit keep_all_assets=true certificate with input=kept and ' ...
         'dropped_assets=0.']);
    assert((islogical(rManifest.strict_contiguous) || ...
            isnumeric(rManifest.strict_contiguous)) && ...
           isscalar(rManifest.strict_contiguous) && ...
           ~logical(rManifest.strict_contiguous), ...
        ['Invalid corrected input: assets with internal date gaps were removed. ' ...
         'Re-export them and retain the missing asset-date cells as NaN.']);
    vExcludeStable(iIdxM) = logical(rManifest.exclude_stablecoins);
    vConfiguredMinMarketCap(iIdxM) = double(rManifest.min_marketcap);
    vKeepAllAssets(iIdxM) = lKeepAllAssets;
    vEffectiveMinMarketCap(iIdxM) = 0;
end

% b01 has already loaded market caps, so it can directly verify that a
% positive configured threshold under keep-all mode did not mask all
% sub-threshold cells. setup calls without the panel and relies on the
% manifest's complete input/kept/dropped certificate.
lPositiveConfiguredThreshold = vConfiguredMinMarketCap > 0;
if any(lPositiveConfiguredThreshold) && ~isempty(mMarketCap)
    dSmallestConfiguredThreshold = ...
        min(vConfiguredMinMarketCap(lPositiveConfiguredThreshold));
    assert(any(isfinite(mMarketCap(:)) & mMarketCap(:) > 0 & ...
               mMarketCap(:) < dSmallestConfiguredThreshold), ...
        ['keep_all_assets was certified, but the loaded market-cap panel ' ...
         'contains no positive observation below the configured threshold.']);
end

assert(isfield(rMetaData, 'vStableCoin'), ...
    'MetaData.mat must contain the original vStableCoin classification.');
vStableCoin = rMetaData.vStableCoin(:);
assert((islogical(vStableCoin) || isnumeric(vStableCoin)) && ...
    all(isfinite(double(vStableCoin))) && ...
    all(double(vStableCoin) == 0 | double(vStableCoin) == 1), ...
    'MetaData vStableCoin must contain only finite binary flags.');
assert(any(logical(vStableCoin)), ...
    ['The purported unscreened universe contains no stablecoins, although ' ...
     'exclude_stablecoins=false was certified.']);

% Persist a compact certificate in b0DataOLHC.mat.  b02 requires this field,
% so starting midway from a legacy or pre-gate intermediate cannot silently
% bypass the raw-input checks above.
cManifestText = unique(cManifestText, 'stable');
rDigest = java.security.MessageDigest.getInstance('SHA-256');
for iIdxM = 1:numel(cManifestText)
    vBytes = uint8(unicode2native(cManifestText{iIdxM}, 'UTF-8'));
    rDigest.update(typecast(vBytes(:), 'int8'));
    rDigest.update(int8(0));
end
vDigestSigned = int8(rDigest.digest());
vDigest = typecast(vDigestSigned(:), 'uint8');
rInputProvenance = struct();
rInputProvenance.lValidated = true;
rInputProvenance.sManifestSHA256 = ...
    lower(reshape(dec2hex(vDigest, 2).', 1, []));
rInputProvenance.cManifest = cManifest(:);
rInputProvenance.exclude_stablecoins = any(vExcludeStable);
rInputProvenance.min_marketcap = max(vEffectiveMinMarketCap);
rInputProvenance.configured_min_marketcap = max(vConfiguredMinMarketCap);
rInputProvenance.keep_all_assets = all(vKeepAllAssets | ...
    vConfiguredMinMarketCap == 0);
rInputProvenance.strict_contiguous = false;

% A screening manifest certifies exporter settings, not the bytes actually
% consumed. Bind every external data source used anywhere in the full
% pipeline to this build with streaming content hashes. LTW_3factor.mat is
% deliberately omitted: setup.m recreates it atomically from the hashed
% workbook, so hashing the derived MAT would bind a serialization artifact
% rather than an independent source.
cInputNames = [cRawFiles,{ ...
    'screening_summary.json', ...
    'F-F_Research_Data_Factors_daily.CSV', ...
    'LTW_3factor.xlsx', ...
    'UCRY.csv'}];
cInputHashes = cell(size(cInputNames));
vInputBytes = NaN(size(cInputNames));
for iIdxF = 1:numel(cInputNames)
    sInputFile = fullfile(sCanonicalData,cInputNames{iIdxF});
    rInfo = dir(sInputFile);
    assert(numel(rInfo) == 1 && ~rInfo.isdir, ...
        'Required corrected input is missing: %s',sInputFile);
    vInputBytes(iIdxF) = rInfo.bytes;
    cInputHashes{iIdxF} = fFileSHA256(sInputFile);
end
rInputProvenance.cRawInputName = cInputNames(:);
rInputProvenance.cRawInputSHA256 = cInputHashes(:);
rInputProvenance.vRawInputBytes = vInputBytes(:);
rAggregate = java.security.MessageDigest.getInstance('SHA-256');
for iIdxF = 1:numel(cInputNames)
    vRecord = unicode2native(sprintf('%s%c%s%c%.0f%c', ...
        cInputNames{iIdxF},0,cInputHashes{iIdxF},0, ...
        vInputBytes(iIdxF),0),'UTF-8');
    rAggregate.update(typecast(uint8(vRecord(:)),'int8'));
end
vRawDigest = typecast(int8(rAggregate.digest()),'uint8');
rInputProvenance.sRawInputsSHA256 = ...
    lower(reshape(dec2hex(vRawDigest,2).',1,[]));

sPipelineScope = lower(strtrim(getenv('PIPELINE_SCOPE')));
if isempty(sPipelineScope)
    sPipelineScope = 'full';
end
if ~strcmp(sPipelineScope,'baseline')
    rInputProvenance.sPipelineMode = 'full';
else
    rInputProvenance.sPipelineMode = 'baseline-only';
end
rInputProvenance.sValidatedAt = char(datetime('now', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss'));
end
