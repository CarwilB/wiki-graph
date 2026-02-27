# ICE Detention Facilities Data: Variable Changes Across Fiscal Years

*Analysis based on `facilities_data_list` (FY19–FY26), after header cleaning and column derivation in `import-ice-detention.qmd`.*

## Variables Common to All Years (30)

The following 30 variables are present in every year's table:

**Facility identity**
- `facility_name`, `facility_address`, `facility_city`, `facility_state`, `facility_zip`
- `facility_aor`, `facility_type_detailed`, `facility_male_female`
- `facility_average_length_of_stay_alos`

**ADP — Detainee Classification**
- `adp_detainee_classification_level_a`, `_b`, `_c`, `_d`

**ADP — Criminality**
- `adp_criminality_male_crim`, `adp_criminality_male_non_crim`
- `adp_criminality_female_crim`, `adp_criminality_female_non_crim`

**ADP — Threat Level**
- `adp_ice_threat_level_1`, `adp_ice_threat_level_2`, `adp_ice_threat_level_3`
- `adp_no_ice_threat_level`, `adp_mandatory`

**Inspections (core)**
- `inspections_guaranteed_minimum`, `inspections_last_inspection_type`

**Derived columns** (added by pipeline)
- `sum_classification_levels`, `sum_criminality_levels`, `sum_threat_levels`
- `share_non_crim`, `share_no_threat`, `facility_type_wiki`

---

## Variables NOT Present in All Years (19)

All 19 are in the `inspections_*` namespace. The data has three structural eras:

### Era 1: FY19–FY22 — Two inspections reported, combined

| Variable | FY19 | FY20 | FY21 | FY22 | FY23 | FY24 | FY25 | FY26 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `inspections_last_inspection_standard` | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| `inspections_last_inspection_rating_final` | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| `inspections_last_inspection_date` | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| `inspections_second_to_last_inspection_type` | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| `inspections_second_to_last_inspection_standard` | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| `inspections_second_to_last_inspection_rating` | ✓ | ✓ | ✓ | — | — | — | — | — |
| `inspections_second_to_last_inspection_date` | ✓ | ✓ | ✓ | ✓ | — | — | — | — |

### Era 2: FY23 only — Split by inspector body

In FY23, ICE reported two concurrent inspection programs separately. Both are nearly fully populated (115 of 121 rows each), and they represent genuinely different inspection events: dates differ for all 115 facilities, and ratings differ for 114 of 115.

| Variable | Inspector body | Rating scale |
|---|---|---|
| `inspections_odo_inspection_end_date` | ODO | — |
| `inspections_odo_last_inspection_standard` | ODO | — |
| `inspections_odo_final_rating` | ODO | Superior / Good / Acceptable/Adequate |
| `inspections_last_nakamoto_inspection_standard` | Nakamoto | — |
| `inspections_last_nakamoto_inspection_rating_final` | Nakamoto | Meets Standard / Acceptable |
| `inspections_last_nakamoto_inspection_date` | Nakamoto | — |
| `inspections_second_to_last_nakamoto_inspection_type` | Nakamoto | — |
| `inspections_second_to_last_nakamoto_inspection_standard` | Nakamoto | — |
| `inspections_second_to_last_nakamoto_inspection_date` | Nakamoto | — |

**ODO** (Office of Detention Oversight) uses a graduated grading scale. **Nakamoto** uses a standards-compliance scale. These are not interchangeable.

### Era 3: FY24–FY26 — Simplified, end-date added

| Variable | FY19 | FY20 | FY21 | FY22 | FY23 | FY24 | FY25 | FY26 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `inspections_last_inspection_end_date` | — | — | — | — | — | ✓ | ✓ | ✓ |
| `inspections_last_final_rating` | — | — | — | — | — | ✓ | ✓ | ✓ |
| `inspections_pending_inspection` | — | — | — | — | — | ✓ | ✓ | — |

---

## Likely Cross-Era Correspondences

| Concept | FY19–22 | FY23 | FY24–26 |
|---|---|---|---|
| Last inspection final rating | `inspections_last_inspection_rating_final` | `inspections_odo_final_rating` (closer match) | `inspections_last_final_rating` |
| Last inspection date | `inspections_last_inspection_date` | `inspections_odo_inspection_end_date` | `inspections_last_inspection_end_date` |
| Last inspection standard | `inspections_last_inspection_standard` | `inspections_odo_last_inspection_standard` | `inspections_last_inspection_standard` |

The ODO columns in FY23 are the better match to FY24–26, given the shared graded rating scale. Nakamoto columns use a different vocabulary and map less cleanly.
