"""The four value-added specifications and the school-level value-added estimates.

  * M1 - OLS  y ~ baseline                                   (VA = mean residual)
  * M2 - OLS  y ~ within-school baseline + school-mean       (VA = mean residual)
  * M3 - HLM  y ~ baseline + (1 | school)                    (VA = predicted RE)
  * M4 - HLM  y ~ within + school-mean + (1 | school)        (VA = predicted RE)

statsmodels ``MixedLM`` (REML) is the Python counterpart of R's ``lme4::lmer``.
The models are fit with the conjugate-gradient optimiser, which converges
reliably on this data.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

from . import config


# --- OLS models (M1, M2) -----------------------------------------------------

def fit_ols(df: pd.DataFrame, rhs: list[str]) -> dict:
    """Fit an OLS model; return coefficients, fit stats and per-row residuals."""
    formula = "outcome_score ~ " + " + ".join(rhs)
    res = smf.ols(formula, data=df).fit()
    n_params = len(res.params)  # includes intercept
    return {
        "params": res.params,
        "bse": res.bse,
        "pvalues": res.pvalues,
        "r_squared": res.rsquared,
        "rmse": float(np.sqrt(np.mean(res.resid ** 2))),
        # R's AIC(lm) counts the residual variance as an extra parameter.
        "aic": float(-2 * res.llf + 2 * (n_params + 1)),
        "resid": res.resid,
    }


# --- HLM models (M3, M4) -----------------------------------------------------

def fit_hlm(df: pd.DataFrame, rhs: list[str]) -> dict:
    """Fit a random-intercept HLM by REML and return fixed effects, variance
    components, predicted school random effects and fit stats."""
    formula = "outcome_score ~ " + " + ".join(rhs)
    res = smf.mixedlm(formula, df, groups=df["school_code"]).fit(
        reml=True, method=["cg"])

    theta = float(res.cov_re.iloc[0, 0])   # sigma^2_school
    sigma = float(res.scale)               # sigma^2_residual
    random_effects = {str(k): float(v.iloc[0]) for k, v in res.random_effects.items()}
    # Conditional residuals (fitted values include the random effects).
    resid_cond = df["outcome_score"].to_numpy() - res.fittedvalues.to_numpy()

    return {
        "params": res.fe_params,
        "bse": res.bse_fe,
        "pvalues": res.pvalues[res.fe_params.index],
        "sigma2_school": theta,
        "sigma2_residual": sigma,
        "icc": theta / (theta + sigma),
        "rmse": float(np.sqrt(np.mean(resid_cond ** 2))),
        "aic": float(-2 * res.llf),  # matches R's AIC() for the REML lmer fits
        "random_effects": random_effects,
    }


# --- Per-subject estimation --------------------------------------------------

def _school_mean_resid(df: pd.DataFrame, resid: pd.Series, name: str) -> pd.DataFrame:
    tmp = df[["school_code"]].copy()
    tmp[name] = resid.to_numpy()
    return tmp.groupby("school_code", observed=True)[name].mean().reset_index()


def estimate_subject(df: pd.DataFrame, subject: str) -> dict:
    """Estimate all four models and build the school value-added table."""
    m1 = fit_ols(df, ["baseline_score"])
    m2 = fit_ols(df, ["baseline_within_school", "school_baseline_mean"])
    m3 = fit_hlm(df, ["baseline_score"])
    m4 = fit_hlm(df, ["baseline_within_school", "school_baseline_mean"])

    # School-level value-added: mean residual (OLS) or predicted RE (HLM).
    school = df.groupby("school_code", observed=True).agg(
        school_n_students=("school_n_students", "first"),
        school_baseline_mean=("school_baseline_mean", "first"),
        school_outcome_mean=("outcome_score", "mean"),
    ).reset_index()

    va1 = _school_mean_resid(df, m1["resid"], "va_ols_simple")
    va2 = _school_mean_resid(df, m2["resid"], "va_ols_context")
    school = school.merge(va1, on="school_code").merge(va2, on="school_code")
    school["school_code"] = school["school_code"].astype(str)
    school["va_hlm_simple"] = school["school_code"].map(m3["random_effects"])
    school["va_hlm_context"] = school["school_code"].map(m4["random_effects"])

    # Ranks: 1 = highest value-added (R's min_rank(desc(.))).
    for col, rank in [("va_ols_simple", "rank_ols_simple"),
                      ("va_ols_context", "rank_ols_context"),
                      ("va_hlm_simple", "rank_hlm_simple"),
                      ("va_hlm_context", "rank_hlm_context")]:
        school[rank] = school[col].rank(ascending=False, method="min").astype(int)
    school["rank_change_m1_m3"] = (school["rank_ols_simple"] - school["rank_hlm_simple"]).abs()

    coefficients = _coefficient_table(subject, {"M1: OLS": m1, "M2: OLS + composition": m2,
                                                "M3: HLM": m3, "M4: HLM + composition": m4})
    model_stats = _model_stats_table(subject, df, m1, m2, m3, m4)
    return {"school_effects": school, "coefficients": coefficients, "model_stats": model_stats}


def _coefficient_table(subject: str, models: dict) -> pd.DataFrame:
    rows = []
    for model_name, fit in models.items():
        for term in fit["params"].index:
            rows.append({
                "subject": subject, "model": model_name, "term": term,
                "estimate": float(fit["params"][term]),
                "std_error": float(fit["bse"][term]),
                "p_value": float(fit["pvalues"][term]),
            })
    return pd.DataFrame(rows)


def _model_stats_table(subject, df, m1, m2, m3, m4) -> pd.DataFrame:
    n = len(df)
    k = df["school_code"].nunique()
    common = dict(subject=subject, n_students=n, n_schools=k)
    return pd.DataFrame([
        {**common, "model": "M1: OLS", "estimator": "OLS", "r_squared": m1["r_squared"],
         "rmse": m1["rmse"], "sigma2_school": np.nan, "sigma2_residual": np.nan,
         "icc": np.nan, "aic": m1["aic"]},
        {**common, "model": "M2: OLS + composition", "estimator": "OLS", "r_squared": m2["r_squared"],
         "rmse": m2["rmse"], "sigma2_school": np.nan, "sigma2_residual": np.nan,
         "icc": np.nan, "aic": m2["aic"]},
        {**common, "model": "M3: HLM", "estimator": "HLM", "r_squared": np.nan,
         "rmse": m3["rmse"], "sigma2_school": m3["sigma2_school"],
         "sigma2_residual": m3["sigma2_residual"], "icc": m3["icc"], "aic": m3["aic"]},
        {**common, "model": "M4: HLM + composition", "estimator": "HLM", "r_squared": np.nan,
         "rmse": m4["rmse"], "sigma2_school": m4["sigma2_school"],
         "sigma2_residual": m4["sigma2_residual"], "icc": m4["icc"], "aic": m4["aic"]},
    ])


def run_all(samples: dict) -> dict:
    """Estimate both subjects; return per-subject results."""
    return {subject: estimate_subject(df, subject) for subject, df in samples.items()}
