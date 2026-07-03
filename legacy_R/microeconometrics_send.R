# Advanced Econometrics 2 / Microeconometrics
# School value-added models
# Andrea Garrido Sáez

# Packages ---------------------------------------------------------------

required_packages <- c(
  "readxl", "dplyr", "tidyr", "ggplot2", "lme4", "lmerTest",
  "lmtest", "sandwich", "car", "performance", "tibble", "broom",
  "broom.mixed", "readr", "stringr", "purrr", "openxlsx"
)

installed <- rownames(installed.packages())
to_install <- setdiff(required_packages, installed)
if (length(to_install) > 0) install.packages(to_install, dependencies = TRUE)
invisible(lapply(required_packages, library, character.only = TRUE))

# Paths ------------------------------------------------------------------

# Select data file
data_file <- file.choose()

output_dir  <- "microeconometrics_outputs"
tables_dir  <- file.path(output_dir, "overleaf", "tables")
figures_dir <- file.path(output_dir, "overleaf", "figures")
csv_dir     <- file.path(output_dir, "csv")

purrr::walk(c(output_dir, tables_dir, figures_dir, csv_dir), ~dir.create(.x, showWarnings = FALSE, recursive = TRUE))

# Options for checking outputs in RStudio
SHOW_PLOTS_IN_RSTUDIO <- TRUE

# Open main tables in RStudio when the script is run interactively.
SHOW_TABLES_IN_RSTUDIO <- TRUE

# Helper functions -------------------------------------------------------

fmt <- function(x, digits = 3) {
  if (length(x) == 0) return("--")
  out <- rep("--", length(x))
  ok <- !is.na(x)
  if (is.numeric(x)) {
    out[ok] <- formatC(x[ok], digits = digits, format = "f", big.mark = ",")
  } else {
    out[ok] <- as.character(x[ok])
  }
  out
}

fmt_int <- function(x) formatC(as.numeric(x), format = "f", digits = 0, big.mark = ",")

sig_stars <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < 0.001 ~ "^{***}",
    p < 0.01  ~ "^{**}",
    p < 0.05  ~ "^{*}",
    TRUE ~ ""
  )
}

escape_latex <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("_", "\\\\_", x)
  x <- gsub("&", "\\\\&", x)
  x <- gsub("%", "\\\\%", x)
  x <- gsub("#", "\\\\#", x)
  x
}

write_lines <- function(x, file) writeLines(x, con = file, useBytes = TRUE)

latex_table <- function(caption, label, header, rows, notes = NULL, size = "\\small", landscape = FALSE) {
  align <- paste0("l", paste(rep("c", length(header) - 1), collapse = ""))
  lines <- c(
    "\\begin{table}[H]",
    "\\centering",
    size,
    paste0("\\caption{", caption, "}"),
    paste0("\\label{", label, "}"),
    "\\begin{threeparttable}",
    "\\begin{adjustbox}{max width=\\textwidth}",
    paste0("\\begin{tabular}{", align, "}"),
    "\\toprule",
    paste(header, collapse = " & "), "\\\\",
    "\\midrule",
    rows,
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{adjustbox}"
  )
  if (!is.null(notes)) {
    lines <- c(lines, "\\begin{tablenotes}", "\\footnotesize", paste0("\\item ", notes), "\\end{tablenotes}")
  }
  lines <- c(lines, "\\end{threeparttable}", "\\end{table}")
  if (landscape) lines <- c("\\begin{landscape}", lines, "\\end{landscape}")
  lines
}

rmse <- function(model) sqrt(mean(resid(model)^2, na.rm = TRUE))

get_var_components <- function(model) {
  vc <- as.data.frame(VarCorr(model))
  school_var <- vc$vcov[vc$grp == "school_code"][1]
  resid_var  <- vc$vcov[vc$grp == "Residual"][1]
  tibble(
    sigma2_school = school_var,
    sigma2_residual = resid_var,
    ICC = school_var / (school_var + resid_var)
  )
}

get_random_effects <- function(model, effect_name) {
  re <- ranef(model, condVar = TRUE)$school_code
  post_var <- attr(re, "postVar")
  se <- sqrt(post_var[1, 1, ])
  tibble(
    school_code = rownames(re),
    !!effect_name := re[, "(Intercept)"],
    !!paste0("se_", effect_name) := se,
    !!paste0("ci_low_", effect_name) := re[, "(Intercept)"] - 1.96 * se,
    !!paste0("ci_high_", effect_name) := re[, "(Intercept)"] + 1.96 * se
  )
}

