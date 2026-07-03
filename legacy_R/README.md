# Legacy R implementation

`microeconometrics_send.R` is the **original** analysis, written in R for the
seminar paper (Advanced Econometrics 2 / Microeconometrics). It is kept here as
the reference implementation.

The Python pipeline in [`../src/`](../src) reproduces its results (see the main
[README](../README.md#python--r-replication)). New work should go in the Python
code; this script is preserved for provenance.

## Running it

Requires R with, among others: `readxl`, `dplyr`, `tidyr`, `ggplot2`, `lme4`,
`lmerTest`, `lmtest`, `sandwich`, `car`, `broom`, `broom.mixed`, `openxlsx`
(the script installs missing packages automatically).

The script reads the data through an interactive file picker
(`file.choose()`) — select `../data/mi_base.xlsx` when prompted. Beyond the CSV
tables it also emits LaTeX tables (for Overleaf) and a formatted Excel workbook,
which the Python port does not replicate (it focuses on the analysis and the
result tables/figures).
