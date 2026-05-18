# upload_prov_to_commons.R
# Uploads Bolivia province locator maps to Wikimedia Commons.
# All 112 files are uploaded fresh (no prior version on Commons).
#
# Prerequisites (same as upload_hd_to_commons.R):
#   ~/.Renviron:
#     COMMONS_BOT_USER=Carwil@YourBotName
#     COMMONS_BOT_PASSWORD=your_bot_password
#     COMMONS_AUTHOR=Carwil
#
#   In session:
#     gadm_adm2             — OCHA admin2 sf object (NAME_2 = province, NAME_1 = department)
#     wikidata_bo_provinces — Wikidata province table with qid and ine_code columns
#     prov_id_lookup_table  — maps id_prov (4-digit INE code) to province_gadm + department

library(httr2)
library(dplyr)
library(tibble)
library(jsonlite)
library(stringi)

COMMONS_API <- "https://commons.wikimedia.org/w/api.php"
TODAY       <- format(Sys.Date(), "%Y-%m-%d")
BOT_USER    <- Sys.getenv("COMMONS_BOT_USER")
BOT_PASS    <- Sys.getenv("COMMONS_BOT_PASSWORD")
AUTHOR      <- Sys.getenv("COMMONS_AUTHOR")
PROV_DIR    <- "output/locator_maps/prov-maps-hd"

stopifnot(
  "COMMONS_BOT_USER not set in .Renviron"     = nzchar(BOT_USER),
  "COMMONS_BOT_PASSWORD not set in .Renviron" = nzchar(BOT_PASS),
  "COMMONS_AUTHOR not set in .Renviron"       = nzchar(AUTHOR)
)


# ==============================================================================
# §1 — BUILD UPLOAD METADATA TABLE
# ==============================================================================

# Province names that appear in more than one department.
dupe_prov_names <- gadm_adm2 |>
  st_drop_geometry() |>
  count(NAME_2) |>
  filter(n > 1) |>
  pull(NAME_2)

# Reconstruct the hd_stem each province entry produces
# (matches the naming algorithm in generate_locator_maps_workbench_hd.R §8b).
prov_stem_tbl <- gadm_adm2 |>
  st_drop_geometry() |>
  distinct(NAME_2, NAME_1) |>
  mutate(
    clean_name = stri_trans_general(NAME_2, "Latin-ASCII"),
    clean_dept = stri_trans_general(NAME_1, "Latin-ASCII"),
    hd_stem = if_else(
      NAME_2 %in% dupe_prov_names,
      gsub("[^a-zA-Z0-9_()-]", "_", paste0(clean_name, "_(", clean_dept, ")")),
      gsub("[^a-zA-Z0-9_-]",   "_", clean_name)
    )
  )

# Enumerate SVG files and join to the lookup.
prov_files_df <- tibble(
  prov_file = list.files(PROV_DIR, pattern = "\\.svg$", full.names = TRUE)
) |>
  filter(!grepl("batch_log", prov_file)) |>
  mutate(hd_stem = sub("_prov_locator_map\\.svg$", "", basename(prov_file)))

# Province QID lookup: wikidata_bo_provinces.ine_code → prov_id_lookup_table.id_prov
# → province_gadm + department → qid
prov_qid_tbl <- wikidata_bo_provinces |>
  select(qid, ine_code) |>
  left_join(
    prov_id_lookup_table |> select(id_prov, province_gadm, department),
    by = c("ine_code" = "id_prov")
  )

upload_meta <- prov_files_df |>
  left_join(prov_stem_tbl, by = "hd_stem") |>
  rename(province = NAME_2, department = NAME_1) |>
  left_join(prov_qid_tbl, by = c("province" = "province_gadm", "department")) |>
  mutate(
    commons_filename = if_else(
      province %in% dupe_prov_names,
      paste0(province, " (", department, ") prov locator map.svg"),
      paste0(province, " prov locator map.svg")
    )
  )

# Sanity checks
n_unmatched <- sum(is.na(upload_meta$province))
if (n_unmatched > 0) {
  cat("WARNING:", n_unmatched, "files could not be matched to province lookup:\n")
  upload_meta |> filter(is.na(province)) |> pull(hd_stem) |> cat(sep = "\n")
  cat("\n")
}

cat(sprintf("Province upload plan: %d files\n", nrow(upload_meta)))
cat(sprintf("  %d with department disambiguator (Cercado)\n",
            sum(upload_meta$province %in% dupe_prov_names, na.rm = TRUE)))

n_missing_qid <- sum(is.na(upload_meta$qid))
if (n_missing_qid > 0) {
  cat("WARNING:", n_missing_qid, "provinces have no Wikidata QID:\n")
  upload_meta |> filter(is.na(qid)) |>
    select(province, department) |> print()
}