save_plot <- function(plot, filename, width = 7, height = 5) {
  # Show plot in RStudio Plots pane when the script is run interactively.
  if (isTRUE(SHOW_PLOTS_IN_RSTUDIO)) print(plot)

  # Also save the plot for Overleaf.
  ggsave(file.path(figures_dir, filename), plot, width = width, height = height, dpi = 300)
}

# Load and clean data ----------------------------------------------------

raw_data <- readxl::read_excel(data_file)
names(raw_data) <- toupper(trimws(names(raw_data)))

required_columns <- c("RUT", "RBD04", "RBD06", "MAT04", "MAT06", "LEN04", "LEN06")
missing_columns <- setdiff(required_columns, names(raw_data))
if (length(missing_columns) > 0) {
  stop(paste("Missing required variables:", paste(missing_columns, collapse = ", ")))
}

data_clean <- raw_data %>%
  select(all_of(required_columns)) %>%
  distinct()

cat("\n==============================\n")
cat("BASIC DATA CHECKS\n")
cat("==============================\n")
cat("Rows after exact duplicates:", nrow(data_clean), "\n")
cat("Different students:", n_distinct(data_clean$RUT), "\n")
cat("Schools in 2006:", n_distinct(data_clean$RBD06), "\n")
print(colSums(is.na(data_clean)))

# Build the Mathematics and Language samples -----------------------------

build_subject_sample <- function(data, pre_test, post_test, subject_name) {
  data %>%
    transmute(
      student_id = RUT,
      school_code = as.factor(RBD06),
      baseline_score = as.numeric(.data[[pre_test]]),
      outcome_score = as.numeric(.data[[post_test]]),
      subject = subject_name
    ) %>%
    filter(!is.na(student_id), !is.na(school_code), !is.na(baseline_score), !is.na(outcome_score)) %>%
    group_by(school_code) %>%
    mutate(
      school_baseline_mean = mean(baseline_score),
      baseline_within_school = baseline_score - school_baseline_mean,
      school_n_students = n()
    ) %>%
    ungroup()
}

math_data <- build_subject_sample(data_clean, "MAT04", "MAT06", "Mathematics")
language_data <- build_subject_sample(data_clean, "LEN04", "LEN06", "Language")

cat("\n==============================\n")
cat("FINAL ANALYSIS SAMPLES\n")
cat("==============================\n")
cat("Mathematics observations:", nrow(math_data), " | schools:", n_distinct(math_data$school_code), "\n")
cat("Language observations:", nrow(language_data), " | schools:", n_distinct(language_data$school_code), "\n")

# Descriptive statistics -------------------------------------------------

descriptive_table <- bind_rows(
  math_data %>% summarise(subject = "Mathematics", students = n(), schools = n_distinct(school_code), mean_pre_test = mean(baseline_score), mean_post_test = mean(outcome_score), correlation = cor(baseline_score, outcome_score)),
  language_data %>% summarise(subject = "Language", students = n(), schools = n_distinct(school_code), mean_pre_test = mean(baseline_score), mean_post_test = mean(outcome_score), correlation = cor(baseline_score, outcome_score))
)

write_csv(descriptive_table, file.path(csv_dir, "table1_descriptive_statistics.csv"))

# Estimate the four models -----------------------------------------------

