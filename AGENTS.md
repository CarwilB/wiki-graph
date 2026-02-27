# wiki-graph project memory

## Project overview

Bolivia community geography project. The goal is to map INE community codes to
IGM geographic point identifiers, enabling downstream linkage to locations
(coordinates) and Wikidata entities.

## Key data files

| File | Description |
|------|-------------|
| `data/CLASIF_UB_GEOG_COMUNIDAD.xlsx` | INE community list with 19,418 communities. Columns include `Codigo` (11-digit INE code), `CIUDAD/COMUNIDAD`, `DEPARTAMENTO`, `PROVINCIA`, `MUNICIPIO`, and numeric segment columns `DEP`, `PRO`, `MUN`. |
| `data/localizacion_poblaciones_2016.json` | IGM GeoJSON point dataset: 23,891 settlement points. Key columns: `id_unico` (unique IGM identifier), `nombre_dep` (department), `nombre_c_1` (community name, uppercase), `tipo_area`, `tipo_pobla`. |
| `data/igm_localizacion_2016/poblaciones.shp` | Same IGM data as shapefile (POINT geometry, WGS84). |
| `data/etnicidad_tenencia/usca_final.shp` | USCA community-level multipolygon boundaries (MULTIPOLYGON, WGS84). 14,426 features. Key column: `cod10dig` (10-digit INE code — pad with leading zero to match `Codigo`). Also has `eth_tie_fi` and `usc_agreg` (ethnicity/land tenure classifications). |
| `data/etnicidad_tenencia/usca_final.dbf` | Attribute table of the above (no geometry). |
| `data/igm_localizacion_2016/poblaciones.dbf` | Attribute table of the IGM shapefile. No INE codes — department and settlement name only. |
| `data/gadm41_BOL_3.gpkg` | GADM Bolivia level-3 (municipality) boundaries. Layer: `ADM_ADM_3`. Columns: `NAME_1` (department), `NAME_2` (province), `NAME_3` (municipality). |
| `data/crosswalk_ine_igm.rds` | **Primary output.** Crosswalk from INE `Codigo` to IGM `id_unico`. Load with `readRDS("data/crosswalk_ine_igm.rds")`. |
| `data/crosswalk_ine_igm.csv` | Same crosswalk as CSV for interoperability. |

## INE code structure

11-digit string (stored as character, with leading zero):
```
0 | DD | PP | MM | C | SSS
  dept  prov  mun  canton  seq
```
- Positions 2–3: department (2 digits)
- Positions 4–5: province (2 digits)
- Positions 6–7: municipality (2 digits)
- Position 8: canton (1 digit)
- Positions 9–11: community sequence number (3 digits)

The USCA file uses a 10-digit form (no leading zero). Pad with `paste0("0", cod10dig)` to match `Codigo`.

## Crosswalk schema

Columns: `Codigo`, `department`, `municipality`, `com_name`, `id_unico`, `match_status`, `n_geo`, `canton_split_group`

### match_status values

| Status | Meaning |
|--------|---------|
| `unique` | Direct 1-to-1 name match within department (13,998) |
| `unique_via_spatial` | Ambiguous name resolved by GADM municipality boundary (4,077) |
| `unique_via_name` | Ambiguous name resolved by proximity to municipality centroid (23) |
| `unique_via_usca` | Ambiguous name resolved by USCA community polygon containment (142) |
| `ambiguous_canton_split` | Same community listed under multiple canton codes due to administrative reorganisation; all sibling codes share the same IGM candidate pool (1,518 rows / 344 groups) |
| `ambiguous_dispersed` | All IGM candidates are `tipo_area == "dis"` (dispersed settlement); the IGM dataset recorded multiple points for the same dispersed community. Treat all candidates as a valid coordinate pool rather than selecting one (967) |
| `ambiguous` | Genuinely repeated name within same municipality; correct point cannot be determined automatically (64) |
| `ambiguous_no_spatial` | Name recurs across municipalities; no spatial disambiguation succeeded (170) |
| `unmatched` | No IGM point with matching name found (5) |

### canton_split_group

For `ambiguous_canton_split` rows, this column holds the lowest `Codigo` among all sibling codes in the group. All siblings resolve to the same IGM candidate pool — this many-to-one mapping is expected and correct.

To build a deduplicated community key (one per physical place):
```r
community_key = coalesce(canton_split_group, Codigo)
```

## Primary pipeline script

`ine_community_mapping.R` — runs the full pipeline from raw data to crosswalk:
1. Load INE Excel and IGM GeoJSON
2. Normalize names (strip non-ASCII, uppercase, collapse punctuation)
3. Join on department + name → `crosswalk_raw`
4. Spatial join with GADM municipality boundaries → resolves most ambiguous cases
5. Name-proximity fallback for points outside GADM polygons
6. Spatial join with USCA community polygons → `unique_via_usca`
7. Canton-split detection → `ambiguous_canton_split` + `canton_split_group`
8. Dispersed-settlement reclassification → `ambiguous_dispersed` (all candidates `tipo_area == "dis"`)
9. Export to `data/crosswalk_ine_igm.rds` and `.csv`
10. Defines `ine_match_status(codigo)` lookup function (tolerates 10- or 11-digit codes)

## Key relationships

- `ine_geog_2013$Codigo` ↔ `crosswalk$Codigo` (join key: INE → crosswalk)
- `crosswalk$id_unico` ↔ `igm_sf$id_unico` (join key: crosswalk → IGM point/coordinates)
- `usca_sf$cod10dig` ↔ `Codigo` after `paste0("0", cod10dig)` (INE code in USCA)
- GADM `NAME_1`/`NAME_3` → INE `department`/`municipality` via manual name crosswalk in script (many spelling differences)

## Canton splits

344 groups of INE codes point to the same physical community because Bolivia's canton boundaries were reorganised after the 2001 census. 141 municipalities affected; Potosí has the most (36 municipalities). Within a group, the community sequence number (last 3 digits of `Codigo`) is usually preserved — only the canton digit changes.
