# ---- get_wikidata_subclasses -------------------------------------------------

#' Get All Subclasses of a Wikidata Class
#'
#' Convenience wrapper for \code{get_wikidata_instances()} that automatically
#' sets \code{object_type = "subclass"}. Retrieves all subclasses (P279) of a
#' given class from Wikidata with their labels, descriptions, optional extra
#' properties, subclass-of statements, and Wikipedia articles.
#'
#' Items are fetched from the Wikidata API in batches of \code{batch_size}
#' (default 50, the API maximum) to avoid rate-limiting errors.
#'
#' @param class_qid Character. The Wikidata QID of the class (e.g., "Q34770"
#'   for language)
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
#'   have multiple claims. These must NOT also appear in \code{property}.
#'   For each property named \code{pname} in \code{numeric_list_property_names},
#'   the following columns are added:
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
#' @return A tibble with columns:
#'   - qid
#'   - label_<lang>, description_<lang> for each language
#'   - Columns from \code{property} and \code{numeric_list_properties}
#'   - subclass_of (QIDs of parent classes from P279)
#'   - wikipedia_articles
#'
#' @examples
#' # Get all language subclasses
#' language_types <- get_wikidata_subclasses("Q34770", limit = 500)
#'
#' # Get subclasses with additional properties
#' organism_subclasses <- get_wikidata_subclasses(
#'   "Q7239",  # organism
#'   property = c("P31", "P279"),
#'   property_names = c("instance_of", "parent_class"),
#'   languages = c("en", "es", "de"),
#'   limit = 1000
#' )
#'
#' @export
get_wikidata_subclasses <- function(class_qid,
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

  get_wikidata_instances(
    class_qid                       = class_qid,
    property                        = property,
    property_names                  = property_names,
    country                         = country,
    languages                       = languages,
    limit                           = limit,
    batch_size                      = batch_size,
    batch_delay                     = batch_delay,
    numeric_list_properties         = numeric_list_properties,
    numeric_list_property_names     = numeric_list_property_names,
    entity_props                    = entity_props,
    object_type                     = "subclass"
  )
}
