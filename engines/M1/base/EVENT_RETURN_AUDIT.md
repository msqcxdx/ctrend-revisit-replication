# Extreme-return event and raw-data correction audit

Audit date: 2026-07-25 UTC

This audit covers the complete 2014--2022 input sample, not only assets held
by CTREND. A large return is an investigation trigger, never a deletion or
correction rule. No asset is removed because it has an extreme return.

## 1. Immutable source and audit population

The six vendor panels and metadata remain unchanged. v2 validates and hashes
them first, then applies only verified same-CMCID integer unit-continuity
adjustments in memory before preserving the economic endpoint-close layer.

| source | SHA256 |
|---|---|
| `close_cmc.csv` | `a052fde4de348fc6398f52a1f5c5f2a076fe375d59dd651dfd2f906fb6d47522` |
| `market_cap_cmc.csv` | `e0c750db735646c99c152313635ae80b2199f8e2b5f0e8d1b2d0ed0f7ea3811c` |
| `volume_cmc.csv` | `542806308b51eacaaa67cc4a60389fb21d0849d389a9fa01012375e2369e5225` |
| `MetaData.mat` | `677ed051adef679df963c62168f4f57c6f66bf9b1f22f07c41601e2fe6626903` |

`audit/scan_extreme_raw_returns.m` found:

- 12,146 adjacent-day CMC gross returns at least 5 or at most 0.2;
- 5,173 fixed Tuesday-to-Tuesday endpoint gross returns at least 5 or at
  most 0.2;
- 2,833 unique CMC assets in the union;
- 1,621 daily and 650 weekly events whose formation market cap was at least
  USD 1 million.

The complete raw event rows, not a selected sample, are saved in:

- `audit/output/daily_extreme_discontinuity_inventory.csv`;
- `audit/output/weekly_extreme_return_inventory.csv`;
- `audit/output/daily_extreme_event_disposition.csv`; and
- `audit/output/weekly_extreme_event_disposition.csv`.

## 2. Independent-source search

Every one of the 2,833 event assets was searched at CoinLore. Mapping is
accepted only when both normalized project name and symbol match exactly.
Ticker-only matches, nearest names and human-selected alternatives fail
closed. This produced:

- 1,645 unambiguous asset mappings with external history;
- 5,889 daily and 2,148 weekly exact-UTC external endpoint windows;
- 4,485 cached search/history response files, totaling 113,712,475 bytes,
  each with its own SHA256 in `coinlore_asset_mapping.csv`.

No nearest-date substitution is permitted: both external endpoints must
equal the CMC UTC dates exactly. CoinLore states that its core price history
is internally produced from multiple exchange APIs rather than copied from a
single third-party aggregator:
<https://www.coinlore.com/methodology>.

Cross-source classifications before the causal level gate were:

| comparison | daily | weekly |
|---|---:|---:|
| no unambiguous exact external window | 6,257 | 3,025 |
| external normal while CMC is extreme | 4,868 | 1,041 |
| external corroborates extreme direction | 526 | 943 |
| partial/ambiguous directional evidence | 264 | 99 |
| external extreme in the opposite direction | 231 | 65 |

Disagreement alone is not sufficient to alter CMC. Different venue coverage,
illiquidity and daily-close conventions can generate legitimate source
differences.

## 3. Verified holder-continuous unit corrections

For a documented token conversion, all pre-transition OHLC is expressed in
the post-transition holder unit. On a mixed-unit transition bar, only the
identified fields are scaled and high/low is minimally restored to contain
the corrected open and close.

