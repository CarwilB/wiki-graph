# Household-Based Intergenerational Language Transmission Analysis

**Last updated:** March 2026  
**Relevant files:** `bolivia-censo-2024.qmd`, `analyze_child_parent_cel.R`

---

## Overview

This analysis measures **direct parental language transmission**: among children (aged 0–14) whose co-resident parent speaks Aymara or Quechua as a mother tongue, what fraction currently speak that language themselves?

This is distinct from the retention heatmaps elsewhere in `bolivia-censo-2024.qmd`, which track adults who learned an indigenous language as children and still use it daily. The household analysis captures active transmission _in progress_ — whether the language is being passed to the next generation right now.

---

## Census data structure

The CNPV 2024 person file (`Persona_CPV-2024.csv`) does not include explicit parent–child links. Household relationships are encoded via `p24_parentes` (relationship to head of household). The key codes used in this analysis are:

| Code | Meaning |
|------|---------|
| 1 | Head of household (`jefe/a`) |
| 2 | Spouse / partner (`cónyuge`) |
| 3 | Child of head (`hijo/a`) |
| 4 | Stepchild (`hijastro/a`) |
| 5 | Child-in-law (`nuera/yerno`) |
| 6 | Grandchild (`nieto/a`) |
| 9 | Parent of head (`padre/madre`) |

Dwellings are uniquely identified by the composite key `idep_iprov_imun_i00` (department + province + municipality + dwelling number).

Language data:

- `idioma_mat` — mother tongue (language learned in childhood; integer code)
- `p331_idiohab1_cod`, `p332_idiohab2_cod`, `p333_idiohab3_cod` — up to three languages currently spoken

Language codes relevant to this analysis: **2 = Aymara**, **27 = Quechua**, **6 = Castellano**.

---

## Two implementations

### 1. Main analysis (`bolivia-censo-2024.qmd`, chunks `transmission-setup` and `transmission-by-muni`)

This is the primary production pipeline. It uses a **simplified parent definition**: only household heads (code 1) and spouses (code 2) are treated as parents.

**Rationale:** The head/spouse pair covers the vast majority of parent–child configurations in Bolivian households, and keeps the logic unambiguous. More complex family structures (grandchildren raised by grandparents, etc.) are excluded rather than approximated.

**Pipeline:**

```
ds_persona (Arrow dataset, full 11.4M rows)
  │
  ├─ select minimal columns: idep, iprov, imun, i00, p26_edad,
  │         idioma_mat, p331/p332/p333, p24_parentes
  │
  ├─ collect() → households (in-memory)
  │     dwelling_key = paste(idep, iprov, imun, i00, sep = "_")
  │     muni_code    = sprintf("%02d%02d%02d", idep, iprov, imun)
  │
  ├─ parents_lang  ← filter p24_parentes ∈ {1, 2}, keep dwelling_key + idioma_mat
  │
  └─ children_all  ← filter p26_edad < 15, keep dwelling_key + muni_code + language cols
```

**Transmission metric (Aymara example):**

```
children_all
  inner_join parents_lang on dwelling_key          # keep only children with a linked parent
  filter parent_idioma == 2                        # restrict to Aymara-speaking parents
  mutate speaks_aymara = any of p331/p332/p333 == 2
  group_by muni_code
  summarise:
    n_parents_aymara       = n_distinct(dwelling_key)
    n_children_with_parent = n()
    n_children_speak_aymara = sum(speaks_aymara)
  transmission_rate = n_children_speak_aymara / n_children_with_parent
```

Quechua follows identically with `parent_idioma == 27`.

**"Speaks the language"** is defined broadly: the child has the language in _any_ of their three language slots (`p331`, `p332`, `p333`). This includes children who are bilingual (Aymara + Castellano). `NA` values in the language slots are treated as `FALSE`.

**Multiple parents per dwelling:** An `inner_join` (not a `semi_join`) is used, so a child with both a Aymara-speaking head and a Aymara-speaking spouse appears once per parent row. This inflates `n_children_with_parent` slightly relative to a count of unique children. The effect is small in practice (most households have at most one Aymara-speaking parent among head and spouse) and does not affect transmission rate calculations meaningfully.

### 2. Extended analysis (`analyze_child_parent_cel.R`)

`analyze_child_parent_cel()` is a more flexible function that:

- Accepts any geographic filter via `geo_codes` (fed through `read_census_geo()`)
- Handles three parent-linkage configurations beyond head/spouse:

| Child `p24` | Inferred parent `p24` | Scenario |
|---|---|---|
| 3 or 4 (child/stepchild of head) | 1 or 2 (head/spouse) | Standard nuclear household |
| 6 (grandchild of head) | 3, 4, or 5 (children/in-laws of head) | Child raised by grandparents; parents are gen-2 |
| 1 (child IS the head, rare) | 9 (parent of head) | Young head with co-resident parent |

