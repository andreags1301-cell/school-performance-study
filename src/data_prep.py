"""Load the raw panel and build the Mathematics and Language analysis samples.

Mirrors the ``build_subject_sample`` logic of the legacy R script: keep valid
2004/2006 scores with an observed 2006 school, then add the within-school
decomposition of the baseline score used by the composition models.
"""
from __future__ import annotations

import pandas as pd

from . import config


def load_clean(path=config.DATA_FILE) -> pd.DataFrame:
    """Load the Excel panel, upper-case column names, keep the required columns
    and drop exact duplicate rows (matching the R ``distinct()`` step)."""
    raw = pd.read_excel(path)
    raw.columns = [c.strip().upper() for c in raw.columns]

    missing = [c for c in config.REQUIRED_COLUMNS if c not in raw.columns]
    if missing:
        raise ValueError(f"Missing required variables: {', '.join(missing)}")

    return raw[config.REQUIRED_COLUMNS].drop_duplicates()


def build_subject_sample(data: pd.DataFrame, pre: str, post: str,
                         subject: str) -> pd.DataFrame:
    """Build a single-subject student-level sample with school composition."""
    df = pd.DataFrame({
        "student_id": data["RUT"],
        "school_code": data["RBD06"].astype("category"),
        "baseline_score": pd.to_numeric(data[pre], errors="coerce"),
        "outcome_score": pd.to_numeric(data[post], errors="coerce"),
        "subject": subject,
    }).dropna(subset=["student_id", "school_code", "baseline_score", "outcome_score"])

    grp = df.groupby("school_code", observed=True)["baseline_score"]
    df["school_baseline_mean"] = grp.transform("mean")
    df["baseline_within_school"] = df["baseline_score"] - df["school_baseline_mean"]
    df["school_n_students"] = df.groupby("school_code", observed=True)["baseline_score"].transform("size")
    return df.reset_index(drop=True)


def build() -> dict:
    """Return ``{subject: student-level sample}`` for both subjects."""
    clean = load_clean()
    return {
        subject: build_subject_sample(clean, cols["pre"], cols["post"], subject)
        for subject, cols in config.SUBJECTS.items()
    }
