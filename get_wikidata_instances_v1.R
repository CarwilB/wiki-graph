# ---- add_wikidata_property --------------------------------------------------

#' Add a Wikidata Property to a Data Frame
#'
#' Fetches a single-valued property from Wikidata and appends it as a new
#' column to a data frame that contains a `qid` column. Handles entity-type,
#' string, and time values. Issues a message when an item has multiple
#' statements for the requested property.
#'
#' @param df A data frame with a `qid` column.
#' @param property Character. Wikidata property ID (e.g., "P14142").
#' @param name Character. Name of the new column. Defaults to the property ID.
#'
#' @return The input data frame with a new character column appended.
#'
#' @examples
#' departments |> add_wikidata_property("P14142", name = "ine_code")
add_wikidata_property <- function(df, property, name = property) {

  if (!"qid" %in% names(df)) stop("df must contain a 'qid' column")
  if (!grepl("^P\\d+$", property)) stop("property must be in format 'P123'")

  qids <- df$qid

  values <- map_chr(qids, function(qid) {
    Sys.sleep(0.1)

    tryCatch({
      r <- GET(
        "https://www.wikidata.org/w/api.php",
        query = list(
          action = "wbgetentities",
          ids = qid,
          format = "json",
          props = "claims"
        )
      )

      entity <- fromJSON(content(r, "text", encoding = "UTF-8"))$entities[[qid]]
      claims <- entity$claims[[property]]

      if (is.null(claims) || nrow(claims) == 0) {
        return(NA_character_)
      }

      if (nrow(claims) > 1) {
        message(qid, " has ", nrow(claims), " values for ", property,
                "; using the first (rank: ", claims$rank[1], ")")
      }

      snak <- claims$mainsnak[1, ]
      dv   <- snak$datavalue[[1]]

      # Dispatch on value type
      if (is.data.frame(dv) && "amount" %in% names(dv)) {
        sub("^\\+", "", dv$amount[[1]])
      } else if (is.data.frame(dv)) {
        as.character(dv$id)
      } else if (is.character(dv)) {
        dv
      } else {
        as.character(dv)
      }

    }, error = function(e) {
      message("Error on ", qid, ": ", conditionMessage(e))
      NA_character_
    })
  })

  df[[name]] <- values
  df
}

# ---- .extract_numeric_list_property -----------------------------------------
# Internal helper: extract all claims for a single quantity property from one
# entity, including per-claim year (P585 qualifier) and reference (P854 URL
# or P248 "stated in" QID). Returns a flat named list of scalars suitable for
# inclusion in a bind_rows() record.
#
# Output columns for pname = "population", max_vals = 10:
#   population         — most recent value (numeric; sorted by year desc, NAs last)
#   population_n       — total number of claims (integer)
#   population_1       — value of claim 1 (numeric)
#   population_1_year  — year of claim 1 (integer, from P585, or NA)
#   population_1_ref   — reference of claim 1 (character URL or "wd:Qxxx", or NA)
#   ... up to population_10 / population_10_year / population_10_ref

