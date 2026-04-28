# ine_igm_community_crosswalk.R
#
# Portable helper script: loads the INE–IGM community crosswalk and exposes two
# look-up functions.  Source this file from any script that needs crosswalk access:
#
#   source("ine_igm_community_crosswalk.R")
#
# After sourcing, `crosswalk_geo_ine`, `ine_match_status()`, and
# `igm_match_status()` are available in the calling environment.
# ---------------------------------------------------------------------------

library(dplyr)
library(stringr)

crosswalk_geo_ine <- readRDS("data/crosswalk_ine_igm.rds")

# ---------------------------------------------------------------------------
# match_status values (shared by both functions)
# ---------------------------------------------------------------------------
#   unique                 – one IGM geo point matched by name within department
#   unique_via_spatial     – ambiguous name resolved by GADM municipality boundary
#   unique_via_name        – ambiguous name resolved by proximity to municipality centroid
#   unique_via_usca        – ambiguous name resolved by USCA community polygon
#   ambiguous_canton_split – same community listed under multiple canton codes due to
#                            administrative reorganisation; all codes in the group share
#                            the same IGM candidate pool (many-to-one is intentional)
#   ambiguous_dispersed    – all IGM candidates are tipo_area == "dis" (dispersed
#                            settlement); the IGM dataset recorded multiple points for
#                            the same dispersed community; treat all candidates as a
#                            valid coordinate pool
#   ambiguous              – multiple IGM candidates remain after all spatial steps
#   ambiguous_no_spatial   – name recurs across municipalities; no spatial disambiguation
#   unmatched              – no IGM geo point found with a matching name
#   not_found              – the code does not exist in the INE community list

# ---------------------------------------------------------------------------

#' Look up crosswalk status for an INE community code
#'
#' Accepts both 10-digit (cod10dig style, no leading zero) and 11-digit
#' (Codigo style, with leading zero) INE codes and prints a human-readable
#' summary of how — or whether — that community was matched to an IGM geo point.
#'
#' @param codigo Character or integer. An INE community code, either 10 or 11
#'   digits.  10-digit inputs are automatically padded with a leading zero.
#' @param crosswalk A data frame with the same structure as `crosswalk_geo_ine`
#'   (columns: `Codigo`, `department`, `municipality`, `com_name`, `id_unico`,
#'   `match_status`, `n_geo`, `canton_split_group`).  Defaults to the
#'   package-level `crosswalk_geo_ine` loaded when this script is sourced.
#'
#' @return The subset of `crosswalk` rows for `codigo`, invisibly.  The
#'   function is called primarily for its printed side-effect.
#'
#' @section Match status values:
#' \describe{
#'   \item{unique}{One IGM point matched by name within the department.}
#'   \item{unique_via_spatial}{Resolved by confirming the point lies within the
#'     GADM municipality boundary.}
#'   \item{unique_via_name}{Resolved by selecting the point closest to the
#'     correct municipality centroid.}
#'   \item{unique_via_usca}{Resolved by confirming the point falls inside the
#'     USCA community boundary.}
#'   \item{ambiguous_canton_split}{Community appears under multiple INE codes
#'     due to canton reorganisation; all codes share the same IGM pool.}
#'   \item{ambiguous_dispersed}{All IGM candidates are dispersed-type points;
#'     use the full pool as valid coordinates.}
#'   \item{ambiguous}{Multiple IGM points remain; manual review needed.}
#'   \item{ambiguous_no_spatial}{Name recurs across municipalities; no spatial
#'     disambiguation was possible.}
#'   \item{unmatched}{No IGM point with a matching name was found.}
#' }
#'
#' @examples
#' ine_match_status("01010010001")   # 11-digit Codigo
#' ine_match_status("1010010001")    # 10-digit form — auto-padded
ine_match_status <- function(codigo, crosswalk = crosswalk_geo_ine) {
  # Normalise to 11-digit form (pad with leading zero if 10 digits)
  codigo <- as.character(codigo)
  codigo <- ifelse(nchar(codigo) == 10, paste0("0", codigo), codigo)

  rows <- crosswalk[crosswalk$Codigo == codigo, ]

  if (nrow(rows) == 0) {
    cat("Code", codigo, "not found in crosswalk.\n")
    return(invisible(NULL))
  }

  status      <- rows$match_status[1]
  com_name    <- rows$com_name[1]
  mun         <- rows$municipality[1]
  dep         <- rows$department[1]
  split_group <- rows$canton_split_group[1]

  explanation <- switch(status,
    unique =
      "Uniquely matched: one IGM geo point shares this community's name within its department.",
    unique_via_spatial =
      "Uniquely matched via GADM spatial join: an ambiguous name match was resolved by confirming the geo point lies within the correct municipality boundary.",
    unique_via_name =
      "Uniquely matched via name proximity: an ambiguous match was resolved by selecting the geo point closest to the correct municipality centroid.",
    unique_via_usca =
      "Uniquely matched via USCA polygon: an ambiguous match was resolved by confirming the geo point falls inside the USCA community boundary for this INE code.",
    ambiguous_canton_split = {
      grp_codes <- sort(unique(crosswalk$Codigo[
        !is.na(crosswalk$canton_split_group) &
          crosswalk$canton_split_group == split_group
      ]))
      paste0(
        "Canton-split duplicate: this community appears under ", length(grp_codes),
        " INE codes (", paste(grp_codes, collapse = ", "), ") because canton boundaries ",
        "were reorganised over time. All codes in this group point to the same pool of ",
        n_distinct(rows$id_unico), " IGM geo candidate(s). ",
        "Many-to-one mapping (several codes -> same IGM points) is expected here."
      )
    },
    ambiguous_dispersed = paste0(
      "Dispersed settlement pool: ", n_distinct(rows$id_unico), " IGM geo points all typed ",
      "as 'dis' (dispersed) share this community's name. The IGM dataset recorded multiple ",
      "points for the same dispersed community. All candidates are valid coordinates for ",
      "this community — use them as a pool rather than selecting one."
    ),
    ambiguous = paste0(
      "Ambiguous: ", rows$n_geo[1], " IGM geo points share this community's name within ",
      mun, " municipality. The correct point cannot be determined automatically. ",
      "Manual review or additional data is needed."
    ),
    ambiguous_no_spatial = paste0(
      "Ambiguous (cross-municipality): ", rows$n_geo[1], " IGM geo points share this ",
      "community's name and it recurs across multiple municipalities. No spatial ",
      "disambiguation was possible. Manual review is needed."
    ),
    unmatched =
      "Unmatched: no IGM geo point with a matching name was found for this community.",
    paste("Unknown status:", status)
  )

  cat(sprintf(
    "Code:        %s\nCommunity:   %s\nMunicipality:%s (%s)\nStatus:      %s\n\n%s\n",
    codigo, com_name, mun, dep, status, explanation
  ))

  invisible(rows)
}

