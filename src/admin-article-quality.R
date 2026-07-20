# admin-article-quality.R
# Shared utilities for fetching Wikidata population data, Wikipedia article text,
# and computing article quality metrics (infobox coverage, length, citations)
# across multi-country, multi-language admin-division analyses.
#
# Depends on: src/wikipedia-tools.R (must be sourced first)
# Used by:    wikipedia-admin-presence.qmd, wikipedia-admin-presence-ssa.qmd

library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(stringr)
library(tidyr)
library(tibble)

# ---- Wikidata Population via SPARQL ------------------------------------------

#' Fetch population (P1082) from Wikidata for a vector of QIDs
#'
#' Uses SPARQL with VALUES clause to batch-query. Returns the most recent
#' population figure and its year (P585 qualifier) for each QID.
#'
#' @param qids Character vector of Wikidata QIDs
#' @param cache_file Optional path to cache/load results as RDS
#' @param batch_size Number of QIDs per SPARQL query (default 200)
#' @return tibble with columns: qid, population, pop_year
fetch_wikidata_population <- function(qids, cache_file = NULL, batch_size = 200) {
  if (!is.null(cache_file) && file.exists(cache_file)) {
    cached <- readRDS(cache_file)
    missing_qids <- setdiff(qids, cached$qid)
    if (length(missing_qids) == 0) {
      message("Population: loaded from cache (", nrow(cached), " items)")
      return(cached |> filter(qid %in% qids))
    }
    message("Population: cache has ", nrow(cached), " items, ",
            length(missing_qids), " new QIDs to fetch")
    qids_to_fetch <- missing_qids
  } else {
    cached <- tibble(qid = character(), population = numeric(),
                     pop_year = integer())
    qids_to_fetch <- qids
  }

  batches <- split(qids_to_fetch, ceiling(seq_along(qids_to_fetch) / batch_size))
  new_results <- list()

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    values_clause <- paste0("wd:", batch, collapse = " ")

    query <- sprintf('
SELECT ?item ?pop ?year WHERE {
  VALUES ?item { %s }
  ?item p:P1082 ?popStatement .
  ?popStatement ps:P1082 ?pop .
  OPTIONAL { ?popStatement pq:P585 ?date . }
  BIND(YEAR(?date) AS ?year)
}
ORDER BY ?item DESC(?year)
', values_clause)

    message("Population batch ", i, "/", length(batches),
            " (", length(batch), " QIDs)...")

    r <- tryCatch({
      GET(
        "https://query.wikidata.org/sparql",
        query = list(query = query, format = "json"),
        user_agent("wiki-graph-admin-quality/1.0"),
        timeout(120)
      )
    }, error = function(e) {
      message("  SPARQL error: ", e$message)
      NULL
    })

    if (is.null(r) || status_code(r) != 200) {
      if (!is.null(r)) message("  HTTP ", status_code(r))
      Sys.sleep(5)
      next
    }

    res <- fromJSON(content(r, "text", encoding = "UTF-8"))
    if (length(res$results$bindings) == 0) next

    batch_df <- as_tibble(res$results$bindings) |>
      mutate(
        qid = str_extract(item$value, "Q\\d+$"),
        population = as.numeric(pop$value),
        pop_year = as.integer(year$value)
      ) |>
      select(qid, population, pop_year)

    # Keep only the most recent population per QID
    batch_df <- batch_df |>
      arrange(qid, desc(pop_year)) |>
      group_by(qid) |>
      slice(1) |>
      ungroup()

    new_results[[i]] <- batch_df
    Sys.sleep(2)
  }

  new_df <- bind_rows(new_results)

  # Merge with cache
  result <- bind_rows(cached, new_df) |>
    distinct(qid, .keep_all = TRUE)

  if (!is.null(cache_file)) {
    saveRDS(result, cache_file)
    message("Population: saved ", nrow(result), " items to ", cache_file)
  }

  result |> filter(qid %in% qids)
}


# ---- Extract article titles from presence cache ------------------------------

