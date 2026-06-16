# Expand prov_id_lookup_table and muni_id_lookup_table with OEP 2026 names
#
# This script adds new columns to prov_id_lookup_table and muni_id_lookup_table
# that map province/municipality ID codes to their OEP (Órgano Electoral Plurinacional)
# 2026 official names. These may differ from CPV 2024 census names.
#
# Sources: OEP 2026 electoral administrative divisions

library(tidyverse)

muni_id_lookup_table <- muni_id_lookup_table |> select(-muni_oep2026)
prov_id_lookup_table <- prov_id_lookup_table |> select(-province_oep2026)

# Create mapping of id_prov to OEP 2026 province names
oep2026_prov_mapping <- tibble::tribble(
  ~id_prov, ~province_oep2026,
  "0211", "Sud Yungas",
  "0502", "Bustillo",
  "0505", "Chárcas",
  "0508", "Sud Chichas",
  "0509", "Nor Lipez",
  "0510", "Sud Lipez",
  "0604", "Avilés",
  "0606", "O' Connor",
  "0703", "José Miguel De Velasco",
  "0708", "Vallegrande",
  "0710", "Obispo Santistéban",
  "0802", "Vaca Díez"
)

# Add the new column to prov_id_lookup_table via left join
if (!"province_oep2026" %in% colnames(prov_id_lookup_table)) {
  prov_id_lookup_table <- prov_id_lookup_table |>
    left_join(oep2026_prov_mapping, by = "id_prov")
} else {
  warning("Column 'province_oep2026' already exists in prov_id_lookup_table. Skipping join.")
}

# Verification: show rows with OEP 2026 province names
if (interactive()) {
  cat("OEP 2026 province mappings:\n")
  prov_id_lookup_table |>
    filter(!is.na(province_oep2026)) |>
    select(id_prov, province_cpv2024, province_oep2026) |>
    print(n = Inf)
}

# Create mapping of id_muni to OEP 2026 municipality names
oep2026_muni_mapping <- tibble::tribble(
  ~id_muni, ~muni_oep2026,
  "010201", "Villa Azurduy",
  "010301", "Villa Zudañez",
  "010303", "Villa Mojocoya",
  "010304", "Villa Ricardo Mujia-Icla",
  "010404", "Villa Alcalá",
  "010901", "Camataqui - Villa Abecia",
  "011001", "Villa Vaca Guzmán - Muyupampa",
  "020306", "Waldo Ballivian",
  "030301", "Ayopaya (Villa De Independencia)",
  "030902", "Sipe Sipe",
  "031403", "San Benito (Villa José Quintín Mendoza)",
  "070401", "San Pedro De Buena Vista",
  "050901", "Colcha \"K\"",
  "051001", "San Pablo De Lípez",
  "051102", "Caiza \"D\"",
  "060401", "Uriondo (Concepción)",
  "070301", "San Ignacio De Velasco",
  "070302", "San Miguel De Velasco",
  "070902", "Pampa Grande",
  "071002", "General Agustín Saavedra"
)

# Add the new column to muni_id_lookup_table via left join
if (!"muni_oep2026" %in% colnames(muni_id_lookup_table)) {
  muni_id_lookup_table <- muni_id_lookup_table |>
    left_join(oep2026_muni_mapping, by = "id_muni")
} else {
  warning("Column 'muni_oep2026' already exists in muni_id_lookup_table. Skipping join.")
}

# Verification: show rows with OEP 2026 municipality names
if (interactive()) {
  cat("\nOEP 2026 municipality mappings:\n")
  muni_id_lookup_table |>
    filter(!is.na(muni_oep2026)) |>
    select(id_muni, muni_cpv2024, muni_oep2026, department) |>
    print(n = Inf)
}

# Fill in OEP 2026 columns with CPV 2024 values where OEP 2026 is NA
prov_id_lookup_table <- prov_id_lookup_table |>
  mutate(province_oep2026 = coalesce(province_oep2026, province_cpv2024))

muni_id_lookup_table <- muni_id_lookup_table |>
  mutate(muni_oep2026 = coalesce(muni_oep2026, muni_cpv2024))

saveRDS(prov_id_lookup_table, here::here("data", "prov_id_lookup_table.rds"))
saveRDS(muni_id_lookup_table, here::here("data", "muni_id_lookup_table.rds"))
