# Integration Guide: Butterfly Helpers

## Summary

Three new files have been created to functionalize the diverging "butterfly" bar charts used in both `albo-restudy-2024.qmd` and `bolivia-censo-2024.qmd`:

1. **`butterfly_helpers.R`** — Core helper functions (modular + one-call wrapper)
2. **`BUTTERFLY_HELPERS_DESIGN.md`** — Detailed design documentation
3. **`INTEGRATION_GUIDE.md`** — This file; integration instructions

## Quick Start

### In `albo-restudy-2024.qmd`

**Replace** the current CEL butterfly code chunks (~160 lines each) with:

```r
source("butterfly_helpers.R")

# ── CEL by urban/rural: diverging bar chart (counts) ──
urbrur_labels <- c("1" = "Urban", "2" = "Rural")

cel_urbrur <- albo_vars |>
  mutate(urbrur_label = urbrur_labels[as.character(urbrur)]) |>
  filter(!is.na(urbrur_label), !is.na(cel)) |>
  count(urbrur_label, cel) |>
  mutate(cel_chr = as.character(cel))

cel_labels_int <- c(
  "0" = "0 — No identity, no language",
  "1" = "1 — No identity, speaks (no childhood)",
  "2" = "2 — No identity, speaks + childhood (bilingual)",
  "3" = "3 — No identity, speaks + childhood (monolingual)",
  "4" = "4 — Identity only",
  "5" = "5 — Identity + language (no childhood)",
  "6" = "6 — Identity + language + childhood (bilingual)",
  "7" = "7 — Identity + language + childhood (monolingual)"
)

make_butterfly(
  cel_urbrur,
  group_var = "urbrur_label",
  category_var = "cel_chr",
  n_var = "n",
  left_cats = c("0", "1", "1.5", "2", "3"),
  right_cats = c("4", "4.5", "5", "6", "7"),
  colors_map = cel_colors,
  category_labels = cel_labels_int,
  label_prefix = "CEL",
  text_colors = c("0" = "white", "1" = "grey20", "1.5" = "grey20", 
                  "2" = "grey20", "3" = "white", "4" = "grey20", 
                  "4.5" = "grey20", "5" = "white", "6" = "white", "7" = "white"),
  title = "CEL distribution by urban/rural — CNPV 2024",
  subtitle = "Condición Étnico-Lingüística (Albó & Romero)  |  n = 11,365,333",
  arrow_left = "← No indigenous identity (CEL 0–3)",
  arrow_right = "Indigenous identity (CEL 4–7) →"
)
```

**Benefits:**
- ~40 lines of code vs ~160 (75% reduction)
- Inline comments eliminated; intent is clear
- No `ggplot_build()` boilerplate; all handled internally
- Easy to adjust colors, thresholds, titles without deep ggplot knowledge

### In `bolivia-censo-2024.qmd`

The existing `make_count_diverging()` function (lines 686–782) is language–identity specific and works well. **Two options:**

#### Option A: Keep as-is (recommended for now)

The function is self-contained and doesn't need refactoring. It's mature and language-specific in ways `make_butterfly()` may not capture.

#### Option B: Refactor to use `make_butterfly()` internally

If `make_count_diverging()` is called only once or twice, it could be simplified:

```r
source("butterfly_helpers.R")

make_count_diverging_new <- function(df, lvls_right, lvls_left, cols, title, ...) {
  # Minimal wrapper: rename columns and call make_butterfly()
  
  div_df <- df |>
    rename(
      group_label = idioma_grp,
      category = outcome_plot,
      count = n
    )
  
  make_butterfly(
    div_df,
    group_var = "group_label",
    category_var = "category",
    n_var = "count",
    left_cats = lvls_left,
    right_cats = lvls_right,
    colors_map = cols,
    title = title,
    # ... remaining params ...
  )
}
```

**Recommendation:** Only do this if there are 3+ uses of `make_count_diverging()` or if significant refactoring is needed anyway.

## File Structure

```
wiki-graph/
├── butterfly_helpers.R                (NEW)
├── BUTTERFLY_HELPERS_DESIGN.md        (NEW)
├── INTEGRATION_GUIDE.md               (NEW, this file)
├── cel_helpers.R                      (EXISTING: load colors + lookup tables)
├── albo-restudy-2024.qmd              (EDIT: use make_butterfly in CEL sections)
└── bolivia-censo-2024.qmd             (OPTIONAL: refactor make_count_diverging)
```

## Dependencies