| CMC ID | asset | transition | documented holder conversion | raw gross | holder-unit gross |
|---:|---|---|---:|---:|---:|
| 638 | Trollcoin | 2015-12-02 | 10 old TROLL = 1 new TROLL | 6.6152 | 0.6615 |
| 895 | Xaurum | 2016-08-22 | 1 XAU = 8,000 XAUR | 0.0001468 | 1.1742 |
| 1902 | MyBit | 2018-06-07 | 1 old MYB = 36 new MYB | 0.03858 | 1.3888 |
| 3468 | Fivebalance | 2019-04-18 | 50 old FBN = 1 new FBN | 85.7113 | 1.7142 |
| 4069 | Blockburn | 2020-03-06 | 1 old BURN = 100 new BURN | 0.002574 | 0.2574 |
| 4275 | Furucombo | 2021-01-20 | CMC pre-launch quote-unit error, multiply prior prices by 1,000 | 1,133.1043 | 1.1331 |
| 5834 | ADD.xyz | 2021-03-10 | 10 PLT = 1 ADD | 13.7287 | 1.3729 |

Evidence:

- Trollcoin's December 2015 chain swap is documented in its whitepaper, and
  the contemporaneous swap announcement gives the 10:1 ratio:
  <https://trollcoin.com/files/Trollcoin_Whitepaper.pdf> and
  <https://bitcointalk.org/index.php?topic=452810.0>.
- Xaurum's migration from XAU to XAUR was 1:8,000:
  <https://themerkle.com/xaurum-starts-trading-on-c-cex/>.
- MyBit announced that every old MYB holder would receive 36 new tokens:
  <https://medium.com/mybit-dapp/as-we-are-on-the-brink-of-entering-mybits-new-era-we-have-a-very-important-announcement-to-make-a4cda1cd6956>.
- Fivebalance's migration from ERC-20 to its own chain was 50:1:
  <https://medium.com/tag/fivebalance>.
- Blockburn's exchange migration notice gives 1:100:
  <https://www.waivio.com/@boynman/blockburn-burn-swap>.
- ADD.xyz's project announcement gives 10 PLT for 1 ADD:
  <https://medium.com/addxyz/add-token-launches-token-swap-complete-4725ad948fb3>.
- COMBO is not a holder split. The project fixed total supply at
  100,000,000 and launched 4% of supply in January 2021, whereas the raw
  pre-break price/cap identity implies roughly 42 billion tokens and the
  post-break identity roughly 42 million—a discontinuity of approximately
  1,000.215. The smallest coherent repair is a factor-1,000 pre-break CMC
  quote-unit correction:
  <https://medium.com/furucombo/announcing-combo-token-launch-53ea05a68e74>
  and
  <https://docs.furucombo.app/governance/combo-is-here/combo-distribution>.

Ten transition-adjacent market-cap cells are also corrected where CMC mixes
the new price unit with stale old-unit circulating supply: Trollcoin on
2015-12-02; Fivebalance on 2019-04-18--22 and 2019-04-24; and Blockburn on
2020-03-06--08. No other market-cap cell is changed.

## 4. Verified real events that remain economic returns

There is no production external-error gate. Dated events are used to explain
or unit-normalize a same-CMCID history, never to delete an extreme payoff.

- DNotes 2.0 was a 1:1 swap. It changes neither holder units nor the economic
  return and is preserved:
  <https://www.prnewswire.com/news-releases/dnotes-prepares-to-introduce-dnotes-20-upgrade-launches-new-bitcointalk-forum-300461907.html>.
- The May 2022 Terra/LUNC collapse and hyperinflation are real market events
  and remain untrimmed economic payoffs.
- Origin Dollar's 2020-11-17 move occurred with a documented attack draining
  more than USD 7 million; both exploit and relaunch windows are preserved:
  <https://www.originprotocol.com/blog/origin-dollar-ousd-detailed-compensation-plan?lang=en>.
- Marlin/POND's first trading/price-discovery day is corroborated by an
  independent history that records an 82.09% loss on 2020-12-22:
  <https://www.coinglass.com/currencies/POND/historical-data>.

INNBCL's influential March/April 2020 returns predate its publicly discussed
June token swap. Its certified CMC observations have single/double-digit or
near-zero dollar volume and unstable implied supply. Independent research
also flags the CMC series as implausible:
<https://bitcointalk.org/index.php?topic=5242368.0> and
<https://alexandria.unisg.ch/server/api/core/bitstreams/2bc8397d-47dd-4f66-8467-9004b2c9d212/content>.
Nevertheless, absent an exact contemporaneous causal correction signal, v2
preserves an INNBCL cell rather than deleting the asset or retrospectively
labelling every thin print as bad.

