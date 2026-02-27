library(readr)
library(httr)
library(jsonlite)
library(tidyverse)


census_table_2012 <- readRDS("data/census_table_municipios_2012u.rds")
muni_lookup_ine <- census_table_2012 %>%
  select(cod.mun, municipality, province, department, cod.dep)


prov_lookup_ine <- census_table_2012 %>%
#  mutate(cod.prov = str_sub(cod.mun, 1, 4)) %>%
  select(cod.prov, province, department) %>% distinct()

dep_lookup_ine <- census_table_2012 %>%
  mutate(cod.dep = str_sub(cod.mun, 1, 2)) %>%
  select(cod.dep, department) %>% distinct()

dep_lookup_ine <- dep_lookup_ine %>%
  mutate(label_en = paste(department, "Department"))

departments_wd <- get_wikidata_instances("Q250050", languages = c("en", "es"))

departments <- departments_wd %>%
  left_join(select(dep_lookup_ine, label_en, cod.dep))

departments <- departments %>%
  mutate(department = str_replace(label_en, " Department", ""))

departments_1 <- departments %>%
  rowwise() %>%
  mutate(quick_statement=create_quick_statement(qid, "P14142", cod.dep,
                                                reference_qid = "Q138354774")) %>%
  ungroup()


add_quick_statement_column <- function(dataframe, qid_col, property, value_col, ...){
  dataframe %>%
    rowwise() %>%
    mutate(quick_statement = create_quick_statement({{ qid_col }}, property, {{ value_col }}, ...)) %>%
    ungroup()
}

departments_2 <- departments %>% add_quick_statement_column(qid, "P14142", cod.dep,
                                          reference_qid = "Q138354774")


# I made the Qid for an online source that verifies the information:
#  Instituto Nacional de Estadística. “Clasificación de Ubicación
#  Geográfica a Nivel Comunidad.” Instituto Nacional de Estadística,
#  January 1, 2013. https://anda.ine.gob.bo/index.php/catalog/71/download/716.

departments[,c(1,2,10)] # view the statements
writeLines(departments$quick_statement)

# Now let's do this for provinces and municipalities.

# Departments are common knowledge, but we'll want to actually import
# that source file from here on.
ine_geog_2013 <- readxl::read_excel("data/CLASIF_UB_GEOG_COMUNIDAD.xlsx")
ine_geog_2013 <- ine_geog_2013 %>%
  rename(
    department = DEPARTAMENTO,
    province = PROVINCIA,
    municipality = MUNICIPIO) %>%
  mutate(cod.prov = paste0(DEP, PRO),
         cod.mun = paste0(DEP, PRO, MUN),
         cod.com = Codigo) %>%
  rename(cod.dep = DEP)

ine_geog_provinces <- ine_geog_2013 %>%
  select(cod.prov, province, department) %>%
  distinct()
nrow(ine_geog_provinces)

ine_geog_municipalities <- ine_geog_2013 %>%
  select(cod.mun, municipality, province, department) %>%
  distinct()
nrow(ine_geog_municipalities)

# We need Q codes for the provinces and municipalities.

provinces <- get_wikidata_instances("Q1062593", c("P131", "P17"), c("located_in", "country"))
  # get department names from the table we've already imported
provinces <- provinces %>%
   left_join(select(departments, qid, department), by=join_by("located_in"=="qid")) %>%
   relocate(department, .after="located_in")

# visual inspection shows that not all have "Province" in label_en, but
# it's just 6 that don't.
provinces_without_suffix <- provinces %>%
  filter(!str_detect(label_en, "Province") | str_detect(label_en, "Cercado"))
# next step is to relabel these, but create_quick_statements has
# broken logic for labels.
provinces_without_suffix <- provinces_without_suffix %>%
  add_quick_statement_column(qid, property="L", value=str_c(.data$label_en, " Province (", department, ")"), lang="en")
writeLines(provinces_without_suffix$quick_statement)

# We only had to run that once. Let's go back and check our work:
provinces <- get_wikidata_instances("Q1062593", c("P131", "P17"), c("located_in", "country"))
# get department names from the table we've already imported
provinces <- provinces %>%
  left_join(select(departments, qid, department), by=join_by("located_in"=="qid")) %>%
  relocate(department, .after="located_in")
# Note that if we recreate provinces_without_suffix, it now has zero items.
provinces <- provinces |>
  mutate(province = str_extract(label_en, "^(.+)\\s+Province", group = 1))

provinces_ine <- provinces %>% left_join(ine_geog_provinces, by=c("province", "department"))