`butterfly_helpers.R` loads:
- `tidyverse` (dplyr, ggplot2, etc.)
- `ggrepel` (label repulsion)
- Implicitly expects `scales::comma()` and `scales::percent_format()`

All are standard in both scripts already.

## Key Parameters Explained

### `make_butterfly()` signature

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `df` | tibble | — | Must have columns: `group_var`, `category_var`, `n_var` |
| `group_var` | chr | — | Name of grouping column (y-axis) |
| `category_var` | chr | — | Name of categorical dimension (fill) |
| `n_var` | chr | `"n"` | Count column name |
| `left_cats` | chr vector | NULL | Categories for left side; auto-split if NULL |
| `right_cats` | chr vector | NULL | Categories for right side; auto-split if NULL |
| `colors_map` | named chr | NULL | `category -> hex` mapping; uses ggplot defaults if NULL |
| `category_labels` | named chr | NULL | `category -> description` for legend (e.g., "0" = "0 — No identity, no language") |
| `label_prefix` | chr | `""` | Prefix for segment labels (e.g., "CEL: 1.2M") |
| `text_colors` | named chr | NULL | `category -> color` for label text (white/grey20) |
| `title` | chr | `"..."` | Plot title |
| `subtitle` | chr | `""` | Plot subtitle |
| `arrow_left` | chr | `"← Left"` | Left-side annotation |
| `arrow_right` | chr | `"Right →"` | Right-side annotation |
| `left_arrow_color` | chr | `"#4a5568"` | Left arrow color |
| `right_arrow_color` | chr | `"#2166ac"` | Right arrow color |
| `base_size` | num | `14` | Font size (scales all text) |
| `seed` | int | `7841` | Random seed for label repulsion |

### Modular functions

For more control, use individual functions:

```r
# Step 1: Prepare diverging data
prep <- prepare_butterfly_data(df, group_var = "col1", category_var = "col2", ...)

# Step 2: Extract bar positions (for accurate labels)
bar_pos <- extract_bar_positions(prep$data, colors_map = colors, y_labs = prep$y_labs)

# Step 3: Prepare smart labels (inside vs. above)
labels <- prepare_butterfly_labels(bar_pos, label_prefix = "CEL", text_colors = tc)

# Step 4: Make ggplot
p <- make_butterfly_plot(prep$data, labels, colors_map = colors, ...)

# Step 5: Customize (if needed)
p + theme(...)
```

## Testing

Both helper functions have been tested with actual CEL data from `albo_vars.rds`:

- ✓ CEL by urban/rural (2 groups × 10 CEL levels)
- ✓ CEL by age group (5 age groups × 10 CEL levels)
- ✓ One-call `make_butterfly()` wrapper
- ✓ Modular `prepare_*()` approach
- ✓ Correct label placement via `ggplot_build()`
- ✓ Left/right totals and segment labels
- ✓ Legend generation

## Next Steps

1. **Copy `butterfly_helpers.R`** to wiki-graph root
2. **In albo-restudy-2024.qmd:**
   - Add `source("butterfly_helpers.R")` once (top of CEL section)
   - Replace CEL butterfly code chunks with `make_butterfly()` calls
   - Adjust `base_size`, colors, and text as desired
3. **Optional:** Evaluate whether `make_count_diverging()` in bolivia-censo-2024.qmd should be refactored
4. **Document:** Add note to README/memory file pointing to `BUTTERFLY_HELPERS_DESIGN.md`

## Troubleshooting

**Q: Labels are overlapping despite `geom_text_repel()`**  
A: Increase `inside_threshold` in `prepare_butterfly_labels()` to move more labels to `geom_text_repel()`. Default is 6% of x-range.

**Q: Some categories not appearing in the legend**  
A: Ensure `colors_map` includes all category values. Missing entries will fall back to ggplot defaults.

**Q: Plot looks "squished" vertically**  
A: Increase `fig_height` parameter in Quarto chunk options (currently default is 5–6).

**Q: I need different label thresholds for different parts of a category**  
A: Use the modular approach and call `prepare_butterfly_labels()` twice with different thresholds, then manually `bind_rows()` the results before passing to `make_butterfly_plot()`.

## References

- `BUTTERFLY_HELPERS_DESIGN.md` — Full design rationale and examples
- `butterfly_helpers.R` — Inline code documentation
- `albo-restudy-2024.qmd` lines 838–1156 — Current (inline) butterfly implementations
- `bolivia-censo-2024.qmd` lines 686–782 — Language-specific `make_count_diverging()`
