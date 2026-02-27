# ---- expand_located_in ------------------------------------------------------

#' Expand a \code{located_in} List Column into Labelled Location Columns
#'
#' Takes a data frame with a \code{located_in} list column of Wikidata QIDs
#' (as produced by \code{get_wikidata_instances()}) and replaces it with eight
#' flat columns describing up to two location entities. Labels and type
#' information are fetched live from the Wikidata API.
#'
#' The two slots (\code{loc_1}, \code{loc_2}) correspond to the first and
#' second elements of each \code{located_in} vector, in the order they appear.
#' For semantic routing by entity type (province vs. department), see
#' \code{\link{expand_located_in_pd}}.
#'
#' @param df A data frame with a \code{located_in} list column whose elements
#'   are character vectors of Wikidata QIDs.
#'
#' @return The input data frame with \code{located_in} replaced by eight
#'   character columns:
#'   \describe{
#'     \item{loc_1_qid}{QID of the first location entity.}
#'     \item{loc_1_en}{English label of the first location entity.}
#'     \item{loc_1_es}{Spanish label of the first location entity.}
#'     \item{loc_1_type}{English label of the first P31 (instance of) value
#'       for the first location entity.}
#'     \item{loc_2_qid}{QID of the second location entity (\code{NA} if only
#'       one location is listed).}
#'     \item{loc_2_en}{English label of the second location entity.}
#'     \item{loc_2_es}{Spanish label of the second location entity.}
#'     \item{loc_2_type}{English label of the first P31 value for the second
#'       location entity.}
#'   }
#'
#' @examples
#' municipalities_wd |> expand_located_in()
#'
#' @seealso \code{\link{expand_located_in_pd}}
expand_located_in <- function(df) {
  # Collect all unique QIDs we need to look up
  all_qids <- unique(unlist(df$located_in))
  all_qids <- all_qids[!is.na(all_qids)]

  message("Fetching ", length(all_qids), " unique QIDs...")

  # Fetch info for each unique QID: labels (en, es) and first P31 instance_of
  qid_info <- map(all_qids, function(qid) {
    Sys.sleep(0.1)
    tryCatch({
      r <- GET(
        "https://www.wikidata.org/w/api.php",
        query = list(
          action = "wbgetentities",
          ids = qid,
          format = "json",
          props = "labels|claims"
        )
      )
      entity <- fromJSON(content(r, "text", encoding = "UTF-8"))$entities[[qid]]

      label_en <- entity$labels$en$value %||% NA_character_
      label_es <- entity$labels$es$value %||% NA_character_

      # Get first P31 QID
      p31_qid <- NA_character_
      if ("P31" %in% names(entity$claims)) {
        p31_df <- entity$claims$P31
        if (nrow(p31_df) > 0) {
          p31_qid <- p31_df$mainsnak[1, ]$datavalue[[1]]$id
        }
      }

      list(qid = qid, label_en = label_en, label_es = label_es, p31_qid = p31_qid)
    }, error = function(e) {
      message("Error on ", qid, ": ", e$message)
      list(qid = qid, label_en = NA_character_, label_es = NA_character_, p31_qid = NA_character_)
    })
  }) |> bind_rows()

  # Now fetch labels for all unique P31 QIDs (the "type" labels)
  p31_qids <- unique(qid_info$p31_qid[!is.na(qid_info$p31_qid)])
  message("Fetching labels for ", length(p31_qids), " unique P31 (type) QIDs...")

  p31_labels <- map(p31_qids, function(qid) {
    Sys.sleep(0.1)
    tryCatch({
      r <- GET(
        "https://www.wikidata.org/w/api.php",
        query = list(
          action = "wbgetentities",
          ids = qid,
          format = "json",
          props = "labels"
        )
      )
      entity <- fromJSON(content(r, "text", encoding = "UTF-8"))$entities[[qid]]
      list(p31_qid = qid, type_en = entity$labels$en$value %||% NA_character_)
    }, error = function(e) {
      list(p31_qid = qid, type_en = NA_character_)
    })
  }) |> bind_rows()

  # Join type labels onto qid_info
  qid_info <- qid_info |> left_join(p31_labels, by = "p31_qid")

  # Build a named lookup: QID -> list(label_en, label_es, type)
  lookup <- split(qid_info, qid_info$qid) |>
    map(function(row) list(
      label_en = row$label_en,
      label_es = row$label_es,
      type = row$type_en
    ))

  # Now expand the located_in column
  expanded <- map(df$located_in, function(qids) {
    q1 <- qids[1]
    q2 <- if (length(qids) >= 2) qids[2] else NA_character_

    get_info <- function(q) {
      if (is.na(q)) {
        list(qid = NA_character_, en = NA_character_, es = NA_character_, type = NA_character_)
      } else {
        info <- lookup[[q]]
        list(qid = q, en = info$label_en, es = info$label_es, type = info$type)
      }
    }

    i1 <- get_info(q1)
    i2 <- get_info(q2)

    tibble(
      loc_1_qid = i1$qid, loc_1_en = i1$en, loc_1_es = i1$es, loc_1_type = i1$type,
      loc_2_qid = i2$qid, loc_2_en = i2$en, loc_2_es = i2$es, loc_2_type = i2$type
    )
  }) |> bind_rows()

  # Bind new columns and drop the original located_in
  bind_cols(select(df, -located_in), expanded)
}