estimate_subject <- function(student_data, label) {
  cat("\n==============================\n")
  cat("ESTIMATING MODELS:", label, "\n")
  cat("==============================\n")

  m1 <- lm(outcome_score ~ baseline_score, data = student_data)
  m2 <- lm(outcome_score ~ baseline_within_school + school_baseline_mean, data = student_data)
  m3 <- lmer(outcome_score ~ baseline_score + (1 | school_code), data = student_data, REML = TRUE)
  m4 <- lmer(outcome_score ~ baseline_within_school + school_baseline_mean + (1 | school_code), data = student_data, REML = TRUE)

  # Extra diagnostics saved but not all reported.
  diagnostics <- list(
    reset_m1 = tryCatch(resettest(m1, power = 2:3, type = "fitted"), error = function(e) e),
    reset_m2 = tryCatch(resettest(m2, power = 2:3, type = "fitted"), error = function(e) e),
    bp_m1 = tryCatch(bptest(m1), error = function(e) e),
    bp_m2 = tryCatch(bptest(m2), error = function(e) e),
    vif_m2 = tryCatch(vif(m2), error = function(e) e),
    robust_m1 = tryCatch(coeftest(m1, vcov = vcovHC(m1, type = "HC3")), error = function(e) e),
    robust_m2 = tryCatch(coeftest(m2, vcov = vcovHC(m2, type = "HC3")), error = function(e) e)
  )

  # School value-added estimates
  va_m1 <- student_data %>%
    mutate(resid_m1 = resid(m1)) %>%
    group_by(school_code) %>%
    summarise(
      va_ols_simple = mean(resid_m1),
      school_n_students = first(school_n_students),
      school_baseline_mean = first(school_baseline_mean),
      school_outcome_mean = mean(outcome_score),
      .groups = "drop"
    )

  va_m2 <- student_data %>%
    mutate(resid_m2 = resid(m2)) %>%
    group_by(school_code) %>%
    summarise(va_ols_context = mean(resid_m2), .groups = "drop")

  va_m3 <- get_random_effects(m3, "va_hlm_simple")
  va_m4 <- get_random_effects(m4, "va_hlm_context")

  school_effects <- va_m1 %>%
    mutate(school_code = as.character(school_code)) %>%
    left_join(va_m2 %>% mutate(school_code = as.character(school_code)), by = "school_code") %>%
    left_join(va_m3, by = "school_code") %>%
    left_join(va_m4, by = "school_code") %>%
    mutate(
      rank_ols_simple = min_rank(desc(va_ols_simple)),
      rank_ols_context = min_rank(desc(va_ols_context)),
      rank_hlm_simple = min_rank(desc(va_hlm_simple)),
      rank_hlm_context = min_rank(desc(va_hlm_context)),
      rank_change_m1_m3 = abs(rank_ols_simple - rank_hlm_simple),
      rank_change_m2_m4 = abs(rank_ols_context - rank_hlm_context),
      rank_change_m3_m4 = abs(rank_hlm_simple - rank_hlm_context)
    )

  # Fixed-effect coefficients
  coefficient_table <- bind_rows(
    broom::tidy(m1) %>% mutate(model = "M1: OLS"),
    broom::tidy(m2) %>% mutate(model = "M2: OLS + composition"),
    broom.mixed::tidy(m3, effects = "fixed") %>% mutate(model = "M3: HLM"),
    broom.mixed::tidy(m4, effects = "fixed") %>% mutate(model = "M4: HLM + composition")
  ) %>%
    mutate(subject = label) %>%
    select(subject, model, term, estimate, std.error, statistic, p.value)

  var_m3 <- get_var_components(m3)
  var_m4 <- get_var_components(m4)

  model_stats <- bind_rows(
    tibble(subject = label, model = "M1: OLS", estimator = "OLS", n_students = nrow(student_data), n_schools = n_distinct(student_data$school_code), r_squared = summary(m1)$r.squared, rmse = rmse(m1), sigma2_school = NA_real_, sigma2_residual = NA_real_, ICC = NA_real_, AIC = AIC(m1)),
    tibble(subject = label, model = "M2: OLS + composition", estimator = "OLS", n_students = nrow(student_data), n_schools = n_distinct(student_data$school_code), r_squared = summary(m2)$r.squared, rmse = rmse(m2), sigma2_school = NA_real_, sigma2_residual = NA_real_, ICC = NA_real_, AIC = AIC(m2)),
    tibble(subject = label, model = "M3: HLM", estimator = "HLM", n_students = nrow(student_data), n_schools = n_distinct(student_data$school_code), r_squared = NA_real_, rmse = rmse(m3), sigma2_school = var_m3$sigma2_school, sigma2_residual = var_m3$sigma2_residual, ICC = var_m3$ICC, AIC = AIC(m3)),
    tibble(subject = label, model = "M4: HLM + composition", estimator = "HLM", n_students = nrow(student_data), n_schools = n_distinct(student_data$school_code), r_squared = NA_real_, rmse = rmse(m4), sigma2_school = var_m4$sigma2_school, sigma2_residual = var_m4$sigma2_residual, ICC = var_m4$ICC, AIC = AIC(m4))
  )

  list(
    models = list(m1 = m1, m2 = m2, m3 = m3, m4 = m4),
    diagnostics = diagnostics,
    school_effects = school_effects,
    coefficient_table = coefficient_table,
    model_stats = model_stats
  )
}

sink(file.path(output_dir, "console_output_models_and_diagnostics.txt"), split = TRUE)
math_results <- estimate_subject(math_data, "Mathematics")
language_results <- estimate_subject(language_data, "Language")
sink()

