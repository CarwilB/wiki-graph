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
#'
#' @return A list with:
#'   - instances: tibble returned by get_wikidata_instances() (possibly trimmed)
#'   - presence: logical matrix [n_items x n_languages]
#'   - data: tibble with qid (+ optional labels) + 0/1 columns per language
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
                                                 drop_other_langs = TRUE) {
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

  if (nrow(inst) == 0) {
    langs <- if (is.null(languages)) character(0) else languages
    presence <- matrix(FALSE, nrow = 0, ncol = length(langs),
                       dimnames = list(character(0), langs))
    return(list(instances = inst, presence = presence, data = tibble::tibble()))
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

  list(
    instances = inst,
    presence  = presence,
    data      = out_df
  )
}
