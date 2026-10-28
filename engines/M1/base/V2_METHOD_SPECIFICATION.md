# CTREND corrected pipeline v2 — method specification

> Historical July-2026 specification retained for provenance. It is not the
> normative specification of the isolated 24-August-2026 new-v2 3 x 3 source.
> The current common missing-data and no-cash same-leg terminal-settlement
> rules are defined in `docs/METHOD_BOUNDARIES.md` and executable tests.

This directory is an independent source copy. It does not share `DATA`,
`Results`, `.canonical`, logs, or runtime-code links with `corrected_code/`.
No v2 result is valid unless it is produced from a v2 run whose source
fingerprint and weekly data-build ID match the saved artifacts.

## 1. Minimal historical-label outlier rule

For a target week `t`:

1. construct the formation universe using information available at each
   historical week;
2. for every realized train/validation week `s < t`, fit the lower and upper
   quantiles from the finite strict statistical returns in week `s`'s own
   formation universe;
3. truncate or winsorize only week `s`'s historical labels with those
   week-`s` cutoffs;
4. never include `t` or a future week in a cutoff reference;
5. keep the target statistical label as the raw strict core return; and
6. keep target portfolio P&L as the raw positive-close endpoint return.

The cutoff reference is independent of predictor availability. A missing
predictor may reduce one regression's support, but it cannot change the
weekly return-cleaning threshold.

Validation weeks are already realized at target formation. They are therefore
cleaned on their own weekly cross-sections before equation-(10) selection.
The selected set is then fixed for the target week as before.

## 2. Figure 1

Average-return and Sharpe bars use explicit signed `yticks`, matching
`yticklabels`, deterministic `ylim`, and `yline(0)`. Axis limits are computed
from the plotted values and always include zero. This is a presentation fix;
it does not change any factor return or statistic.

## 3. Table 6

### Paper table

The main table retains the paper's 55,296 applicable method-design cells:

- 3,072 b09 designs;
- two portfolio breakpoints;
- five estimators with one applicable forecast-weight/validation definition;
  and
- CS-C-ENet with all four forecast-weight/validation definitions.

Each paper cell remains a method-specific available-case Sharpe ratio, and
the table is explicitly labelled as such. Exact method-specific weekly N is
saved.

### Parallel strict estimator comparison

For estimator comparisons, forecast weighting is fixed to equal and
validation to no, producing one definition of each of the six estimators in
every one of the 6,144 balanced base design cells. From the saved b09 factor
returns, v2 reports:

- own-week Sharpe, N, start/end date, and scheduled-week coverage;
- all-six-estimator common-week Sharpe and the same support audit;
- all 15 pairwise common-week Sharpes, differences, common/union N, and
  Jaccard overlap; and
- scheduled, eligible, estimated, finite, expected-failure, unexpected-
  failure, detailed ENet status, and empty-selection counts from b09.

The intersection mask is formed independently within each fixed
design/breakpoint cell. No return is filled with zero, carried across a gap,
or borrowed from a different design cell. Cross-design summaries impose a
second balanced-cell gate: every compared Sharpe must be defined and common-
week support must cover at least 50% of the full scheduled OOS calendar.
Intersection/union overlap must also be at least 50%, preventing a small but
perfectly coincident support from passing. Both denominators are reported
separately. Thus methods cannot be compared after separately dropping
different failed design cells. The parallel table is a comparability audit;
it does not replace the published table.

## 4. Extreme endpoint events

`EVENT_RETURN_AUDIT.md` records the complete universe-wide inventory,
external comparison, event evidence and row-level disposition. The immutable
vendor files are hashed before v2 applies the following input-specific layer
in memory:

1. seven documented holder-continuous unit histories are expressed in their
   post-transition units by adjusting older raw OHLC before any return,
   weekly aggregation, characteristic or technical indicator is computed;
2. ten exact stale-supply market-cap cells adjacent to those same-CMCID unit
   transitions are corrected; and
3. different CMCIDs remain different assets and are never spliced or
   rescaled across columns, even when a project documents a conversion (for
   example NPXS CMCID 2603 and PUNDIX CMCID 9040).

The independently reproduced 2,600-row CMC-versus-CoinLore disagreement
list is retained only as an audit candidate list. The independent decision
package re-fetched all 2,600 CMC observations but provided no second
independent historical price source or verified exchange candle. Therefore
none of those observations, including the three disputed bitCNY dates, is
changed or made unavailable in the production pipeline. A large return or
one-source disagreement is evidence for investigation, not evidence that
authorizes a data edit.

Corrections never use CTREND membership, predictor availability or a future
portfolio payoff. No asset is removed, no observed return is filled with
zero or cash, and a genuinely absent selected endpoint still fails closed
under the existing portfolio accounting rule. Only executable MATLAB files
enter the scientific and runner source inventories; external comparison
tables remain non-production audit evidence.
