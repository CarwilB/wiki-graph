# src/pcode-crosswalk.R
#
# Crosswalk between Wikidata QIDs and OCHA p-codes from the
# Global Administrative Boundaries GDB (admin2 / admin3 layers).
#
# Two matching strategies are used, applied in priority order:
#   1. Code-based  — Wikidata properties whose values reconstruct the pcode
#                    directly (e.g. P14142 for Bolivia, P7325 for Colombia).
#   2. Name-based  — Normalized string matching between Wikidata labels and
#                    GDB name columns, with optional hierarchical narrowing
#                    via P131 (located in administrative territorial entity).
#
# Dependencies: httr, jsonlite, dplyr, purrr, stringr, tidyr, tibble, stringi
#
# Main entry points
#   build_pcode_crosswalk()      — full pipeline, returns a QID ↔ pcode tibble
#   make_pcode_quickstatements() — generate QuickStatements for a country

library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(stringr)
library(tidyr)
library(tibble)
library(stringi)

# ---- Country configuration ---------------------------------------------------

#' Default code-property configuration
#'
#' For each country where a Wikidata external-ID property reliably reconstructs
#' the GDB pcode via paste0(iso2, property_value), record the property and the
#' admin levels it covers.
PCODE_CODE_PROPERTIES <- tribble(
  ~country,      ~pid,     ~iso2, ~adm_levels,
  "Bolivia",    "P14142", "BO",  list(c("ADM2", "ADM3")),
  "Colombia",   "P7325",  "CO",  list(c("ADM2", "ADM3")),
  "Mexico",     "P3801",  "MX",  list("ADM2"),
  "Costa Rica", "P281",   "CR",  list("ADM3"),
  "Chile",      "P6929",  "CL",  list("ADM3"),
  "Haiti",      "P1370",  "HT",  list("ADM2")
)

#' Admin-type prefixes to strip before name comparison (after normalization)
#'
#' Handles labels like "Cantón Quijos", "Provincia de Arauco", "Municipio de X".
ADMIN_PREFIX_PATTERN <- paste0(
  "^(",
  paste(c(
    "canton de ", "canton ",
    "provincia de ", "provincia ",
    "province of ", "province ",
    "municipio de ", "municipio ",
    "municipality of ", "municipality ",
    "municipalidad de ", "municipalidad ",
    "departamento de ", "departamento ",
    "department of ", "department ",
    "district of ", "district ",
    "distrito de ", "distrito ",
    "parroquia de ", "parroquia ",
    "corregimiento de ", "corregimiento ",
    "arrondissement de ", "arrondissement ",
    "commune de ", "commune ",
    "barrio de ", "barrio "
  ), collapse = "|"),
  ")"
)


# ---- Name normalization helpers ----------------------------------------------