.extract_numeric_list_property <- function(entity, pid, pname, max_vals = 10) {

  # All-NA result returned when property is absent or empty
  empty_result <- function() {
    out <- list()
    out[[pname]]               <- NA_real_
    out[[paste0(pname, "_n")]] <- 0L
    for (i in seq_len(max_vals)) {
      out[[paste0(pname, "_", i)]]          <- NA_real_
      out[[paste0(pname, "_", i, "_year")]] <- NA_integer_
      out[[paste0(pname, "_", i, "_ref")]]  <- NA_character_
    }
    out
  }

  if (!pid %in% names(entity$claims)) return(empty_result())
  claims_df <- entity$claims[[pid]]
  if (is.null(claims_df) || nrow(claims_df) == 0) return(empty_result())

  n_claims <- nrow(claims_df)

  # Extract (amount, year, ref) for each claim row
  records <- lapply(seq_len(n_claims), function(i) {

    # ---- amount ----
    amount <- tryCatch({
      dv <- claims_df$mainsnak[i, ]$datavalue[[1]]
      if (is.data.frame(dv) && "amount" %in% names(dv))
        as.numeric(sub("^\\+", "", dv$amount[[1]]))
      else NA_real_
    }, error = function(e) NA_real_)

    # ---- year from P585 (point in time) qualifier ----
    year <- tryCatch({
      qual <- claims_df$qualifiers[[i]]
      if (!is.null(qual) && "P585" %in% names(qual)) {
        p585_df  <- qual[["P585"]]
        dv       <- p585_df$datavalue[[1]]
        # fromJSON() may produce a list (with $value$time) or a data frame
        time_str <- if (is.list(dv) && !is.data.frame(dv)) {
          dv$value$time
        } else if (is.data.frame(dv) && "time" %in% names(dv)) {
          dv$time[[1]]
        } else NULL
        if (!is.null(time_str) && !is.na(time_str))
          as.integer(regmatches(time_str, regexpr("\\d{4}", time_str)))
        else NA_integer_
      } else NA_integer_
    }, error = function(e) NA_integer_)

    # ---- ref: prefer P854 (reference URL), fallback P248 (stated in) ----
    ref <- tryCatch({
      refs <- claims_df$references[[i]]
      if (!is.null(refs) && length(refs) > 0) {
        snaks <- refs[[1]]$snaks
        if (!is.null(snaks) && "P854" %in% names(snaks)) {
          # P854 is a URL string value
          dv <- snaks[["P854"]][[1]]$datavalue[[1]]
          if (is.character(dv))    dv
          else if (is.list(dv))   as.character(dv$value)
          else                    NA_character_
        } else if (!is.null(snaks) && "P248" %in% names(snaks)) {
          # P248 is an entity value
          dv  <- snaks[["P248"]][[1]]$datavalue[[1]]
          qid_val <- if (is.data.frame(dv) && "id" %in% names(dv)) dv$id[[1]]
                     else if (is.list(dv))                          dv$value$id
                     else                                           NA_character_
          if (!is.null(qid_val) && !is.na(qid_val)) paste0("wd:", qid_val)
          else NA_character_
        } else NA_character_
      } else NA_character_
    }, error = function(e) NA_character_)

    list(amount = amount, year = year, ref = ref)
  })

  # Sort by year descending, NAs last
  years <- sapply(records, function(r) if (is.null(r$year) || is.na(r$year)) NA_integer_ else r$year)
  ord   <- order(is.na(years), -ifelse(is.na(years), 0L, years))
  records <- records[ord]
  n <- length(records)

  # Build the flat output list
  out <- list()
  out[[pname]]               <- records[[1]]$amount   # most recent
  out[[paste0(pname, "_n")]] <- n

  for (i in seq_len(max_vals)) {
    if (i <= n) {
      out[[paste0(pname, "_", i)]]          <- records[[i]]$amount
      out[[paste0(pname, "_", i, "_year")]] <- records[[i]]$year
      out[[paste0(pname, "_", i, "_ref")]]  <- records[[i]]$ref
    } else {
      out[[paste0(pname, "_", i)]]          <- NA_real_
      out[[paste0(pname, "_", i, "_year")]] <- NA_integer_
      out[[paste0(pname, "_", i, "_ref")]]  <- NA_character_
    }
  }

  out
}

# ---- .parse_entity -----------------------------------------------------------
# Internal helper: parse a single Wikidata entity object into a named list
# suitable for bind_rows(). Used by get_wikidata_instances() and
# resume_get_wikidata_instances().

