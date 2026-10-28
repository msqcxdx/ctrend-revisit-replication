# Data availability and rights boundary

The research sample concerns daily cryptocurrency OHLC, volume and market capitalization over a historical window sufficient to form weekly CTREND observations from April 2015 through May 2022. The accepted internal input panel has a separate SHA-256 inventory at `data/RAW_INPUTS.sha256`; this file lists hashes, **not** the vendor observations or a transferable data license.

| Input | Public repository | Access and limitation |
| --- | --- | --- |
| CMC open, high, low, close, volume and market-cap panels | Not included | Obtain under your own applicable CMC agreement or other lawful access. No redistribution grant for this project's raw snapshot was documented. See the [CMC API terms](https://pro.coinmarketcap.com/user-agreement) and confirm the terms governing your actual acquisition channel. |
| Author's original CTREND factor workbook/code | `reference/dataverse_files.zip` and a derived weekly CSV | [Harvard Dataverse DOI 10.7910/DVN/NTIVT8](https://doi.org/10.7910/DVN/NTIVT8), dataset metadata CC0 1.0. An embedded GRS helper retains its separate BSD attribution. This does not license CMC raw quotes. |
| LTW three-factor, Fama–French daily factors, UCRY | Not included | Retrieve from the original creators under their own terms. Their source links are listed in the Dataverse package's `0_readme.txt`. |
| Per-coin holdings, source prices, full 18×3,072 model outputs, detailed follow-up payloads | Not included | Held in controlled storage pending rights review and a separately authorized access route. Public summary tables cannot reconstruct these inputs. |
| MATLAB and toolboxes | Not included | Obtain a suitable licensed installation; required product names are in `environment/TOOLBOXES.txt`. |

The six raw CMC matrix names expected by the controlled input schema are `open_cmc.csv`, `high_cmc.csv`, `low_cmc.csv`, `close_cmc.csv`, `volume_cmc.csv`, and `market_cap_cmc.csv`; additional metadata and the three auxiliary input files are required. `cmc_acquisition/bundle.py` and `scripts/data_bundle.py` describe/validate the **interface**, not permission to collect data. The online downloader was intentionally excluded from the public export pending channel-specific permission review.

The source code, accepted summaries, input hashes and original author package are separate rights objects. The release ledger records each disposition. No DOI for a public full-run archive is asserted.