math_effects <- math_results$school_effects
language_effects <- language_results$school_effects
all_coefficients <- bind_rows(math_results$coefficient_table, language_results$coefficient_table)
all_model_stats <- bind_rows(math_results$model_stats, language_results$model_stats)

# Ranking comparisons ----------------------------------------------------

summarise_rank_comparison <- function(df, subject_label, comparison_label, rank_a, rank_b) {
  changes <- abs(df[[rank_a]] - df[[rank_b]])
  tibble(
    comparison = comparison_label,
    subject = subject_label,
    spearman = cor(df[[rank_a]], df[[rank_b]], method = "spearman", use = "complete.obs"),
    mean_rank_change = mean(changes, na.rm = TRUE),
    median_rank_change = median(changes, na.rm = TRUE),
    max_rank_change = max(changes, na.rm = TRUE),
    schools = nrow(df)
  )
}

ranking_comparisons <- bind_rows(
  summarise_rank_comparison(math_effects, "Mathematics", "M1 vs M3", "rank_ols_simple", "rank_hlm_simple"),
  summarise_rank_comparison(language_effects, "Language", "M1 vs M3", "rank_ols_simple", "rank_hlm_simple"),
  summarise_rank_comparison(math_effects, "Mathematics", "M2 vs M4", "rank_ols_context", "rank_hlm_context"),
  summarise_rank_comparison(language_effects, "Language", "M2 vs M4", "rank_ols_context", "rank_hlm_context"),
  summarise_rank_comparison(math_effects, "Mathematics", "M3 vs M4", "rank_hlm_simple", "rank_hlm_context"),
  summarise_rank_comparison(language_effects, "Language", "M3 vs M4", "rank_hlm_simple", "rank_hlm_context")
)

# Transition matrix: before and after composition ------------------------

make_transition <- function(df, subject_label) {
  df %>%
    mutate(
      before_q = ntile(rank_hlm_simple, 4),
      after_q = ntile(rank_hlm_context, 4),
      before_q = factor(before_q, levels = 1:4, labels = c("Q1 best", "Q2", "Q3", "Q4 worst")),
      after_q = factor(after_q, levels = 1:4, labels = c("Q1 best", "Q2", "Q3", "Q4 worst"))
    ) %>%
    count(before_q, after_q) %>%
    pivot_wider(names_from = after_q, values_from = n, values_fill = 0) %>%
    mutate(subject = subject_label, .before = 1)
}

transition_table <- bind_rows(
  make_transition(math_effects, "Mathematics"),
  make_transition(language_effects, "Language")
)

# Selected high and low VA schools under Model 3 -------------------------

make_top_bottom_m3 <- function(df, subject_label, n_each = 5) {
  top <- df %>% arrange(rank_hlm_simple) %>% slice_head(n = n_each) %>% mutate(group = "Top")
  bottom <- df %>% arrange(desc(rank_hlm_simple)) %>% slice_head(n = n_each) %>% mutate(group = "Bottom")
  bind_rows(top, bottom) %>%
    mutate(subject = subject_label) %>%
    select(
      subject, group, school_code, school_n_students,
      va_ols_simple, va_ols_context, va_hlm_simple, va_hlm_context,
      rank_ols_simple, rank_hlm_simple, rank_change_m1_m3
    )
}

top_bottom_m3 <- bind_rows(
  make_top_bottom_m3(math_effects, "Mathematics", 5),
  make_top_bottom_m3(language_effects, "Language", 5)
)

# Appendix outputs -------------------------------------------------------

preferred_va_distribution <- bind_rows(
  math_effects %>% summarise(subject = "Mathematics", schools = n(), mean = mean(va_hlm_context), sd = sd(va_hlm_context), min = min(va_hlm_context), p25 = quantile(va_hlm_context, .25), median = median(va_hlm_context), p75 = quantile(va_hlm_context, .75), max = max(va_hlm_context)),
  language_effects %>% summarise(subject = "Language", schools = n(), mean = mean(va_hlm_context), sd = sd(va_hlm_context), min = min(va_hlm_context), p25 = quantile(va_hlm_context, .25), median = median(va_hlm_context), p75 = quantile(va_hlm_context, .75), max = max(va_hlm_context))
)

math_language_common <- math_effects %>%
  select(school_code, math_va = va_hlm_context, math_rank = rank_hlm_context) %>%
  inner_join(language_effects %>% select(school_code, lang_va = va_hlm_context, lang_rank = rank_hlm_context), by = "school_code")

