# Plan: Bolivia Municipal Locator Maps (339 municipalities)

## Objective
Create 339 locator maps (one per municipality) following Wikipedia's 2012 convention color scheme, showing each municipality highlighted in the "territory of interest" color while providing geographic context.

## Available Resources

### Data Assets
- **GADM Bolivia level-3**: 344 municipality polygons (MULTIPOLYGON, WGS84) in `data/gadm41_BOL_3.gpkg`
  - Fields: NAME_1 (department), NAME_2 (province), NAME_3 (municipality)
  - Covers Bolivia's entire territory
- **INE-GADM mapping**: Already established in `ine_community_mapping.R` (295 of 339 direct name matches, manual overrides for rest)
- **Municipality centroids**: Computed in `ine_community_mapping.R` via `st_centroid()`
- **Reference image**: https://upload.wikimedia.org/wikipedia/commons/9/99/Bolivia_Municipios.png (raster, painted fill style)

### Color Scheme (Wikipedia 2012)
- `territory_of_interest`: `#C12838` (marked/focus area - dark red)
- `surrounding_internal`: `#FDFBEA` (internal territories - pale cream)
- `surrounding_external`: `#DFDFDF` (surrounding landmass - light gray)
- `borders_dept`: `#656565` (department boundaries - dark gray, solid)
- `borders_mun`: `#656565` (municipal boundaries - dark gray, lighter/dashed)
- `water_bodies`: `#C7E7FB` (light blue)
- `coastlines`: `#1278AB` (darker blue)

---

## APPROACH 1: Image Fill on Raster Reference

### Method
1. Download or use local copy of Bolivia_Municipios.png
2. Convert to RGB in R (using `imager` or `magick`)
3. Load municipality boundaries (GADM)
4. For each municipality:
   - Calculate centroid
   - Identify pixel at centroid location
   - Perform flood-fill (paint-bucket algorithm) from that pixel
   - Recolor flood-filled region to `#C12838`
   - Export PNG

### Pros
- Preserves the exact cartographic style and detail of the original Wikipedia image
- Faster rendering (direct pixel operations)
- Small output file size (PNG compression)
- No need to manually add neighboring countries or ocean

### Cons
- **Brittle**: Flood-fill depends critically on:
  - Accurate centroid→pixel mapping (requires precise georeference of raster)
  - Internal boundaries being continuous and closed
  - No pixel corruption or anti-aliasing artifacts at boundary edges
- **Error-prone**: A single misaligned centroid or pixel bleed = incorrect fill region
- **Limited scalability**: Raster image loses sharpness when zoomed
- **Coordinate mismatch risk**: Original PNG georeference metadata may be imprecise or missing
- **Difficult QA**: Hard to verify correct fill region programmatically (would need manual inspection of all 339 maps)

### Implementation Complexity: **MEDIUM-HIGH**
- Requires GDAL/GeoReferencer or manual coordinate calibration
- Flood-fill algorithm needs careful edge-case handling (islands, enclaves, coastal geometry)
- Raster←→vector coordinate transformation is a common source of off-by-one errors

---

## APPROACH 2: Vector Reconstruction from GADM + Natural Features

### Method
1. Load GADM Bolivia level-3 municipalities (already in session)
2. Acquire natural feature datasets:
   - **Coastline/ocean boundary**: GADM level-0 (Bolivia national boundary) OR Natural Earth coastlines
   - **Neighboring countries**: GADM level-1 or level-0 for AR, PE, BR, CL, PY
   - **Lake Titicaca**: Natural Earth lakes dataset (50m resolution) OR manual polygon
   - **Rivers/major hydrography** (optional): Natural Earth or GADM level-2 rivers
3. For each of 339 municipalities:
   - Subset GADM to current municipality (target) + all others (context)
   - Calculate bounding box or fixed frame around target
   - Generate SVG with:
     - Ocean/water background (`#C7E7FB`)
     - Neighboring country fills (`#DFDFDF`)
     - Internal department boundaries (solid `#656565`)
     - Internal municipal boundaries (lighter/dashed `#656565`)
     - Target municipality fill (`#C12838`)
   - Save as `{municipality_name}_locator_map.svg`

