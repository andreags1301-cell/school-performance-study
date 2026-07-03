"""Project configuration: paths, data schema and model definitions.

School value-added study on Chilean student panel data (2004 -> 2006), estimated
separately for Mathematics and Language. See docs/ for the full research report.
"""
from __future__ import annotations

from pathlib import Path

# --- Paths -------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]

DATA_FILE = ROOT / "data" / "mi_base.xlsx"
RESULTS_DIR = ROOT / "results"
FIGURES_DIR = RESULTS_DIR / "figures"
TABLES_DIR = RESULTS_DIR / "tables"
ASSETS_DIR = ROOT / "assets"

# --- Data schema -------------------------------------------------------------
# Columns needed from the raw Excel (names are upper-cased and trimmed on load).
#   RUT   -> student national id            RBD06 -> 2006 school id (the unit)
#   MAT04 -> 2004 Maths score (baseline)    MAT06 -> 2006 Maths score (outcome)
#   LEN04 -> 2004 Language score (baseline) LEN06 -> 2006 Language score (outcome)
REQUIRED_COLUMNS = ["RUT", "RBD04", "RBD06", "MAT04", "MAT06", "LEN04", "LEN06"]

# --- Subjects: (pre-test, post-test) columns --------------------------------
SUBJECTS = {
    "Mathematics": {"pre": "MAT04", "post": "MAT06"},
    "Language": {"pre": "LEN04", "post": "LEN06"},
}

# --- The four value-added specifications ------------------------------------
# M1: OLS  y ~ baseline
# M2: OLS  y ~ within-school baseline + school-mean baseline (composition)
# M3: HLM  y ~ baseline + (1 | school)
# M4: HLM  y ~ within-school baseline + school-mean baseline + (1 | school)
MODELS = ["M1: OLS", "M2: OLS + composition", "M3: HLM", "M4: HLM + composition"]
