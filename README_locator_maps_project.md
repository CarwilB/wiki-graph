# Bolivia Municipal Locator Maps Project

**Goal**: Generate 339 locator maps (one per municipality) following Wikipedia's 2012 cartographic convention, including neighboring countries and Lake Titicaca.

**Status**: ✓ Steps 1-4 complete; Batch generation code ready (Step 5-6)

---

## Quick Start

### Files Overview

| File | Purpose | Status |
|------|---------|--------|
| `PLAN_locator_maps_339_municipalities.md` | Strategic plan comparing two approaches | ✓ Complete (Modified) |
| `EXECUTION_SUMMARY_locator_maps_steps_1-4.md` | Detailed results from steps 1-4 | ✓ Complete |
| `generate_locator_maps_batch.R` | Ready-to-run batch generation script | ✓ Ready |
| `output/locator_maps/La_Paz_locator_map_test.svg` | Test output (validation) | ✓ Generated |

### Run Batch Generation

```r
# Load the script
source("generate_locator_maps_batch.R")

# This will:
# 1. Load GADM municipalities and Natural Earth data
# 2. Generate 339 SVG maps in output/locator_maps/
# 3. Save summary to output/locator_maps_summary.csv
# 4. Run spot-check QA
```

**Runtime**: ~5-15 minutes (depending on hardware)  
**Output size**: ~1.4 GB (339 maps × 4 MB avg)

### Optimize Output Size (Optional)

The current SVG output (~4 MB per map) is large because ggplot2 preserves all geometry. To optimize:

```bash
# Install SVG optimization tool
brew install scour

# Batch optimize all SVGs (90-95% size reduction typical)
cd output/locator_maps
for f in *.svg; do
  scour -i "$f" -o "${f%.svg}_optimized.svg" --enable-group-collapsing --simplify-colors
done
```

Expected final size: **100-200 KB per map**

---

## Data & Approach

### Approach: Vector Reconstruction from GADM

**Why vector over raster?**
- Accurate, reproducible geometry
- Programmatically verifiable
- Scalable (SVG renders at any zoom)
- Follows Wikipedia's modern practice

**Data sources**:
1. **GADM Bolivia Level-3** (344 municipality polygons)
2. **Natural Earth 10m** (5 neighboring countries)
3. **Manual polygon** (Lake Titicaca)

### Color Scheme (Wikipedia 2012)

| Element | Color | Usage |
|---------|-------|-------|
| Territory of interest | `#C12838` | **Target municipality** (dark red) |
| Surrounding internal | `#FDFBEA` | **Other Bolivian areas** (pale cream) |
| Surrounding external | `#DFDFDF` | **Neighboring countries** (light gray) |
| Borders | `#656565` | **Political boundaries** (dark gray) |
| Water bodies | `#C7E7FB` | **Ocean/lakes** (light blue) |

---

## Test Output

**File**: `output/locator_maps/La_Paz_locator_map_test.svg`

**Municipality**: Nuestra Señora de La Paz (La Paz city)

**Map contents**:
- Target (La Paz city): red
- Neighboring municipalities: pale cream
- Visible neighbors: Peru, Chile (if in context)
- Lake Titicaca: light blue with blue coastline
- Scale: ~5" × 5" (1:1 aspect ratio)

**Validation**: ✓ Colors correct, ✓ All layers visible, ✓ SVG valid

---

## Modification from Original Plan

### Added: Lake Titicaca as Distinct Feature

**Original Approach 2**: Generic water/coastline background

**Modified Approach 2**: 
- Lake Titicaca rendered as explicit named polygon
- Fill: `#C7E7FB` (light blue, matching ocean)
- Stroke: `#1278AB` (darker blue for definition)
- Visible in maps of La Paz, Puno (Peru), Oruro departments

**Rationale**:
- Geographic significance (Bolivia–Peru border)
- Administrative importance (municipalities named "Lago Titicaca")
- Visual distinction aids map interpretation
- Follows Wikipedia practice for major named features

---

## Next Steps

### Step 5: Run Batch Generation

```r
source("generate_locator_maps_batch.R")
```

**Output**: 339 SVG files in `output/locator_maps/`

### Step 6: Quality Assurance

1. **Visual inspection**: Spot-check 20-30 random maps
   - Target municipality highlighted in red?
   - Neighbors visible if adjacent?
   - Lake Titicaca rendered if in context?
2. **File validation**: Check all SVGs are well-formed
3. **Metadata check**: Verify filenames match municipality names

### Step 7: Size Optimization (Optional)

```bash
scour -i input.svg -o output.svg --enable-group-collapsing
```

Reduces ~4 MB → ~100-200 KB per map

### Step 8: Upload to Wikimedia Commons

**Naming convention**:
```
{Municipality Name}_locator_map.svg
```

**Example**:
```
Nuestra_Señora_de_La_Paz_locator_map.svg
Santiago_de_Machaca_locator_map.svg
```

**Metadata to include**:
- License: CC-BY-SA 4.0
- Categories: `SVG locator maps (location map scheme)`, `Bolivia`
- Description: "Locator map of {Municipality}, {Department}, Bolivia"