#' Extract article titles from raw wikidata presence cache files
#'
#' The presence-matrix cache files store $instances with a wikipedia_articles
#' list-column containing strings like "en: Article_Title". This function
#' extracts those into a tidy (qid, lang, title) tibble.
#'
#' @param cache_files Character vector of RDS file paths
#' @param languages Character vector of language codes to extract (NULL = all)
#' @return tibble with columns: qid, lang, title
extract_article_titles_from_cache <- function(cache_files, languages = NULL) {
  all_titles <- list()

  for (f in cache_files) {
    if (!file.exists(f)) {
      message("  Skipping missing file: ", f)
      next
    }
    cached <- readRDS(f)
    inst <- cached$instances
    if (is.null(inst) || !"wikipedia_articles" %in% names(inst)) next

    for (i in seq_len(nrow(inst))) {
      arts <- inst$wikipedia_articles[[i]]
      if (length(arts) == 0) next
      qid <- inst$qid[i]

      for (art in arts) {
        parts <- str_match(art, "^(\\w+):\\s*(.+)$")
        if (is.na(parts[1, 1])) next
        lang <- parts[1, 2]
        title <- parts[1, 3]

        if (!is.null(languages) && !lang %in% languages) next

        all_titles <- c(all_titles, list(tibble(
          qid = qid, lang = lang, title = title
        )))
      }
    }
  }

  if (length(all_titles) == 0) {
    return(tibble(qid = character(), lang = character(), title = character()))
  }

  bind_rows(all_titles) |> distinct()
}


# ---- Batch wikitext fetch with multi-language caching ------------------------

#' Fetch and cache wikitext for multiple articles across languages
#'
#' @param titles_df tibble with columns: qid, lang, title
#' @param cache_base Base directory for wikitext cache (e.g. "wikipedia-pages/sa_adm2")
#' @param delay Seconds between API calls
#' @param progress Whether to show progress
#' @return titles_df with added column: wikitext
fetch_wikitext_batch <- function(titles_df, cache_base, delay = 0.5,
                                 progress = TRUE) {
  dir.create(cache_base, showWarnings = FALSE, recursive = TRUE)

  n <- nrow(titles_df)
  wikitext <- character(n)
  n_cached <- 0
  n_fetched <- 0

  for (i in seq_len(n)) {
    lang <- titles_df$lang[i]
    title <- titles_df$title[i]

    # Create language subdirectory
    lang_dir <- file.path(cache_base, lang)
    dir.create(lang_dir, showWarnings = FALSE, recursive = TRUE)

    # Sanitise filename
    safe_name <- gsub("[/:*?\"<>|]", "_", title)
    cache_path <- file.path(lang_dir, paste0(safe_name, ".txt"))

    if (file.exists(cache_path)) {
      wikitext[i] <- paste(readLines(cache_path, warn = FALSE), collapse = "\n")
      n_cached <- n_cached + 1
    } else {
      if (delay > 0 && n_fetched > 0) Sys.sleep(delay)

      txt <- tryCatch(
        get_wikitext_by_name(title, lang = lang),
        error = function(e) NULL
      )

      if (!is.null(txt)) {
        writeLines(txt, cache_path)
        wikitext[i] <- txt
      } else {
        wikitext[i] <- NA_character_
      }
      n_fetched <- n_fetched + 1
    }

    if (progress && i %% 100 == 0) {
      message("  Wikitext: ", i, "/", n, " (", n_cached, " cached, ",
              n_fetched, " fetched)")
    }
  }

  message("  Wikitext complete: ", n_cached, " from cache, ",
          n_fetched, " freshly fetched")
  titles_df$wikitext <- wikitext
  titles_df
}


# ---- Infobox field canonical mapping ----------------------------------------

