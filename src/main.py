"""End-to-end analysis pipeline.

Run from the repository root with the project environment active:

    python -m src.main

Reproduces the full analysis of the legacy R script:
  1. Load the panel and build the Mathematics and Language samples.
  2. Estimate the four value-added models (M1-M4) for each subject.
  3. Build the school value-added table, rankings and reclassification.
  4. Save all tables to results/tables/ and figures to results/figures/.
"""
from __future__ import annotations

import warnings

import pandas as pd

from . import config, data_prep, models, plots, rankings

_RULE = "=" * 70


def _header(title: str) -> None:
    print(f"\n{_RULE}\n{title}\n{_RULE}")


def main() -> None:
    warnings.simplefilter("ignore")

    # 1. Data --------------------------------------------------------------
    samples = data_prep.build()
    _header("SAMPLES")
    for subject, df in samples.items():
        print(f"  {subject:12} students = {len(df):>6} | schools = {df['school_code'].nunique()} | "
              f"pre-post corr = {df['baseline_score'].corr(df['outcome_score']):.3f}")

    # 2-3. Models, value-added and rankings --------------------------------
    results = models.run_all(samples)
    rk = rankings.run_all(results)

    coefficients = pd.concat([results[s]["coefficients"] for s in results], ignore_index=True)
    model_stats = pd.concat([results[s]["model_stats"] for s in results], ignore_index=True)

    _header("TABLE 2 - Model fit and variance decomposition")
    print(model_stats[["subject", "model", "r_squared", "rmse", "sigma2_school",
                       "sigma2_residual", "icc", "aic"]]
          .to_string(index=False, float_format=lambda v: f"{v:.3f}", na_rep="--"))

    _header("TABLE 3 - Coefficient estimates")
    print(coefficients.to_string(index=False, float_format=lambda v: f"{v:.3f}"))

    _header("TABLE 4 - Ranking comparisons")
    print(rk["ranking_comparisons"].to_string(index=False, float_format=lambda v: f"{v:.3f}"))

    _header("TABLE 8 - Mathematics vs Language value-added")
    print(rk["math_language_correlation"].to_string(index=False, float_format=lambda v: f"{v:.3f}"))

    # 4. Persist tables and figures ---------------------------------------
    config.TABLES_DIR.mkdir(parents=True, exist_ok=True)
    coefficients.to_csv(config.TABLES_DIR / "table3_coefficients.csv", index=False)
    model_stats.to_csv(config.TABLES_DIR / "table2_model_fit_variance.csv", index=False)
    rk["ranking_comparisons"].to_csv(config.TABLES_DIR / "table4_ranking_comparisons.csv", index=False)
    rk["transition_matrix"].to_csv(config.TABLES_DIR / "table5_transition_matrix.csv", index=False)
    rk["top_bottom"].to_csv(config.TABLES_DIR / "table6_top_bottom_schools.csv", index=False)
    rk["va_distribution"].to_csv(config.TABLES_DIR / "table7_va_distribution.csv", index=False)
    rk["math_language_correlation"].to_csv(config.TABLES_DIR / "table8_math_language_correlation.csv", index=False)
    for subject in results:
        safe = subject.lower()
        results[subject]["school_effects"].to_csv(
            config.TABLES_DIR / f"school_value_added_{safe}.csv", index=False)

    saved = plots.save_all(samples, results)

    _header("OUTPUTS WRITTEN")
    for path in sorted(config.TABLES_DIR.glob("*.csv")):
        print(f"  {path.relative_to(config.ROOT)}")
    for path in saved:
        print(f"  {path.relative_to(config.ROOT)}")


if __name__ == "__main__":
    main()