# ==============================================================================
# §2 — WIKITEXT BUILDER
# ==============================================================================

# Catalan elision: "de X" → "d'X" when X begins with a vowel.
ca_prep <- function(name) {
  if (grepl("^[AEIOUaeiouÀÈÌÒÙàèìòùÁÉÍÓÚáéíóú]", name)) {
    paste0("d\u2019", name)
  } else {
    paste0("de ", name)
  }
}

build_descriptions <- function(province) {
  list(
    en = paste0("Locator map showing ", province,
                " Province in a map of Bolivian municipalities, provinces, and departments"),
    es = paste0("Mapa de localización que muestra la provincia de ", province,
                " en un mapa de los municipios, provincias y departamentos de Bolivia"),
    ca = paste0("Mapa localitzador que mostra la prov\u00edncia ", ca_prep(province),
                " en un mapa dels municipis, prov\u00edncies i departaments de Bol\u00edvia.")
  )
}

build_wikitext <- function(province, date, author) {
  desc <- build_descriptions(province)

  paste0(
    "=={{int:filedesc}}==\n",
    "{{Information\n",
    "|description={{en|1=", desc$en, "}}\n",
    "{{es|1=", desc$es, "}}\n",
    "{{ca|1=", desc$ca, "}}\n",
    "|date=", date, "\n",
    "|source={{own}}<br>Internal borders drawn from Bolivia (Plurinational State of)",
    " administrative level 0-3 boundaries (COD-AB) dataset version 02, which is CC-BY-IGO",
    " UN Office of Coordination of Humanitarian Assistance.",
    " https://data.humdata.org/dataset/cod-ab-bol\n",
    "|author=[[User:", author, "|", author, "]]\n",
    "|permission=\n",
    "|other versions=\n",
    "}}\n\n",
    "=={{int:license-header}}==\n",
    "{{self|cc-zero}}\n\n",
    "[[Category:Locator maps of provinces of Bolivia]]"
  )
}


# ==============================================================================
# §3 — API SESSION HELPERS
# ==============================================================================

cookie_file <- tempfile(fileext = ".txt")
writeLines("", cookie_file)

commons_req <- function() {
  request(COMMONS_API) |>
    req_options(cookiefile = cookie_file, cookiejar = cookie_file) |>
    req_retry(max_tries = 3, backoff = \(i) 5)
}

commons_login <- function() {
  login_token <- commons_req() |>
    req_url_query(action = "query", meta = "tokens", type = "login", format = "json") |>
    req_perform() |>
    resp_body_json() |>
    _$query$tokens$logintoken

  resp <- commons_req() |>
    req_method("POST") |>
    req_body_form(
      action = "login", format = "json",
      lgname = BOT_USER, lgpassword = BOT_PASS, lgtoken = login_token
    ) |>
    req_perform() |>
    resp_body_json()

  if (resp$login$result != "Success")
    stop("Login failed: ", resp$login$reason)
  cat("Logged in as", resp$login$lgusername, "\n")
  invisible(resp)
}

get_csrf_token <- function() {
  commons_req() |>
    req_url_query(action = "query", meta = "tokens", format = "json") |>
    req_perform() |>
    resp_body_json() |>
    _$query$tokens$csrftoken
}

# Upload a new file (ignorewarnings allows overwriting an existing file).
upload_file <- function(local_path, commons_filename, wikitext, csrf_token) {
  commons_req() |>
    req_method("POST") |>
    req_body_multipart(
      action         = "upload",
      format         = "json",
      filename       = commons_filename,
      text           = wikitext,
      comment        = paste0("Bolivia province locator map — COD-AB source data (", TODAY, ")"),
      token          = csrf_token,
      ignorewarnings = "true",
      file           = curl::form_file(local_path, type = "image/svg+xml")
    ) |>
    req_timeout(120) |>
    req_perform() |>
    resp_body_json()
}

# Edit the description page only (fallback when upload detects a duplicate SVG).
edit_file_description <- function(commons_filename, wikitext, csrf_token) {
  commons_req() |>
    req_method("POST") |>
    req_body_form(
      action  = "edit",
      format  = "json",
      title   = paste0("File:", commons_filename),
      text    = wikitext,
      summary = paste0("Bolivia province locator map — COD-AB source data (", TODAY, ")"),
      token   = csrf_token
    ) |>
    req_perform() |>
    resp_body_json()
}

# Add a single structured-data claim to a file (by M-id).
add_sdc_claim <- function(mid, property, qid, csrf_token) {
  value_json <- toJSON(list(`entity-type` = "item", id = qid), auto_unbox = TRUE)
  resp <- commons_req() |>
    req_method("POST") |>
    req_body_form(
      action   = "wbcreateclaim",
      format   = "json",
      entity   = mid,
      property = property,
      snaktype = "value",
      value    = value_json,
      token    = csrf_token
    ) |>
    req_perform() |>
    resp_body_json()
  if (!is.null(resp$error))
    warning("SDC claim ", property, " on ", mid, " failed: ", resp$error$info)
  invisible(resp)
}