math_language_correlation <- tibble(
  common_schools = nrow(math_language_common),
  pearson_va_correlation = cor(math_language_common$math_va, math_language_common$lang_va, use = "complete.obs"),
  spearman_rank_correlation = cor(math_language_common$math_rank, math_language_common$lang_rank, method = "spearman", use = "complete.obs")
)

# Save CSV outputs -------------------------------------------------------

write_csv(math_effects, file.path(csv_dir, "math_school_value_added_all_models.csv"))
write_csv(language_effects, file.path(csv_dir, "language_school_value_added_all_models.csv"))
write_csv(all_coefficients, file.path(csv_dir, "fixed_coefficients_all_models.csv"))
write_csv(all_model_stats, file.path(csv_dir, "model_fit_variance_decomposition.csv"))
write_csv(ranking_comparisons, file.path(csv_dir, "ranking_comparisons_fused_table.csv"))
write_csv(transition_table, file.path(csv_dir, "composition_transition_matrix.csv"))
write_csv(top_bottom_m3, file.path(csv_dir, "top_bottom_5_selected_under_model3.csv"))
write_csv(preferred_va_distribution, file.path(csv_dir, "appendix_distribution_preferred_va_model4.csv"))
write_csv(math_language_correlation, file.path(csv_dir, "appendix_math_language_correlation_model4.csv"))

# Figures ----------------------------------------------------------------

plot_pre_post <- function(df, title, file) {
  p <- ggplot(df, aes(x = baseline_score, y = outcome_score)) +
    geom_point(alpha = 0.15, size = 0.7) +
    geom_smooth(method = "lm", se = FALSE) +
    labs(title = title, x = "2004 prior score", y = "2006 later score") +
    theme_minimal()
  save_plot(p, file)
}

plot_pre_post(math_data, "Mathematics: 2006 score against 2004 score", "figure0a_math_pre_post_scatter.png")
plot_pre_post(language_data, "Language: 2006 score against 2004 score", "figure0b_language_pre_post_scatter.png")

plot_rank <- function(df, x, y, title, xlab, ylab, file) {
  p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]])) +
    geom_point(alpha = 0.55, size = 1) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
    labs(title = title, x = xlab, y = ylab) +
    theme_minimal()
  save_plot(p, file)
}

plot_rank(math_effects, "rank_ols_simple", "rank_hlm_simple", "Mathematics: Model 1 versus Model 3 rankings", "Model 1 rank", "Model 3 rank", "figure1_math_m1_vs_m3_rankings.png")
plot_rank(language_effects, "rank_ols_simple", "rank_hlm_simple", "Language: Model 1 versus Model 3 rankings", "Model 1 rank", "Model 3 rank", "figure2_language_m1_vs_m3_rankings.png")
plot_rank(math_effects, "rank_hlm_simple", "rank_hlm_context", "Mathematics: HLM rankings before and after composition", "Model 3 rank", "Model 4 rank", "figure3_math_m3_vs_m4_rankings.png")
plot_rank(language_effects, "rank_hlm_simple", "rank_hlm_context", "Language: HLM rankings before and after composition", "Model 3 rank", "Model 4 rank", "figure4_language_m3_vs_m4_rankings.png")

p_ml <- ggplot(math_language_common, aes(x = math_va, y = lang_va)) +
  geom_point(alpha = 0.6, size = 1) +
  geom_smooth(method = "lm", se = FALSE) +
  labs(title = "Mathematics and Language value-added", x = "Mathematics VA, Model 4", y = "Language VA, Model 4") +
  theme_minimal()
save_plot(p_ml, "appendix_math_language_va_correlation.png")

# LaTeX tables -----------------------------------------------------------

# Table 1
rows_t1 <- descriptive_table %>%
  mutate(row = paste0(escape_latex(subject), " & ", fmt_int(students), " & ", fmt_int(schools), " & ", fmt(mean_pre_test, 2), " & ", fmt(mean_post_test, 2), " & ", fmt(correlation, 3), " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Descriptive statistics by subject", "tab:desc", c("Subject", "Students", "Schools", "Mean pre-test", "Mean post-test", "Correlation"), rows_t1, "The pre-test is the 2004 score and the post-test is the 2006 score. Schools are defined using RBD06."), file.path(tables_dir, "table1_descriptive_statistics.tex"))

