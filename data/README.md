# Data

`mi_base.xlsx` — student-level panel from the Chilean national assessment,
linking each student's scores in **2004** (end of primary) and **2006**
(secondary). One row per student. **Not committed** (student microdata with
national ids; `data/` is git-ignored).

## Columns used by the analysis

| Column  | Description                                             |
|---------|---------------------------------------------------------|
| `RUT`   | Student national id (used only to de-duplicate rows)    |
| `RBD04` | 2004 school id                                          |
| `RBD06` | 2006 school id — **the value-added unit** (`school_code`) |
| `MAT04` | 2004 Mathematics score (Maths baseline)                 |
| `MAT06` | 2006 Mathematics score (Maths outcome)                  |
| `LEN04` | 2004 Language score (Language baseline)                 |
| `LEN06` | 2006 Language score (Language outcome)                  |

The file also contains `GENERO04/06` and `GRUPO04/06`, which the analysis does
not use. Rows with missing scores or school id are dropped per subject, giving
the estimation samples reported in Table 1 (Maths N = 75,939; Language N =
75,524; 926 schools).

To run the analysis, place the Excel file at `data/mi_base.xlsx` (see the path
in [`src/config.py`](../src/config.py)).
