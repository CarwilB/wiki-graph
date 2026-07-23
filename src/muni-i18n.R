# muni-i18n.R
# Shared internationalization layer for the Bolivia municipality generators.
#
# Provides:
#   - muni_translations   : parsed transcats data-value translation list
#                           (variables: "ethnic_group", "language")
#   - muni_var_labels      : transcats horizontal variable-name/label table
#   - label(key, lang)     : resolve a UI/section/column label to `lang`
#   - translate_values(x, variable, lang) : translate a vector of raw data
#                           values (census category strings) to `lang`
#
# Source language for data values is the raw census string, coded "raw".
# Supported display languages: "en", "es".
#
# Dependencies: transcats, readr

library(transcats)

# ---- Load translation assets --------------------------------------------------

.muni_i18n_dir <- here::here("data", "translations")

muni_translations <- readRDS(file.path(.muni_i18n_dir, "muni_translations.rds"))
muni_var_labels   <- readr::read_csv(
  file.path(.muni_i18n_dir, "muni_var_labels.csv"),
  show_col_types = FALSE
)

# Register with transcats so its own accessors (variable_name(), translated_join(),
# translated_levels()) work out of the box against these tables.
transcats::set_source_lang("raw")
transcats::set_active_translation_table(muni_translations)
transcats::set_var_name_table(muni_var_labels)

# ---- Label accessor -----------------------------------------------------------

#' Resolve a UI / section / column label to a language
#'
#' Thin string-keyed wrapper over the transcats variable-name table. Unlike
#' transcats::variable_name() (which uses non-standard evaluation on the key),
#' this takes the key as a string, which is convenient for programmatic use.
#'
#' @param key  Label key (string), e.g. "sec_population", "col_seat".
#' @param lang Target language code ("en" or "es").
#' @param name_table Horizontal variable-name table; defaults to muni_var_labels.
#' @return A single character string. Errors if the key is unknown.
label <- function(key, lang, name_table = muni_var_labels) {
  if (!key %in% names(name_table)) {
    stop("Unknown label key: '", key, "'", call. = FALSE)
  }
  row <- name_table[name_table$language == lang, , drop = FALSE]
  if (nrow(row) == 0) {
    stop("Language '", lang, "' not present in label table", call. = FALSE)
  }
  row[[key]][1]
}

# ---- Data-value translator ----------------------------------------------------

#' Translate a vector of raw census data values to a display language
#'
#' Wraps transcats::translated_levels() for a single categorical variable.
#' Values not present in the translation table pass through unchanged (with a
#' warning) so the pipeline is robust to new census categories.
#'
#' @param x        Character vector of raw census values (the translation keys).
#' @param variable Which translation table to use: "ethnic_group" or "language".
#' @param lang     Target language code ("en" or "es").
#' @param translation_table transcats translation list; defaults to muni_translations.
#' @return Character vector of translated display values, same length as `x`.
translate_values <- function(x, variable, lang,
                             translation_table = muni_translations) {
  tbl <- translation_table[[variable]]
  if (is.null(tbl)) {
    stop("No translation table for variable '", variable, "'", call. = FALSE)
  }
  idx <- match(x, tbl[["raw"]])
  out <- tbl[[lang]][idx]
  missing <- is.na(idx)
  if (any(missing)) {
    warning("translate_values(): ", sum(missing),
            " value(s) not in '", variable, "' table; passing through raw: ",
            paste(unique(x[missing]), collapse = ", "), call. = FALSE)
    out[missing] <- x[missing]
  }
  out
}