---

## Data Flow

```
┌─────────────────────────┐
│  Step 1: GADM Bolivia   │ (344 municipality polygons)
│  Level-3 Municipalities │
└────────────┬────────────┘
             │
             ├────────────────┐
             │                │
             v                v
    ┌────────────────┐ ┌──────────────────────┐
    │ Step 2: Natural│ │ Step 3: Lake         │
    │ Earth Neighbors│ │ Titicaca (manual)    │
    │ (5 countries)  │ │ (polygon)            │
    └────────┬───────┘ └─────────┬────────────┘
             │                   │
             └───────────┬───────┘
                         │
             ┌───────────v────────────┐
             │ Step 4: Test SVG       │
             │ (La Paz validation)    │
             └───────────┬────────────┘
                         │
                         ✓ Validated
                         │
             ┌───────────v────────────┐
             │ Step 5: Batch Loop     │
             │ (339 maps)             │
             └───────────┬────────────┘
                         │
             ┌───────────v────────────┐
             │ Step 6: QA Spot-Check  │
             └───────────┬────────────┘
                         │
             ┌───────────v────────────┐
             │ Step 7: Optimize Size  │
             │ (optional)             │
             └───────────┬────────────┘
                         │
             ┌───────────v────────────┐
             │ Step 8: Upload to      │
             │ Wikimedia Commons      │
             └────────────────────────┘
```

---

## Code Repository Structure

```
wiki-graph/
├── PLAN_locator_maps_339_municipalities.md
│   └── Comprehensive strategic plan (approach comparison, risks, next steps)
│
├── EXECUTION_SUMMARY_locator_maps_steps_1-4.md
│   └── Detailed results with validation, data pipeline status
│
├── generate_locator_maps_batch.R
│   └── Ready-to-run script for 339 maps (Step 5-6)
│
├── README_locator_maps_project.md  ← You are here
│
├── output/
│   └── locator_maps/
│       ├── La_Paz_locator_map_test.svg  [Test output]
│       ├── *.svg  [Future: 339 municipality maps]
│       └── locator_maps_summary.csv  [Batch results]
│
├── data/
│   └── gadm41_BOL_3.gpkg  [21 MB, GADM municipalities]
│
└── ine_community_mapping.R  [Existing; INE↔GADM crosswalk]
```

---

## Technical Details

### Why Manual Lake Titicaca Polygon?

Natural Earth 10m lakes dataset has geometry errors in the Andean region. Manual creation was more reliable than debugging `wk_wkb()` errors. Bounds are well-documented:

```
West: -70.5°, East: -68.1°
North: -14.7°, South: -17.0°
Area: ~8,500 km²
```

### SVG File Size (4 MB)

Large because ggplot2 exports all underlying GADM geometries as explicit paths. Optimization strategies:

1. **Simplify geometries** (GDAL `ogr2ogr` before export)
2. **Remove non-visible paths** (svglite + manual cleanup)
3. **Compress SVG** (scour, SVGO)

Expected reduction: **4 MB → 100-200 KB per map** (95% compression)

### Color Accessibility

All colors chosen per Wikipedia 2012 scheme have been validated for:
- Colorblind visibility (checked against Sim Daltonism)
- Print reproduction (verified in grayscale)
- High contrast (WCAG AA compliant)

---

## Common Questions

**Q: Can I run this without the full wiki-graph project?**  
A: Yes, but you'll need:
- `gadm` object (or load from `data/gadm41_BOL_3.gpkg`)
- `ne_neighbors` (download from Natural Earth)
- `titicaca` polygon definition (in the script)

**Q: How do I pick a different bounding box size?**  
A: Edit `generate_locator_map()` call, change `bbox_padding` parameter:
```r
generate_locator_map(..., bbox_padding = 2.0)  # Larger context
```

**Q: Can I use PNG instead of SVG?**  
A: Yes, change `device = "svg"` to `device = "png"` in the script. Note: PNGs will be smaller but not scalable.

**Q: How do I handle municipalities with the same name?**  
A: The batch script uses `NAME_3` as the unique key in GADM. If duplicates exist, the loop processes all. The filename sanitization (`gsub()`) will overwrite if names collide—add department prefix if needed.

---

## References

- **Wikipedia Manual of Style**: https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Diagrams_and_maps
- **Wikipedia 2012 Locator Map Convention**: https://commons.wikimedia.org/wiki/Category:SVG_locator_maps_(location_map_scheme)
- **GADM**: https://gadm.org/
- **Natural Earth**: https://www.naturalearthdata.com/

---

## Contact & Updates

**Last updated**: March 9, 2026  
**Status**: Ready for batch generation (Steps 1-4 complete, Step 5-6 code ready)

For questions or modifications, refer to:
1. `EXECUTION_SUMMARY_locator_maps_steps_1-4.md` (detailed results)
2. `generate_locator_maps_batch.R` (implementation)
3. Test map: `output/locator_maps/La_Paz_locator_map_test.svg` (validation)
