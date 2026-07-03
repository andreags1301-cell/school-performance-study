"""School-ranking comparisons and reclassification (report Tables 4-8).

Translates the value-added estimates into ranking stability (Spearman), quartile
transition matrices, selected top/bottom schools, the distribution of the
preferred estimate, and the Mathematics-Language correlation.
"""
from __future__ import annotations

import pandas as pd
from scipy import stats


# --- Table 4: ranking stability ---------------------------------------------

def _compare(df: pd.DataFrame, subject: str, label: str,
             rank_a: str, rank_b: str) -> dict:
    changes = (df[rank_a] - df[rank_b]).abs()
    spearman = stats.spearmanr(df[rank_a], df[rank_b]).statistic
    return {
        "comparison": label, "subject": subject,
        "spearman": spearman,
        "mean_rank_change": changes.mean(),
        "median_rank_change": changes.median(),
        "max_rank_change": int(changes.max()),
        "schools": len(df),
    }


def ranking_comparisons(effects: dict) -> pd.DataFrame:
    """Table 4 - Spearman correlation and rank movement across VA definitions."""
    rows = []
    for label, a, b in [("M1 vs M3", "rank_ols_simple", "rank_hlm_simple"),
                        ("M2 vs M4", "rank_ols_context", "rank_hlm_context"),
                        ("M3 vs M4", "rank_hlm_simple", "rank_hlm_context")]:
        for subject in ("Mathematics", "Language"):
            rows.append(_compare(effects[subject], subject, label, a, b))
    # Order like the report: group by comparison, Maths then Language.
    return pd.DataFrame(rows)


# --- Table 5: quartile transition matrix ------------------------------------

def transition_matrix(effects: dict) -> pd.DataFrame:
    """Table 5 - quartile transitions from Model 3 to Model 4 rankings."""
    labels = ["Q1 high", "Q2", "Q3", "Q4 low"]
    frames = []
    for subject in ("Mathematics", "Language"):
        df = effects[subject].copy()
        # Split schools into quartiles by rank: rank 1 (best) -> Q1 high.
        df["before_q"] = pd.qcut(df["rank_hlm_simple"], 4, labels=labels)
        df["after_q"] = pd.qcut(df["rank_hlm_context"], 4, labels=labels)
        mat = (df.groupby(["before_q", "after_q"], observed=False).size()
               .unstack("after_q").reindex(index=labels, columns=labels).fillna(0).astype(int))
        mat.insert(0, "subject", subject)
        frames.append(mat.reset_index().rename(columns={"before_q": "initial_quartile"}))
    return pd.concat(frames, ignore_index=True)


# --- Table 6: selected top/bottom schools under Model 3 ---------------------

def top_bottom(effects: dict, n_each: int = 5) -> pd.DataFrame:
    cols = ["subject", "group", "school_code", "school_n_students",
            "va_ols_simple", "va_ols_context", "va_hlm_simple", "va_hlm_context",
            "rank_ols_simple", "rank_hlm_simple", "rank_change_m1_m3"]
    frames = []
    for subject in ("Mathematics", "Language"):
        df = effects[subject].sort_values("rank_hlm_simple")
        top = df.head(n_each).assign(group="Top")
        bottom = df.tail(n_each).sort_values("rank_hlm_simple", ascending=False).assign(group="Bottom")
        out = pd.concat([top, bottom]).assign(subject=subject)
        frames.append(out[cols])
    return pd.concat(frames, ignore_index=True)


# --- Table 7: distribution of the preferred (Model 4) estimate --------------

def va_distribution(effects: dict) -> pd.DataFrame:
    rows = []
    for subject in ("Mathematics", "Language"):
        va = effects[subject]["va_hlm_context"]
        rows.append({
            "subject": subject, "schools": len(va), "mean": va.mean(), "sd": va.std(),
            "min": va.min(), "p25": va.quantile(.25), "median": va.median(),
            "p75": va.quantile(.75), "max": va.max(),
        })
    return pd.DataFrame(rows)


# --- Table 8: Mathematics vs Language value-added ---------------------------

def math_language_correlation(effects: dict) -> pd.DataFrame:
    m = effects["Mathematics"][["school_code", "va_hlm_context", "rank_hlm_context"]]
    l = effects["Language"][["school_code", "va_hlm_context", "rank_hlm_context"]]
    common = m.merge(l, on="school_code", suffixes=("_math", "_lang"))
    return pd.DataFrame([{
        "common_schools": len(common),
        "pearson_va_correlation": common["va_hlm_context_math"].corr(common["va_hlm_context_lang"]),
        "spearman_rank_correlation": stats.spearmanr(
            common["rank_hlm_context_math"], common["rank_hlm_context_lang"]).statistic,
    }])


def run_all(results: dict) -> dict:
    effects = {s: results[s]["school_effects"] for s in results}
    return {
        "ranking_comparisons": ranking_comparisons(effects),
        "transition_matrix": transition_matrix(effects),
        "top_bottom": top_bottom(effects),
        "va_distribution": va_distribution(effects),
        "math_language_correlation": math_language_correlation(effects),
    }