# Table 2
rows_t2 <- all_model_stats %>%
  mutate(row = paste0(escape_latex(subject), " & ", escape_latex(model), " & ", fmt_int(n_students), " & ", fmt_int(n_schools), " & ", fmt(r_squared, 3), " & ", fmt(rmse, 2), " & ", fmt(sigma2_school, 2), " & ", fmt(sigma2_residual, 2), " & ", fmt(ICC, 3), " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Model fit and variance decomposition", "tab:fit", c("Subject", "Model", "Students", "Schools", "$R^2$", "RMSE", "$\\sigma^2_{school}$", "$\\sigma^2_{residual}$", "ICC"), rows_t2, "$R^2$ is reported for OLS models. Variance components and ICC are reported for HLM models. ICC is computed as $\\sigma^2_{school}/(\\sigma^2_{school}+\\sigma^2_{residual})$.", size = "\\scriptsize"), file.path(tables_dir, "table2_model_fit_variance.tex"))

# Table 3 with panels and AIC
make_coef_cell <- function(df, model_name, term_name) {
  row <- df %>% filter(model == model_name, term == term_name) %>% slice(1)
  if (nrow(row) == 0) return(c("", ""))
  c(paste0("$", fmt(row$estimate, 3), sig_stars(row$p.value), "$"), paste0("$($", fmt(row$std.error, 3), "$)$"))
}

make_panel_rows <- function(subject_label) {
  co <- all_coefficients %>% filter(subject == subject_label)
  st <- all_model_stats %>% filter(subject == subject_label)
  models <- c("M1: OLS", "M2: OLS + composition", "M3: HLM", "M4: HLM + composition")
  terms <- list(
    "Intercept" = "(Intercept)",
    "$X_{ij}$" = "baseline_score",
    "$X_{ij}-\\overline{X}_{j}$" = "baseline_within_school",
    "$\\overline{X}_{j}$" = "school_baseline_mean"
  )
  rows <- c(paste0("\\multicolumn{5}{l}{\\textbf{Panel: ", subject_label, "}} \\\\"))
  for (term_label in names(terms)) {
    cells <- purrr::map(models, ~make_coef_cell(co, .x, terms[[term_label]]))
    rows <- c(rows, paste0(term_label, " & ", paste(purrr::map_chr(cells, 1), collapse = " & "), " ", "\\\\"))
    rows <- c(rows, paste0(" & ", paste(purrr::map_chr(cells, 2), collapse = " & "), " ", "\\\\"))
  }
  aic_cells <- sapply(models, function(m) fmt((st %>% filter(model == m) %>% slice(1))$AIC, 1))
  c(rows, paste0("AIC & ", paste(aic_cells, collapse = " & "), " ", "\\\\"), "\\addlinespace")
}

rows_t3 <- c(make_panel_rows("Mathematics"), make_panel_rows("Language"))
write_lines(latex_table("Coefficient estimates from the four value-added specifications", "tab:coefficients", c("", "M1 OLS", "M2 OLS + comp.", "M3 HLM", "M4 HLM + comp."), rows_t3, "Standard errors are in parentheses. $X_{ij}$ is the 2004 prior score, $X_{ij}-\\overline{X}_{j}$ is the within-school prior score, and $\\overline{X}_{j}$ is school composition. Significance codes: $^{***}p<0.001$, $^{**}p<0.01$, $^{*}p<0.05$.", size = "\\scriptsize"), file.path(tables_dir, "table3_coefficient_estimates_paper_style.tex"))

# Table 4
rows_t4 <- ranking_comparisons %>%
  mutate(row = paste0(escape_latex(comparison), " & ", escape_latex(subject), " & ", fmt(spearman, 3), " & ", fmt(mean_rank_change, 2), " & ", fmt(median_rank_change, 2), " & ", fmt_int(max_rank_change), " & ", fmt_int(schools), " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Ranking comparisons across value-added definitions", "tab:rankcomp", c("Comparison", "Subject", "Spearman corr.", "Mean rank change", "Median rank change", "Max rank change", "Schools"), rows_t4, "Spearman correlation compares the order of schools across two rankings. M1 and M2 are OLS residual-based models. M3 and M4 are HLM random-intercept models. M2 and M4 include composition."), file.path(tables_dir, "table4_ranking_comparisons_fused.tex"))

# Table 5
rows_t5 <- transition_table %>%
  mutate(row = paste0(escape_latex(subject), " & ", escape_latex(before_q), " & ", `Q1 best`, " & ", Q2, " & ", Q3, " & ", `Q4 worst`, " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Rank transition matrix before and after adding composition", "tab:transition", c("Subject", "Before composition", "After Q1 best", "After Q2", "After Q3", "After Q4 worst"), rows_t5, "Q1 is the best-performing quartile and Q4 is the worst-performing quartile. Rows are based on Model 3 and columns on Model 4."), file.path(tables_dir, "table5_transition_matrix.tex"))

