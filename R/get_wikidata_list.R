# ---- .resolve_property_names ------------------------------------------------
# Internal helper: resolve and pad/truncate property_names vectors to match
# the length of the property vector, issuing warnings if requested.

.resolve_property_names <- function(props, names, type_label = "property") {
  if (is.null(props) || length(props) == 0) return(NULL)

  props <- as.character(props)
  n_prop <- length(props)

  if (is.null(names)) {
    names <- props
  }

  n_names <- length(names)

  if (n_names > n_prop) {
    if (type_label == "property") {
      message("property_names has more entries (", n_names, ") than property (",
              n_prop, "); extra names will be ignored.")
    }
    names <- names[seq_len(n_prop)]
  } else if (n_names < n_prop) {
    if (n_names > 0 && type_label == "property") {
      message("property_names has fewer entries (", n_names, ") than property (",
              n_prop, "); falling back to property IDs for unnamed columns.")
    }
    names <- c(names, props[(n_names + 1):n_prop])
  }

  names
}

# ---- .validate_entity_props -------------------------------------------------
# Internal helper: Ensure that entity_props includes 'claims' when properties
# are requested.

.validate_entity_props <- function(property, numeric_list_properties, entity_props) {
  if (!is.null(property) && length(property) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("property=... requires entity_props to include 'claims' (so we can read property values).")
  }
  if (!is.null(numeric_list_properties) && length(numeric_list_properties) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("numeric_list_properties requires entity_props to include 'claims'.")
  }
}

# ---- get_listed_wikidata_items -----------------------------------------------

#' Get Details for a List of Wikidata QIDs
#'
#' Retrieves labels, descriptions, optional extra properties,
#' instance-of/subclass-of statements, and Wikipedia articles for a given
#' vector of QIDs.
#'
#' Items are fetched from the Wikidata API in batches of \code{batch_size}
#' (default 50, the API maximum) to avoid rate-limiting errors.
#'
#' @param qid_list Character vector. A list of Wikidata QIDs (e.g., c("Q1", "Q2")).
#'   `NA` values are automatically removed.
#' @param property Character or character vector. Optional property ID(s) to
#'   retrieve as additional columns. Default is \code{NULL}.
#' @param property_names Character vector. Column names to use for extra properties.
#' @param languages Character vector. Language codes for labels and descriptions.
#'   Default is c("en", "es").
#' @param batch_size Integer. Number of items per API request (max 50).
#' @param batch_delay Numeric. Seconds to wait between batches. Default is 1.
#' @param numeric_list_properties Character vector of property IDs to treat as
#'   quantity statements with multiple claims over time.
#' @param numeric_list_property_names Character vector. Column name prefixes
#'   for each entry in \code{numeric_list_properties}.
#' @param entity_props Character. Pipe-separated list of Wikidata entity props.
#'   Default is "labels|descriptions|claims|sitelinks".
#' @param object_type Character. Either "instance" (default) or "subclass" to
#'   indicate how the hierarchy structure should be parsed from P31/P279.
#'
#' @return A tibble with columns for qid, labels, descriptions, properties, etc.
#'
#' @examples
#' get_listed_wikidata_items(c("Q250050", "Q1062710", NA))
#'
#' @export
get_listed_wikidata_items <- function(qid_list,
                                      property                    = NULL,
                                      property_names              = NULL,
                                      languages                   = c("en", "es"),
                                      batch_size                  = 50,
                                      batch_delay                 = 1,
                                      numeric_list_properties     = NULL,
                                      numeric_list_property_names = NULL,
                                      entity_props                = "labels|descriptions|claims|sitelinks",
                                      object_type                 = "instance") {

  # Validate object_type
  if (!object_type %in% c("instance", "subclass")) {
    stop('object_type must be "instance" or "subclass"')
  }

  # Clean up and validate qid_list
  qid_list <- as.character(na.omit(qid_list))
  if (length(qid_list) == 0) {
    message("qid_list is empty or only contains NAs.")
    return(tibble())
  }

  invalid_qids <- qid_list[!grepl("^Q\\d+$", qid_list)]
  if (length(invalid_qids) > 0) {
    stop("All items in qid_list must be in format 'Q123'. Invalid examples: ",
         paste(head(invalid_qids, 3), collapse = ", "))
  }

  batch_size <- min(as.integer(batch_size), 50L)

  # Resolve property names and validate props using shared helpers
  property_names <- .resolve_property_names(property, property_names, "property")
  numeric_list_property_names <- .resolve_property_names(
    numeric_list_properties, numeric_list_property_names, "numeric_list"
  )
  .validate_entity_props(property, numeric_list_properties, entity_props)

  message("Found ", length(qid_list), " valid QIDs. Retrieving details in batches of ",
          batch_size, "...")

  # Fetch in batches
  items_data <- .fetch_qids_in_batches(
    qids = qid_list,
    property = property,
    property_names = property_names,
    languages = languages,
    batch_size = batch_size,
    batch_delay = batch_delay,
    numeric_list_properties = numeric_list_properties,
    numeric_list_property_names = numeric_list_property_names,
    entity_props = entity_props,
    object_type = object_type
  )

  # Convert to tibble and simplify single-value list columns
  result_df <- bind_rows(items_data) |> simplify_list_columns()

  message("Successfully retrieved ", nrow(result_df), " items")
  result_df
}

