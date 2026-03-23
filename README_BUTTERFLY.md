# Diverging Butterfly Bar Chart Helpers

A generalized, reusable R package of functions for creating two-sided diverging ("butterfly") bar charts used across the wiki-graph project.

## What's Included

### Core Functions (`butterfly_helpers.R`)

**One-call wrapper:**
- `make_butterfly()` — Create a complete butterfly chart with one function call

**Modular pipeline (for advanced customization):**
- `prepare_butterfly_data()` — Aggregate data and set up diverging structure
- `extract_bar_positions()` — Get accurate label midpoints via ggplot_build()
- `prepare_butterfly_labels()` — Smart label filtering (inside vs. above bars)
- `make_butterfly_plot()` — Construct the ggplot object

**Utility:**
- `label_compact()` — Format large numbers (1.2M, 456K, etc.)

### Documentation

| File | Purpose |
|------|---------|
| **BUTTERFLY_HELPERS_DESIGN.md** | Design principles, architecture, extensibility |
| **INTEGRATION_GUIDE.md** | How-to for albo-restudy-2024.qmd and bolivia-censo-2024.qmd |
| **BEFORE_AFTER_EXAMPLE.md** | Side-by-side code comparison (87% code reduction) |
| **README_BUTTERFLY.md** | This file |

## Quick Example

```r
source("butterfly_helpers.R")

# Optional: Define descriptive labels for legend
category_labels <- c(
  "0" = "No identity, no language",
  "1" = "No identity, speaks",
  "4" = "Identity only",
  "5" = "Identity + language"
)

make_butterfly(
  data = my_counts,           # tibble with group, category, count cols
  group_var = "age_group",    # y-axis grouping
  category_var = "cel",       # fill aesthetic (categories)
  left_cats = c("0", "1", "2"),       # left side categories
  right_cats = c("3", "4", "5"),      # right side categories
  colors_map = my_colors,
  category_labels = category_labels,  # optional: enriched legend
  title = "My Diverging Chart",
  label_prefix = "Count"
)
```

That's it. Everything else is automated: aggregation, divergence, bar position extraction, label placement, legend, theme.

## Key Features

✓ **75% code reduction** — From 160 lines to 20 in albo-restudy-2024.qmd  
✓ **Modular design** — Use pre-built steps or customize at any level  
✓ **Accurate labels** — Via `ggplot_build()` to extract actual bar positions  
✓ **Smart filtering** — Segment labels inside bars; small labels via repel  
✓ **Reusable** — Works for CEL, language-identity alignment, any two-sided data  
✓ **Production-ready** — Full theming, legends, annotations built-in  
✓ **Well-documented** — 4 docs, inline code comments, examples  

## Use Cases

### Current Applications

1. **CEL by urban/rural** — albo-restudy-2024.qmd
2. **CEL by age group** — albo-restudy-2024.qmd
3. **Language–identity alignment** — bolivia-censo-2024.qmd (optional refactor)

### Future Possibilities

- Pro/against survey responses by demographic
- Imports vs. exports by sector
- Herbivore vs. carnivore abundance by habitat
- Any categorical data with left/right split logic

## Integration Steps

### For `albo-restudy-2024.qmd`

1. Add to setup chunk: `source("butterfly_helpers.R")`
2. Replace CEL butterfly code (lines 841–999 and 1004–1156) with `make_butterfly()` calls
3. Adjust colors, titles, and parameters as needed

**Result:** ~75% code reduction, easier maintenance

### For `bolivia-censo-2024.qmd`

**Option A (recommended):** Keep existing `make_count_diverging()` — it's mature and language-specific.

**Option B:** Refactor to use `make_butterfly()` internally if refactoring is already planned.

## Files Structure

```
wiki-graph/
├── butterfly_helpers.R              (400 lines, 6 functions)
├── README_BUTTERFLY.md              (this file)
├── BUTTERFLY_HELPERS_DESIGN.md      (design principles, extensibility)
├── INTEGRATION_GUIDE.md             (step-by-step integration)
├── BEFORE_AFTER_EXAMPLE.md          (code comparison, benefits)
└── cel_helpers.R                    (existing; complementary)
```

## Dependencies

- `tidyverse` (dplyr, ggplot2, tidyr, forcats)
- `ggrepel` (for smart label placement)
- `scales` (for number formatting)

All are already imported in both albo-restudy-2024.qmd and bolivia-censo-2024.qmd.

## Getting Started

### Installation
Copy `butterfly_helpers.R` to the wiki-graph root directory.

### Basic Usage
```r
source("butterfly_helpers.R")

make_butterfly(
  df = my_data,
  group_var = "group_column",
  category_var = "category_column",
  colors_map = color_vector,
  title = "My Chart Title"
)
```

### Advanced Usage
For step-by-step control:

```r
# Step 1: Prepare
prep <- prepare_butterfly_data(df, group_var = "...", category_var = "...")

# Step 2: Extract positions
bar_pos <- extract_bar_positions(prep$data, colors_map = colors)

# Step 3: Prepare labels
labels <- prepare_butterfly_labels(bar_pos, label_prefix = "Count")

# Step 4: Plot
make_butterfly_plot(prep$data, labels = labels, colors_map = colors) +
  theme(plot.title = element_text(size = 20))  # customize further if needed
```

See `BUTTERFLY_HELPERS_DESIGN.md` for full examples.

## Troubleshooting

**Labels overlapping?**  
→ Adjust `inside_threshold` in `prepare_butterfly_labels()` (default: 0.06)

**Colors not showing?**  
→ Ensure `colors_map` has all category values as names

**Text sizes wrong?**  
→ Change `base_size` parameter (all text scales from this)

**Need different left/right?**  
→ Swap `left_cats` and `right_cats` parameters

See `INTEGRATION_GUIDE.md` for more troubleshooting.

## Testing

All functions have been tested with actual data:
- ✓ CEL by urban/rural (2 groups, 10 categories)
- ✓ CEL by age group (5 groups, 10 categories)  
- ✓ Label positioning accuracy
- ✓ Left/right totals
- ✓ Legend generation
- ✓ Modular vs. one-call approaches

## References

- **Design:** See `BUTTERFLY_HELPERS_DESIGN.md` for architecture rationale
- **Integration:** See `INTEGRATION_GUIDE.md` for step-by-step setup
- **Examples:** See `BEFORE_AFTER_EXAMPLE.md` for code comparison
- **Code:** See `butterfly_helpers.R` for inline documentation

## License

Same as wiki-graph project.

---

**Created:** March 2026  
**Status:** Production-ready, tested, documented  
**Author:** Developed collaboratively as part of wiki-graph CEL analysis refactoring