# Add depicts, license, and copyright-status SDC claims.
add_sdc_for_file <- function(mid, qid, csrf_token) {
  if (!is.na(qid)) {
    Sys.sleep(0.5)
    add_sdc_claim(mid, "P180", qid,        csrf_token)  # depicts
  }
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P275", "Q6938433", csrf_token)  # license: CC0 1.0
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P6216", "Q19652",  csrf_token)  # copyright status: public domain
}

# Set SDC captions in English, Spanish, and Catalan.
add_sdc_captions <- function(mid, province, csrf_token) {
  descs <- build_descriptions(province)
  for (lang in names(descs)) {
    Sys.sleep(0.5)
    resp <- commons_req() |>
      req_method("POST") |>
      req_body_form(
        action   = "wbsetlabel",
        format   = "json",
        id       = mid,
        language = lang,
        value    = descs[[lang]],
        token    = csrf_token
      ) |>
      req_perform() |>
      resp_body_json()
    if (!is.null(resp$error))
      warning("Caption (", lang, ") on ", mid, " failed: ", resp$error$info)
  }
}


# ==============================================================================
# §4 — DRY RUN (set dry_run = FALSE to actually upload)
# ==============================================================================

dry_run <- TRUE

if (dry_run) {
  cat("=== DRY RUN — no files will be uploaded ===\n\n")
  cat("First 3 wikitext previews:\n\n")
  for (i in 1:min(3, nrow(upload_meta))) {
    row <- upload_meta[i, ]
    cat("---", row$commons_filename, "---\n")
    cat(build_wikitext(row$province, TODAY, AUTHOR), "\n\n")
  }
  cat("\nMetadata table (first 10 rows):\n")
  print(upload_meta |>
          select(province, department, commons_filename, prov_file) |>
          head(10))
  stop("Dry run complete. Set dry_run <- FALSE and re-run to upload.", call. = FALSE)
}

# upload_meta <- head(upload_meta, 10)  # For testing: limit to first 10 rows.


# ==============================================================================
# §5 — UPLOAD LOOP
# ==============================================================================

commons_login()
csrf <- get_csrf_token()

upload_log <- vector("list", nrow(upload_meta))
t0 <- Sys.time()