# ---- get_wikidata_instances --------------------------------------------------

#' Get All Instances of a Wikidata Class
#' (documentation remains identical...)
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
                                   entity_props                = "labels|descriptions|claims|sitelinks",
                                   object_type                 = "instance") {

  # Validate object_type
  if (!object_type %in% c("instance", "subclass")) {
    stop('object_type must be "instance" or "subclass"')
  }

  # Use shared helpers for property resolution and validation
  property_names <- .resolve_property_names(property, property_names, "property")
  numeric_list_property_names <- .resolve_property_names(
    numeric_list_properties, numeric_list_property_names, "numeric_list"
  )
  .validate_entity_props(property, numeric_list_properties, entity_props)

  # Validate input
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  if (!is.null(country) && !grepl("^Q\\d+$", country))
    stop("country must be in format 'Q123'")
  batch_size <- min(as.integer(batch_size), 50L)

  # Determine property ID and message suffix
  property_id <- if (object_type == "instance") "P31" else "P279"
  type_label <- if (object_type == "instance") "instances" else "subclasses"

  # Step 1: SPARQL — get all QIDs
  qids <- .sparql_get_qids(class_qid, country, limit, property_id)

  if (length(qids) == 0) {
    message("No ", type_label, " found for ", class_qid)
    return(tibble())
  }

  message("Found ", length(qids), " ", type_label, ". Retrieving details in batches of ",
          batch_size, "...")

  # Step 2: fetch in batches
  items_data <- .fetch_qids_in_batches(
    qids, property, property_names, languages, batch_size, batch_delay,
    numeric_list_properties, numeric_list_property_names,
    entity_props = entity_props,
    object_type = object_type
  )

  # Convert to tibble and simplify single-value list columns
  result_df <- bind_rows(items_data) |> simplify_list_columns()

  message("Successfully retrieved ", nrow(result_df), " items")
  result_df
}

# ---- resume_get_wikidata_instances -------------------------------------------

#' Resume a Partially-Completed get_wikidata_instances() Query
#' (documentation remains identical...)
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
                                          entity_props                = "labels|descriptions|claims|sitelinks",
                                          object_type                 = "instance") {

  if (!"qid" %in% names(partial_result))
    stop("partial_result must contain a 'qid' column")
  if (!grepl("^Q\\d+$", class_qid))
    stop("class_qid must be in format 'Q123'")
  if (!object_type %in% c("instance", "subclass"))
    stop('object_type must be "instance" or "subclass"')
  batch_size <- min(as.integer(batch_size), 50L)

  # Use shared helpers for property resolution and validation
  property_names <- .resolve_property_names(property, property_names, "property")
  numeric_list_property_names <- .resolve_property_names(
    numeric_list_properties, numeric_list_property_names, "numeric_list"
  )
  .validate_entity_props(property, numeric_list_properties, entity_props)

  # Determine property ID
  property_id <- if (object_type == "instance") "P31" else "P279"
  type_label <- if (object_type == "instance") "instances" else "subclasses"

  # Step 1: re-run SPARQL to get the complete QID list
  message("Re-running SPARQL query for ", class_qid, "...")
  all_qids <- .sparql_get_qids(class_qid, country, limit, property_id)

  if (length(all_qids) == 0) {
    message("No ", type_label, " found for ", class_qid)
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
    entity_props = entity_props,
    object_type = object_type
  )

  # Simplify each half before binding so column types match
  new_df <- bind_rows(new_items) |> simplify_list_columns()

  combined <- bind_rows(partial_result, new_df) |>
    distinct(qid, .keep_all = TRUE)

  message("Resume complete. Total items: ", nrow(combined))
  combined
}
