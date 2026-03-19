# Tibble representation of Cuadro 8.1 (p. 190)
# From Molina Barrios & Albó (2006), "Gama étnica y lingüística de la
# población boliviana."
#
# See data/molina-albo-2006.yml for provenance and handling notes.
# See data/datapackage.json for Frictionless Data package descriptor.

library(tibble)
library(dplyr)

# Spanish-language version: faithful to original column names
molina_albo_8_1_es <- tibble(
  categoria = c(7, 6, 5, 4, 3, 2, 1, 0, "Total"),
  pertenece_indigena = c("Sí", "Sí", "Sí", "Sí", "No", "No", "No", "No", NA),
  habla_su_lengua = c("Sí", "Sí", "Sí", "No", "Sí", "Sí", "Sí", "No", NA),
  aprendio_lengua_ninez = c("Sí", "Sí", "No", "No", "Sí", "Sí", "No", "No", NA),
  habla_castellano = c("No", "Sí", "Sí", "Sí", "No", "Sí", "Sí", "Sí", NA),
  codigo_abreviado = c("SSS-c", "SSS+c", "SSN+c", "SNN", "NSS-c", "NSS+c", "NSN", "NNN", NA),
  poblacion_0_14 = c(321054, 315169, 154854, 1041070, 15204, 22524, 24289, 841698, 2735862),
  poblacion_15_mas = c(565336, 1209636, 588989, 683224, 36935, 145119, 224538, 1450384, 4904161),
  poblacion_total = c(886390, 1524805, 743843, 1724294, 52139, 167643, 248827, 2292082, 7640023),
  porcentaje_15_mas = c(11.5, 24.7, 12.0, 13.9, 0.8, 3.0, 4.6, 29.6, 100.0)
)

# English-language version: analytic column names, Total row excluded
molina_albo_8_1_en <- molina_albo_8_1_es |>
  filter(categoria != "Total") |>
  transmute(
    cel = categoria,
    albo_q1 = (pertenece_indigena == "Sí"),
    albo_q2 = (habla_su_lengua == "Sí"),
    albo_q3 = (aprendio_lengua_ninez == "Sí"),
    albo_c = (habla_castellano == "Sí"),
    code = codigo_abreviado,
    pop_0_14 = poblacion_0_14,
    pop_15_plus = poblacion_15_mas,
    pop_total = poblacion_total,
    pct_15_plus = porcentaje_15_mas
  )

# Save to data/
saveRDS(molina_albo_8_1_es, "data/molina_albo_8_1_es.rds")
saveRDS(molina_albo_8_1_en, "data/molina_albo_8_1_en.rds")
write.csv(molina_albo_8_1_es, "data/molina_albo_8_1_es.csv", row.names = FALSE)
write.csv(molina_albo_8_1_en, "data/molina_albo_8_1_en.csv", row.names = FALSE)