.parse_entity <- function(entity, qid, property, property_names, languages,
                           numeric_list_properties     = NULL,
                           numeric_list_property_names = NULL) {

  # Extract labels
  labels_list <- map(languages, function(lang) {
    if (lang %in% names(entity$labels)) entity$labels[[lang]]$value
    else NA_character_
  })
  names(labels_list) <- paste0("label_", languages)

  # Extract descriptions
  descriptions_list <- map(languages, function(lang) {
    if (lang %in% names(entity$descriptions)) entity$descriptions[[lang]]$value
    else NA_character_
  })
  names(descriptions_list) <- paste0("description_", languages)

  # Extract extra properties as list columns
  extra_props <- if (!is.null(property)) {
    prop_values <- map(seq_along(property), function(i) {
      pid   <- property[i]
      pname <- property_names[i]
      vals  <- if ("claims" %in% names(entity) && pid %in% names(entity$claims)) {
        p_df <- entity$claims[[pid]]
        if (nrow(p_df) > 0) {
          map_chr(seq_len(nrow(p_df)), function(j) {
            dv <- p_df$mainsnak[j, ]$datavalue[[1]]
            if (is.data.frame(dv) && "amount" %in% names(dv)) {
              sub("^\\+", "", dv$amount[[1]])   # quantity: strip leading "+"
            } else if (is.data.frame(dv)) {
              as.character(dv$id)               # entity/item value
            } else if (is.character(dv)) {
              dv                                # plain string / URL
            } else {
              as.character(dv)
            }
          })
        } else character(0)
      } else character(0)
      setNames(list(list(vals)), pname)
    })
    unlist(prop_values, recursive = FALSE)
  } else list()

  # Extract numeric list properties (multi-value quantities with year + ref)
  numeric_list_cols <- if (!is.null(numeric_list_properties)) {
    if (!"claims" %in% names(entity)) {
      stop("numeric_list_properties requested but entity has no 'claims' (did you request props without 'claims'?)")
    }
    result <- list()
    for (i in seq_along(numeric_list_properties)) {
      extracted <- .extract_numeric_list_property(
        entity,
        pid   = numeric_list_properties[i],
        pname = numeric_list_property_names[i]
      )
      result <- c(result, extracted)
    }
    result
  } else list()

  # Extract all P31 (instance of) statements
  instance_of <- if ("claims" %in% names(entity) && "P31" %in% names(entity$claims)) {
    p31_df <- entity$claims$P31
    if (nrow(p31_df) > 0) {
      map_chr(seq_len(nrow(p31_df)), function(i) {
        p31_df$mainsnak[i, ]$datavalue[[1]]$id
      })
    } else character(0)
  } else character(0)

  # Extract Wikipedia sitelinks
  wiki_articles <- if (!is.null(entity$sitelinks) && length(entity$sitelinks) > 0) {
    site_names <- names(entity$sitelinks)
    articles <- map_chr(site_names, function(site) {
      if (grepl("wiki$", site) && !grepl("wikivoyage|wikiquote|wikibooks", site)) {
        lang_code <- str_replace(site, "wiki$", "")
        title <- entity$sitelinks[[site]]$title
        if (!is.null(title)) paste0(lang_code, ": ", title) else NA_character_
      } else NA_character_
    })
    articles[!is.na(articles)]
  } else character(0)

  c(
    list(qid = qid),
    labels_list,
    descriptions_list,
    extra_props,
    numeric_list_cols,
    list(
      instance_of        = list(instance_of),
      wikipedia_articles = list(wiki_articles)
    )
  )
}

# ---- .fetch_qids_in_batches --------------------------------------------------
# Internal helper: fetch a vector of QIDs from wbgetentities in batches of
# `batch_size` (max 50), with `batch_delay` seconds between batches.
# Returns a list of parsed entity records suitable for bind_rows().