# Annoyingly there are 46 non-matches, for lots of detailed reasons
# Here are the nonmatches:
provinces_ine_unmatched <- provinces_ine %>% filter(is.na(cod.prov)) %>%  arrange(department, province) %>% select(2, 7) %>% print(n=100)
ine_geog_provinces_unmatched <- ine_geog_provinces %>% filter(!(cod.prov %in% provinces_ine$cod.prov )) %>% arrange(department, province) %>% print(n=100)

# can clean up a bit with str_equivalent, and remaining ones are mainly full name vs last name
# issues. Finally, some spelling variants.

# Claude Sonnet produces a match table
province_matches <- matches
province_matches <- right_join(select(provinces, qid, label_en), province_matches) %>%
  mutate(province_alias_en = str_c(province, " Province"))
province_matches <- province_matches %>% add_quick_statement_column(qid, "A", province_alias_en, lang="en")
writeLines(province_matches$quick_statement)

# saveRDS(province_matches, "data/province-matches.RDS")
province_matches <- readRDS("data/province-matches.RDS")

# Next step, complete this matching and then create quick statements for all provinces.

provinces_ine <- provinces |>
  left_join(province_matches |> select(label_en, ine_province = province), by = "label_en") |>
  mutate(
    province_join   = coalesce(ine_province, province),
    department_join = str_replace(department, "Potosí", "Potosi")
  ) |>
  left_join(ine_geog_provinces, by = c("province_join" = "province", "department_join" = "department")) |>
  select(-ine_province, -province_join, -department_join)

saveRDS(provinces_ine, "data/provinces_ine.RDS")

cat("Total rows:", nrow(provinces_ine), "\n")
cat("Missing cod.prov:", sum(is.na(provinces_ine$cod.prov)), "\n")

provinces_ine <- provinces_ine %>% add_quick_statement_column(qid, "P14142", cod.prov,
                                               reference_qid = "Q138354774")
writeLines(provinces_ine$quick_statement)

# Municipalities
municipalities_wd <- get_wikidata_instances("Q1062710",  c("P131", "P17"), c("located_in", "country"))
# finds 351 instances, but there are 339 municipalities, so that could be a problem

# much editing…
municipalities_wd_original <- municipalities_wd

# cleanup has resolved many city/municipality splits (except Oruro where they
# literally overlap)
municipalities_wd <- get_wikidata_instances("Q1062710",  c("P131", "P17"), c("located_in", "country"))
municipalities_wd_exp <- expand_located_in_pd(municipalities_wd)

municipalities_wd |> filter(lengths(instance_of) > 1)
municipalities_wd_exp |> select(1,2, starts_with("loc"))


ine_geog_municipalities <- ine_geog_municipalities %>%
  add_row(tibble_row("cod.mun" = "050405",
                  "municipality"= "San Pedro de Macha",
                  "province"= "Chayanta",
                  "department"= "Potosi")) %>% arrange(cod.mun)


# ===========================================================================
# Match municipalities_wd_exp to ine_geog_municipalities to get INE codes
# ===========================================================================
# Strategy:
#   Round 1: Direct match on label_es + department (clean WD department names first)
#   Round 2: Cleaned label_es/label_en (strip "Municipio de", " Municipality" etc.) + department
#   Round 3: Manual matches for names that differ substantially between WD and INE
#   Then: De-duplicate cases where two WD items map to the same INE municipality


# --- Enrich WD with department -----------------------------------------------
# Look up department via loc_prov_qid joined to provinces$qid. This avoids
# all province name string matching. provinces$department uses "Potosí";
# normalize to "Potosi" to match INE.
prov_to_dept <- provinces |>
  select(prov_qid = qid, dep_from_prov = department) |>
  mutate(dep_from_prov = str_replace(dep_from_prov, "Potosí", "Potosi"))

wd_clean <- municipalities_wd_exp |>
  mutate(
    dep_direct = loc_dep_es |>
      str_remove("^Departamento de(l )?\\s*") |>
      str_replace("Potosí", "Potosi")
  ) |>
  left_join(prov_to_dept, by = c("loc_prov_qid" = "prov_qid")) |>
  mutate(dept_final = coalesce(dep_direct, dep_from_prov))

# Four items have no province QID and no department — assign manually.
wd_clean <- wd_clean |>
  mutate(dept_final = case_when(
    qid == "Q1108189" ~ "Santa Cruz",  # Yapacani (Ichilo province)
    qid == "Q1531921" ~ "Santa Cruz",  # Montero (Obispo Santiestevan province)
    qid == "Q1108256" ~ "Santa Cruz",  # Puerto Quijarro (German Busch province)
    qid == "Q15835839" ~ "Potosi",     # Villazón (Modesto Omiste province)
    .default = dept_final
  ))


# --- Round 1: Direct match on label_es + department --------------------------
match_r1 <- wd_clean |>
  inner_join(ine_geog_municipalities,
             by = c("label_es" = "municipality", "dept_final" = "department")) |>
  select(qid, cod.mun)