# Table 6: selected high/low schools under M3
rows_t6 <- top_bottom_m3 %>%
  mutate(row = paste0(escape_latex(subject), " & ", escape_latex(group), " & ", escape_latex(school_code), " & ", fmt_int(school_n_students), " & ", fmt(va_ols_simple, 2), " & ", fmt(va_ols_context, 2), " & ", fmt(va_hlm_simple, 2), " & ", fmt(va_hlm_context, 2), " & ", fmt_int(rank_ols_simple), " & ", fmt_int(rank_hlm_simple), " & ", fmt_int(rank_change_m1_m3), " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Selected top and bottom schools under the hierarchical value-added ranking", "tab:topbottom", c("Subject", "Group", "School", "$n_j$", "$VA^1_j$", "$VA^2_j$", "$VA^3_j$", "$VA^4_j$", "$R^1_j$", "$R^3_j$", "$|R^3_j-R^1_j|$"), rows_t6, "Schools are selected according to the Model 3 rank, because the central exam comparison is Model 1 versus Model 3. Model 4 remains the preferred specification for conditional interpretation because it controls for composition.", size = "\\scriptsize", landscape = TRUE), file.path(tables_dir, "table6_top_bottom_5_model3_format.tex"))

# Appendix Table A1
rows_a1 <- preferred_va_distribution %>%
  mutate(row = paste0(escape_latex(subject), " & ", fmt_int(schools), " & ", fmt(mean, 2), " & ", fmt(sd, 2), " & ", fmt(min, 2), " & ", fmt(p25, 2), " & ", fmt(median, 2), " & ", fmt(p75, 2), " & ", fmt(max, 2), " ", "\\\\")) %>%
  pull(row)
write_lines(latex_table("Distribution of preferred value-added estimates", "tab:dist", c("Subject", "Schools", "Mean", "SD", "Min", "P25", "Median", "P75", "Max"), rows_a1, "The preferred value-added estimate is $VA^4_j$, obtained from the HLM with composition."), file.path(tables_dir, "appendix_tableA1_distribution_preferred_va.tex"))

# Appendix Table A2
rows_a2 <- c(
  paste0("Common schools & ", fmt_int(math_language_correlation$common_schools), " ", "\\\\"),
  paste0("Pearson correlation & ", fmt(math_language_correlation$pearson_va_correlation, 3), " ", "\\\\"),
  paste0("Spearman rank correlation & ", fmt(math_language_correlation$spearman_rank_correlation, 3), " ", "\\\\")
)
write_lines(latex_table("Correlation between Mathematics and Language value-added", "tab:mathlanguage", c("Measure", "Value"), rows_a2, "Correlations are computed using the preferred Model 4 value-added estimates."), file.path(tables_dir, "appendix_tableA2_math_language_correlation.tex"))

# Numbers used in the text -----------------------------------------------

get_value <- function(df, comparison_label, subject_label, column) {
  df %>% filter(comparison == comparison_label, subject == subject_label) %>% slice(1) %>% pull({{ column }})
}

report_numbers <- c(
  "% Automatically generated numbers for Overleaf",
  paste0("\\newcommand{\\MathMoneMthreeSpearman}{", fmt(get_value(ranking_comparisons, "M1 vs M3", "Mathematics", spearman), 3), "}"),
  paste0("\\newcommand{\\LangMoneMthreeSpearman}{", fmt(get_value(ranking_comparisons, "M1 vs M3", "Language", spearman), 3), "}"),
  paste0("\\newcommand{\\MathMthreeMfourSpearman}{", fmt(get_value(ranking_comparisons, "M3 vs M4", "Mathematics", spearman), 3), "}"),
  paste0("\\newcommand{\\LangMthreeMfourSpearman}{", fmt(get_value(ranking_comparisons, "M3 vs M4", "Language", spearman), 3), "}"),
  paste0("\\newcommand{\\CommonSchoolsML}{", fmt_int(math_language_correlation$common_schools), "}"),
  paste0("\\newcommand{\\MathLangPearson}{", fmt(math_language_correlation$pearson_va_correlation, 3), "}"),
  paste0("\\newcommand{\\MathLangSpearman}{", fmt(math_language_correlation$spearman_rank_correlation, 3), "}")
)
write_lines(report_numbers, file.path(tables_dir, "report_numbers.tex"))