## 5. External disagreements are audit-only

The date-causal comparison still evaluates 5,630 target cells. It identifies
2,600 factor-five candidate disagreements across 571 assets, but does not
modify production data. Its output is
`audit/output/causal_point_external_disagreement_candidates.csv`.

The independent decision package
`cmc_price_cell_audit_decision_package_20260725.zip` rechecked the exact
2,600-row input and found:

- 2,570 local CMC closes exactly reproduced by a fresh official CMC daily
  response;
- 30 more exactly reproduced by official CMC 1h/4h reaggregation;
- only one usable independent price comparator for 2,458 rows;
- no usable independent comparator for 142 rows because CoinLore identity
  was ambiguous or mismatched;
- no identity-verified exchange candle or second independent historical
  source; and
- zero rows meeting the audit's confirmed-CMC-error standard.

Fresh CMC agreement proves source fidelity, not economic truth. Conversely,
one CoinLore disagreement does not prove CMC false. Under the minimal-change
burden of proof, all 2,600 CMC OHLC observations remain unchanged. The three
previously disputed bitCNY observations also remain unchanged: peg evidence
and a large reversal do not by themselves authorize missing raw prices.

The pointwise comparison, future-bracketed 2,226-cell audit and 25,924-cell
long-episode audit are sensitivity/evidence artifacts only. None is loaded by
`b01ReadData.m`, included in the scientific fingerprint, or packaged as a
production input.

## 6. CMCID boundary and Pundi X

CMC ID is the asset-series key. Different IDs remain different assets even
when a project describes a successor relationship. Pundi X makes this rule
explicit:

- CMC 2603 is Pundi X (Old), symbol NPXS;
- CMC 9040 is Pundi X (New), symbol PUNDIX; and
- the official project conversion is 1,000 NPXS for 1 PUNDIX.

Because the IDs differ, v2 neither splices these columns nor adjusts old NPXS
using new PUNDIX. The 2022 NPXS observations remain the old-token series. A
cross-ID redemption-value series can be reported only as a separate
sensitivity, not as raw-data cleaning.

## 7. Complete disposition and remaining uncertainty

After applying precedence—same-CMCID unit transition, verified real event,
external comparison, unresolved—the raw inventories have these dispositions:

| disposition | daily | weekly |
|---|---:|---:|
| cross-source candidate preserved, audit only | 3,260 | 780 |
| holder-continuous unit repair | 7 | 7 |
| verified real event preserved | 7 | 3 |
| independent source corroborates direction; preserve | 513 | 929 |
| causal gate not met; preserve | 1,727 | 318 |
| no decisive exact external evidence; preserve | 6,632 | 3,136 |
| **total** | **12,146** | **5,173** |

“Unresolved” is not silently converted to “valid” or “invalid.” It means
there is not enough exact, unambiguous, point-in-time evidence for a repair,
so the original return is retained. This is the conservative consequence of
the user's rule that an asset must not be excluded merely because its return
is abnormal.

## 8. Executable validation

`audit/validate_v2_raw_corrections.m` applied the production unit rules to the
real raw panels while retaining 579 relevant/audit asset columns. It
verified:

- seven price-history unit rules and valid transition OHLC;
- ten and only ten changed market-cap cells;
- zero prices made missing;
- all 2,600 external-disagreement candidate closes remain finite and exactly
  unchanged;
- NPXS 2603 and PUNDIX 9040 remain completely unchanged independent columns;
- every changed real close belongs to one of the seven same-CMCID unit rules;
- every volume cell is unchanged;
- no asset is added, deleted or reordered.

The full application record is
`audit/output/v2_raw_correction_application_summary.csv`; transition returns,
market-cap changes and the 2,600 preserved prices have separate CSVs in the
same directory. No external-price CSV is a production runtime dependency.