#' Normalize a character vector for fuzzy name matching
#'
#' Lowercases, strips diacritics via Latin-ASCII transliteration, replaces
#' non-alphanumeric runs with a single space, and trims whitespace.
#'
#' @param x Character vector
#' @return Character vector of the same length
normalize_admin_name <- function(x) {
  x |>
    str_to_lower() |>
    stri_trans_general("Latin-ASCII") |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

#' Strip common admin-type prefixes from a normalized name
#'
#' @param x Character vector already processed by normalize_admin_name()
#' @return Character vector with the prefix removed where it matches
strip_admin_prefix <- function(x) {
  str_remove(x, ADMIN_PREFIX_PATTERN)
}

#' Produce all normalized name variants for a label vector
#'
#' Returns a long tibble with two variants per label: the normalized form and
#' the prefix-stripped form. Duplicate variants are collapsed.
#'
#' @param labels Character vector of raw labels
#' @return Tibble with column \code{norm_label}
label_variants <- function(labels) {
  norm     <- normalize_admin_name(labels)
  stripped <- strip_admin_prefix(norm)
  tibble(norm_label = unique(c(norm, stripped))) |>
    filter(!is.na(norm_label), norm_label != "")
}


# ---- GDB name table builders ------------------------------------------------

#' Build normalized name lookup tables from GDB layers
#'
#' @param adm2_gdb data.frame — the ADM2 GDB layer (geometry dropped)
#' @param adm3_gdb data.frame — the ADM3 GDB layer (geometry dropped)
#' @return Named list with elements \code{adm2} and \code{adm3}, each a tibble
#'   with columns country, adm1_pcode, adm2_pcode [, adm3_pcode], norm_name
build_gdb_name_tables <- function(adm2_gdb, adm3_gdb) {
  adm2_names <- adm2_gdb |>
    select(country, adm1_pcode, adm2_pcode,
           matches("^adm2_name")) |>
    pivot_longer(matches("^adm2_name"), values_to = "raw_name",
                 names_to = "name_var") |>
    filter(!is.na(raw_name), raw_name != "") |>
    mutate(norm_name = normalize_admin_name(raw_name)) |>
    distinct(country, adm1_pcode, adm2_pcode, norm_name)

  adm3_names <- adm3_gdb |>
    select(country, adm1_pcode, adm2_pcode, adm3_pcode,
           matches("^adm3_name")) |>
    pivot_longer(matches("^adm3_name"), values_to = "raw_name",
                 names_to = "name_var") |>
    filter(!is.na(raw_name), raw_name != "") |>
    mutate(norm_name = normalize_admin_name(raw_name)) |>
    distinct(country, adm1_pcode, adm2_pcode, adm3_pcode, norm_name)

  list(adm2 = adm2_names, adm3 = adm3_names)
}


# ---- SPARQL helpers ---------------------------------------------------------

#' SPARQL query: fetch a single property value for a vector of QIDs
#'
#' @param qids Character vector of Wikidata QIDs
#' @param pid  Property ID string (e.g. "P14142")
#' @param batch_size Items per SPARQL VALUES clause (default 300)
#' @param delay Seconds to sleep between batches
#' @return Tibble with columns \code{qid} and \code{value}
sparql_fetch_property <- function(qids, pid, batch_size = 300, delay = 0.4) {
  batches <- split(qids, ceiling(seq_along(qids) / batch_size))
  results <- list()

  for (b in batches) {
    values <- paste0("wd:", b, collapse = " ")
    q <- sprintf(
      "SELECT ?item ?val WHERE { VALUES ?item { %s } ?item wdt:%s ?val . }",
      values, pid
    )
    r <- tryCatch(
      GET("https://query.wikidata.org/sparql",
          query = list(query = q, format = "json"),
          user_agent("wiki-graph-pcode-crosswalk/1.0"),
          timeout(60)),
      error = function(e) { Sys.sleep(3); NULL }
    )
    if (is.null(r) || status_code(r) != 200) { Sys.sleep(2); next }

    rows <- fromJSON(content(r, "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)$results$bindings
    if (length(rows) > 0) {
      results <- c(results, lapply(rows, function(row) tibble(
        qid   = str_extract(row$item$value, "Q\\d+$"),
        value = row$val$value
      )))
    }
    Sys.sleep(delay)
  }

  bind_rows(results)
}

#' SPARQL query: fetch P131 (parent admin unit) for a vector of QIDs
#'
#' @param qids Character vector of Wikidata QIDs
#' @param batch_size Items per SPARQL VALUES clause
#' @param delay Seconds to sleep between batches
#' @return Tibble with columns \code{qid} and \code{parent} (QID of parent unit)
sparql_fetch_parents <- function(qids, batch_size = 200, delay = 0.5) {
  batches <- split(qids, ceiling(seq_along(qids) / batch_size))
  results <- list()

  for (b in batches) {
    values <- paste0("wd:", b, collapse = " ")
    q <- sprintf(
      "SELECT ?item ?parent WHERE { VALUES ?item { %s } ?item wdt:P131 ?parent . }",
      values
    )
    r <- tryCatch(
      GET("https://query.wikidata.org/sparql",
          query = list(query = q, format = "json"),
          user_agent("wiki-graph-pcode-crosswalk/1.0"),
          timeout(60)),
      error = function(e) { Sys.sleep(3); NULL }
    )
    if (is.null(r) || status_code(r) != 200) { Sys.sleep(2); next }

    rows <- fromJSON(content(r, "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)$results$bindings
    if (length(rows) > 0) {
      results <- c(results, lapply(rows, function(row) tibble(
        qid    = str_extract(row$item$value,   "Q\\d+$"),
        parent = str_extract(row$parent$value, "Q\\d+$")
      )))
    }
    Sys.sleep(delay)
  }

  bind_rows(results)
}


# ---- Matching functions ------------------------------------------------------

#' Match QIDs to pcodes via a Wikidata code property
#'
#' Reconstructs the pcode as paste0(iso2, property_value) and checks
#' membership in the provided pcode set.
#'
#' @param qids     Character vector of Wikidata QIDs to query
#' @param pid      Wikidata property ID (e.g. "P14142")
#' @param iso2     Two-letter ISO country code prefix for pcodes
#' @param pcode_set Character vector of valid pcodes to match against
#' @param country  Country label for the output column
#' @param ...      Passed to sparql_fetch_property() (batch_size, delay)
#' @return Tibble with columns qid, pcode, country, match_method
match_by_code <- function(qids, pid, iso2, pcode_set, country, ...) {
  raw <- sparql_fetch_property(qids, pid, ...)
  if (nrow(raw) == 0) return(tibble())

  raw |>
    mutate(pcode = paste0(iso2, value)) |>
    filter(pcode %in% pcode_set) |>
    select(qid, pcode) |>
    distinct(qid, .keep_all = TRUE) |>
    mutate(country = country, match_method = paste0("code_", pid))
}

#' Match Wikidata ADM2 items to GDB ADM2 pcodes by normalized name
#'
#' Builds all label variants (en + es, with and without admin-type prefix),
#' inner-joins on (country, normalized name), and keeps only unambiguous
#' one-to-one matches.
#'
#' @param wd_items   Tibble with columns qid, country, adm_level, label_en, label_es
#' @param gdb_adm2   Output of build_gdb_name_tables()$adm2
#' @return Tibble with columns qid, country, adm_level, adm2_pcode,
#'   adm1_pcode, match_method
match_by_name_adm2 <- function(wd_items, gdb_adm2) {
  wd_long <- wd_items |>
    filter(adm_level == "ADM2") |>
    pivot_longer(c(label_en, label_es), names_to = "lang", values_to = "raw") |>
    filter(!is.na(raw)) |>
    mutate(
      norm     = normalize_admin_name(raw),
      stripped = strip_admin_prefix(norm)
    ) |>
    pivot_longer(c(norm, stripped), names_to = "variant", values_to = "norm_label") |>
    distinct(qid, country, adm_level, norm_label)

  wd_long |>
    inner_join(gdb_adm2 |> select(country, adm1_pcode, adm2_pcode, norm_name),
               by = c("country", "norm_label" = "norm_name"),
               relationship = "many-to-many") |>
    group_by(qid) |>
    summarise(
      n_gdb_hits = n_distinct(adm2_pcode),
      adm2_pcode = first(adm2_pcode),
      adm1_pcode = first(adm1_pcode),
      country    = first(country),
      adm_level  = first(adm_level),
      .groups    = "drop"
    ) |>
    filter(n_gdb_hits == 1) |>
    select(qid, country, adm_level, adm2_pcode, adm1_pcode) |>
    mutate(match_method = "name_adm2")
}

#' Match Wikidata ADM3 items to GDB ADM3 pcodes by normalized name
#'
#' Country-level matching: accepts only names that are unique within the
#' country (one GDB unit per label). Items with ambiguous names are returned
#' in a separate \code{$ambiguous} element for hierarchical resolution.
#'
#' @param wd_items Tibble with columns qid, country, adm_level, label_en, label_es
#' @param gdb_adm3 Output of build_gdb_name_tables()$adm3
#' @return Named list:
#'   \describe{
#'     \item{matched}{Tibble of unambiguous matches}
#'     \item{ambiguous}{QID character vector of items with >1 GDB hit}
#'   }
match_by_name_adm3 <- function(wd_items, gdb_adm3) {
  wd_long <- wd_items |>
    filter(adm_level == "ADM3") |>
    pivot_longer(c(label_en, label_es), names_to = "lang", values_to = "raw") |>
    filter(!is.na(raw)) |>
    mutate(
      norm     = normalize_admin_name(raw),
      stripped = strip_admin_prefix(norm)
    ) |>
    pivot_longer(c(norm, stripped), names_to = "variant", values_to = "norm_label") |>
    distinct(qid, country, adm_level, norm_label)

  joined <- wd_long |>
    inner_join(gdb_adm3 |> select(country, adm2_pcode, adm3_pcode, norm_name),
               by = c("country", "norm_label" = "norm_name"),
               relationship = "many-to-many") |>
    group_by(qid) |>
    summarise(
      n_gdb_hits = n_distinct(adm3_pcode),
      adm3_pcode = first(adm3_pcode),
      adm2_pcode = first(adm2_pcode),
      country    = first(country),
      adm_level  = first(adm_level),
      .groups    = "drop"
    )

  list(
    matched = joined |>
      filter(n_gdb_hits == 1) |>
      select(qid, country, adm_level, adm2_pcode, adm3_pcode) |>
      mutate(match_method = "name_adm3"),
    ambiguous = joined |> filter(n_gdb_hits > 1) |> pull(qid)
  )
}

#' Resolve ambiguous ADM3 name matches using P131 parent hierarchy
#'
#' For items that matched multiple GDB ADM3 units by name, fetch their P131
#' parent from Wikidata, look that parent up in an ADM2 crosswalk, and
#' re-match the name within the correct ADM2 unit.
#'
#' @param ambiguous_qids Character vector of QIDs with ambiguous country-level matches
#' @param wd_items   Tibble with columns qid, country, label_en, label_es
#' @param gdb_adm3   Normalized GDB ADM3 name table (from build_gdb_name_tables()$adm3)
#' @param adm2_xwalk Tibble mapping QID → adm2_pcode (from confirmed ADM2 matches)
#' @param ...        Passed to sparql_fetch_parents() (batch_size, delay)
#' @return Tibble of newly resolved matches with columns
#'   qid, country, adm_level, adm2_pcode, adm3_pcode, match_method
match_by_name_adm3_hierarchical <- function(ambiguous_qids, wd_items,
                                             gdb_adm3, adm2_xwalk, ...) {
  if (length(ambiguous_qids) == 0) return(tibble())

  message("  Fetching P131 parents for ", length(ambiguous_qids),
          " ambiguous ADM3 items...")
  parents <- sparql_fetch_parents(ambiguous_qids, ...)

  # Keep only parents that are in our confirmed ADM2 crosswalk
  anchored <- parents |>
    inner_join(adm2_xwalk |> select(qid, adm2_pcode),
               by = c("parent" = "qid")) |>
    rename(parent_adm2_pcode = adm2_pcode)

  if (nrow(anchored) == 0) return(tibble())

  # Build normalized label variants for the ambiguous items only
  wd_long <- wd_items |>
    filter(qid %in% ambiguous_qids) |>
    pivot_longer(c(label_en, label_es), names_to = "lang", values_to = "raw") |>
    filter(!is.na(raw)) |>
    mutate(
      norm     = normalize_admin_name(raw),
      stripped = strip_admin_prefix(norm)
    ) |>
    pivot_longer(c(norm, stripped), names_to = "variant", values_to = "norm_label") |>
    distinct(qid, country, norm_label)

  anchored |>
    left_join(wd_long, by = "qid", relationship = "many-to-many") |>
    inner_join(
      gdb_adm3 |> select(country, adm2_pcode, adm3_pcode, norm_name),
      by = c("country", "parent_adm2_pcode" = "adm2_pcode",
             "norm_label" = "norm_name")
    ) |>
    group_by(qid) |>
    summarise(
      n_hits     = n_distinct(adm3_pcode),
      adm3_pcode = first(adm3_pcode),
      adm2_pcode = first(parent_adm2_pcode),
      country    = first(country),
      .groups    = "drop"
    ) |>
    filter(n_hits == 1) |>
    left_join(wd_items |> select(qid, adm_level), by = "qid") |>
    select(qid, country, adm_level, adm2_pcode, adm3_pcode) |>
    mutate(match_method = "name_adm3_hierarchical")
}


# ---- Main pipeline ----------------------------------------------------------

#' Build a QID ↔ pcode crosswalk for all countries in all_data
#'
#' Applies code-based matching first (using PCODE_CODE_PROPERTIES or a custom
#' configuration), then name-based matching for all remaining items. For
#' countries listed in \code{hierarchical_countries}, a second-pass P131 fetch
#' is used to resolve ambiguous ADM3 name matches.
#'
#' Countries absent from the GDB (Argentina, Paraguay, Suriname, Uruguay,
#' Cuba, Puerto Rico, Brazil) are silently skipped.
#'
#' @param all_data  Tibble with columns qid, country, adm_level, label_en,
#'   label_es. Typically the combined presence-matrix data from
#'   wikipedia-admin-presence.qmd.
#' @param adm2_gdb  data.frame — GDB ADM2 layer with geometry dropped, joined
#'   to a \code{country} column via ISO2. Must have columns country, iso2,
#'   adm1_pcode, adm2_pcode, adm2_name [, adm2_name1, adm2_name2, adm2_name3].
#' @param adm3_gdb  data.frame — GDB ADM3 layer, analogous structure.
#' @param code_properties Tibble overriding PCODE_CODE_PROPERTIES.
#' @param hierarchical_countries Countries for which ambiguous ADM3 name
#'   matches should be resolved via a P131 SPARQL fetch. Default:
#'   Venezuela and Panama.
#' @param sparql_batch_size Items per SPARQL VALUES clause.
#' @param sparql_delay Seconds between SPARQL batches.
#' @param cache_file Optional path; if the file exists the result is loaded
#'   instead of recomputed.
#'
#' @return Tibble with columns:
#'   \describe{
#'     \item{qid}{Wikidata QID}
#'     \item{country}{Country label}
#'     \item{adm_level}{"ADM2" or "ADM3"}
#'     \item{pcode}{The matched GDB pcode (adm2_pcode or adm3_pcode)}
#'     \item{adm2_pcode}{ADM2 pcode (NA for ADM3 name-matches without parent)}
#'     \item{adm3_pcode}{ADM3 pcode (NA for ADM2 matches)}
#'     \item{match_method}{One of: code_P#####, name_adm2, name_adm3,
#'       name_adm3_hierarchical}
#'   }
#'
#' @examples
#' \dontrun{
#' xwalk <- build_pcode_crosswalk(all_data, adm2_gdb, adm3_gdb)
#' }
build_pcode_crosswalk <- function(all_data,
                                   adm2_gdb,
                                   adm3_gdb,
                                   code_properties       = PCODE_CODE_PROPERTIES,
                                   hierarchical_countries = c("Venezuela", "Panama"),
                                   sparql_batch_size     = 300,
                                   sparql_delay          = 0.4,
                                   cache_file            = NULL) {

  if (!is.null(cache_file) && file.exists(cache_file)) {
    message("Loading crosswalk from cache: ", cache_file)
    return(readRDS(cache_file))
  }

  # Country/pcode universe (GDB countries only)
  gdb_countries <- union(adm2_gdb$country, adm3_gdb$country)
  wd_gdb        <- all_data |> filter(country %in% gdb_countries)
  all_adm2_pcodes <- adm2_gdb$adm2_pcode
  all_adm3_pcodes <- adm3_gdb$adm3_pcode

  message("Building GDB name tables...")
  gdb_names <- build_gdb_name_tables(adm2_gdb, adm3_gdb)

  results <- list()

  # ---- Step 1: Code-based matching ----------------------------------------
  message("Step 1: Code-based matching...")

  for (i in seq_len(nrow(code_properties))) {
    cfg     <- code_properties[i, ]
    country <- cfg$country
    pid     <- cfg$pid
    iso2    <- cfg$iso2
    levels  <- unlist(cfg$adm_levels)

    qids_for_country <- wd_gdb |>
      filter(country == !!country, adm_level %in% levels) |>
      pull(qid)

    if (length(qids_for_country) == 0) next
    message("  ", country, " (", pid, ", n=", length(qids_for_country), ")...")

    pcode_set <- c(all_adm2_pcodes, all_adm3_pcodes)
    matches <- match_by_code(qids_for_country, pid, iso2, pcode_set, country,
                             batch_size = sparql_batch_size,
                             delay      = sparql_delay)

    if (nrow(matches) > 0) {
      # Determine adm_level from which pcode set the match lands in
      matches <- matches |>
        mutate(
          adm_level  = case_when(
            pcode %in% all_adm2_pcodes ~ "ADM2",
            pcode %in% all_adm3_pcodes ~ "ADM3",
            TRUE                       ~ NA_character_
          ),
          adm2_pcode = if_else(adm_level == "ADM2", pcode, NA_character_),
          adm3_pcode = if_else(adm_level == "ADM3", pcode, NA_character_)
        ) |>
        filter(!is.na(adm_level))
      results[["code"]] <- bind_rows(results[["code"]], matches)
      message("    → ", nrow(matches), " matched")
    }
  }

  confirmed_code_qids <- if (!is.null(results[["code"]])) results[["code"]]$qid else character()

  # ADM2 crosswalk so far (code-based) — used for hierarchical ADM3 resolution
  adm2_xwalk_so_far <- bind_rows(results) |>
    filter(!is.na(adm2_pcode)) |>
    select(qid, adm2_pcode) |>
    distinct()

  # ---- Step 2: Name-based ADM2 matching -----------------------------------
  message("Step 2: Name-based ADM2 matching...")

  wd_adm2_unmatched <- wd_gdb |>
    filter(adm_level == "ADM2", !qid %in% confirmed_code_qids)

  if (nrow(wd_adm2_unmatched) > 0) {
    name_adm2 <- match_by_name_adm2(wd_adm2_unmatched, gdb_names$adm2)
    results[["name_adm2"]] <- name_adm2 |>
      mutate(
        adm3_pcode = NA_character_,
        pcode      = adm2_pcode
      ) |>
      select(qid, country, adm_level, pcode, adm2_pcode, adm3_pcode, match_method)
    message("  → ", nrow(name_adm2), " ADM2 name matches")

    # Update ADM2 crosswalk with name-matched entries
    adm2_xwalk_so_far <- bind_rows(
      adm2_xwalk_so_far,
      name_adm2 |> select(qid, adm2_pcode)
    ) |> distinct()
  }

  # ---- Step 3: Name-based ADM3 matching -----------------------------------
  message("Step 3: Name-based ADM3 matching...")

  wd_adm3_unmatched <- wd_gdb |>
    filter(adm_level == "ADM3", !qid %in% confirmed_code_qids)

  if (nrow(wd_adm3_unmatched) > 0) {
    adm3_result <- match_by_name_adm3(wd_adm3_unmatched, gdb_names$adm3)
    results[["name_adm3"]] <- adm3_result$matched |>
      mutate(
        pcode      = adm3_pcode,
        adm2_pcode = NA_character_
      ) |>
      select(qid, country, adm_level, pcode, adm2_pcode, adm3_pcode, match_method)
    message("  → ", nrow(adm3_result$matched), " ADM3 country-level name matches")

    # ---- Step 4: Hierarchical ADM3 for ambiguous cases --------------------
    hier_qids <- intersect(adm3_result$ambiguous,
                           wd_gdb |> filter(country %in% hierarchical_countries) |> pull(qid))
    message("Step 4: Hierarchical ADM3 (", length(hier_qids), " ambiguous items in [",
            paste(hierarchical_countries, collapse = ", "), "])...")

    if (length(hier_qids) > 0) {
      hier_result <- match_by_name_adm3_hierarchical(
        hier_qids,
        wd_items   = wd_gdb,
        gdb_adm3   = gdb_names$adm3,
        adm2_xwalk = adm2_xwalk_so_far,
        batch_size = sparql_batch_size,
        delay      = sparql_delay
      )
      results[["name_adm3_hier"]] <- hier_result |>
        mutate(
          pcode = adm3_pcode
        ) |>
        select(qid, country, adm_level, pcode, adm2_pcode, adm3_pcode, match_method)
      message("  → ", nrow(hier_result), " hierarchical ADM3 matches")
    }
  }

  # ---- Merge: code-based takes priority over name-based ------------------
  # Normalise code-based results to the same schema
  code_normalised <- if (!is.null(results[["code"]])) {
    results[["code"]] |>
      select(qid, country, adm_level, pcode, adm2_pcode, adm3_pcode, match_method)
  } else {
    tibble()
  }

  crosswalk <- bind_rows(
    code_normalised,
    results[["name_adm2"]],
    results[["name_adm3"]],
    results[["name_adm3_hier"]]
  ) |>
    # Sort so code_* < name_* alphabetically; slice keeps first (code preferred)
    arrange(qid, match_method) |>
    group_by(qid) |>
    slice(1) |>
    ungroup()

  if (!is.null(cache_file)) {
    saveRDS(crosswalk, cache_file)
    message("Crosswalk saved to ", cache_file)
  }

  crosswalk
}


# ---- QuickStatements generation ---------------------------------------------

#' Generate QuickStatements to add pcode (P7590) to Wikidata items
#'
#' Produces one QuickStatements command per matched item for a given country.
#' **Does not execute anything** — the output is a tibble for review before
#' upload.
#'
#' The default property is P7590 (OCHA P-code). A reference block is added
#' when either \code{reference_qid} or \code{reference_url} is supplied.
#'
#' @param crosswalk     Tibble from build_pcode_crosswalk()
#' @param country       Country name to filter (must match crosswalk$country)
#' @param pid           Wikidata property to set. Default "P7590" (OCHA P-code).
#' @param adm_levels    Which admin levels to include. Default both.
#' @param methods       Character vector of match_method values to include,
#'   or NULL to include all methods.
#' @param reference_qid Wikidata QID for "stated in" (P248) reference, or NULL.
#' @param reference_url URL for P854 reference, or NULL.
#' @param retrieved_date Date to record as S813 (retrieved). Default today.
#' @param output_file   Optional path to write the statements as a TSV.
#'
#' @return Tibble with columns qid, country, adm_level, pcode, match_method,
#'   quick_statement. Invisibly also writes \code{output_file} if specified.
#'
#' @examples
#' \dontrun{
#' qs <- make_pcode_quickstatements(
#'   crosswalk, country = "Bolivia",
#'   reference_url = "https://data.humdata.org/dataset/...",
#'   output_file   = "data/qs_bolivia_pcode.tsv"
#' )
#' cat(qs$quick_statement, sep = "\n")
#' }
make_pcode_quickstatements <- function(crosswalk,
                                        country,
                                        pid            = "P7590",
                                        adm_levels     = c("ADM2", "ADM3"),
                                        methods        = NULL,
                                        reference_qid  = NULL,
                                        reference_url  = NULL,
                                        retrieved_date = Sys.Date(),
                                        output_file    = NULL) {

  # Validate
  if (!country %in% crosswalk$country) {
    stop("Country '", country, "' not found in crosswalk. ",
         "Available: ", paste(sort(unique(crosswalk$country)), collapse = ", "))
  }

  rows <- crosswalk |>
    filter(
      country   == !!country,
      adm_level %in% adm_levels,
      !is.na(pcode)
    )

  if (!is.null(methods)) {
    rows <- rows |> filter(match_method %in% methods)
  }

  if (nrow(rows) == 0) {
    message("No rows matched the filter criteria.")
    return(invisible(tibble()))
  }

  # Build QuickStatements using create_quick_statement()
  rows <- rows |>
    rowwise() |>
    mutate(
      quick_statement = create_quick_statement(
        qid            = qid,
        property       = pid,
        value          = pcode,
        type           = "string",
        reference_qid  = reference_qid,
        reference_url  = reference_url,
        retrieved_date = retrieved_date
      )
    ) |>
    ungroup()

  if (!is.null(output_file)) {
    writeLines(rows$quick_statement, output_file)
    message("Wrote ", nrow(rows), " statements to ", output_file)
  }

  rows |> select(qid, country, adm_level, pcode, match_method, quick_statement)
}


# ---- Coverage summary -------------------------------------------------------

#' Summarise crosswalk coverage relative to all_data
#'
#' @param crosswalk Tibble from build_pcode_crosswalk()
#' @param all_data  The same all_data used to build the crosswalk
#' @param gdb_countries Character vector of countries present in the GDB
#' @return Tibble with one row per country × adm_level, showing
#'   n_wikidata, n_matched, pct_matched, and the primary match method
summarise_crosswalk_coverage <- function(crosswalk, all_data, gdb_countries) {
  totals <- all_data |>
    filter(country %in% gdb_countries) |>
    count(country, adm_level, name = "n_wikidata")

  crosswalk |>
    count(country, adm_level, match_method, name = "n_matched") |>
    left_join(totals, by = c("country", "adm_level")) |>
    mutate(pct = round(100 * n_matched / n_wikidata, 1)) |>
    arrange(country, adm_level, match_method)
}
