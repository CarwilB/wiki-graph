# Analysis: Recent Changes to wikipedia-admin-presence.qmd

**Commit**: b04031ac "Wikipedia admin units status update and code upgrade"  
**Date**: Mon Jul 20 09:12:14 2026  
**Analysis**: Identifies improvements replicable in `wikipedia-admin-presence-ssa.qmd`

---

## File Comparison Summary

| Aspect | SA (1374 lines) | SSA (866 lines) |
|--------|---|---|
| **Regions covered** | 4 (SA, MCA, Brazil) | 1 (Sub-Saharan Africa) |
| **ADM levels** | ADM2, ADM3 | ADM2, ADM3 (top 10 pop) |
| **Languages** | 3 (en, es, pt) + Quechua | 4 (en, fr, ar, sw) |
| **Documentation** | Inline | Structured appendix |
| **Cache tracking** | Yes (digest) | No |
| **Heatmap viz** | Per-language facets | Combined only |

---

## Replicable Improvements for SSA

### Priority 1: Ready to Apply (Low Risk, High Value)

#### **1. Cache Invalidation Tracking for Article Quality**
- **Location**: Line 626 in SSA (`#| label: ssa-article-quality`)
- **Change**: Add `#| cache-extra: !expr digest::digest(readLines("src/admin-article-quality.R"))`
- **Benefit**: Automatically invalidates cache when helper script changes
- **Implementation**: One-line addition
- **Status**: ✓ APPLY

**Before**:
```r
#| label: ssa-article-quality
#| cache: true
```

**After**:
```r
#| label: ssa-article-quality
#| cache: true
#| cache-extra: !expr digest::digest(readLines("src/admin-article-quality.R"))
```

---

#### **2. Language-Faceted Coverage Heatmaps**
- **Location**: After "Coverage heatmap" section (~line 346)
- **Change**: Add separate heatmaps for each featured language (en, fr, ar, sw)
- **Benefit**: Reveals language-specific coverage gaps (e.g., Arabic articles concentrated in certain regions)
- **Implementation**: Medium effort (new visualization subsection with faceted plots)
- **Status**: ✓ APPLY

**Concept** (from SA version, lines 777-812):
```r
### Coverage by language

### English coverage
[facet_wrap or facet_grid heatmap for English only]

### French coverage
[heatmap for French only]

### Arabic coverage
[heatmap for Arabic only]

### Swahili coverage
[heatmap for Swahili only]
```

**Specific code pattern from SA**:
```r
all_data |>
  filter(!is.na(en)) |>  # or respective lang column
  count(country, adm_level, en) |>
  ggplot(aes(x = country, y = adm_level, fill = en)) +
  geom_tile() +
  scale_fill_viridis_c()
```

---

### Priority 2: Conditional/Deferred Changes

#### **3. Region Variable in Population Table**
- **Requirement**: Add `~region` column to `ssa_adm2_registry` and `ssa_adm3_registry`
- **Benefit**: Allows sub-regional analysis (e.g., "How does East Africa differ from West Africa?")
- **Implementation**: Medium effort (modify registries, update grouping)
- **Status**: ⚠ CONDITIONAL - Only if region taxonomy is defined
- **Example from SA** (line 849-850):
  ```r
  all_data_pop |>
    group_by(region, country, adm_level) |>  # <-- adds region
  ```

**Question for decision**: Is there a meaningful regional breakdown in Sub-Saharan Africa registries?
- If yes: Add region column and apply grouping change
- If no: Skip this improvement

---

### Priority 3: Already Present in SSA (No Action Needed)

These improvements exist in SSA and don't need replication:

#### ✓ **Better Appendix Organization**
- SSA has explicit Appendix (lines 814-859) with:
  - Registries reference
  - Excluded countries documentation
  - ADM3 exclusion notes
  - Class selection notes
- SA could adopt this structure

#### ✓ **Callout Boxes for Caveats**
- SSA uses Quarto callout syntax at lines 140-145:
  ```markdown
  ::: {.callout-note}
  Some ADM2 classes capture items that are technically ADM1...
  :::
  ```
- SA could adopt this for better caveat visibility

#### ✓ **Region-Appropriate Language Selection**
- Both documents correctly select languages for their regions
- SSA: en, fr, ar, sw (appropriate for Sub-Saharan Africa)
- SA: en, es, pt, qu (appropriate for Latin America)
- No change needed

---

## Implementation Roadmap

### Immediate (One session)
1. **Add cache dependency tracking** (1 min)
   - File: `wikipedia-admin-presence-ssa.qmd`, line 627
   - Action: Insert `cache-extra` line

### Short-term (1-2 sessions)
2. **Design language-faceted heatmaps** (30-60 min)
   - File: `wikipedia-admin-presence-ssa.qmd`, after line 388
   - Action: Create new subsection with per-language coverage visualizations
   - Decision: Which heatmap style? (tiles, bars, small multiples?)

### Deferred (depends on data structure)
3. **Add region variable** (if applicable)
   - File: Registry tables at lines 148-189 and 254-299
   - Decision: Define region taxonomy for SSA countries
   - Action: Add column, update table groupings

---

## Code Snippets Ready to Copy

### Snippet A: Enhanced Cache Configuration
```r
```{r}
#| label: ssa-article-quality
#| cache: true
#| cache-extra: !expr digest::digest(readLines("src/admin-article-quality.R"))

# ... existing code ...
```
```

### Snippet B: Language-Specific Heatmap Template
```r
```{r}
#| label: fig-coverage-heatmap-by-lang
#| fig-width: 10
#| fig-height: 8
#| fig-cap: "Wikipedia coverage heatmaps by featured language"

# Prepare data with region and country
coverage_by_lang <- all_data |>
  pivot_longer(cols = all_of(featured_langs), 
               names_to = "language", 
               values_to = "has_article")

# Create faceted heatmap
coverage_by_lang |>
  filter(has_article == 1) |>
  count(country, adm_level, language) |>
  group_by(language, country) |>
  summarise(pct_coverage = n() / n_distinct(adm_level), .groups = "drop") |>
  ggplot(aes(x = country, y = adm_level, fill = pct_coverage)) +
  geom_tile() +
  facet_wrap(~ factor(language, levels = featured_langs, 
                      labels = featured_labels)) +
  scale_fill_viridis_c(name = "% units with article", option = "viridis") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
```
```

---

## Summary Table: What to Do Where

| Improvement | File | Lines | Type | Status | Effort |
|-------------|------|-------|------|--------|--------|
| Cache tracking | SSA | 627 | Add | ✓ APPLY | 1 min |
| Language heatmaps | SSA | ~395 | New section | ✓ APPLY | 30 min |
| Region variable | Both | 150, 254 | Enhance | ⚠ CONDITIONAL | 20 min |
| Appendix format | SA | ~1350 | Restructure | ← Reverse | 30 min |
| Callout boxes | SA | ~200-400 | Add | ← Reverse | 20 min |

---

## Files for Reference

- **Original commit**: `b04031ac`
- **SA file**: `wikipedia-admin-presence.qmd` (1374 lines)
- **SSA file**: `wikipedia-admin-presence-ssa.qmd` (866 lines)

---

**Last updated**: July 20, 2026  
**Analysis completed for**: wiki-graph project