#' Cross-language canonical field name map
#'
#' Maps lowercased, underscore-normalised field names from English, Spanish,
#' and Portuguese admin-unit infoboxes to a single canonical English key.
#' Entries without a mapping are left unchanged by canonicalize_field_names().
#'
#' Canonical keys used elsewhere in the pipeline:
#'   population_total  — total/resident population figure
#'   population_as_of  — year or date of the population figure
#'   area_total_km2    — total area in km²
#'   official_name     — official place name
#'   seat              — administrative seat / capital
INFOBOX_FIELD_CANONICAL <- c(
  # ---- Population value ----
  # English
  "population_total"      = "population_total",
  "population"            = "population_total",
  "pop"                   = "population_total",
  # Spanish  (Ficha de entidad subnacional)
  "población"             = "population_total",
  "poblacion"             = "population_total",
  # Portuguese  (Info/Município do Brasil, Info/Assentamento, etc.)
  "população_total"       = "population_total",
  "populacao_total"       = "population_total",
  "população"             = "population_total",
  "populacao"             = "population_total",
  "populacao_municipio"   = "population_total",

  # ---- Population year ----
  # English
  "population_as_of"      = "population_as_of",
  "census_year"           = "population_as_of",
  "population_year"       = "population_as_of",
  # Spanish
  "población_año"         = "population_as_of",
  "poblacion_ano"         = "population_as_of",
  # Portuguese
  "população_em"          = "population_as_of",
  "populacao_em"          = "population_as_of",
  "população_data"        = "population_as_of",
  "data_pop"              = "population_as_of",
  "censo"                 = "population_as_of",

  # ---- Area ----
  # English
  "area_total_km2"        = "area_total_km2",
  "area_total"            = "area_total_km2",
  "area_km2"              = "area_total_km2",
  "area"                  = "area_total_km2",
  # Spanish
  "superficie"            = "area_total_km2",
  "superficie_total"      = "area_total_km2",
  # Portuguese
  "área_total_km2"        = "area_total_km2",
  "area_total_km2"        = "area_total_km2",  # already canonical; kept for explicitness
  "área"                  = "area_total_km2",
  "área_ref"              = "area_total_km2",

  # ---- Official name ----
  # English
  "official_name"         = "official_name",
  "name"                  = "official_name",
  # Spanish
  "nombre"                = "official_name",
  "nombre_completo"       = "official_name",
  # Portuguese
  "nome"                  = "official_name",
  "nome_oficial"          = "official_name",

  # ---- Administrative seat / capital ----
  # English
  "seat"                  = "seat",
  "capital"               = "seat",
  # Spanish  (capital is the same word)
  # Portuguese
  "sede"                  = "seat"
)

#' Apply canonical field names to a character vector
#'
#' Fields present in INFOBOX_FIELD_CANONICAL are replaced with their canonical
#' equivalent; all others are left unchanged.
#'
#' @param fields Character vector of lowercased, underscore-normalised field names
#' @return Character vector of the same length with canonical names substituted
canonicalize_field_names <- function(fields) {
  mapped     <- INFOBOX_FIELD_CANONICAL[fields]
  no_mapping <- is.na(mapped)
  mapped[no_mapping] <- fields[no_mapping]
  unname(mapped)
}


# ---- Population extraction from infobox -------------------------------------

#' Extract population value and year from a raw infobox list
#'
#' Uses INFOBOX_FIELD_CANONICAL to locate the population and population-year
#' fields regardless of the article language.
#'
#' Year extraction first checks the dedicated year field; if absent it falls
#' back to looking for a four-digit year inside the population value itself.
#'
#' @param infobox Named list returned by extract_infobox(), or NULL
#' @return List with two elements:
#'   \describe{
#'     \item{pop_value}{Cleaned population string, or NA_character_}
#'     \item{pop_year}{Integer year, or NA_integer_}
#'   }
extract_infobox_population <- function(infobox) {
  if (is.null(infobox) || length(infobox) == 0) {
    return(list(pop_value = NA_character_, pop_year = NA_integer_))
  }

  norm_names <- str_to_lower(str_replace_all(names(infobox), "\\s+", "_"))
  canonical  <- canonicalize_field_names(norm_names)

  # -- Population value --
  pop_idx   <- which(canonical == "population_total")
  pop_value <- NA_character_
  if (length(pop_idx) > 0) {
    pop_value <- clean_infobox_value(infobox[[pop_idx[1]]])
  }

  # -- Population year --
  year_idx <- which(canonical == "population_as_of")
  pop_year <- NA_integer_
  if (length(year_idx) > 0) {
    clean_yr <- clean_infobox_value(infobox[[year_idx[1]]])
    if (!is.na(clean_yr)) {
      yr_match <- str_extract(clean_yr, "\\b(19|20)\\d{2}\\b")
      if (!is.na(yr_match)) pop_year <- as.integer(yr_match)
    }
  }
  # Fallback: extract year embedded in population value (e.g. "7,941 (2024)")
  # Guard: skip when the entire value IS the year-like number (e.g. pop = 2089)
  if (is.na(pop_year) && !is.na(pop_value)) {
    yr_match <- str_extract(pop_value, "\\b(19|20)\\d{2}\\b")
    bare     <- str_remove_all(pop_value, "[\\s,.]")
    if (!is.na(yr_match) && bare != yr_match) {
      pop_year <- as.integer(yr_match)
    }
  }

  list(pop_value = pop_value, pop_year = pop_year)
}