- Can filter on age range or mother tongue rather than just 0–14
- Cross-tabulates **child CEL × max parent CEL** and produces a color-coded heatmap
- Returns a list: `$linked` (child–parent pairs), `$child_max_parent` (one row per child with max/min parent CEL), `$cross` (cross-tabulation), `$linkage_summary` (coverage by relationship type)

This function is used for case studies (e.g. El Alto: `analyze_child_parent_cel("020105")`) and national-level CEL transmission analysis, but the municipality-level aggregation in the main document uses the simpler production pipeline above.

---

## Output files

| File | Description |
|------|-------------|
| `data/aymara_transmission_by_muni.rds` | 327 municipalities. Columns: `muni_code`, `language`, `n_speakers_aymara`, `n_parents_aymara`, `n_children_with_parent`, `n_children_speak_aymara`, `transmission_rate`. |
| `data/quechua_transmission_by_muni.rds` | 340 municipalities. Same schema with `_quechua` suffix columns. |
| `data/aymara_transmission_by_albo.rds` | Aggregated by Albó-Romero municipality group (B–I). Includes median, mean, Q25, Q75 of `transmission_rate` across municipalities. |
| `data/quechua_transmission_by_albo.rds` | Same, for Quechua. |

---

## Albó-Romero group classification

Municipalities are classified into groups A–I using the `albo_classify()` function, based on thresholds applied to CEL percentages from `cel_geo`:

| Group | Conditions (all must hold) | Character |
|-------|---------------------------|-----------|
| A | CEL ≥5: ≥90%; CEL ≥4: ≥90%; CEL ≥2: ≥90% | Overwhelmingly indigenous-language communities |
| B | CEL ≥5: >67%; CEL ≥4: >80%; CEL ≥2: >90% | Strong indigenous identity and language |
| C | CEL ≥5: >50%; CEL ≥4: >67%; CEL ≥2: >67% | High indigenous identity |
| D | CEL ≥5: >33%; CEL ≥4: >50%; CEL ≥2: >67% | Medium-high identity |
| E | CEL ≥2: >75% | Majority indigenous-connected |
| F | CEL ≥2: >50% | Mixed, majority indigenous-connected |
| G | CEL ≥2: >33% | Mixed, minority indigenous-connected |
| H | CEL ≥2: >10% | Predominantly assimilated, some indigenous presence |
| I | CEL ≥2: ≤10% | Minimal indigenous identity |

`cel_geo` is filtered to `!is.na(municipality) & is.na(urban_rural)` before classification to use aggregate (non-urban/rural-stratified) rows only.

No municipality in the 2024 census data meets the Group A threshold. Group B is the highest-identity group in practice.

---

## Key national findings (CNPV 2024)

| Language | Children with speaking parent | Children who speak it | Transmission rate |
|----------|--:|--:|--:|
| Aymara | 425,655 | 123,894 | **29.1%** |
| Quechua | 915,114 | 365,976 | **40.0%** |

Even in the strongest-retention municipalities (Group B), roughly 3 in 5 Aymara children and roughly 1 in 2 Quechua children are not acquiring the language despite having a speaking parent. Transmission rates approach zero in Groups G–I for Aymara and are under 20% for Quechua.

---

## Design decisions and caveats

**Parent definition (head/spouse only).** The main pipeline restricts parents to `p24_parentes ∈ {1, 2}`. This excludes plausible parents in households where neither parent is the head (e.g. extended households where the grandparent is head). The extended `analyze_child_parent_cel()` function handles these cases but is used only for exploratory case studies, not the municipality-level aggregation.

**"Speaks" vs. "mother tongue".** The outcome is whether the child _currently speaks_ the language (any of `p331`/`p332`/`p333`), not whether they report it as their mother tongue (`idioma_mat`). This is the more relevant measure for transmission: it captures children who are bilingual as well as those who learned the language but may not claim it as primary.

**Parent language is mother tongue, not current speech.** The _parent_ is identified by their mother tongue (`idioma_mat`), not current language use. This correctly captures parents who _are_ speakers — not parents who merely have indigenous heritage but no longer speak the language.

**Multiple children per dwelling.** Where a dwelling has multiple children aged 0–14 and a single Aymara-speaking parent, each child appears as a separate row and contributes independently to the transmission count. This is the desired behavior.

**Minimum parent threshold for choropleths.** Transmission rates are only mapped where `n_parents_aymara ≥ 100`. Below this threshold, small-number instability makes rates unreliable.

**Age range (0–14).** Chosen to match the standard definition of children in the census. It includes infants who would not yet be expected to speak any language. A stricter age floor (e.g. 3–14) would likely raise transmission rates slightly.
