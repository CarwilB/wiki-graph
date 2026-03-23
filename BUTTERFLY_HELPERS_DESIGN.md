# Diverging "Butterfly" Bar Chart Helpers

## Overview

`butterfly_helpers.R` provides a generalized, reusable pipeline for creating two-sided diverging bar charts (colloquially "butterfly" charts) that appear in multiple wiki-graph analyses:

- CEL distribution by urban/rural (albo-restudy-2024.qmd)
- CEL distribution by age group (albo-restudy-2024.qmd)
- Language–identity alignment by language group (bolivia-censo-2024.qmd, `count-plot-editorial`)

## Design Principles

### 1. **Modular Pipeline**

Instead of monolithic plotting functions, the script exports four levels of abstraction:

| Function | Purpose | Input | Output |
|----------|---------|-------|--------|
| `prepare_butterfly_data()` | Aggregate + diverge | Long counts tibble | Diverged DF + metadata |
| `extract_bar_positions()` | Get accurate labels | Diverged DF | Bar position/midpoint tibble |
| `prepare_butterfly_labels()` | Smart label filtering | Bar positions | Inside/above/total labels |
| `make_butterfly_plot()` | Construct ggplot | Diverged DF + labels | ggplot2 object |
| `make_butterfly()` | One-call convenience | Aggregated counts | ggplot2 object |

**Users can:**
- Call `make_butterfly()` for a one-liner plot with sensible defaults
- Use individual functions to customize intermediate steps
- Skip steps entirely and manually construct what's needed

### 2. **Generalized Left/Right Split**

The core distinction in a butterfly chart is dividing categories into "left" (e.g., CEL 0–3, no identity) and "right" (CEL 4–7, with identity) sides. The functions handle this flexibly:

```r
# Explicit left/right categories
left_cats = c("0", "1", "1.5", "2", "3")
right_cats = c("4", "4.5", "5", "6", "7")

# Or auto-detect by splitting alphabetically (useful for generic cases)
# If neither is specified, left_cats/right_cats are computed from unique values
```

### 3. **Accurate Label Positioning via `ggplot_build()`**

A key challenge with diverging bars is label placement. ggplot2's `position_stack()` stacks in a specific order (reversed factor levels closest to axis), which is non-obvious for negative values.

**Solution:** Extract actual bar positions post-rendering:

```r
bar_positions <- extract_bar_positions(df, colors_map = cel_colors)
# Returns: mid, width, xmin, xmax for each segment — perfectly aligned with rendered plot
```

This avoids fragile cumsum logic that breaks if stacking assumptions change.

### 4. **Smart Label Filtering**

Segment labels are filtered by width thresholds:

- **Inside**: Wide enough for direct `geom_text()` (default: >6% of x-range)
- **Above**: Small enough to need `geom_text_repel()` (default: 0.5%–6% of x-range)
- **Unlabeled**: Tiny segments below threshold

Totals (left + right sums) always appear outside the bars.

## Usage Examples

### Example 1: CEL by urban/rural (one-liner)

```r
source("butterfly_helpers.R")

cel_urbrur <- albo_vars |>
  mutate(urbrur_label = c("1" = "Urban", "2" = "Rural")[as.character(urbrur)]) |>
  filter(!is.na(urbrur_label), !is.na(cel)) |>
  count(urbrur_label, cel) |>
  mutate(cel_chr = as.character(cel))

make_butterfly(
  cel_urbrur,
  group_var = "urbrur_label",
  category_var = "cel_chr",
  n_var = "n",
  left_cats = c("0", "1", "1.5", "2", "3"),
  right_cats = c("4", "4.5", "5", "6", "7"),
  colors_map = cel_colors,
  label_prefix = "CEL",
  text_colors = c("0" = "white", "1" = "grey20", ...), # see cel_helpers.R for full mapping
  title = "CEL distribution by urban/rural",
  subtitle = "Bolivia CPV 2024"
)
```

### Example 2: Language–identity alignment (step-by-step)

```r
# Step 1: Prepare data
prep <- prepare_butterfly_data(
  language_alignment_counts,
  group_var = "idioma_grp",
  category_var = "outcome_plot",
  left_cats = c("Does not identify", "No response", "Generic identity", "Different group"),
  right_cats = c("Matching group", "Identifies as indigenous")
)
df <- prep$data

# Step 2: Extract accurate bar positions
bar_pos <- extract_bar_positions(df, colors_map = outcome_colors, y_labs = prep$y_labs)

# Step 3: Customize label thresholds
labels <- prepare_butterfly_labels(
  bar_pos,
  inside_threshold = 0.08,  # wider threshold for this dataset
  above_threshold = 0.003
)

# Step 4: Modify ggplot (e.g., custom theme)
p <- make_butterfly_plot(df, labels, colors_map = outcome_colors)
p + theme(plot.title = element_text(size = 20))
```

## Integration with Existing Scripts

### `albo-restudy-2024.qmd`

Replace the current inline CEL butterfly code (~160 lines) with:

```r
#| label: cel-urbrur-diverging
source("butterfly_helpers.R")

# ... (data prep: cel_urbrur) ...

make_butterfly(
  cel_urbrur,
  group_var = "urbrur_label",
  category_var = "cel_chr",
  # ... remaining params ...
)
```

### `bolivia-censo-2024.qmd`

The existing `make_count_diverging()` function is language–identity specific. It can be **refactored to use `make_butterfly()`** internally, or replaced entirely if users prefer more control.

## Extensibility

The functions are designed to work with any two-sided categorical data:

- **Ecological data**: herbivore vs. carnivore abundance by habitat
- **Survey results**: pro/against opinions by demographic
- **Mortality**: deaths vs. survivals by age group
- **Economic**: imports vs. exports by sector

Just provide:
- Long format: `(group, category, count)`
- Left/right split logic
- Color mapping
- Axis/legend labels

## Notes

- **Dependencies**: tidyverse, ggplot2, ggrepel, scales (all imported by helper script)
- **Font scaling**: All text sizes scale off `base_size` parameter
- **ggplot_build() usage**: Requires a bare geom_col plot; works with or without colors_map (if NULL, uses ggplot defaults)
- **Reproducibility**: Set `seed` parameter for consistent label repulsion across runs

## Files Modified/Created

- **NEW**: `butterfly_helpers.R` (main helper script)
- **NEW**: `BUTTERFLY_HELPERS_DESIGN.md` (this file)
- **PENDING**: `albo-restudy-2024.qmd` (use make_butterfly() for CEL sections)
- **PENDING**: `bolivia-censo-2024.qmd` (optional refactor of make_count_diverging)