# ---- expand_located_in_pd ---------------------------------------------------

#' Expand \code{located_in} into Province and Department Columns
#'
#' A Bolivia-specific variant of \code{\link{expand_located_in}} that routes
#' each location QID into either a province slot or a department slot based on
#' its P31 (instance of) value, rather than positionally. Each row receives at
#' most one province and one department.
#'
#' Classification rules:
#' \itemize{
#'   \item P31 includes \strong{Q1062593} (province of Bolivia) → \code{loc_prov_*}
#'   \item P31 includes \strong{Q250050} (department of Bolivia) → \code{loc_dep_*}
#'   \item Neither → logged as a warning message and silently dropped.
#' }
#'
#' @param df A data frame with a \code{located_in} list column whose elements
#'   are character vectors of Wikidata QIDs.
#'
#' @return The input data frame with \code{located_in} replaced by six
#'   character columns:
#'   \describe{
#'     \item{loc_prov_qid}{QID of the province the entity is located in.}
#'     \item{loc_prov_en}{English label of the province.}
#'     \item{loc_prov_es}{Spanish label of the province.}
#'     \item{loc_dep_qid}{QID of the department the entity is located in.}
#'     \item{loc_dep_en}{English label of the department.}
#'     \item{loc_dep_es}{Spanish label of the department.}
#'   }
#'   All six columns are \code{NA} when no matching location of that type is
#'   found.
#'
#' @examples
#' municipalities_wd |> expand_located_in_pd()
#'
#' @seealso \code{\link{expand_located_in}}
expand_located_in_pd <- function(df) {
  all_qids <- unique(unlist(df$located_in))
  all_qids <- all_qids[!is.na(all_qids)]

  message("Fetching ", length(all_qids), " unique QIDs...")

  qid_info <- map(all_qids, function(qid) {
    Sys.sleep(0.2)
    tryCatch({
      r <- GET(
        "https://www.wikidata.org/w/api.php",
        query = list(
          action = "wbgetentities",
          ids = qid,
          format = "json",
          props = "labels|claims"
        ),
        timeout(30)
      )
      entity <- fromJSON(content(r, "text", encoding = "UTF-8"))$entities[[qid]]

      label_en <- entity$labels$en$value %||% NA_character_
      label_es <- entity$labels$es$value %||% NA_character_

      p31_qids <- character(0)
      if ("P31" %in% names(entity$claims)) {
        p31_df <- entity$claims$P31
        if (nrow(p31_df) > 0) {
          p31_qids <- map_chr(seq_len(nrow(p31_df)), function(i) {
            p31_df$mainsnak[i, ]$datavalue[[1]]$id
          })
        }
      }

      type <- case_when(
        "Q1062593" %in% p31_qids ~ "province",
        "Q250050"  %in% p31_qids ~ "department",
        TRUE ~ "other"
      )

      list(qid = qid, label_en = label_en, label_es = label_es, type = type)
    }, error = function(e) {
      message("Error on ", qid, ": ", e$message)
      list(qid = qid, label_en = NA_character_, label_es = NA_character_, type = "other")
    })
  }) |> bind_rows()

  # Report any unclassified entities, with the rows from df that contain them
  others <- qid_info |> filter(type == "other")
  if (nrow(others) > 0) {
    # Find which rows of df contain each unclassified QID
    affected <- map(others$qid, function(bad_qid) {
      df[map_lgl(df$located_in, ~ bad_qid %in% .x), 1:2]
    }) |> bind_rows() |> distinct()

    affected_str <- paste(
      apply(affected, 1, paste, collapse = " / "),
      collapse = "\n  "
    )

    message(
      "Warning: ", nrow(others), " QID(s) not classified as province or department: ",
      paste(others$qid, collapse = ", "),
      "\n  Affected rows:\n  ", affected_str
    )
  }

  lookup <- split(qid_info, qid_info$qid) |>
    map(function(row) list(
      label_en = row$label_en,
      label_es = row$label_es,
      type = row$type
    ))

  expanded <- map(df$located_in, function(qids) {
    prov <- list(qid = NA_character_, en = NA_character_, es = NA_character_)
    dep  <- list(qid = NA_character_, en = NA_character_, es = NA_character_)

    for (q in qids) {
      info <- lookup[[q]]
      if (is.null(info)) next
      if (info$type == "province") {
        prov <- list(qid = q, en = info$label_en, es = info$label_es)
      } else if (info$type == "department") {
        dep <- list(qid = q, en = info$label_en, es = info$label_es)
      }
    }

    tibble(
      loc_prov_qid = prov$qid, loc_prov_en = prov$en, loc_prov_es = prov$es,
      loc_dep_qid  = dep$qid,  loc_dep_en  = dep$en,  loc_dep_es  = dep$es
    )
  }) |> bind_rows()

  bind_cols(select(df, -located_in), expanded)
}
