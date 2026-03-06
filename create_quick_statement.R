#' Create QuickStatements V1 Syntax Commands
#'
#' Generate QuickStatements commands for various data types including strings,
#' monolingual text, labels, and descriptions with optional references.
#'
#' For more on QuickStatements syntax, see
#' https://www.wikidata.org/wiki/Help:QuickStatements or
#' https://meta.wikimedia.org/wiki/QuickStatements_3.0
#'
#' @param qid Character. The Wikidata item ID (e.g., "Q42")
#' @param property Character. The property ID (e.g., "P31" for statements,
#'   "L" for labels, "D" for descriptions, "A" for aliases)
#' @param value Character. The value to add
#' @param lang Character. Language code (required for monolingual text, labels,
#'   descriptions, and aliases). Default is NULL.
#' @param type Character. Type of value: "string", "monolingual", "label",
#'   "description", "alias", "item", "time", "quantity", "coordinate".
#'   Default is "string".
#' @param retrieved_date Character or Date. Date to use as retrieved date.
#'   If NULL (default), uses current system date. Only used if \code{reference_url}
#'   or \code{reference_qid} is provided.
#' @param reference_url Character. URL to use as reference (P854). If provided,
#'   a reference block is added to the statement. Default is NULL.
#' @param reference_qid Character. Wikidata item QID to use as a "stated in"
#'   (P248) reference. If provided, a reference block is added to the statement.
#'   Default is NULL.
#' @param qualifiers List. Optional list of qualifiers as name-value pairs
#'   (e.g., list(P585 = "+2020-01-01T00:00:00Z/11")).
#' @param comment Character. Optional edit summary comment.
#'
#' @return Character string containing the QuickStatements command
#'
#' @examples
#' # String value
#' create_quick_statement("Q14579", "P348", "6.13.7")
#'
#' # Monolingual text
#' create_quick_statement("Q935", "P1559", "Isaac Newton",
#'                       lang = "en", type = "monolingual")
#'
#' # Label; using either type = "label" or property = "L" is sufficient
#' create_quick_statement("Q1001", property = "L", "Mahatma Gandhi",
#'                       lang = "en", type = "label")
#'
#' # Description; using either type = "description" or property = "D" is sufficient
#' create_quick_statement("Q1001", property = "D",
#'                       "Indian independence activist (1869-1948)",
#'                       lang = "en", type = "description")
#'
#' # With reference URL
#' create_quick_statement("Q42", "P19", "Q350", type = "item",
#'                       reference_url = "https://example.com")
#'
#' # With stated-in reference
#' create_quick_statement("Q42", "P19", "Q350", type = "item",
#'                       reference_qid = "Q36578")
#'
#' @export

create_quick_statement <- function(qid,
                                   property,
                                   value,
                                   lang = NULL,
                                   type = "string",
                                   retrieved_date = NULL,
                                   reference_url = NULL,
                                   reference_qid = NULL,
                                   qualifiers = NULL,
                                   comment = NULL) {
  is_qid <- function(string){
    grepl("^Q\\d+$", string) | (string == "LAST")
  }
  is_prop <- function(string){
    grepl("^P\\d+$", string)
  }

  # Validate inputs
  if (!grepl("^Q\\d+$", qid) && qid != "LAST") {
    stop("qid must be in format 'Q123' or 'LAST'")
  }

  # Build the command based on type
  command_parts <- c(qid)

  if ((property == "L") | (type == "label")) {
    if (is.null(lang)) {
      stop("lang parameter is required for labels")
    }
    command_parts <- c(command_parts, paste0("L", lang), paste0('"', value, '"'))

  } else if ((property == "D") |(type == "description")) {
    if (is.null(lang)) {
      stop("lang parameter is required for descriptions")
    }
    command_parts <- c(command_parts, paste0("D", lang), paste0('"', value, '"'))

  } else if ((property == "A") | (type == "alias")) {
    if (is.null(lang)) {
      stop("lang parameter is required for aliases")
    }
    command_parts <- c(command_parts, paste0("A", lang), paste0('"', value, '"'))

  } else if (type == "monolingual") {
    if (is.null(lang)) {
      stop("lang parameter is required for monolingual text")
    }
    if (!grepl("^P\\d+$", property)) {
      stop("property must be in format 'P123' for statements")
    }
    command_parts <- c(command_parts, property, paste0(lang, ':"', value, '"'))

  } else if (type == "string") {
    if (!grepl("^P\\d+$", property)) {
      stop("property must be in format 'P123' for statements")
    }
    command_parts <- c(command_parts, property, paste0('"', value, '"'))

  } else if (type %in% c("item", "time", "quantity", "coordinate")) {
    if (!grepl("^P\\d+$", property)) {
      stop("property must be in format 'P123' for statements")
    }
    command_parts <- c(command_parts, property, value)

  } else {
    stop("Invalid type. Must be one of: string, monolingual, label, description, alias, item, time, quantity, coordinate")
  }

  # Add qualifiers if provided
  # QuickStatements qualifier syntax: qalXXX (not PXX), e.g. qal585 for P585
  if (!is.null(qualifiers)) {
    for (qual_prop in names(qualifiers)) {
      if (!grepl("^P\\d+$", qual_prop)) {
        stop(paste("Qualifier property must be in format 'P123':", qual_prop))
      }
      qal_label <- paste0("qal", gsub("^P", "", qual_prop))
      command_parts <- c(command_parts, qal_label, qualifiers[[qual_prop]])
    }
  }

  # Add reference block if reference_url or reference_qid is provided
  add_reference <- !is.null(reference_url) || !is.null(reference_qid)

  if (add_reference) {
    if (type %in% c("label", "description", "alias")) {
      warning("References cannot be added to labels, descriptions, or aliases")
    } else {
      # Add "stated in" reference (P248) if reference_qid provided
      if (!is.null(reference_qid)) {
        if (!grepl("^Q\\d+$", reference_qid)) {
          stop("reference_qid must be in format 'Q123'")
        }
        command_parts <- c(command_parts, "S248", reference_qid)
      }

      # Add reference URL (P854) if reference_url provided
      if (!is.null(reference_url)) {
        command_parts <- c(command_parts, "S854", paste0('"', reference_url, '"'))
      }

      # Format and append retrieved date
      if (is.null(retrieved_date)) {
        retrieved_date <- Sys.Date()
      }
      date_formatted <- format(as.Date(retrieved_date), "+%Y-%m-%dT00:00:00Z/11")
      command_parts <- c(command_parts, "S813", date_formatted)
    }
  }

  # Add comment if provided
  if (!is.null(comment)) {
    command_parts <- c(command_parts, paste0("/* ", comment, " */"))
  }

  # Join with tabs
  paste(command_parts, collapse = " | ")
}

