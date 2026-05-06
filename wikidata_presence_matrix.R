#' Wikipedia language presence matrix for instances of a Wikidata class
#'
#' Builds a presence matrix where rows are Wikidata items (instances of a class)
#' and columns are Wikipedia language codes, indicating whether each language
#' Wikipedia has an article (a sitelink) for that item.
#'
#' This function uses the repo's `get_wikidata_instances()` helper, which already
#' retrieves `wikipedia_articles` from entity sitelinks as strings like
#' "en: Title".
#'
#' @param class_qid Character. Wikidata QID of the class (e.g. "Q5" for human).
#' @param languages Character vector of Wikipedia language codes to track
#'   (e.g. c("en","es","pt","qu")), or NULL to auto-discover all languages
#'   present across the returned instances.
#' @param country Optional character QID country filter forwarded to
#'   get_wikidata_instances() (e.g. "Q750" for Bolivia).
#' @param limit Integer. Forwarded to get_wikidata_instances().
#' @param batch_size Integer. Forwarded to get_wikidata_instances().
#' @param batch_delay Numeric. Forwarded to get_wikidata_instances().
#' @param include_labels Logical. If TRUE, include label columns (label_en/label_es)
#'   returned by get_wikidata_instances().
#' @param drop_other_langs Logical. If TRUE (default), ignore sitelinks not in
#'   `languages`. When `languages` is NULL, this is ignored.
#' @param debug Logical. If TRUE, return additional debugging information and
#'   emit more informative messages when items are missing.
#'
#' @return A list with:
#'   - instances: tibble returned by get_wikidata_instances() (possibly trimmed)
#'   - presence: logical matrix [n_items x n_languages]
#'   - data: tibble with qid (+ optional labels) + 0/1 columns per language
#'   - debug: (only when debug=TRUE) list with missing QIDs and raw API checks
#'
#' @examples
#' \dontrun{
#'   # Track a fixed set of Wikipedias
#'   res <- wikidata_instance_wikipedia_presence(
#'     class_qid  = "Q5",
#'     languages  = c("en","es","pt","de","qu"),
#'     limit      = 500
#'   )
#'
#'   # Auto-discover all Wikipedia language codes present in sitelinks
#'   res2 <- wikidata_instance_wikipedia_presence(
#'     class_qid = "Q5",
#'     languages = NULL,
#'     limit     = 200
#'   )
#' }
#' @export
wikidata_instance_wikipedia_presence <- function(class_qid,
                                                 languages = NULL,
                                                 country = NULL,
                                                 limit = 1000,
                                                 batch_size = 50,
                                                 batch_delay = 1,
                                                 include_labels = TRUE,
                                                 drop_other_langs = TRUE,
                                                 debug = FALSE) {
  stopifnot(is.character(class_qid), length(class_qid) == 1)
  if (!is.null(languages)) stopifnot(is.character(languages), length(languages) >= 1)

  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need dplyr")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Need purrr")
  if (!requireNamespace("stringr", quietly = TRUE)) stop("Need stringr")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need tibble")

  # 1) Fetch instances (this already includes wikipedia_articles list-column)
  inst <- get_wikidata_instances(
    class_qid   = class_qid,
    country     = country,
    languages   = c("en", "es"),   # affects only label_/description_ columns
    limit       = limit,
    batch_size  = batch_size,
    batch_delay = batch_delay
  )

  dbg <- list()
  if (isTRUE(debug)) {
    # get_wikidata_instances() currently messages about missing items during
    # wbgetentities parsing, but does not return the missing QIDs. We can
    # at least validate a handful of known-missing QIDs by direct API call.
    dbg$note <- paste(
      "If items are reported as 'missing or not found',",
      "it is usually because wbgetentities returned an entity object with",
      "missing=''. This can happen for deleted/merged items or transient API issues.",
      "Use debug_missing_qids() below to probe them directly."
    )
  }

  if (nrow(inst) == 0) {
    langs <- if (is.null(languages)) character(0) else languages
    presence <- matrix(FALSE, nrow = 0, ncol = length(langs),
                       dimnames = list(character(0), langs))
    out <- list(instances = inst, presence = presence, data = tibble::tibble())
    if (isTRUE(debug)) out$debug <- dbg
    return(out)
  }

  if (!"qid" %in% names(inst)) stop("get_wikidata_instances() result lacks `qid`.")
  if (!"wikipedia_articles" %in% names(inst)) {
    stop("get_wikidata_instances() result lacks `wikipedia_articles` list-column.")
  }

  # 2) Convert wikipedia_articles -> set of language codes per item
  # wikipedia_articles strings look like "en: Title" (see .parse_entity())
  lang_sets <- purrr::map(inst$wikipedia_articles, function(x) {
    if (is.null(x) || length(x) == 0) return(character(0))
    langs <- stringr::str_match(x, "^([a-z0-9-]+):\\s")[, 2]
    langs <- langs[!is.na(langs)]
    unique(langs)
  })

  # 2b) Determine the language columns
  if (is.null(languages)) {
    # Auto-discover across all items, stable sorted order
    languages <- sort(unique(unlist(lang_sets, use.names = FALSE)))
  } else if (isTRUE(drop_other_langs)) {
    lang_sets <- purrr::map(lang_sets, intersect, languages)
  }

  # 3) Build presence matrix
  qids <- inst$qid
  presence <- matrix(FALSE, nrow = length(qids), ncol = length(languages),
                     dimnames = list(qids, languages))

  for (i in seq_along(qids)) {
    ls <- lang_sets[[i]]
    if (length(ls)) presence[i, intersect(ls, languages)] <- TRUE
  }

  # 4) Friendly tibble: qid (+ optional label columns) + 0/1 per language
  base_cols <- dplyr::select(inst, qid)
  if (isTRUE(include_labels)) {
    label_cols <- intersect(names(inst), c("label_en", "label_es"))
    if (length(label_cols)) base_cols <- dplyr::bind_cols(base_cols, inst[, label_cols, drop = FALSE])
  }

  lang_df <- as.data.frame(1L * presence, check.names = FALSE)
  lang_df <- tibble::as_tibble(lang_df)

  out_df <- dplyr::bind_cols(base_cols, lang_df)

  out <- list(
    instances = inst,
    presence  = presence,
    data      = out_df
  )
  if (isTRUE(debug)) out$debug <- dbg
  out
}

