# Import LAPOP AmericasBarometer Bolivia 2023
# Source: http://datasets.americasbarometer.org/database/index.php?freeUser=true
#
# See data/lapop-bol-2023.yml for provenance and handling notes.

library(haven)
library(dplyr)
library(forcats)

# --- Load raw Stata file ---
lapop_raw <- read_dta("data-raw/BOL_2023_LAPOP_AmericasBarometer_v1.0_w.dta")

# --- Clean labelled columns ---
# Collapse tagged NAs (No sabe, No responde, Inaplicable) to plain NA
lapop <- lapop_raw |>
  zap_missing()

# --- Create factor versions of key categorical variables ---
lapop <- lapop |>
  mutate(
    genero_f        = as_factor(q1tc_r),
    ur_f            = as_factor(ur),
    region_f        = as_factor(estratopri),
    mun_size_f      = as_factor(estratosec),
    etid_f          = as_factor(etid),
    indig_id_f      = as_factor(boletidnew),
    indig_group_f   = as_factor(boletidnewb),
    leng_materna_f  = as_factor(leng1),
    leng_padres_f   = as_factor(leng4),
    educacion_f     = as_factor(edre),
    sit_laboral_f   = as_factor(ocup4a),
    estado_civil_f  = as_factor(q11n)
  )

# --- Strip haven metadata from numeric columns ---
# Keeps factor columns intact, removes labelled class from the rest
lapop <- lapop |>
  mutate(across(where(is.labelled), zap_labels))

# --- Save ---
saveRDS(lapop, "data/lapop_bol_2023.rds")
write.csv(lapop, "data/lapop_bol_2023.csv", row.names = FALSE)

cat("Saved: data/lapop_bol_2023.rds and .csv\n")
cat("Dimensions:", nrow(lapop), "×", ncol(lapop), "\n")
