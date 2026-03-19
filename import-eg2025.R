# Import and clean mesa-level results from the 2025 Bolivian general election.
# First round (17 August 2025) and second round (26 October 2025).
#
# See data/import-eg2025.yml for provenance and handling notes.

library(readr)
library(dplyr)

# --- Column rename map (OEP camelCase → snake_case) --------------------------

geo_renames <- c(
  mesa_code   = "CodigoMesa",
  mesa_number = "NumeroMesa",
  registered  = "InscritosHabilitados",
  country_code = "CodigoPais",
  country_name = "NombrePais",
  dept_code   = "CodigoDepartamento",
  dept_name   = "NombreDepartamento",
  prov_code   = "CodigoProvincia",
  prov_name   = "NombreProvincia",
  mun_code    = "CodigoSeccion",
  mun_name    = "NombreMunicipio",
  localidad_code = "CodigoLocalidad",
  localidad_name = "NombreLocalidad",
  recinto_code   = "CodigoRecinto",
  recinto_name   = "NombreRecinto"
)

vote_renames <- c(
  valid_votes = "VotoValido",
  blank_votes = "VotoBlanco",
  null_votes  = "TotalVotoNulo",
  votes_cast  = "VotoEmitido"
)

# --- First round: all three races --------------------------------------------

raw_1v <- read_csv(
  "data-raw/EG2025_20250824_235619_5976286028509320003.csv",
  show_col_types = FALSE
)

# Ballot slot → party mapping confirmed against the official OEP separata
# (30-08-2025-Separata-resultados-EG2025.pdf, page 4).
party_renames_1v <- c(
  AP         = "Voto1",
  LyP_ADN    = "Voto2",
  APB_SUMATE = "Voto3",
  # Voto4: vacant (0 votes nationally)
  LIBRE      = "Voto5",
  FP         = "Voto6",
  MAS_IPSP   = "Voto7",
  # Voto8: MORENA (0 votes nationally)
  UNIDAD     = "Voto9",
  PDC        = "Voto10"
)

pres_1v <- raw_1v |>
  filter(Descripcion == "PRESIDENTE") |>
  rename(!!!party_renames_1v) |>
  rename(!!!geo_renames) |>
  rename(!!!vote_renames) |>
  select(
    mesa_code, mesa_number, registered,
    country_code, country_name,
    dept_code, dept_name,
    prov_code, prov_name,
    mun_code, mun_name,
    localidad_code, localidad_name,
    recinto_code, recinto_name,
    AP, LyP_ADN, APB_SUMATE, LIBRE, FP, MAS_IPSP, UNIDAD, PDC,
    valid_votes, blank_votes, null_votes, votes_cast
  )

saveRDS(pres_1v, "data/eg2025_presidente_mesa.rds")
write_csv(pres_1v, "data/eg2025_presidente_mesa.csv")

# --- Second round: presidential only -----------------------------------------

raw_2v <- read_csv(
  "data-raw/EG2025_2v_20251026_235911_6311285959951043675.csv",
  show_col_types = FALSE
)

pres_2v <- raw_2v |>
  rename(!!!geo_renames) |>
  rename(!!!vote_renames) |>
  select(
    mesa_code, mesa_number, registered,
    country_code, country_name,
    dept_code, dept_name,
    prov_code, prov_name,
    mun_code, mun_name,
    localidad_code, localidad_name,
    recinto_code, recinto_name,
    PDC, LIBRE,
    valid_votes, blank_votes, null_votes, votes_cast
  )

saveRDS(pres_2v, "data/eg2025_2v_presidente_mesa.rds")
write_csv(pres_2v, "data/eg2025_2v_presidente_mesa.csv")