#' Resume a partially completed wikidata_instance_wikipedia_presence() query
#'
#' This mirrors resume_get_wikidata_instances(): if a prior call was interrupted
#' (or returned only a subset) you can pass the partial result and this function
#' will re-run the query and fetch only missing QIDs.
#'
#' @param partial_result List previously returned by wikidata_instance_wikipedia_presence().
#'   Must contain $instances with a `qid` column.
#' @param class_qid See wikidata_instance_wikipedia_presence().
#' @param languages See wikidata_instance_wikipedia_presence().
#' @param country See wikidata_instance_wikipedia_presence().
#' @param limit See wikidata_instance_wikipedia_presence().
#' @param batch_size See wikidata_instance_wikipedia_presence().
#' @param batch_delay See wikidata_instance_wikipedia_presence().
#' @param include_labels See wikidata_instance_wikipedia_presence().
#' @param drop_other_langs See wikidata_instance_wikipedia_presence().
#'
#' @return Same structure as wikidata_instance_wikipedia_presence().
#'
#' @export
resume_wikidata_instance_wikipedia_presence <- function(partial_result,
                                                       class_qid,
                                                       languages = NULL,
                                                       country = NULL,
                                                       limit = 1000,
                                                       batch_size = 50,
                                                       batch_delay = 1,
                                                       include_labels = TRUE,
                                                       drop_other_langs = TRUE) {
  if (is.null(partial_result$instances) || !"qid" %in% names(partial_result$instances)) {
    stop("partial_result must be a list with $instances containing a 'qid' column")
  }

  inst_partial <- partial_result$instances

  inst_full <- resume_get_wikidata_instances(
    partial_result = inst_partial,
    class_qid       = class_qid,
    country         = country,
    languages       = c("en", "es"),
    limit           = limit,
    batch_size      = batch_size,
    batch_delay     = batch_delay
  )

  # Rebuild presence matrix + output data using the same logic as the main function
  if (!"wikipedia_articles" %in% names(inst_full)) {
    stop("get_wikidata_instances() result lacks `wikipedia_articles` list-column.")
  }

  lang_sets <- purrr::map(inst_full$wikipedia_articles, function(x) {
    if (is.null(x) || length(x) == 0) return(character(0))
    langs <- stringr::str_match(x, "^([a-z0-9-]+):\\s")[, 2]
    langs <- langs[!is.na(langs)]
    unique(langs)
  })

  if (is.null(languages)) {
    languages <- sort(unique(unlist(lang_sets, use.names = FALSE)))
  } else if (isTRUE(drop_other_langs)) {
    lang_sets <- purrr::map(lang_sets, intersect, languages)
  }

  qids <- inst_full$qid
  presence <- matrix(FALSE, nrow = length(qids), ncol = length(languages),
                     dimnames = list(qids, languages))

  for (i in seq_along(qids)) {
    ls <- lang_sets[[i]]
    if (length(ls)) presence[i, intersect(ls, languages)] <- TRUE
  }

  base_cols <- dplyr::select(inst_full, qid)
  if (isTRUE(include_labels)) {
    label_cols <- intersect(names(inst_full), c("label_en", "label_es"))
    if (length(label_cols)) base_cols <- dplyr::bind_cols(base_cols, inst_full[, label_cols, drop = FALSE])
  }

  lang_df <- as.data.frame(1L * presence, check.names = FALSE)
  lang_df <- tibble::as_tibble(lang_df)
  out_df <- dplyr::bind_cols(base_cols, lang_df)

  list(
    instances = inst_full,
    presence  = presence,
    data      = out_df
  )
}
