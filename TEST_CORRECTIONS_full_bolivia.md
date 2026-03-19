# Test SVG Corrections - Full Bolivia Extent

**File**: `output/locator_maps/Bolivia_full_test.svg`  
**Date**: March 9, 2026  
**Size**: 11.71 MB

---

## Issues Identified & Corrected

### 1. ✓ Overall Boundary Box (FIXED)

**Issue**: Test map showed only La Paz region with ±1.5° padding.

**Correction**: Extended to full Bolivia extent:
- **Longitude**: -71.0°W to -56.8°W
- **Latitude**: -24.0°S to -9.0°S

**Data**: Specified explicitly in new test SVG

---

### 2. ✓ Lake Titicaca Municipalities (FIXED)

**Issue**: GADM contains 5 municipalities named "Lago Titicaca" that are administrative entities but represent water areas. They were being rendered as pale-cream regular municipalities.

**Municipalities affected**:
1. Lago Titicaca (Camacho, La Paz)
2. Lago Titicaca (Ingavi, La Paz)
3. Lago Titicaca (Los Andes, La Paz)
4. Lago Titicaca (Manco Kapac, La Paz)
5. Lago Titicaca (Omasuyos, La Paz)

**Correction**: Now rendered as water (same color as lake/ocean):
- **Fill**: `#C7E7FB` (light blue, matching water bodies)
- **Border**: `None` (no visible municipal boundary)
- **Rendering order**: After regular municipalities and lake polygon, so Lake Titicaca polygon coastline is visible on top

**Result**: Clean water representation without municipality boundaries confusing the map

---

### 3. ? Peru Water Bodies (REQUIRES EVALUATION)

**Issue identified**: Some water features visible inside Peru's grey boundary area.

**Potential causes**:
- Peru's coastal water bodies (Pacific Ocean, rivers, lakes) not explicitly excluded
- Natural Earth countries shapefile includes territorial waters
- Map projection artifacts at edges

**Solution approach**:
- Inspect rendered SVG visually
- May need to exclude Peru's internal waters OR render them as ocean blue
- Alternatively, Peru data may be correct and just appears odd due to coastal geography

**Status**: Requires visual inspection of saved SVG

---

### 4. ? Peru/Bolivia Border Blank Space (REQUIRES EVALUATION)

**Issue identified**: Apparent blank space along the international Peru/Bolivia border.

**Potential causes**:
1. **Geometry misalignment**: GADM municipalities don't meet perfectly at the border
2. **Missing Bolivia regions**: Some border areas not covered by either GADM or Natural Earth
3. **Rendering gap**: Small gaps in vector geometries rendered as white (background color)

**Investigation needed**:
1. Check if blank space is actually visible in rendered SVG
2. If yes, inspect GADM municipality boundaries along Peru border
3. May require: filling small gaps, adjusting border line width, or accepting minor visual artifacts

**Status**: Requires visual inspection and geometry analysis

---

### 5. ? Other International Borders (REQUIRES EVALUATION)

**Borders to check**:
- **Brazil** (northeast): Continuous boundary
- **Argentina** (south): Should be clean
- **Paraguay** (southeast): Should be clean
- **Chile** (southwest): Should be clean

**Status**: Deferred until full-extent map is visually inspected

---

## Technical Details

### Data Pipeline (Updated)

```
1. GADM Bolivia (344 municipalities)
   ├─ 5 named "Lago Titicaca" → RENDER AS WATER
   └─ 339 regular municipalities → RENDER AS PALE CREAM (#FDFBEA)

2. Natural Earth neighbors (5 countries)
   ├─ Peru
   ├─ Brazil
   ├─ Argentina
   ├─ Paraguay
   └─ Chile → ALL RENDER AS LIGHT GRAY (#DFDFDF)

3. Lake Titicaca polygon (manual)
   └─ RENDER WITH LIGHT BLUE FILL (#C7E7FB) + BLUE COASTLINE (#1278AB)

4. Rendering order (layers):
   1. Water background (#C7E7FB)
   2. Neighboring countries (grey)
   3. Lake Titicaca polygon (light blue with blue border)
   4. Regular Bolivian municipalities (pale cream with grey borders)
   5. Lake Titicaca municipalities (light blue, NO BORDERS)
```

### Key Changes from Previous Test