# ---------------------------------------------------------------------------

#' Look up crosswalk status for an IGM geo point identifier
#'
#' Given an IGM `id_unico` value, finds all INE community codes that reference
#' it in the crosswalk and prints a human-readable summary.  This is the
#' reverse direction of [ine_match_status()].
#'
#' @details
#' **"-D" suffix normalisation.**  IGM identifiers end in "-D" (e.g.
#' `"BOL-12345-D"`). If the supplied value does not already end in `"-D"`, the
#' suffix is appended automatically before the look-up, so bare numeric or
#' partial identifiers work transparently.
#'
#' **Dispersed-point handling.**  When the matched point belongs to an
#' `ambiguous_dispersed` group, the function reports every INE community code
#' in that pool together with the full set of sibling IGM points — because for
#' dispersed settlements the IGM dataset records several points for the same
#' community, and all are equally valid.
#'
#' **Canton-split handling.**  A single IGM point may legitimately appear under
#' several INE codes whose `match_status` is `ambiguous_canton_split`.  The
#' function lists all codes in the split group and explains the administrative
#' reason.
#'
#' @param id_unico Character.  An IGM geo point identifier, with or without the
#'   trailing `"-D"` suffix.
#' @param crosswalk A data frame with the same structure as `crosswalk_geo_ine`.
#'   Defaults to the package-level `crosswalk_geo_ine` loaded when this script
#'   is sourced.
#'
#' @return The subset of `crosswalk` rows that reference `id_unico`, invisibly.
#'   The function is called primarily for its printed side-effect.
#'
#' @section Match status values:
#' \describe{
#'   \item{unique / unique_via_*}{This point is the sole match for exactly one
#'     INE community code.}
#'   \item{ambiguous_canton_split}{This point is shared by several INE codes
#'     because canton boundaries were reorganised; many-to-one is expected.}
#'   \item{ambiguous_dispersed}{This point is one of several dispersed-type
#'     IGM points that all represent the same community; use the full pool.}
#'   \item{ambiguous / ambiguous_no_spatial}{This point is one of multiple
#'     candidates for an INE community that could not be resolved automatically.}
#' }
#'
#' @examples
#' igm_match_status("BOL-12345-D")   # full identifier
#' igm_match_status("BOL-12345")     # "-D" appended automatically
igm_match_status <- function(id_unico, crosswalk = crosswalk_geo_ine) {

  # --- 1. Normalise: append "-D" if absent -----------------------------------
  id_unico <- as.character(id_unico)
  id_unico <- ifelse(!str_ends(id_unico, "-D"), paste0(id_unico, "-D"), id_unico)

  rows <- crosswalk[!is.na(crosswalk$id_unico) & crosswalk$id_unico == id_unico, ]

  if (nrow(rows) == 0) {
    cat("IGM point", id_unico, "not found in crosswalk.\n")
    return(invisible(NULL))
  }

  # --- 2. Characterise what statuses this point appears under ---------------
  statuses  <- unique(rows$match_status)
  n_codes   <- n_distinct(rows$Codigo)

  # Dominant status (a point should appear under one status type; flag if not)
  dominant_status <- statuses[1]
  if (length(statuses) > 1) {
    warning(sprintf(
      "IGM point %s appears under multiple match_status values (%s). Reporting all.",
      id_unico, paste(statuses, collapse = ", ")
    ))
  }

  # --- 3. Build header lines (department / community may be multi-row) ------
  deps   <- paste(sort(unique(rows$department)),   collapse = ", ")
  muns   <- paste(sort(unique(rows$municipality)), collapse = ", ")
  names_ <- paste(sort(unique(rows$com_name)),     collapse = " / ")

  # --- 4. Build explanation per status --------------------------------------

  # Helper: for dispersed groups, collect sibling points sharing the same
  # INE Codigo(s).
  dispersed_siblings <- function(codigos) {
    sibs <- crosswalk[
      crosswalk$Codigo %in% codigos &
        crosswalk$match_status == "ambiguous_dispersed" &
        !is.na(crosswalk$id_unico),
    ]
    sort(unique(sibs$id_unico))
  }

  explanation <- if ("ambiguous_dispersed" %in% statuses) {

    # --- Dispersed pool -------------------------------------------------------
    # One IGM point may appear in multiple INE Codigos if the pool spans more
    # than one community record (rare but possible via name ambiguity).
    pool_codigos <- sort(unique(rows$Codigo[rows$match_status == "ambiguous_dispersed"]))
    siblings     <- dispersed_siblings(pool_codigos)
    n_siblings   <- length(siblings)
    other_pts    <- setdiff(siblings, id_unico)

    pool_label <- if (n_codes == 1) {
      paste0("INE code ", pool_codigos)
    } else {
      paste0(n_codes, " INE codes: ", paste(pool_codigos, collapse = ", "))
    }

    other_label <- if (length(other_pts) == 0) {
      "No other sibling points."
    } else {
      paste0(
        "Sibling dispersed point(s) for the same community pool (", length(other_pts), "): ",
        paste(other_pts, collapse = ", "), "."
      )
    }

    paste0(
      "Dispersed settlement pool: this point is one of ", n_siblings, " IGM point(s) ",
      "all typed as 'dis' (dispersed) that are collectively mapped to ", pool_label, ". ",
      "The IGM dataset records multiple coordinates for the same dispersed community; ",
      "all points in the pool are equally valid — treat them as a coordinate set rather ",
      "than selecting one. ", other_label
    )

  } else if ("ambiguous_canton_split" %in% statuses) {

    # --- Canton-split pool ----------------------------------------------------
    split_group <- rows$canton_split_group[!is.na(rows$canton_split_group)][1]
    grp_codes   <- sort(unique(crosswalk$Codigo[
      !is.na(crosswalk$canton_split_group) &
        crosswalk$canton_split_group == split_group
    ]))
    pool_pts <- sort(unique(crosswalk$id_unico[
      crosswalk$Codigo %in% grp_codes & !is.na(crosswalk$id_unico)
    ]))
    other_pts <- setdiff(pool_pts, id_unico)

    other_label <- if (length(other_pts) == 0) {
      ""
    } else {
      paste0(
        " Other IGM point(s) in this canton-split pool: ",
        paste(other_pts, collapse = ", "), "."
      )
    }

    paste0(
      "Canton-split pool: this point is referenced by ", length(grp_codes),
      " INE codes (", paste(grp_codes, collapse = ", "), ") because canton boundaries ",
      "were reorganised over time. Many-to-one mapping (several INE codes -> same IGM ",
      "point pool) is expected here.", other_label
    )

  } else if (all(statuses %in% c("unique", "unique_via_spatial",
                                  "unique_via_name", "unique_via_usca"))) {

    # --- Unambiguous 1-to-1 match --------------------------------------------
    codigo_str  <- rows$Codigo[1]
    status_desc <- switch(dominant_status,
      unique              = "by direct name match within the department",
      unique_via_spatial  = "via GADM municipality spatial join",
      unique_via_name     = "via proximity to municipality centroid",
      unique_via_usca     = "via USCA community polygon",
      paste("with status", dominant_status)
    )
    paste0(
      "Uniquely matched: this point is the sole IGM match for INE code ", codigo_str,
      " (", rows$com_name[1], ", ", rows$municipality[1], ", ", rows$department[1],
      "), resolved ", status_desc, "."
    )

  } else if (any(statuses %in% c("ambiguous", "ambiguous_no_spatial"))) {

    # --- Remaining ambiguous --------------------------------------------------
    paste0(
      "Ambiguous candidate: this point is one of ", rows$n_geo[1], " IGM point(s) that ",
      "share the community name '", names_, "' in ", deps, ". ",
      "It has not been resolved to a unique INE code automatically. ",
      "INE code(s) involved: ", paste(sort(unique(rows$Codigo)), collapse = ", "), ". ",
      "Manual review or additional data is needed."
    )

  } else {
    paste("Status(es):", paste(statuses, collapse = ", "))
  }

  cat(sprintf(
    "IGM point:   %s\nCommunity:   %s\nMunicipality:%s (%s)\nStatus:      %s\n\n%s\n",
    id_unico, names_, muns, deps, paste(statuses, collapse = " + "), explanation
  ))

  invisible(rows)
}