#' Add a QuickStatements Column to a Data Frame
#'
#' A convenience wrapper around \code{\link{create_quick_statement}} that adds
#' a \code{quick_statement} column to a data frame by calling
#' \code{create_quick_statement()} row-wise via \code{dplyr::mutate()}.
#'
#' @param dataframe A data frame (or tibble) to add the column to.
#' @param qid_col Unquoted column name containing Wikidata item IDs (e.g., \code{qid}).
#' @param property Character. The property ID (e.g., \code{"P31"}). Passed
#'   directly to \code{create_quick_statement()}.
#' @param value_col Unquoted column name containing the values to add.
#' @param ... Additional named arguments passed to \code{create_quick_statement()}
#'   (e.g., \code{lang}, \code{type}, \code{reference_qid}, \code{reference_url}).
#'
#' @return The input data frame with an additional \code{quick_statement} character column.
#'
#' @examples
#' departments %>%
#'   add_quick_statement_column(qid, "P14142", cod.dep,
#'                              reference_qid = "Q138354774")
#'
#' @export
add_quick_statement_column <- function(dataframe, qid_col, property, value_col, ...){
  dataframe %>%
    rowwise() %>%
    mutate(quick_statement = create_quick_statement({{ qid_col }}, property, {{ value_col }}, ...)) %>%
    ungroup()
}

#' Add a QuickStatements Column with Qualifiers to a Data Frame
#'
#' Like \code{add_quick_statement_column} but exposes the \code{qualifiers}
#' argument so that each statement can carry qualifier triples. Qualifier
#' properties are given as \code{"P123"} and are automatically converted to the
#' QuickStatements \code{qalXXX} token format required by the API.
#'
#' @param dataframe A data frame (or tibble).
#' @param qid_col Unquoted column name containing Wikidata item IDs.
#' @param property Character. The property ID (e.g., \code{"P1098"}).
#' @param value_col Unquoted column name containing statement values.
#' @param qualifiers Named list of qualifier property → value pairs. Names must
#'   be property IDs in format \code{"P123"}. Values are raw QuickStatements
#'   tokens: item QIDs (\code{"Q750"}), dates
#'   (\code{"+2024-01-01T00:00:00Z/9"}), or plain quantities (\code{"42"}).
#'   All values in the list are applied uniformly to every row.
#' @param ... Additional named arguments passed to \code{create_quick_statement()}
#'   (e.g., \code{type}, \code{reference_qid}, \code{reference_url}).
#'
#' @return The input data frame with an additional \code{quick_statement} column.
#'
#' @examples
#' cuadro39_speakers %>%
#'   add_quick_statement_column_q(
#'     qid, "P1098", c2024_total,
#'     qualifiers = list(P276 = "Q750", P585 = "+2024-01-01T00:00:00Z/9"),
#'     type = "quantity",
#'     reference_qid = "Q12345"
#'   )
#'
#' @export
add_quick_statement_column_q <- function(dataframe, qid_col, property, value_col,
                                          qualifiers = NULL, ...) {
  dataframe %>%
    rowwise() %>%
    mutate(quick_statement = create_quick_statement(
      {{ qid_col }}, property, as.character({{ value_col }}),
      qualifiers = qualifiers,
      ...
    )) %>%
    ungroup()
}

remove_quick_statement_column <- function(dataframe, qid_col, property, value_col, ...){
  dataframe %>%
    rowwise() %>%
    mutate(quick_statement = str_c("-", create_quick_statement({{ qid_col }}, property, {{ value_col }}, ...))) %>%
    ungroup()
}

