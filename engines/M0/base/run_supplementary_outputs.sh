#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="${CODE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab 2>/dev/null || true)}"
RESULT_TABLES="$CODE_DIR/Results/Tables"
TMP_DIR="$(mktemp -d /tmp/ctrend_supplementary_XXXXXX)"

TABLE3="$RESULT_TABLES/univariate_portfolio_sorts.tex"
TABLEB2="$RESULT_TABLES/descriptive_statistics_of_asset_pricing_factor_returns.tex"
TABLE6="$RESULT_TABLES/factor_performance_across_research_design_choices.tex"
BACKUP3="$TMP_DIR/table3.tex"
BACKUPB2="$TMP_DIR/tableB2.tex"
BACKUP6="$TMP_DIR/table6.tex"

restore_main_tables() {
  [[ ! -f "$BACKUP3" ]] || cp -f "$BACKUP3" "$TABLE3"
  [[ ! -f "$BACKUPB2" ]] || cp -f "$BACKUPB2" "$TABLEB2"
  [[ ! -f "$BACKUP6" ]] || cp -f "$BACKUP6" "$TABLE6"
  rm -rf "$TMP_DIR"
}
trap restore_main_tables EXIT INT TERM

for required in "$TABLE3" "$TABLEB2" "$TABLE6" \
  "$CODE_DIR/b06Table3_UnivariatePortfolioSorts.m" \
  "$CODE_DIR/b10Table6_FactorPerformanceAcrossResearchDesignChoices.m"; do
  [[ -f "$required" ]] || { echo "Missing prerequisite: $required" >&2; exit 1; }
done

cp -f "$TABLE3" "$BACKUP3"
cp -f "$TABLEB2" "$BACKUPB2"
cp -f "$TABLE6" "$BACKUP6"
cp -f "$CODE_DIR/b06Table3_UnivariatePortfolioSorts.m" "$TMP_DIR/b06_alt.m"
cp -f "$CODE_DIR/b10Table6_FactorPerformanceAcrossResearchDesignChoices.m" "$TMP_DIR/b10_vw.m"
sed -i 's/^lUseLTW = true;/lUseLTW = false;/' "$TMP_DIR/b06_alt.m"
sed -i 's/^lDropEW = false;/lDropEW = true;/' "$TMP_DIR/b10_vw.m"

echo "Generating Table B.7 from the paper-defined alternative-factor switch"
"$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "try, cd('$CODE_DIR'); eval(fileread('$TMP_DIR/b06_alt.m')); copyfile('$TABLE3','$RESULT_TABLES/univariate_portfolio_sorts_alternative_factor_data.tex','f'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
cp -f "$BACKUP3" "$TABLE3"
cp -f "$BACKUPB2" "$TABLEB2"

echo "Generating Figure B.1 and Table B.6 from the paper-defined value-weighted-only switch"
"$MATLAB_BIN" -licmode onlinelicensing -nodisplay -nosplash -batch \
  "try, cd('$CODE_DIR'); eval(fileread('$TMP_DIR/b10_vw.m')); fSaveOpenFigures('b10FigureB1_ValueWeightedResearchDesigns'); copyfile('$TABLE6','$RESULT_TABLES/factor_performance_across_research_design_choices_value_weighted_only.tex','f'); exit(0); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end"
cp -f "$BACKUP6" "$TABLE6"

for output in \
  "$RESULT_TABLES/univariate_portfolio_sorts_alternative_factor_data.tex" \
  "$RESULT_TABLES/factor_performance_across_research_design_choices_value_weighted_only.tex" \
  "$CODE_DIR/Results/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure01.png" \
  "$CODE_DIR/Results/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure02.png" \
  "$CODE_DIR/Results/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure03.png" \
  "$CODE_DIR/Results/Figures/b10FigureB1_ValueWeightedResearchDesigns_figure04.png"; do
  [[ -s "$output" ]] || { echo "Supplementary output missing: $output" >&2; exit 1; }
done

echo "Supplementary outputs completed"
