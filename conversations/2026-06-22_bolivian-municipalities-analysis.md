# Chat: Bolivia Municipal Boundary Analysis & Wikipedia Generator Updates
**Date**: 2026-06-22  
**Project**: wiki-graph  

## Summary
Fixed accent encoding corruption in historical GeoJSON fondos layers (1985–2010), created comprehensive province evolution analysis, built a census population wikitable generator spanning four decades (1992–2024), and updated municipality infobox templates with geographic coordinate ranges extracted from shapefile bounding boxes.

## Key Accomplishments

### 1. Fixed Accent Encoding in Historical Boundary Data
**Problem**: All 87 accented characters (í, é, á, ó, ú, ñ) were corrupted to literal `?` in six historical GeoJSON files (1985–2010), causing duplicate entries like "Potos?" vs "Potosí".

**Solution**: 
- Parsed corrupted names from historical fondos using lookup tables (`muni_lookup`, `prov_id_lookup_table` from `cel_helpers.R`)
- Replaced names via left_join on municipality/province codes
- Result: All 327 municipalities in historical snapshots now have proper UTF-8 encoding

**Files modified**: `bolivia-muni-changes.qmd`

### 2. New Province Evolution Analysis Section
Added comprehensive analysis tracking creation of new provinces across 1985–present:
- **1985 → 1989**: 4 new provinces (Tiraque, Gen. José Manuel Pando, Mejillones, Enrique Baldivieso)
- **1989 → 1993**: 3 new provinces (Caranavi, Nor Carangas, Guarayos)
- **Since 1993**: No provincial creations (stable at 112 provinces)

**Files modified**: `bolivia-muni-changes.qmd`

### 3. Built Census Population Wikitable Generator
**Data sources integrated**:
- 2024, 2012, 2001: INE `population_municipality.rds` (current boundaries)
- 1992: Parsed all 327 census fichas (`../bolivia-data/censo_2001/Fichas Resumen por municipios/`) via PDF text extraction
- 2001 ficha cross-check: 284/327 exact matches with INE data; 42 mismatches align with subdivided municipalities

**1992 eligibility rule**: Province-count rule — 1992 values included only for municipalities in provinces where count unchanged between 2002 baseline (327 munis) and current map. Result: 306 municipalities eligible for 1992 column.

**Wikitable features**:
- Horizontal format: two rows (years / values)
- Adaptive columns: 4 columns (1992–2024) or 3 columns (2001–2024) depending on subdivision status
- Separate citations: 1992 references CENSO 1992 catalog; 2001/2012/2024 reference INE 2024 CPV download with URLs

**Files created**: `data/cpv2024/census_pop_historical.rds`  
**Files modified**: `bolivia-muni-generator-en.qmd`

### 4. Replaced Infobox Point Coordinates with Bounding Box Ranges
**Previous approach**: Single point coordinates from shapefile centroid  
**New approach**: Geographic coordinate ranges (lat/lon extents) from bounding boxes

**Format**: 
```
| Latitude = 19°21′ S to 18°54′ S
| Longitude = 65°55′ W to 65°31′ W
```

**Implementation**:
- Loaded adm3 shapefile from `../ultimate-consequences/maps/humdata.org_cod-ab-bol/bol_admin_boundaries.shp/bol_admin3.shp`
- Computed min/max lat/lon for all 339 municipalities (339 rows from shapefile)
- Created DMS formatter: decimal degrees → `d°m′ H` format
- Replaced `{{coord|...}}` template with separate `|latitude` and `|longitude` fields

**Files modified**: `bolivia-muni-infobox-en.qmd`

## Technical Notes

### Data Quality Issues
1. **Historical encoding**: GeoJSON files from GeoBolivia archives had character encoding lost at source; not recoverable via iconv. Solution: lookup-based replacement.
2. **Ficha parsing**: Small populations (<1000) lacked comma delimiters in PDFs; regex improved to handle both formats.
3. **2001 mismatches**: Minor methodology differences between ficha tabulations and INE retroactive allocations to current boundaries (expected for subdivided municipalities).

### Unchanged Province Identification
Provinces with same municipality count in both 2002 baseline (327-municipality fondos) and current layer:
- 103 unchanged provinces → 306 eligible municipalities for 1992 column
- Excluded: 37 municipalities in 9 changed provinces (new municipalities created post-2002)

### Coordinate Range Coverage
- Shapefile provides 339 bounding boxes (all current municipalities)
- No missing coordinates (unlike center_lat/center_lon which were sparse in xlsx)
- Ranges accurately reflect territorial extent; more informative than point centroids

## Files Modified/Created

| File | Change |
|------|--------|
| `bolivia-muni-changes.qmd` | Fixed accent encoding; added province evolution section |
| `bolivia-muni-generator-en.qmd` | Integrated census population wikitable (1992–2024) with dual citation refs |
| `bolivia-muni-infobox-en.qmd` | Replaced point coords with bounding box ranges from adm3 shapefile |
| `data/cpv2024/census_pop_historical.rds` | New: 340 municipalities × 5 columns (id_muni, pop_2001/2012/2024, pop_1992) |
| `.positai/chats/` | Archive mechanism for future chat sessions |

## Recommendations for Future Work

1. **Ficha parsing automation**: Consider batch processing other census years (1992, 2012) if available in similar PDF format
2. **Coordinate validation**: Cross-check bounding box ranges against published geographic extent descriptions in census documents
3. **Subdivision boundary documentation**: Maintain explicit mapping of which municipalities were subdivided and in which transition (e.g., Puna/Ckochas pair)
4. **Wikipedia consistency**: Ensure infobox latitude/longitude fields are recognized by Wikipedia's Infobox Settlement template (may need template parameter adjustment)

---
**Last updated**: 2026-06-22, 12:21 PM PDT