### Pros
- **Accurate and reproducible**: Vector geometry is precise; no raster georeference guesswork
- **Highly scalable**: SVG renders sharply at any zoom level
- **Easy QA**: Geometry is directly queryable (can verify each output programmatically)
- **Maintainable**: Clean code; easy to update styling or fix errors in one place
- **Batch automation**: Single script generates all 339 maps consistently
- **Interoperability**: SVG is widely supported; can be embedded in web, edited, or converted to PNG per-map
- **Following best practice**: Wikipedia's own locator maps are increasingly SVG-based

### Cons
- **Requires additional data sources**:
  - Neighboring country boundaries (Peru, Brazil, Argentina, Paraguay, Chile)
  - Ocean/coastline polygon (or use negative space)
  - Optional: rivers, lakes
- **More code**: Multi-step geometry preparation, SVG templating/generation
- **Larger file per map**: SVG is text; ~50–200 KB per map (vs. ~5–20 KB for optimized PNG)
- **Data wrangling**: Must join GADM → INE municipality codes, handle name mismatches, ensure CRS consistency

### Implementation Complexity: **MEDIUM**
- Data acquisition and prep: straightforward with `rnaturalearth` or GADM
- SVG generation: can use `ggplot2` + `ggsave(..., device="svg")` OR `sf` + `{svglite}` OR manual XML construction
- Loop over 339 municipalities: trivial once the template is working

---

## Comparative Assessment

| Factor | Approach 1 (Raster Fill) | Approach 2 (Vector Reconstruction) |
|--------|--------------------------|----------------------------------|
| **Accuracy** | ⚠️ Depends on raster georeference | ✅ Precise WGS84 geometry |
| **Reproducibility** | ⚠️ Image-specific; hard to fix | ✅ Code-based; easily fixed/updated |
| **Validation** | ❌ Requires manual spot-checks | ✅ Programmatic QA possible |
| **File size** | ✅ Small (PNG) | ⚠️ Larger (SVG) |
| **Rendering speed** | ✅ Fast (raster) | ⚠️ Slower (vector rendering) |
| **Scalability** | ⚠️ Limited (raster blurring) | ✅ Unlimited (vector) |
| **Flexibility** | ❌ Style locked to source image | ✅ Customizable styling |
| **Data requirements** | ⚠️ Just one PNG | ✅ GADM + neighboring countries |
| **Wikipedia compliance** | ✅ Matches existing style | ✅ Follows 2012 SVG standard |

---

## Recommendation: **APPROACH 2 (Vector Reconstruction)**

**Rationale:**
1. **Accuracy over style matching**: Programmatically verifiable geometry eliminates the risk of silent errors (incorrect fills going unnoticed).
2. **Batch production**: A single script produces all 339 maps with guaranteed consistency. Approach 1 would require testing many raster operations.
3. **Maintenance**: One typo or style change in Approach 2 = one fix. In Approach 1, a georeference error = 339 bad maps.
4. **Wikipedia standards**: Wikipedia's own SVG locator maps (e.g., for countries/regions) follow this exact pattern.
5. **Future use**: SVGs are more useful for downstream workflows (web embedding, editing, format conversion).
6. **Effort**: Once the data pipeline is set up, looping over municipalities is negligible. The hard part is the same in both (INE↔GADM mapping, already done).

### Key Risks (Approach 2)
- **Neighboring country boundaries**: Need to acquire and align correctly. **Solution**: Use rnaturalearth's `ne_countries()` at 1:10m resolution, crop to Bolivia's neighbors, ensure same CRS.
- **Ocean/water rendering**: Need a coastline polygon or negative space. **Solution**: Use `ne_coastline()` or extract from GADM's national boundary.
- **INE↔GADM name mismatch**: Already solved in `ine_community_mapping.R`; reuse that lookup.

---

## Next Steps (if approved)
1. Acquire Natural Earth 1:10m country boundaries for AR, PE, BR, CL, PY
2. Prepare ocean/coastline polygon (Natural Earth or GADM-derived)
3. Draft single SVG template for one test municipality (e.g., La Paz)
4. Validate styling against 2012 color scheme
5. Create loop function: `generate_locator_map(mun_code)` → saves to `output/locator_maps/{mun_name}.svg`
6. Batch generate 339 maps
7. Sample QA: spot-check 10–20 random outputs for correctness
8. Push to Wikimedia Commons