.fetch_qids_in_batches <- function(qids, property, property_names, languages,
                                   batch_size = 50, batch_delay = 1,
                                   numeric_list_properties     = NULL,
                                   numeric_list_property_names = NULL) {
  batches    <- split(qids, ceiling(seq_along(qids) / batch_size))
  n_batches  <- length(batches)
  api_url    <- "https://www.wikidata.org/w/api.php"
  all_parsed <- vector("list", length(qids))
  idx        <- 1L

  for (b in seq_along(batches)) {
    batch <- batches[[b]]
    message("  Batch ", b, "/", n_batches,
            " (", length(batch), " items)...")

    tryCatch({
      api_response <- GET(
        url   = api_url,
        query = list(
          action = "wbgetentities",
          ids    = paste(batch, collapse = "|"),
          format = "json",
          props  = entity_props
        ),
        user_agent("WikidataR-instances-retrieval")
      )

      item_data <- fromJSON(content(api_response, "text", encoding = "UTF-8"))
      entities  <- item_data$entities
      if (any(batch %in% c("Q32","Q33","Q38","Q228"))) {
        message("DEBUG status_code: ", httr::status_code(api_response))
        txt <- httr::content(api_response, "text", encoding="UTF-8")
        message("DEBUG first 200 chars: ", substr(txt, 1, 200))
        message("DEBUG has entities names? ", !is.null(names(entities)))
        message("DEBUG entities name sample: ", paste(head(names(entities), 20), collapse=","))
        message("DEBUG Q32 in names(entities): ", "Q32" %in% names(entities))
      }

      for (qid in batch) {
        entity <- entities[[qid]]
        if (qid %in% c("Q32","Q33","Q38", "Q228", "Q252")) {
          message("DEBUG ", qid, " names(entity) = ", paste(names(entity), collapse=","))
          message("DEBUG ", qid, " class(entity) = ", paste(class(entity), collapse=","))
          message("DEBUG ", qid, " missing field is: ", paste(capture.output(str(entity$missing)), collapse=" "))
        }
        missing_flag <- is.null(entity) || (is.list(entity) &&
                                              "missing" %in% names(entity))
        if (missing_flag) {
          message("  Item ", qid, " missing or not found; skipping.")
          all_parsed[[idx]] <- NULL
        } else {
          all_parsed[[idx]] <- tryCatch(
            .parse_entity(entity, qid, property, property_names, languages,
                          numeric_list_properties, numeric_list_property_names),
            error = function(e) {
              message("  Error parsing ", qid, ": ", e$message)
              NULL
            }
          )
        }
        idx <- idx + 1L
      }
    }, error = function(e) {
      message("  Batch ", b, " failed: ", e$message,
              "\n  Items in batch: ", paste(batch, collapse = ", "))
      for (qid in batch) {
        all_parsed[[idx]] <<- NULL
        idx <<- idx + 1L
      }
    })

    if (b < n_batches) Sys.sleep(batch_delay)
  }

  compact(all_parsed)
}

# ---- .sparql_get_qids --------------------------------------------------------
# Internal helper: run the SPARQL query and return a character vector of QIDs.

.sparql_get_qids <- function(class_qid, country, limit) {
  country_triple <- if (!is.null(country)) {
    sprintf("  ?item wdt:P17 wd:%s .\n", country)
  } else ""

  sparql_query <- sprintf(
    'SELECT DISTINCT ?item WHERE {\n  ?item wdt:P31 wd:%s .\n%s}\nLIMIT %d\n',
    class_qid, country_triple, limit
  )

  response <- GET(
    url   = "https://query.wikidata.org/sparql",
    query = list(query = sparql_query, format = "json"),
    user_agent("WikidataR-instances-retrieval")
  )

  if (status_code(response) != 200) {
    stop("SPARQL query failed with status: ", status_code(response))
  }

  results <- fromJSON(content(response, "text", encoding = "UTF-8"))

  if (length(results$results$bindings) == 0) {
    return(character(0))
  }

  str_extract(results$results$bindings$item$value, "Q\\d+$")
}

# ---- get_wikidata_instances --------------------------------------------------

