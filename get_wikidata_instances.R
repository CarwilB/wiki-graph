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
      if (is.data.frame(dv)) {
        # Entity/item type: return the QID
        as.character(dv$id)
      } else if (is.character(dv)) {
        # String / external-id / url
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

# ---- .parse_entity -----------------------------------------------------------
# Internal helper: parse a single Wikidata entity object into a named list
# suitable for bind_rows(). Used by get_wikidata_instances() and
# resume_get_wikidata_instances().

.parse_entity <- function(entity, qid, property, property_names, languages) {

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
      vals  <- if (pid %in% names(entity$claims)) {
        p_df <- entity$claims[[pid]]
        if (nrow(p_df) > 0) {
          map_chr(seq_len(nrow(p_df)), function(j) {
            dv <- p_df$mainsnak[j, ]$datavalue[[1]]
            if (is.data.frame(dv) && "amount" %in% names(dv)) {
              sub("^\\+", "", dv$amount)          # quantity: strip leading "+", keep as char for now
            } else if (is.data.frame(dv)) {
              as.character(dv$id)                  # entity/item value
            }
          })
        } else character(0)
      } else character(0)
      setNames(list(list(vals)), pname)
    })
    unlist(prop_values, recursive = FALSE)
  } else list()

  # Extract all P31 (instance of) statements
  instance_of <- if ("P31" %in% names(entity$claims)) {
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
                                   batch_size = 50, batch_delay = 1) {

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
          props  = "labels|descriptions|claims|sitelinks"
        ),
        user_agent("WikidataR-instances-retrieval")
      )

      item_data <- fromJSON(content(api_response, "text", encoding = "UTF-8"))
      entities  <- item_data$entities

      for (qid in batch) {
        entity <- entities[[qid]]
        if (is.null(entity) || isTRUE(entity$missing == "")) {
          message("  Item ", qid, " missing or not found; skipping.")
          all_parsed[[idx]] <- NULL
        } else {
          all_parsed[[idx]] <- tryCatch(
            .parse_entity(entity, qid, property, property_names, languages),
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
#' (default 50, the API maximum) to avoid rate-limiting errors that occur
#' when retrieving hundreds of items one-by-one.
#'
#' @param class_qid Character. The Wikidata QID of the class (e.g., "Q250050")
#' @param property Character or character vector. Optional property ID(s) to
#'   retrieve as additional columns (e.g., \code{"P131"} or
#'   \code{c("P131", "P17")}). Default is \code{NULL}.
#' @param property_names Character vector. Column names to use for the extra
#'   properties. If shorter than \code{property}, missing names fall back to
#'   the property ID. If longer, the extra names are ignored and a message is
#'   issued. Default is \code{NULL} (use property IDs as column names).
#' @param country Character. Optional Wikidata QID of a country (e.g., "Q750"
#'   for Bolivia). When supplied, only instances whose P17 (country) statement
#'   matches this QID are returned. Default is \code{NULL} (no country filter).
#' @param languages Character vector. Language codes for labels and descriptions.
#'   Default is c("en", "es").
#' @param limit Integer. Maximum number of results to return. Default is 1000.
#' @param batch_size Integer. Number of items per API request (max 50).
#'   Default is 50.
#' @param batch_delay Numeric. Seconds to wait between batches. Default is 1.
#'
#' @return A tibble with columns:
#'   - qid: Item QID
#'   - label_XX: Label in each requested language
#'   - description_XX: Description in each requested language
#'   - One list column per entry in \code{property} (named by \code{property_names})
#'   - instance_of: List column of all P31 values
#'   - wikipedia_articles: List column of Wikipedia sitelinks
#'
#' @examples
#' get_wikidata_instances("Q250050", languages = c("en", "es"))
#'
#' get_wikidata_instances("Q1062593",
#'                        property = c("P131", "P31"),
#'                        property_names = c("located_in", "instance_of"))
#'
#' @export
get_wikidata_instances <- function(class_qid,
                                   property       = NULL,
                                   property_names = NULL,
                                   country        = NULL,
                                   languages      = c("en", "es"),
                                   limit          = 1000,
                                   batch_size     = 50,
                                   batch_delay    = 1,
                                   numeric_properties = NULL) {
  numeric_properties <- as.character(numeric_properties)  # handles length-1 string

  # Resolve column names for extra properties
  if (!is.null(property)) {
    n_prop  <- length(property)
    n_names <- length(property_names)

    if (n_names > n_prop) {
      message("property_names has more entries (", n_names, ") than property (",
              n_prop, "); extra names will be ignored.")
      property_names <- property_names[seq_len(n_prop)]
    } else if (n_names < n_prop) {
      if (n_names > 0) {
        message("property_names has fewer entries (", n_names, ") than property (",
                n_prop, "); falling back to property IDs for unnamed columns.")
      }
      property_names <- c(property_names, property[(n_names + 1):n_prop])
    }
  }

  # Validate input
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  if (!is.null(country) && !grepl("^Q\\d+$", country))
    stop("country must be in format 'Q123'")
  batch_size <- min(as.integer(batch_size), 50L)

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
    qids, property, property_names, languages, batch_size, batch_delay
  )

  # Convert to tibble and simplify single-value list columns
  result_df <- bind_rows(items_data) |> simplify_list_columns()

  # Coerce declared numeric columns from character to numeric
  for (nm in numeric_properties) {
    if (nm %in% names(result_df))
      result_df[[nm]] <- as.numeric(result_df[[nm]])
  }

  message("Successfully retrieved ", nrow(result_df), " items")
  result_df
}

# ---- resume_get_wikidata_instances -------------------------------------------

#' Resume a Partially-Completed get_wikidata_instances() Query
#'
#' Use this when \code{get_wikidata_instances()} was interrupted part-way
#' through (e.g. due to a network error or rate-limit rejection) and you have
#' a partial result. The function re-runs the SPARQL query to obtain the full
#' QID list, skips any QIDs already present in \code{partial_result}, fetches
#' the remainder in batches, then returns the combined, de-duplicated tibble.
#'
#' @param partial_result A tibble previously returned (or partially returned)
#'   by \code{get_wikidata_instances()}. Must contain a \code{qid} column.
#' @param class_qid Character. Same value used in the original call.
#' @param property Character vector. Same value used in the original call.
#' @param property_names Character vector. Same value used in the original call.
#' @param country Character. Same value used in the original call.
#' @param languages Character vector. Same value used in the original call.
#' @param limit Integer. Same value used in the original call. Default 1000.
#' @param batch_size Integer. Items per API request (max 50). Default 50.
#' @param batch_delay Numeric. Seconds between batches. Default 1.
#'
#' @return A tibble with the same columns as \code{get_wikidata_instances()},
#'   containing all items (previously retrieved + newly fetched).
#'
#' @examples
#' # Original call was interrupted:
#' # municipalities_wd <- get_wikidata_instances("Q1062710", c("P131","P17"),
#' #                                              c("located_in","country"))
#' # Resume with what was saved:
#' municipalities_wd <- resume_get_wikidata_instances(
#'   municipalities_wd, "Q1062710",
#'   property       = c("P131", "P17"),
#'   property_names = c("located_in", "country")
#' )
#'
#' @export
resume_get_wikidata_instances <- function(partial_result,
                                          class_qid,
                                          property       = NULL,
                                          property_names = NULL,
                                          country        = NULL,
                                          languages      = c("en", "es"),
                                          limit          = 1000,
                                          batch_size     = 50,
                                          batch_delay    = 1) {

  if (!"qid" %in% names(partial_result))
    stop("partial_result must contain a 'qid' column")
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  batch_size <- min(as.integer(batch_size), 50L)

  # Resolve property names the same way as get_wikidata_instances()
  if (!is.null(property)) {
    n_prop  <- length(property)
    n_names <- length(property_names)
    if (n_names > n_prop) {
      property_names <- property_names[seq_len(n_prop)]
    } else if (n_names < n_prop) {
      property_names <- c(property_names, property[(n_names + 1):n_prop])
    }
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
    remaining, property, property_names, languages, batch_size, batch_delay
  )

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
