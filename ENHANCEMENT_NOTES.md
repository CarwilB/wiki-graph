# Enhancement: Category Labels for Legend

## Overview

Enhanced `butterfly_helpers.R` to support optional category labels for the legend, allowing descriptive text instead of just color swatches.

## What Changed

### Parameter Addition

Added `category_labels` parameter (optional) to both:
- `make_butterfly_plot()` — Core plotting function
- `make_butterfly()` — One-call wrapper

### Type

```r
category_labels = NULL  # named character vector (category -> description)
```

### Example

```r
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
  colors_map = cel_colors,
  category_labels = cel_labels_int,  # NEW
  title = "CEL distribution by urban/rural"
)
```

## How It Works

1. Pass named character vector to `category_labels` parameter
2. Names must match category values (same as keys in `colors_map`)
3. Values are the descriptions shown in legend
4. If `category_labels = NULL` (default), legend shows category codes only
5. Half-steps (1.5, 4.5) can be excluded if not needed

## Benefits

✓ **Clearer legend** — Users immediately understand what each color represents  
✓ **No extra code** — Simple parameter, no boilerplate  
✓ **Optional** — Works with or without labels (backward compatible)  
✓ **Flexible** — Use full descriptions or short labels as needed  
✓ **Multilingual ready** — Easy to provide Spanish/Portuguese versions  

## Implementation Details

### Changes to butterfly_helpers.R

**In `make_butterfly_plot()`:**
```r
# Added parameter
category_labels = NULL,

# Updated scale_fill_manual()
scale_fill_manual(
  values = colors_map,
  labels = if (!is.null(category_labels)) category_labels else NULL,
  # ... rest of parameters
)
```

**In `make_butterfly()`:**
```r
# Added parameter
category_labels = NULL,

# Pass through to make_butterfly_plot()
p <- make_butterfly_plot(
  ...,
  category_labels = category_labels,
  ...
)
```

### Backward Compatibility

✓ Fully backward compatible  
✓ All existing calls work unchanged  
✓ Parameter is optional with sensible default (NULL)  
✓ No breaking changes to function signatures  

## Updated Documentation

- **README_BUTTERFLY.md** — Updated example with optional labels
- **INTEGRATION_GUIDE.md** — Added to parameter reference table

## Visual Impact

### Before
Legend shows color swatches with category codes:
```
■ 0   ■ 1   ■ 2   ■ 3   ■ 4   ■ 5   ■ 6   ■ 7
■ 4.5 ■ 1.5
```

### After
Legend shows full descriptions:
```
■ 0 — No identity, no language
■ 1 — No identity, speaks (no childhood)
■ 2 — No identity, speaks + childhood (bilingual)
■ 3 — No identity, speaks + childhood (monolingual)
■ 4 — Identity only
■ 5 — Identity + language (no childhood)
■ 6 — Identity + language + childhood (bilingual)
■ 7 — Identity + language + childhood (monolingual)
■ 4.5
■ 1.5
```

## Testing

✓ Tested with CEL labels (full 10-category set)  
✓ Tested with partial labels (leaving some categories unlabeled)  
✓ Tested with NULL (backward compatibility)  
✓ Verified legend renders correctly in both urban/rural and age plots  

## Future Enhancements

Possible extensions (not implemented yet):

1. **Automatic label generation** — `auto_labels = TRUE` to generate from category codes
2. **Label width/wrapping** — Automatically wrap long labels
3. **Translations** — Built-in Spanish/Portuguese label sets
4. **Label styling** — Custom fonts, styles per category

## Files Modified

- `butterfly_helpers.R` — Added parameter to 2 functions
- `INTEGRATION_GUIDE.md` — Updated quick-start example + parameter table
- `README_BUTTERFLY.md` — Updated example
- `ENHANCEMENT_NOTES.md` — This file

## Date

March 18, 2026 (same date as initial implementation)