#' Get All Instances of a Wikidata Class
#'
#' Retrieves all instances (P31) of a given class from Wikidata with their
#' labels, descriptions, optional extra properties, instance-of statements,
#' and Wikipedia articles.
#'
#' Items are fetched from the Wikidata API in batches of \code{batch_size}
#' (default 50, the API maximum) to avoid rate-limiting errors.
#'
#' @param class_qid Character. The Wikidata QID of the class (e.g., "Q250050")
#' @param property Character or character vector. Optional property ID(s) to
#'   retrieve as additional columns (e.g., \code{"P131"} or
#'   \code{c("P131", "P17")}). Default is \code{NULL}.
#' @param property_names Character vector. Column names to use for the extra
#'   properties. Default is \code{NULL} (use property IDs as column names).
#' @param country Character. Optional Wikidata QID of a country (e.g., "Q750"
#'   for Bolivia). Default is \code{NULL} (no country filter).
#' @param languages Character vector. Language codes for labels and descriptions.
#'   Default is c("en", "es").
#' @param limit Integer. Maximum number of results to return. Default is 1000.
#' @param batch_size Integer. Number of items per API request (max 50).
#'   Default is 50.
#' @param batch_delay Numeric. Seconds to wait between batches. Default is 1.
#' @param numeric_list_properties Character vector of property IDs (e.g.,
#'   \code{"P1082"}) whose values are Wikidata quantity statements that may
#'   have multiple claims (e.g. population figures across years). These must
#'   NOT also appear in \code{property}. For each property named \code{pname}
#'   in \code{numeric_list_property_names}, the following columns are added:
#'   \describe{
#'     \item{pname}{Most recent value (numeric; sorted by P585 year desc).}
#'     \item{pname_n}{Total number of claims (integer).}
#'     \item{pname_1 … pname_10}{Individual values (numeric).}
#'     \item{pname_1_year … pname_10_year}{Year from P585 qualifier (integer).}
#'     \item{pname_1_ref … pname_10_ref}{Reference URL (P854) or
#'       \code{"wd:Qxxx"} (P248), or \code{NA} (character).}
#'   }
#' @param numeric_list_property_names Character vector. Column name prefixes
#'   for each entry in \code{numeric_list_properties}. Defaults to the
#'   property IDs if \code{NULL}.
#' @param entity_props Character. Pipe-separated list of Wikidata entity props
#'   to request from \code{wbgetentities} (e.g. "labels|sitelinks"). Default is
#'   "labels|descriptions|claims|sitelinks".
#'
#' @return A tibble with columns as described above.
#'
#' @examples
#' get_wikidata_instances("Q250050", languages = c("en", "es"))
#'
#' get_wikidata_instances(
#'   "Q1062710",
#'   property                    = c("P131", "P17", "P14142"),
#'   property_names              = c("located_in", "country", "ine_code"),
#'   numeric_list_properties     = "P1082",
#'   numeric_list_property_names = "population"
#' )
#'
#' @export
get_wikidata_instances <- function(class_qid,
                                   property                    = NULL,
                                   property_names              = NULL,
                                   country                     = NULL,
                                   languages                   = c("en", "es"),
                                   limit                       = 1000,
                                   batch_size                  = 50,
                                   batch_delay                 = 1,
                                   numeric_list_properties     = NULL,
                                   numeric_list_property_names = NULL,
                                   entity_props                = "labels|descriptions|claims|sitelinks") {

  # Resolve column names for regular extra properties
  if (!is.null(property)) {
    n_prop  <- length(property)
    n_names <- length(property_names)
    if (n_names > n_prop) {
      message("property_names has more entries (", n_names, ") than property (",
              n_prop, "); extra names will be ignored.")
      property_names <- property_names[seq_len(n_prop)]
    } else if (n_names < n_prop) {
      if (n_names > 0)
        message("property_names has fewer entries (", n_names, ") than property (",
                n_prop, "); falling back to property IDs for unnamed columns.")
      property_names <- c(property_names, property[(n_names + 1):n_prop])
    }
  }

  # Resolve column name prefixes for numeric list properties
  numeric_list_properties <- as.character(numeric_list_properties)
  if (length(numeric_list_properties) > 0) {
    if (is.null(numeric_list_property_names))
      numeric_list_property_names <- numeric_list_properties
    n_nlp  <- length(numeric_list_properties)
    n_nlpn <- length(numeric_list_property_names)
    if (n_nlpn < n_nlp)
      numeric_list_property_names <- c(numeric_list_property_names,
                                       numeric_list_properties[(n_nlpn + 1):n_nlp])
    if (n_nlpn > n_nlp)
      numeric_list_property_names <- numeric_list_property_names[seq_len(n_nlp)]
  }

  # Validate input
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  if (!is.null(country) && !grepl("^Q\\d+$", country))
    stop("country must be in format 'Q123'")
  batch_size <- min(as.integer(batch_size), 50L)

  # Validate props requirements based on requested features
  if (!is.null(property) && length(property) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("property=... requires entity_props to include 'claims' (so we can read property values).")
  }
  if (!is.null(numeric_list_properties) && length(numeric_list_properties) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("numeric_list_properties requires entity_props to include 'claims'.")
  }

  # Step 1: SPARQL — get all QIDs
  qids <- .sparql_get_qids(class_qid, country, limit)

  if (length(qids) == 0) {
    message("No instances found for ", class_qid)
    return(tibble())
  }

  message("Found ", length(qids), " instances. Retrieving details in batches of ",
          batch_size, "...")

  # Step 2: fetch in batches
  items_data <- .fetch_qids_in_batches(
    qids, property, property_names, languages, batch_size, batch_delay,
    numeric_list_properties, numeric_list_property_names,
    entity_props = entity_props
  )

  # Convert to tibble and simplify single-value list columns
  result_df <- bind_rows(items_data) |> simplify_list_columns()

  message("Successfully retrieved ", nrow(result_df), " items")
  result_df
}

