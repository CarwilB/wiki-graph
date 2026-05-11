# ---- resume_get_wikidata_subclasses ------------------------------------------

#' Resume a Partially-Completed get_wikidata_subclasses() Query
#'
#' Convenience wrapper for \code{resume_get_wikidata_instances()} that
#' automatically sets \code{object_type = "subclass"}. Use this when
#' \code{get_wikidata_subclasses()} was interrupted part-way through and you
#' have a partial result. Re-runs the SPARQL query to obtain the full QID list,
#' skips already-retrieved QIDs, fetches the remainder in batches, then returns
#' the combined, de-duplicated tibble.
#'
#' @param partial_result A tibble previously returned (or partially returned)
#'   by \code{get_wikidata_subclasses()}. Must contain a \code{qid} column.
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
#' @return A tibble with the same columns as \code{get_wikidata_subclasses()},
#'   containing all items (previously retrieved + newly fetched).
#'
#' @examples
#' # Start a subclass retrieval
#' language_types <- get_wikidata_subclasses("Q34770", limit = 500)
#'
#' # If interrupted, resume from partial result
#' language_types_complete <- resume_get_wikidata_subclasses(
#'   language_types,
#'   "Q34770",
#'   limit = 500
#' )
#'
#' @export
resume_get_wikidata_subclasses <- function(partial_result,
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

  resume_get_wikidata_instances(
    partial_result                  = partial_result,
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
