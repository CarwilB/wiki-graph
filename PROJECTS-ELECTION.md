# Bolivia 2025 General Election (EG2025)

August 24, 2025 general election results. Raw data from OEP (Órgano Electoral Plurinacional) computo portal.

## Key Files

| File | Description |
|------|-------------|
| `data-raw/EG2025_20250824_235619_5976286028509320003.csv` | Raw mesa-level results. 69,279 mesas × 38 columns. Downloaded 2025-08-24. Includes all three races: Presidente, Diputado Uninominal (63 circunscripciones), Diputado Circunscripción Especial (7 indigenous seats). |
| `data/eg2025_presidente_mesa.rds` | **Cleaned presidential results.** 35,253 mesas × 27 columns. Party columns renamed. Primary deliverable. |
| `data/eg2025_presidente_mesa.csv` | Same as CSV for interoperability. |
| `data/import-eg2025.yml` | YAML sidecar: provenance, ballot slot mapping, summary statistics. |
| `import-eg2025.R` | Import script. |
| `eg2025-resultados.qmd` | Quarto document: dept/prov/mun aggregations and choropleths. |

## Presidential Results: Ballot Slot → Party Mapping

| Slot | Party | Votes | % |
|------|-------|------:|---:|
| Voto1 | AP | 456,002 | 8.51 |
| Voto2 | LyP ADN | 77,576 | 1.45 |
| Voto3 | APB SÚMATE | 361,640 | 6.75 |
| Voto4 | *(vacant)* | 0 | 0.00 |
| Voto5 | LIBRE | 1,430,176 | 26.70 |
| Voto6 | FP | 89,253 | 1.67 |
| Voto7 | MAS-IPSP | 169,887 | 3.17 |
| Voto8 | MORENA *(0 votes)* | 0 | 0.00 |
| Voto9 | UNIDAD | 1,054,568 | 19.69 |
| Voto10 | PDC | 1,717,432 | 32.06 |
| Voto11 | *(especial race only)* | 412 | — |
| Voto12 | *(especial race only)* | 2,266 | — |

Voto4 and Voto8 (MORENA) are zero across all races (disqualified/withdrawn).

## Geographic Codes

Data uses OEP internal codes, **not INE codes**. Department codes 1–9 match INE ordering. Province (`CodigoProvincia`) and municipality (`CodigoSeccion`) are sequential within parent. Join to GADM spatial data by name matching against `data/gadm41_BOL_3.gpkg`. ~13 municipalities (TIOC/AIOC indigenous autonomies created post-GADM) will not match.

## Key Statistics

- **Turnout**: 86.95% (6,900,418 of 7,936,515 registered)
- **Null votes**: 19.87% of votes cast (1,371,049). Cochabamba exceptionally high (33.3%).
- **Winner**: PDC (32.06%) — dominates altiplano (La Paz 47%, Oruro 48%, Potosí 43%)
- **LIBRE** (26.70%) — strongest in Santa Cruz (38%) and lowlands
- **UNIDAD** (19.69%) — strongest in Beni (38%) and Tarija (38%)
- **MAS-IPSP** (3.17%) — historic low for ruling party
