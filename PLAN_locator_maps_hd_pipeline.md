# HD Locator Maps — Full Pipeline Plan
**Script**: `generate_locator_maps_workbench_hd.R`  
**Source data**: OCHA COD-AB-BOL (`../ultimate-consequences/maps/humdata.org_cod-ab-bol/bol_admin_boundaries.shp/`)  
**Last test run**: May 2026 — 9 test maps generated OK

---

## What changed from the original workbench

| | `generate_locator_maps_workbench.R` | `generate_locator_maps_workbench_hd.R` |
|---|---|---|
| Boundary source | GADM 4.1 (`gadm41_BOL_3.gpkg`) | OCHA COD-AB-BOL shapefiles |
| Municipality count | 340 (incl. "Lago Titicaca" row) | 339 (no Lago Titicaca row) |
| ADM3 column | `NAME_3` | `adm3_name` → renamed to `NAME_3` at load |
| ADM2 column | `NAME_2` | `adm2_name` → renamed to `NAME_2` at load |
| ADM1 column | `NAME_1` | `adm1_name` → renamed to `NAME_1` at load |
| Titicaca polygon | GADM municipality polygon | Empty (0-row) — lake drawn from NE layer |
| Output dir | `output/locator_maps/muni-maps-final` | `output/locator_maps/workbench_hd` (test) |

All downstream code (§5–§7) is unchanged because column renaming happens at load time.

---

## Steps to run the full 339-municipality batch

### 1. Evaluate the 9 test maps
Open `output/locator_maps/workbench_hd/` and check:
- Internal borders (municipality and province) look crisp
- Titicaca is correctly filled blue (from NE layer — no OCHA polygon)
- No gap slivers between Bolivia and neighbours
- Target municipality highlight colour (`#C12838`) renders correctly
- File sizes: the test run produced ~3.8 MB per SVG; if that is too large for
  Commons upload, lower `simp_municipalities` (e.g. `0.03`) and re-run the 9
  test maps before batch

### 2. Tune simplification if needed
In `generate_locator_maps_workbench_hd.R`, edit `params` in §1:
```r
simp_municipalities  = 0.05,   # ← lower for smaller files
simp_bolivia_outline = 0.05,
simp_neighbors       = 0.03,
```
Re-run `source("generate_locator_maps_workbench_hd.R")` with `run_all <- FALSE`
to get fresh test maps before committing to the full batch.

### 3. Set the output directory for the final batch
Change `output_dir` in `params` (§1) from the test folder to the production
folder, e.g.:
```r
output_dir = "output/locator_maps/muni-maps-hd",
```

### 4. Flip to batch mode and run
```r
run_all <- TRUE   # line ~77
```
Then `source("generate_locator_maps_workbench_hd.R")`.

Expected run time: ~3–5 min for 339 municipalities (scales with simplification
level and hardware).  A `batch_log.csv` is written to `output_dir` when done.

### 5. Inspect the batch log
```r
log <- read.csv("output/locator_maps/muni-maps-hd/batch_log.csv")
summary(log$size_kb)
# Any nulls mean a municipality lookup failed:
log[is.na(log$size_kb), ]
```

### 6. Upload to Wikimedia Commons
Use the existing Commons upload pipeline (`upload_to_commons.R`).  Point
`out_dir` / `upload_df` at the new `muni-maps-hd/` folder.  Verify a handful
manually before bulk-uploading.

---

## Notes / known issues

- **Lago Titicaca**: OCHA does not include a Lago Titicaca municipality polygon.
  The lake is rendered from Natural Earth (`ne_10m_lakes`) which covers the
  entire lake including Peruvian waters — visually correct.
- **Duplicate municipality names**: OCHA has 9 duplicate `adm3_name` values
  (`San Pedro ×3`, `Santa Rosa ×3`, `El Puente`, `Entre Ríos`, `San Ignacio`,
  `San Javier`, `San Lorenzo`, `San Ramón`, `Totora` each ×2).
  The script already disambiguates file names using `muni_id_lookup_table`
  (`dupe_anexo_names`), but verify those are correctly disambiguated in the
  batch log.
- **SVG file sizes**: OCHA boundaries are somewhat more detailed than GADM at
  the same simplification level.  If SVGs exceed ~2 MB each and Commons upload
  is slow, reduce `simp_municipalities` from `0.05` to `0.03`.