# --- Round 2: Cleaned names + department -------------------------------------
# Strip common prefixes/suffixes that differ between WD and INE
wd_clean <- wd_clean |>
  mutate(
    name_es_clean = label_es |>
      str_remove("^Municipio( de)?\\s+") |>
      str_remove("\\s*\\(municipio\\)$"),
    name_en_clean = label_en |>
      str_remove("\\s+[Mm]unicipality$") |>
      str_remove("^Municipio( de)?\\s+"),
    match_name = coalesce(name_es_clean, name_en_clean)
  )

unmatched_r1 <- wd_clean |> filter(!qid %in% match_r1$qid)

match_r2 <- unmatched_r1 |>
  inner_join(ine_geog_municipalities,
             by = c("match_name" = "municipality", "dept_final" = "department")) |>
  select(qid, cod.mun)


# --- Round 3: Manual matches -------------------------------------------------
# Names that diverge enough between WD and INE to require explicit pairing.
match_manual <- tribble(
  ~qid,           ~cod.mun,
  # Fuzzy name differences (accents, word order, abbreviations)
  "Q685208",    "080401",  # Santa Ana del Yacuma    -> Santa Ana de Yacuma
  "Q721682",    "071501",  # Ascencion de Guarayos   -> Ascension de Guarayos
  "Q647771",    "040503",  # Cruz De Machacamarca    -> Cruz de Machacamarca
  "Q775675",    "050204",  # Chuquihuta              -> Chuquiuta
  "Q1477898",   "051001",  # San Pablo de Lipez      -> San Pablo de Lipez
  "Q1108206",   "070603",  # Colpa Belgica           -> Colpa Belgica
  "Q939128",    "030702",  # Santivannez             -> Santivannez
  "Q1107968",   "071201",  # San Matias              -> San Matias
  "Q15121209",  "060601",  # Entre Rios              -> Entre Rios (Tarija)
  "Q647899",    "040801",  # Salinas de Garci Mendoza -> Salinas de Garcia Mendoza
  "Q637609",    "051102",  # Caiza D                 -> Caiza "D"
  "Q920327",    "010602",  # Yamparaez               -> Yamparaez
  "Q1108189",   "070403",  # Yapacani                -> Yapacani
  "Q328298",    "060303",  # Villa Montes            -> Villamontes
  "Q647918",    "040504",  # Yunguyo del Litoral     -> Yunguyo de Litoral
  "Q647829",    "040302",  # Choquecota              -> Choque Cota
  "Q328303",    "060301",  # Yacuiba                 -> Yacuiba
  "Q1108166",   "070805",  # Pucara                  -> Pucara
  "Q1108279",   "070502",  # Pailon                  -> Pailon
  "Q542442",    "070802",  # El Trigal               -> Trigal
  "Q624520",    "050502",  # Torotoro                -> Toro Toro
  "Q1521101",   "030902",  # Sipe Sipe               -> Sipesipe
  "Q1814929",   "020301",  # Coro Coro               -> Corocoro
  "Q647818",    "040903",  # Uru Chipaya             -> Chipaya
  "Q1108286",   "070303",  # San Rafael de Velasco   -> San Rafael
  "Q1953160",   "080501",  # San Ignacio de Moxos    -> San Ignacio
  "Q598031",    "070702",  # Charagua Pueblo         -> Charagua
  "Q624522",    "050501",  # San Pedro de Buena Vista -> S.P. De Buena Vista
  "Q198363",    "090401",  # Santa Rosa del Abuna    -> Santa Rosa (Pando)
  "Q2303100",   "041401",  # Santiago de Huari       -> Huari
  "Q198357",    "090502",  # Villa Nueva             -> Villa Nueva (Loma Alta)
  "Q289565",    "020403",  # Puerto Carabuco         -> Pto. Carabuco
  "Q993949",    "071002",  # General Saavedra        -> Gral. Saavedra
  "Q1108271",   "071403",  # El Carmen Rivero Torrez -> Carmen Rivero Torrez
  "Q198392",    "090301",  # Puerto Gonzalo Moreno   -> Gonzalo Moreno
  "Q647778",    "041201",  # Andamarca               -> Santiago de Andamarca
  "Q647890",    "040202",  # Santuario de Quillacas  -> Quillacas
  "Q681960",    "020803",  # Tiwanaku                -> Tiahuanacu
  "Q684618",    "040104",  # Soracachi               -> Pari - Paria - Soracachi
  "Q1034638",   "030701",  # Capinota (Villa Capinota in WD) -> Capinota
  "Q1142199",   "010901",  # Camataqui               -> Villa Abecia
  "Q1477919",   "050701",  # Sacaca                  -> Villa de Sacaca
  "Q1485787",   "030301",  # Ayopaya (Apopaya in WD) -> Independencia
  "Q1544480",   "021006",  # Licoma Pampa            -> Villa Libertad Licoma
  "Q1544495",   "021601",  # General Juan Jose Perez -> Charazani
  "Q1544586",   "021801",  # Curahuara               -> San Pedro Cuarahuara
  "Q121543",    "011001",  # Villa Vaca Guzman       -> Muyupampa
  "Q198394",    "090202",  # San Pablo (Pando)       -> San Pedro (Manuripi)
  # Items identified via Wikipedia article text (no WD name labels)
  "Q647811",    "040701",  # Huanuni
  "Q1107950",   "070704",  # Cuevo
  "Q1108295",   "071401",  # Puerto Suarez
  "Q1142006",   "010401",  # Padilla
  "Q1892759",   "041101",  # Eucaliptus
  "Q1952875",   "031501",  # Bolivar (Cochabamba)
  "Q1953215",   "060101",  # Tarija
  "Q1953261",   "070201",  # Warnes
)

