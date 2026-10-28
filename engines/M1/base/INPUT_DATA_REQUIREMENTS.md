# Corrected Baseline CMC Input Contract

This run reproduces only the paper baseline, but it still requires an
unscreened raw universe. The old pipeline constructs value-weighted market
return and market illiquidity before applying baseline's stablecoin and USD 1
million formation-time filters. Those common series enter multiple
characteristics. Pre-removing even never-eligible assets can therefore change
baseline estimates.

## Required files and axes

`DATA/` must contain the six daily panels `close_cmc.csv`, `open_cmc.csv`,
`high_cmc.csv`, `low_cmc.csv`, `market_cap_cmc.csv`, and `volume_cmc.csv`, plus
`MetaData.mat`.

- All six panels must have exactly the same strictly increasing, unique daily
  date axis and the same finite, unique CMC asset IDs in the same order.
- The shared calendar is continuous. This does **not** mean that each asset
  must be continuous: an asset's internal missing dates remain `NaN` in its
  cells.
- `MetaData.mat` must retain the original `vStableCoin` classification.
- Assets with no usable core observation at all may be absent. Otherwise an
  asset must not be removed because it is a stablecoin, remains below a later
  threshold, or contains an internal gap; missing asset-date cells stay `NaN`.

## Provenance manifest

Place `screening_summary.json` beside the underlying `DATA/` directory. The
validator follows both a directory symlink and individual raw-file symlinks,
requires all seven raw inputs to resolve to one source directory, and validates
every manifest it can discover. The preferred representation is:

```json
{
  "exclude_stablecoins": false,
  "min_marketcap": 0,
  "strict_contiguous": false
}
```

A positive configured `min_marketcap` is also accepted when the exporter
explicitly certifies `keep_all_assets=true`, `input_asset_files_seen ==
kept_assets`, and `dropped_assets=0`. In that case `b01` additionally verifies
that the loaded panel really contains positive market-cap cells below the
configured threshold. This distinguishes an unused legacy parameter from an
effective screen.

An effective upstream market-cap cutoff, stablecoin deletion, or
`strict_contiguous=true` is rejected. A contradictory local
manifest cannot override the manifest beside a symlinked source. On success,
`b01ReadData` stores a SHA-256 certificate and source-code fingerprint in
`b0DataOLHC.mat`; `b02` refuses older or source-stale intermediates.

Within this certified universe, the daily raw-market statistic uses precisely
the asset-days having a finite current return and a positive finite lagged
market cap, with weights re-normalized over that observable date-t cross-section.
Stablecoin, size, price, history-length, and CTREND complete-case filters do not
enter it. An internal gap remains `NaN` for that asset-date; it is not imputed as
zero and does not erase other assets' observable market return.

## Packaged input

The run-local `DATA` snapshot contains 10,314 of 10,314 input assets and
reports `dropped_assets=0`, `keep_all_assets=true`,
`exclude_stablecoins=false`, and `strict_contiguous=false`. Its configured
`min_marketcap=1000000` is an overridden legacy parameter: the market-cap panel
contains positive observations below USD 1 million. It therefore satisfies the
effective unscreened contract.