# ---- Leader year extraction -------------------------------------------------

#' Extract the most salient year from leader-name infobox fields
#'
#' Searches for years in leader/mayor/governor fields across English
#' (`leader_name`), Spanish (`dirigentes_nombres`, `alcalde`, `dirigente1`,
#' `dirigente1_año`, `dirigentes_años`), and Portuguese (`prefeito`,
#' `intendente`) infobox templates. Prefers a term-start year in
#' (YYYY–YYYY) patterns, falls back to any 20xx year.
#'
#' @param wikitext Character string of article wikitext
#' @return Integer year, or NA_integer_
extract_leader_year <- function(wikitext) {
  if (is.na(wikitext) || nchar(wikitext) == 0) return(NA_integer_)

  field_pats <- c(
    "\\|\\s*leader_name\\d?\\s*=\\s*([^\n]+)",
    "\\|\\s*dirigentes_nombres\\s*=\\s*([^\n]+)",
    "\\|\\s*dirigente1\\s*=\\s*([^\n]+)",
    "\\|\\s*alcalde\\s*=\\s*([^\n]+)",
    "\\|\\s*prefeito\\s*=\\s*([^\n]+)",
    "\\|\\s*intendente\\s*=\\s*([^\n]+)"
  )

  for (pat in field_pats) {
    m <- str_match(wikitext, regex(pat, ignore_case = TRUE))
    if (!is.na(m[1, 2])) {
      val <- m[1, 2]
      # Prefer (YYYY-YYYY) term-start patterns
      yr <- str_match(val, "\\((20\\d{2})(?:\\s*[-\u2013]|\\))")
      if (!is.na(yr[1, 2])) return(as.integer(yr[1, 2]))
      # Fallback: any 20xx year in the value
      yr2 <- str_extract(val, "\\b(20\\d{2})\\b")
      if (!is.na(yr2)) return(as.integer(yr2))
    }
  }

  # Explicit year field (Spanish templates)
  yr_field <- str_match(wikitext, regex(
    "\\|\\s*dirigente1_a\u00f1o\\s*=\\s*(\\d{4})", ignore_case = TRUE
  ))
  if (!is.na(yr_field[1, 2])) return(as.integer(yr_field[1, 2]))

  # dirigentes_años (may list multiple years)
  yr_field2 <- str_match(wikitext, regex(
    "\\|\\s*dirigentes_a\u00f1os\\s*=\\s*([^\n]+)", ignore_case = TRUE
  ))
  if (!is.na(yr_field2[1, 2])) {
    yr <- str_extract(yr_field2[1, 2], "\\b(20\\d{2})\\b")
    if (!is.na(yr)) return(as.integer(yr))
  }

  NA_integer_
}


# ---- Compute article quality metrics ----------------------------------------

#' Compute quality metrics for articles with wikitext
#'
#' Uses functions from src/wikipedia-tools.R: extract_infobox(),
#' count_citations(), count_refs()
#'
#' @param df tibble with columns: qid, lang, title, wikitext
#' @return df with added columns: n_chars, n_citations, n_refs,
#'   has_infobox, n_infobox_fields, infobox_field_names
compute_article_quality <- function(df) {
  is_blank <- \(v) is.null(v) || v == "" || trimws(v) == "" ||
    startsWith(trimws(v), "<!--")

  df |>
    mutate(
      n_chars = nchar(wikitext),
      n_citations = map_int(wikitext, count_citations),
      n_refs = map_int(wikitext, count_refs),
      infobox_raw = map(wikitext, \(w) {
        if (is.na(w)) return(NULL)
        extract_infobox(w)
      }),
      has_infobox = !map_lgl(infobox_raw, is.null),
      n_infobox_fields = map_int(infobox_raw, \(ib) {
        if (is.null(ib)) return(0L)
        sum(!map_lgl(ib, is_blank))
      }),
      infobox_field_names = map(infobox_raw, \(ib) {
        if (is.null(ib)) return(character(0))
        nms <- names(ib)[!map_lgl(ib, is_blank)]
        str_to_lower(str_replace_all(nms, "\\s+", "_"))
      }),
      # Population presence and recency from the infobox
      .infobox_pop    = map(infobox_raw, extract_infobox_population),
      infobox_pop_value = map_chr(.infobox_pop, \(p) p$pop_value),
      infobox_pop_year  = map_int(.infobox_pop, \(p) {
        if (is.na(p$pop_year)) NA_integer_ else p$pop_year
      })
    ) |>
    select(-infobox_raw, -.infobox_pop)
}