# ---- resume_get_wikidata_instances -------------------------------------------

#' Resume a Partially-Completed get_wikidata_instances() Query
#'
#' Use this when \code{get_wikidata_instances()} was interrupted part-way
#' through and you have a partial result. Re-runs the SPARQL query to obtain
#' the full QID list, skips already-retrieved QIDs, fetches the remainder in
#' batches, then returns the combined, de-duplicated tibble.
#'
#' @param partial_result A tibble previously returned (or partially returned)
#'   by \code{get_wikidata_instances()}. Must contain a \code{qid} column.
#' @param class_qid Character. Same value used in the original call.
#' @param property Character vector. Same value used in the original call.
#' @param property_names Character vector. Same value used in the original call.
#' @param country Character. Same value used in the original call.
#' @param languages Character vector. Same value used in the original call.
#' @param limit Integer. Default 1000.
#' @param batch_size Integer. Items per API request (max 50). Default 50.
#' @param batch_delay Numeric. Seconds between batches. Default 1.
#' @param numeric_list_properties Character vector. Same value used in the
#'   original call. Default \code{NULL}.
#' @param numeric_list_property_names Character vector. Same value used in the
#'   original call. Default \code{NULL}.
#' @param entity_props Character. Same value used in the original call.
#'   Default "labels|descriptions|claims|sitelinks".
#'
#' @return A tibble with the same columns as \code{get_wikidata_instances()},
#'   containing all items (previously retrieved + newly fetched).
#'
#' @examples
#' municipalities_wd <- resume_get_wikidata_instances(
#'   municipalities_wd, "Q1062710",
#'   property                    = c("P131", "P17", "P14142"),
#'   property_names              = c("located_in", "country", "ine_code"),
#'   numeric_list_properties     = "P1082",
#'   numeric_list_property_names = "population"
#' )
#'
#' @export
resume_get_wikidata_instances <- function(partial_result,
                                          class_qid,
                                          property                    = NULL,
                                          property_names              = NULL,
                                          country                     = NULL,
                                          languages                   = c("en", "es"),
                                          limit                       = 1000,
                                          batch_size                  = 50,
                                          batch_delay                 = 1,
                                          numeric_list_properties     = NULL,
                                          numeric_list_property_names = NULL,
                                          entity_props                = "labels|descriptions|claims|sitelinks") {

  if (!"qid" %in% names(partial_result))
    stop("partial_result must contain a 'qid' column")
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  batch_size <- min(as.integer(batch_size), 50L)

  # Resolve property names
  if (!is.null(property)) {
    n_prop  <- length(property)
    n_names <- length(property_names)
    if (n_names > n_prop)
      property_names <- property_names[seq_len(n_prop)]
    else if (n_names < n_prop)
      property_names <- c(property_names, property[(n_names + 1):n_prop])
  }

  # Resolve numeric list property names
  numeric_list_properties <- as.character(numeric_list_properties)
  if (length(numeric_list_properties) > 0) {
    if (is.null(numeric_list_property_names))
      numeric_list_property_names <- numeric_list_properties
    n_nlp  <- length(numeric_list_properties)
    n_nlpn <- length(numeric_list_property_names)
    if (n_nlpn < n_nlp)
      numeric_list_property_names <- c(numeric_list_property_names,
                                       numeric_list_properties[(n_nlpn + 1):n_nlp])
    if (n_nlpn > n_nlp)
      numeric_list_property_names <- numeric_list_property_names[seq_len(n_nlp)]
  }

  # Validate props requirements
  if (!is.null(property) && length(property) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("property=... requires entity_props to include 'claims'.")
  }
  if (!is.null(numeric_list_properties) && length(numeric_list_properties) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("numeric_list_properties requires entity_props to include 'claims'.")
  }

  # Step 1: re-run SPARQL to get the complete QID list
  message("Re-running SPARQL query for ", class_qid, "...")
  all_qids <- .sparql_get_qids(class_qid, country, limit)

  if (length(all_qids) == 0) {
    message("No instances found for ", class_qid)
    return(partial_result)
  }

  already_done <- partial_result$qid
  remaining    <- setdiff(all_qids, already_done)

  message(length(already_done), " already retrieved, ",
          length(remaining),    " remaining out of ",
          length(all_qids),     " total.")

  if (length(remaining) == 0) {
    message("Nothing left to fetch — returning partial_result as-is.")
    return(partial_result |> simplify_list_columns())
  }

  # Step 2: fetch remaining QIDs in batches
  message("Fetching remaining ", length(remaining), " items in batches of ",
          batch_size, "...")
  new_items <- .fetch_qids_in_batches(
    remaining, property, property_names, languages, batch_size, batch_delay,
    numeric_list_properties, numeric_list_property_names,
    entity_props = entity_props
  )

  # Simplify each half before binding so column types match
  new_df <- bind_rows(new_items) |> simplify_list_columns()

  combined <- bind_rows(partial_result, new_df) |>
    distinct(qid, .keep_all = TRUE)

  message("Resume complete. Total items: ", nrow(combined))
  combined
}

# ---- simplify_list_columns --------------------------------------------------

#' Simplify Single-Value List Columns in a Data Frame
#'
#' Finds list columns where every element contains 0 or 1 values and replaces
#' them with a plain character column: the single value, or \code{NA} for
#' empty elements. List columns with any element containing 2 or more values
#' are left unchanged.
#'
#' @param df A data frame or tibble.
#'
#' @return The input data frame with qualifying list columns converted to
#'   character vectors.
#'
#' @examples
#' simplify_list_columns(departments_wd)
#'
#' @export
simplify_list_columns <- function(df) {
  df |>
    mutate(across(
      where(~ is.list(.) && all(map_int(., length) <= 1)),
      ~ map_chr(., ~ if (length(.) == 0) NA_character_ else as.character(.[[1]]))
    ))
}