for (i in seq_len(nrow(upload_meta))) {
  row <- upload_meta[i, ]

  if (!file.exists(row$prov_file)) {
    cat(sprintf("[%3d/%d] SKIP — file not found: %s\n", i, nrow(upload_meta), row$prov_file))
    upload_log[[i]] <- tibble(province = row$province, department = row$department,
                              status = "file_not_found", commons_filename = row$commons_filename)
    next
  }

  # Refresh CSRF token every 50 uploads
  if (i %% 50 == 1) csrf <- get_csrf_token()

  wt   <- build_wikitext(row$province, TODAY, AUTHOR)
  resp <- tryCatch(
    upload_file(row$prov_file, row$commons_filename, wt, csrf),
    error = \(e) list(error = list(info = conditionMessage(e)))
  )

  # If SVG content is an exact duplicate, fall back to a description-only edit.
  is_duplicate <- !is.null(resp$error) &&
    grepl("duplicate", resp$error$info, ignore.case = TRUE)

  if (is_duplicate) {
    edit_resp <- tryCatch(
      edit_file_description(row$commons_filename, wt, csrf),
      error = \(e) list(error = list(info = conditionMessage(e)))
    )
    if (!is.null(edit_resp$error)) {
      cat(sprintf("[%3d/%d] ERROR (edit): %s — %s\n",
                  i, nrow(upload_meta), row$commons_filename, edit_resp$error$info))
      upload_log[[i]] <- tibble(province = row$province, department = row$department,
                                status = "error", message = edit_resp$error$info,
                                commons_filename = row$commons_filename)
      next
    }
    action_label <- "EDT"
    page_id <- NULL
  } else if (!is.null(resp$error)) {
    cat(sprintf("[%3d/%d] ERROR: %s — %s\n",
                i, nrow(upload_meta), row$commons_filename, resp$error$info))
    upload_log[[i]] <- tibble(province = row$province, department = row$department,
                              status = "error", message = resp$error$info,
                              commons_filename = row$commons_filename)
    next
  } else {
    action_label <- "UPD"
    page_id <- resp$upload$pageid
  }

  # Fall back to title query if pageid not returned
  if (is.null(page_id)) {
    lookup  <- commons_req() |>
      req_url_query(action = "query", format = "json",
                    titles = paste0("File:", row$commons_filename)) |>
      req_perform() |>
      resp_body_json()
    page_id <- lookup$query$pages[[1]]$pageid
  }

  mid <- paste0("M", page_id)

  # Add depicts/license/copyright SDC and captions on fresh uploads.
  if (action_label == "UPD" && !is.null(page_id)) {
    add_sdc_for_file(mid, row$qid, csrf)
    add_sdc_captions(mid, row$province, csrf)
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eta     <- (elapsed / i) * (nrow(upload_meta) - i)
  cat(sprintf("[%3d/%d] %s %-55s  (ETA %s)\n",
              i, nrow(upload_meta), action_label, row$commons_filename,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))

  commons_url <- paste0("https://commons.wikimedia.org/wiki/File:",
                        gsub(" ", "_", row$commons_filename))

  upload_log[[i]] <- tibble(
    province         = row$province,
    department       = row$department,
    qid              = row$qid        %||% NA_character_,
    commons_filename = row$commons_filename,
    commons_url      = commons_url,
    mid              = mid,
    local_file       = row$prov_file,
    upload_date      = TODAY,
    status           = if (action_label == "EDT") "desc_edited" else "uploaded"
  )

  Sys.sleep(1.5)
}


# ==============================================================================
# §5b — DESCRIPTION-ONLY EDIT PASS
# Run this section independently if files are already uploaded but wikitext
# needs updating. Adjust desc_edit_start to skip already-edited files.
# ==============================================================================

desc_edit_start <- 1

desc_edit_meta <- upload_meta[desc_edit_start:nrow(upload_meta), ]

commons_login()
csrf <- get_csrf_token()

desc_edit_log <- vector("list", nrow(desc_edit_meta))
t0 <- Sys.time()

for (i in seq_len(nrow(desc_edit_meta))) {
  row <- desc_edit_meta[i, ]

  if (i %% 50 == 1) csrf <- get_csrf_token()

  wt   <- build_wikitext(row$province, TODAY, AUTHOR)
  resp <- tryCatch(
    edit_file_description(row$commons_filename, wt, csrf),
    error = \(e) list(error = list(info = conditionMessage(e)))
  )

  if (!is.null(resp$error)) {
    cat(sprintf("[%3d/%d] ERROR: %s — %s\n",
                i, nrow(desc_edit_meta), row$commons_filename, resp$error$info))
    desc_edit_log[[i]] <- tibble(province = row$province, department = row$department,
                                 commons_filename = row$commons_filename,
                                 status = "error", message = resp$error$info)
    next
  }

  is_nochange <- isTRUE(!is.null(resp$edit$nochange))
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eta     <- (elapsed / i) * (nrow(desc_edit_meta) - i)
  cat(sprintf("[%3d/%d] %s %-55s  (ETA %s)\n",
              i, nrow(desc_edit_meta),
              if (is_nochange) "---" else "EDT",
              row$commons_filename,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))

  desc_edit_log[[i]] <- tibble(province = row$province, department = row$department,
                                commons_filename = row$commons_filename,
                                revid  = resp$edit$newrevid %||% NA_integer_,
                                status = if (is_nochange) "nochange" else "desc_edited")

  Sys.sleep(1)
}

desc_edit_df <- bind_rows(Filter(Negate(is.null), desc_edit_log))
cat(sprintf(
  "\nDescription edit pass done in %.0f min — %d edited, %d already current, %d errors\n",
  as.numeric(difftime(Sys.time(), t0, units = "mins")),
  sum(desc_edit_df$status == "desc_edited"),
  sum(desc_edit_df$status == "nochange"),
  sum(desc_edit_df$status == "error")
))


# ==============================================================================
# §6 — SUMMARY AND SAVE
# ==============================================================================

upload_df <- bind_rows(Filter(Negate(is.null), upload_log))
cat(sprintf(
  "\nDone in %.0f min — %d uploaded, %d description-only edits, %d not found, %d errors\n",
  as.numeric(difftime(Sys.time(), t0, units = "mins")),
  sum(upload_df$status == "uploaded"),
  sum(upload_df$status == "desc_edited"),
  sum(upload_df$status == "file_not_found"),
  sum(upload_df$status == "error")
))

commons_prov_full <- upload_meta |>
  left_join(
    upload_df |> select(province, department, commons_url, mid, upload_date, status),
    by = c("province", "department")
  )

rds_path <- file.path(PROV_DIR, "commons_prov_upload_log.rds")
csv_path <- file.path(PROV_DIR, "commons_prov_upload_log.csv")

saveRDS(commons_prov_full, rds_path)
write.csv(commons_prov_full, csv_path, row.names = FALSE)
cat("Log written to", csv_path, "\n")
cat("RDS written to", rds_path, "\n")