# Excel workbook ---------------------------------------------------------

excel_file <- file.path(output_dir, "microeconometrics_results_clean_final.xlsx")
wb <- createWorkbook()

header_style <- createStyle(textDecoration = "bold", fgFill = "#D9EAF7", border = "Bottom", halign = "center")
title_style  <- createStyle(fontSize = 14, textDecoration = "bold")
num_style    <- createStyle(numFmt = "0.000")

add_sheet <- function(wb, sheet, data, title) {
  addWorksheet(wb, sheet)
  writeData(wb, sheet, title, startRow = 1, startCol = 1)
  addStyle(wb, sheet, title_style, rows = 1, cols = 1)
  writeData(wb, sheet, data, startRow = 3, startCol = 1, withFilter = TRUE)
  addStyle(wb, sheet, header_style, rows = 3, cols = 1:ncol(data), gridExpand = TRUE)
  numeric_cols <- which(sapply(data, is.numeric))
  if (length(numeric_cols) > 0) addStyle(wb, sheet, num_style, rows = 4:(nrow(data) + 3), cols = numeric_cols, gridExpand = TRUE, stack = TRUE)
  freezePane(wb, sheet, firstActiveRow = 4)
  setColWidths(wb, sheet, cols = 1:ncol(data), widths = "auto")
}

readme <- tibble(
  Item = c("Preferred model", "Main comparison", "Top/bottom table", "Interpretation", "Caution"),
  Explanation = c(
    "The preferred model for conditional interpretation is Model 4: HLM with composition.",
    "The central exam comparison is Model 1 versus Model 3.",
    "Top/bottom 5 schools are selected under Model 3 and include VA from all four models.",
    "Positive value-added means performance above the model-based expected level.",
    "The estimates are conditional, relative and model-based; they are not causal measures of school quality."
  )
)

add_sheet(wb, "README", readme, "How to read this workbook")
add_sheet(wb, "Table 1 descriptives", descriptive_table, "Table 1: Descriptive statistics")
add_sheet(wb, "Table 2 model fit", all_model_stats, "Table 2: Model fit and variance decomposition")
add_sheet(wb, "Table 3 coefficients", all_coefficients, "Table 3: Coefficient estimates")
add_sheet(wb, "Table 4 rank comp", ranking_comparisons, "Table 4: Ranking comparisons")
add_sheet(wb, "Table 5 transition", transition_table, "Table 5: Transition matrix")
add_sheet(wb, "Table 6 top bottom", top_bottom_m3, "Table 6: Top/bottom 5 selected under Model 3")
add_sheet(wb, "Appendix distribution", preferred_va_distribution, "Appendix A1: Preferred VA distribution")
add_sheet(wb, "Appendix Math-Language", math_language_correlation, "Appendix A2: Math-Language correlation")
add_sheet(wb, "Math full ranking", math_effects %>% arrange(rank_hlm_context), "Full Mathematics rankings")
add_sheet(wb, "Language full ranking", language_effects %>% arrange(rank_hlm_context), "Full Language rankings")

saveWorkbook(wb, excel_file, overwrite = TRUE)

# Optional RStudio table viewer ------------------------------------------

if (isTRUE(SHOW_TABLES_IN_RSTUDIO) && interactive()) {
  View(descriptive_table, "Table 1 - Descriptive statistics")
  View(all_model_stats, "Table 2 - Model fit and variance decomposition")
  View(all_coefficients, "Table 3 - Coefficient estimates")
  View(ranking_comparisons, "Table 4 - Ranking comparisons")
  View(transition_table, "Table 5 - Transition matrix")
  View(top_bottom_m3, "Table 6 - Top/bottom 5 selected under Model 3")
  View(preferred_va_distribution, "Appendix A1 - Preferred VA distribution")
  View(math_language_correlation, "Appendix A2 - Math-Language correlation")
}

# Final message ----------------------------------------------------------

cat("\n==============================\n")
cat("CLEAN FINAL SCRIPT COMPLETE\n")
cat("==============================\n")
cat("Outputs saved in:", normalizePath(output_dir), "\n")
cat("Overleaf tables:", normalizePath(tables_dir), "\n")
cat("Overleaf figures:", normalizePath(figures_dir), "\n")
cat("Plots were also printed to the RStudio Plots pane if SHOW_PLOTS_IN_RSTUDIO = TRUE.\n")
cat("CSV files:", normalizePath(csv_dir), "\n")
cat("Excel workbook:", normalizePath(excel_file), "\n")
cat("==============================\n")