# add_wikidata_labels <- match_manual |> tail(8) |> # just doing this for
#                                                   # cases with no labels
#    left_join(ine_geog_municipalities |> select(cod.mun, municipality),
#             by = "cod.mun") |>
#   filter(!is.na(municipality)) |>
#   mutate(
#     label_en = str_c(municipality, " Municipality"),
#     label_es = str_c("Municipio de ", municipality)
#   ) |>
#   add_quick_statement_column(qid, "L", label_en, lang = "en") |>
#   rename(quick_statement_en = quick_statement) |>
#   add_quick_statement_column(qid, "L", label_es, lang = "es") |>
#   rename(quick_statement_es = quick_statement)
# writeLines(add_wikidata_labels$quick_statement_en)
# writeLines(add_wikidata_labels$quick_statement_es)

# --- Combine all rounds -------------------------------------------------------
all_matches <- bind_rows(match_r1, match_r2, match_manual) |>
  distinct(qid, .keep_all = TRUE)  # rounds are in priority order


# --- De-duplicate: remove WD items that are city/municipality overlaps --------
# These are city QIDs whose geography overlaps with a dedicated municipality QID.
# The municipality-specific item (label_en contains "Municipality") is kept.
wd_duplicates_to_drop <- c(
  "Q1309601",  # San Carlos city      -> keep Q507108  (San Carlos Municipality)
  "Q941357",   # Riberalta city       -> keep Q842368  (Riberalta Municipality)
  "Q2524939",  # Villa Charcas (no label_en) -> keep Q1146801
  "Q1324520",  # El Puente (no label_es)     -> keep Q1108311
  "Q1034638"   # Capinota (Villa Capinota)   -> keep Q1730823 (Capinota Municipality)
)

all_matches <- all_matches |> filter(!qid %in% wd_duplicates_to_drop)
non_matches <- municipalities_wd_exp |> filter(!(qid %in% all_matches$qid))
ine_geog_municipalities |> filter(!(cod.mun %in% municipalities_matched$cod.mun))

# --- Join cod.mun back onto the full WD dataset ------------------------------
municipalities_matched <- municipalities_wd_exp |>
  left_join(all_matches, by = "qid")

cat("Total WD municipalities:", nrow(municipalities_matched), "\n")
cat("Matched to INE code:    ", sum(!is.na(municipalities_matched$cod.mun)), "\n")
cat("Unmatched:              ", sum(is.na(municipalities_matched$cod.mun)), "\n")

# Add quickstatements
municipalities_matched <- municipalities_matched |> add_quick_statement_column(qid, "P14142", cod.mun,
                                                     reference_qid = "Q138354774")
writeLines(municipalities_matched$quick_statement)

# Switch location property from department to province
municipalities_wd_exp %>%
  filter(is.na(loc_prov_en) & (!is.na(loc_dep_en))) %>%
  select(1, 2, loc_prov_en, loc_dep_en)
muni_reconnect <- municipalities_matched %>%
  filter(is.na(loc_prov_en) & (!is.na(loc_dep_en))) %>%
  mutate(cod.prov = str_sub(cod.mun, 1, 4)) %>%
  left_join(select(provinces_ine, cod.prov, qid) %>% rename(new_prov_qid = qid),
            by="cod.prov")

muni_reconnect <- muni_reconnect %>%
  remove_quick_statement_column(qid, "P131", loc_dep_qid) %>%
  rename(removal_quick_statement = quick_statement) %>%
  add_quick_statement_column(qid, "P131", new_prov_qid, type="item")
writeLines(muni_reconnect$removal_quick_statement)
writeLines(muni_reconnect$quick_statement)






