"""Figures: rank-comparison scatters and supporting plots.

Reproduces the report's figures with matplotlib:
  * Figure 1 - Model 1 vs Model 3 school ranks (estimator effect, stable).
  * Figure 2 - Model 3 vs Model 4 school ranks (composition effect, dispersed).
Plus the pre/post score scatters and the Maths-Language value-added scatter.
"""
from __future__ import annotations

import numpy as np
from matplotlib import pyplot as plt

from . import config

_SUBJECTS = ("Mathematics", "Language")


def _rank_panel(ax, df, x, y, title, xlab, ylab):
    ax.scatter(df[x], df[y], s=6, alpha=0.55, color="#333333", edgecolor="none")
    lim = [0, len(df)]
    ax.plot(lim, lim, "--", color="black", linewidth=0.9)
    ax.set(title=title, xlabel=xlab, ylabel=ylab, xlim=lim, ylim=lim)
    ax.grid(True, alpha=0.25)


def rank_comparison_figure(effects, x, y, xlab, ylab, suptitle, path):
    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    for ax, subject in zip(axes, _SUBJECTS):
        _rank_panel(ax, effects[subject], x, y, subject, xlab, ylab)
    fig.suptitle(suptitle, fontsize=13, fontweight="bold")
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


def pre_post_figure(samples, path):
    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    for ax, subject in zip(axes, _SUBJECTS):
        d = samples[subject]
        ax.scatter(d["baseline_score"], d["outcome_score"], s=4, alpha=0.12,
                   color="#2166ac", edgecolor="none")
        b1, b0 = np.polyfit(d["baseline_score"], d["outcome_score"], 1)
        xs = np.linspace(d["baseline_score"].min(), d["baseline_score"].max(), 50)
        ax.plot(xs, b0 + b1 * xs, color="red", linewidth=1.3)
        ax.set(title=subject, xlabel="2004 prior score", ylabel="2006 later score")
        ax.grid(True, alpha=0.25)
    fig.suptitle("Later vs prior score", fontsize=13, fontweight="bold")
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


def math_language_figure(effects, path):
    m = effects["Mathematics"][["school_code", "va_hlm_context"]].rename(
        columns={"va_hlm_context": "math_va"})
    l = effects["Language"][["school_code", "va_hlm_context"]].rename(
        columns={"va_hlm_context": "lang_va"})
    common = m.merge(l, on="school_code")
    fig, ax = plt.subplots(figsize=(6.5, 6))
    ax.scatter(common["math_va"], common["lang_va"], s=8, alpha=0.6,
               color="#333333", edgecolor="none")
    b1, b0 = np.polyfit(common["math_va"], common["lang_va"], 1)
    xs = np.linspace(common["math_va"].min(), common["math_va"].max(), 50)
    ax.plot(xs, b0 + b1 * xs, color="red", linewidth=1.3)
    ax.set(title="Mathematics and Language value-added (Model 4)",
           xlabel="Mathematics VA (Model 4)", ylabel="Language VA (Model 4)")
    ax.grid(True, alpha=0.25)
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


def save_all(samples, results, figures_dir=config.FIGURES_DIR,
             assets_dir=config.ASSETS_DIR):
    figures_dir.mkdir(parents=True, exist_ok=True)
    assets_dir.mkdir(parents=True, exist_ok=True)
    effects = {s: results[s]["school_effects"] for s in results}
    saved = []

    saved.append(rank_comparison_figure(
        effects, "rank_ols_simple", "rank_hlm_simple", "Model 1 rank", "Model 3 rank",
        "Figure 1 - School ranks: Model 1 (OLS) vs Model 3 (HLM), same covariates",
        figures_dir / "fig1_m1_vs_m3_rankings.png"))

    fig2 = rank_comparison_figure(
        effects, "rank_hlm_simple", "rank_hlm_context", "Model 3 rank", "Model 4 rank",
        "Figure 2 - School ranks: Model 3 vs Model 4, before and after composition",
        figures_dir / "fig2_m3_vs_m4_rankings.png")
    saved.append(fig2)
    # Copy the most illustrative figure into assets/ for the README.
    rank_comparison_figure(
        effects, "rank_hlm_simple", "rank_hlm_context", "Model 3 rank", "Model 4 rank",
        "Figure 2 - School ranks: Model 3 vs Model 4, before and after composition",
        assets_dir / "fig2_m3_vs_m4_rankings.png")

    saved.append(pre_post_figure(samples, figures_dir / "fig0_pre_post_scatter.png"))
    saved.append(math_language_figure(effects, figures_dir / "fig3_math_language_va.png"))
    return saved
