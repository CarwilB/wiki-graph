# Community Geography: INE–IGM Crosswalk

Bolivia community geography project. Maps INE community codes to IGM geographic point identifiers, enabling downstream linkage to locations and Wikidata entities.

## Key Data Files

| File | Description |
|------|-------------|
| `data/CLASIF_UB_GEOG_COMUNIDAD.xlsx` | INE community list with 19,418 communities. Columns: `Codigo` (11-digit INE code), `CIUDAD/COMUNIDAD`, `DEPARTAMENTO`, `PROVINCIA`, `MUNICIPIO`. |
| `data/localizacion_poblaciones_2016.json` | IGM GeoJSON point dataset: 23,891 settlement points. Columns: `id_unico`, `nombre_dep`, `nombre_c_1` (community name, uppercase), `tipo_area`, `tipo_pobla`. |
| `data/igm_localizacion_2016/poblaciones.shp` | Same IGM data as POINT shapefile (WGS84). |
| `data/etnicidad_tenencia/usca_final.shp` | USCA community-level MULTIPOLYGON boundaries (WGS84). 14,426 features. Column: `cod10dig` (10-digit INE code — pad with leading zero). Also has `eth_tie_fi`, `usc_agreg`. |
| `data/gadm41_BOL_3.gpkg` | GADM Bolivia level-3 (municipality) boundaries. Layer: `ADM_ADM_3`. Join via `NAME_1`/`NAME_3`. |
| **`data/crosswalk_ine_igm.rds`** | **Primary output.** INE `Codigo` ↔ IGM `id_unico`. Load with `readRDS("data/crosswalk_ine_igm.rds")`. |
| `data/crosswalk_ine_igm.csv` | Same as CSV. |

## INE Code Structure

11-digit string (character, with leading zero):
```
0 | DD | PP | MM | C | SSS
  dept  prov  mun  canton  seq
```

USCA uses 10-digit form (no leading zero). Pad with `paste0("0", cod10dig)` to match `Codigo`.

## Pipeline: `ine_community_mapping.R`

Steps:
1. Load INE Excel and IGM GeoJSON
2. Normalize names (strip non-ASCII, uppercase, collapse punctuation)
3. Join on department + name
4. Spatial join with GADM municipality boundaries
5. Name-proximity fallback for points outside GADM
6. Spatial join with USCA community polygons
7. Canton-split detection → `ambiguous_canton_split` + `canton_split_group`
8. Dispersed-settlement reclassification → `ambiguous_dispersed`
9. Export to RDS and CSV
10. Define `ine_match_status(codigo)` lookup function

## Crosswalk Schema

Columns: `Codigo`, `department`, `municipality`, `com_name`, `id_unico`, `match_status`, `n_geo`, `canton_split_group`

### match_status Values

| Status | Meaning | Count |
|--------|---------|-------|
| `unique` | Direct 1-to-1 name match within department | 13,998 |
| `unique_via_spatial` | Ambiguous name resolved by GADM municipality boundary | 4,077 |
| `unique_via_name` | Ambiguous name resolved by proximity to municipality centroid | 23 |
| `unique_via_usca` | Ambiguous name resolved by USCA polygon containment | 142 |
| `ambiguous_canton_split` | Same community under multiple canton codes (admin reorganisation) | 1,518 rows / 344 groups |
| `ambiguous_dispersed` | All IGM candidates are `tipo_area == "dis"` (dispersed); treat all as valid coordinate pool | 967 |
| `ambiguous` | Genuinely repeated name within same municipality; cannot be resolved automatically | 64 |
| `ambiguous_no_spatial` | Name recurs across municipalities; no spatial disambiguation succeeded | 170 |
| `unmatched` | No IGM point with matching name found | 5 |

### canton_split_group

For `ambiguous_canton_split` rows, this column holds the lowest `Codigo` among all sibling codes in the group. All siblings resolve to the same IGM candidate pool — this many-to-one mapping is expected and correct.

To build a deduplicated community key (one per physical place):
```r
community_key = coalesce(canton_split_group, Codigo)
```

## Canton Splits

344 groups of INE codes point to the same physical community because Bolivia's canton boundaries were reorganised after the 2001 census. 141 municipalities affected; Potosí has the most (36 municipalities). Within a group, the community sequence number (last 3 digits of `Codigo`) is usually preserved — only the canton digit changes.

## Key Relationships

- `ine_geog_2013$Codigo` ↔ `crosswalk$Codigo` (join key: INE → crosswalk)
- `crosswalk$id_unico` ↔ `igm_sf$id_unico` (join key: crosswalk → IGM point/coordinates)
- `usca_sf$cod10dig` ↔ `Codigo` after `paste0("0", cod10dig)` (INE code in USCA)
- GADM `NAME_1`/`NAME_3` → INE `department`/`municipality` via manual name crosswalk (many spelling differences)