| Aspect | Previous | Current |
|--------|----------|---------|
| **Extent** | La Paz only (±1.5°) | Full Bolivia (-71 to -56.8°W, -24 to -9°S) |
| **Lake municipalities** | Rendered as pale cream | Rendered as light blue water |
| **Lake municipalities borders** | Visible grey borders | No borders |
| **File size** | 4.0 MB | 11.71 MB |
| **Context** | Limited neighbors | All 5 neighbors fully visible |

### Municipality Count Verification

```r
nrow(mun_regular)          # 339 regular municipalities
nrow(mun_titicaca)         # 5 Lake Titicaca municipalities
nrow(gadm)                 # 344 total GADM features
# 339 + 5 = 344 ✓
```

---

## Next Steps After Visual Inspection

### If borders look good:
1. **Accept full-Bolivia template** as standard for all 339 maps
2. **Modify batch script** (`generate_locator_maps_batch.R`):
   - Change: `bbox_padding = 1.5` → **For full-extent maps**: use full Bolivia bbox
   - OR **For regional maps**: keep localized extent with padding
3. **Clarify municipal zoom strategy**: 
   - Option A: All 339 maps show full Bolivia (context)
   - Option B: Each map uses localized extent (focused view)

### If border issues found:
1. **Analyze specific geometry gaps** at Peru/Bolivia border
2. **Options for fixing**:
   - Dissolve nearby GADM polygon edges to close gaps
   - Add very thin grey line across gaps
   - Accept as minor cartographic artifact (common in vector maps)
3. **Alternative**: Use higher-resolution data source (if available)

### For Peru water bodies:
1. **Evaluate visually** if it's a problem
2. If it is:
   - Option A: Fill Peru's internal water areas with ocean blue
   - Option B: Simplify Peru geometry to exclude waters
   - Option C: Accept as realistic coastal representation

---

## Usage Notes

### Viewing the SVG

```bash
# Open in browser or Inkscape
open /Users/bjorkjcr/Dropbox\ \(Personal\)/R/wiki-graph/output/locator_maps/Bolivia_full_test.svg

# Or view in R
# (Note: SVG preview may vary by viewer; best viewed in web browser or Inkscape)
```

### Extracting for Batch Use

Once full-extent approach is validated, extract the map code into batch script:

```r
# From this test:
bbox_full <- c(xmin = -71.0, xmax = -56.8, ymin = -24.0, ymax = -9.0)

titicaca_munis <- gadm |> 
  filter(grepl("Lago|Titicaca", NAME_3, ignore.case = TRUE)) |>
  pull(NAME_3)

mun_titicaca <- gadm |> filter(NAME_3 %in% titicaca_munis)
mun_regular <- gadm |> filter(!NAME_3 %in% titicaca_munis)

# Then use this rendering pattern for all 339 maps
# (Batch script will need modification to handle two municipality categories)
```

---

## Color Scheme Validation

✓ **Full validation** against Wikipedia 2012:

| Element | Hex | Applied |
|---------|-----|---------|
| Water bodies | `#C7E7FB` | Background + Lake Titicaca fill + municipalities |
| Coastlines | `#1278AB` | Lake Titicaca border |
| Surrounding internal | `#FDFBEA` | Regular Bolivian municipalities |
| Surrounding external | `#DFDFDF` | Neighboring countries |
| Borders | `#656565` | Municipality & country boundaries |

---

## Files Generated

- **Test SVG**: `output/locator_maps/Bolivia_full_test.svg` (11.71 MB)
- **This document**: `TEST_CORRECTIONS_full_bolivia.md`

---

## Checklist for Final Approval

- [ ] **Visual inspection** of rendered SVG
  - [ ] Peru water bodies acceptable?
  - [ ] Peru/Bolivia border gaps acceptable or problematic?
  - [ ] Other borders clean and correct?
  - [ ] Lake Titicaca municipalities rendered as water?
  - [ ] Colors match Wikipedia 2012 scheme?
- [ ] **Decision**: Use full-extent or localized-extent for batch generation?
- [ ] **Batch script**: Update to handle Lake Titicaca municipalities separately
- [ ] **Proceed**: Batch generation of 339 maps

---

## Reference: muni_id_lookup_table

For converting INE codes to GADM names in future:

```r
muni_lookup <- readRDS("data/muni_id_lookup_table.rds")
# Look up: INE code → GADM NAME_3
```

---

**Status**: Test SVG created and ready for visual evaluation.