# ---- Summarise infobox field coverage ----------------------------------------

#' Compute field frequency table from article quality data
#'
#' @param quality_df tibble with infobox_field_names list-column
#' @param group_vars Optional grouping variables (e.g. "lang", "country")
#' @return tibble of field frequencies
summarise_infobox_coverage <- function(quality_df, group_vars = NULL) {
  if (!is.null(group_vars)) {
    quality_df |>
      group_by(across(all_of(group_vars))) |>
      summarise(
        n_articles = n(),
        n_with_infobox = sum(has_infobox, na.rm = TRUE),
        median_fields = median(n_infobox_fields, na.rm = TRUE),
        mean_fields = round(mean(n_infobox_fields, na.rm = TRUE), 1),
        .groups = "drop"
      )
  } else {
    all_fields <- quality_df |>
      filter(has_infobox) |>
      pull(infobox_field_names) |>
      unlist()

    n_articles <- sum(quality_df$has_infobox, na.rm = TRUE)

    tibble(field = all_fields) |>
      count(field, sort = TRUE) |>
      mutate(pct = round(100 * n / n_articles, 1))
  }
}


# ---- Full pipeline wrapper ---------------------------------------------------

#' Run the full article quality pipeline for a set of presence cache files
#'
#' @param cache_files Named character vector of RDS cache file paths
#'   (names are slugs like "bolivia_muni")
#' @param languages Character vector of language codes to analyze
#' @param wikitext_cache_base Base directory for wikitext files
#' @param quality_cache_file RDS file to cache the final quality data
#' @param delay Delay between API calls
#' @return tibble of article quality metrics
run_article_quality_pipeline <- function(cache_files,
                                          languages,
                                          wikitext_cache_base,
                                          quality_cache_file = NULL,
                                          delay = 0.5) {
  # Check for cached result; invalidate if new columns are missing
  required_cols <- c("infobox_pop_value", "infobox_pop_year")
  if (!is.null(quality_cache_file) && file.exists(quality_cache_file)) {
    cached <- readRDS(quality_cache_file)
    if (all(required_cols %in% names(cached))) {
      message("Loading cached article quality data from ", quality_cache_file)
      return(cached)
    }
    message("Cache at ", quality_cache_file,
            " is missing columns: ",
            paste(setdiff(required_cols, names(cached)), collapse = ", "),
            ". Re-running pipeline.")
  }

  message("Step 1: Extracting article titles from ", length(cache_files),
          " cache files for languages: ", paste(languages, collapse = ", "))
  titles_df <- extract_article_titles_from_cache(cache_files, languages)
  message("  Found ", nrow(titles_df), " article titles")

  if (nrow(titles_df) == 0) {
    message("No articles found. Returning empty tibble.")
    return(tibble())
  }

  message("Step 2: Fetching wikitext (", nrow(titles_df), " articles)...")
  titles_df <- fetch_wikitext_batch(titles_df, wikitext_cache_base, delay = delay)

  # Drop articles where wikitext fetch failed
  n_missing <- sum(is.na(titles_df$wikitext))
  if (n_missing > 0) {
    message("  ", n_missing, " articles had no wikitext (page missing or error)")
  }
  titles_with_text <- titles_df |> filter(!is.na(wikitext))

  message("Step 3: Computing quality metrics for ", nrow(titles_with_text),
          " articles...")
  quality_df <- compute_article_quality(titles_with_text)

  if (!is.null(quality_cache_file)) {
    saveRDS(quality_df, quality_cache_file)
    message("Saved article quality data to ", quality_cache_file)
  }

  quality_df
}
