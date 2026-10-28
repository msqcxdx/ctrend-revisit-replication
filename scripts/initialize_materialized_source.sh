#!/usr/bin/env bash
# CTREND_REVISIT_FILE_PURPOSE: Initialize one materialized engine with verified raw inputs and isolated bootstrap directories.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
SOURCE="${2:-}"
case "$ID" in
  M0_D0|M0_D1|M0_D2) METHOD=M0 ;;
  M1_D0|M1_D1|M1_D2) METHOD=M1 ;;
  M2_D0|M2_D1|M2_D2) METHOD=M2 ;;
  *) exit 2 ;;
esac
[[ -d "$SOURCE" ]] || exit 2
RAW="$ROOT/data/raw/common"
for file in F-F_Research_Data_Factors_daily.CSV LTW_3factor.xlsx MetaData.mat \
  UCRY.csv close_cmc.csv high_cmc.csv low_cmc.csv market_cap_cmc.csv \
  open_cmc.csv volume_cmc.csv; do
  [[ -f "$RAW/$file" && ! -L "$RAW/$file" ]] || {
    echo "required raw file is not installed: $file" >&2; exit 2;
  }
done

if [[ "$METHOD" == M0 || "$METHOD" == M2 ]]; then
  SEED="$SOURCE/.raw_input_seed"
  mkdir "$SEED"
  for file in F-F_Research_Data_Factors_daily.CSV LTW_3factor.xlsx MetaData.mat \
    UCRY.csv close_cmc.csv high_cmc.csv low_cmc.csv market_cap_cmc.csv \
    open_cmc.csv volume_cmc.csv; do
    cp --reflink=auto -- "$RAW/$file" "$SEED/$file"
  done
else
  BOOTSTRAP="${BOOTSTRAP_RESULTS_ROOT:-$ROOT/runtime/bootstrap_results/$ID}"
  [[ "$BOOTSTRAP" == /* ]] || {
    echo "BOOTSTRAP_RESULTS_ROOT must be absolute" >&2; exit 2;
  }
  mkdir -p "$BOOTSTRAP"
  [[ ! -e "$SOURCE/DATA" && ! -e "$SOURCE/Results" &&
     ! -e "$SOURCE/.canonical" ]] || {
    echo "fresh M1 materialization unexpectedly has mutable aliases" >&2; exit 2;
  }
  ln -s "$RAW" "$SOURCE/DATA"
  ln -s "$BOOTSTRAP" "$SOURCE/Results"
fi
echo "MATERIALIZED_SOURCE_INITIALIZED experiment=$ID source=$SOURCE"
