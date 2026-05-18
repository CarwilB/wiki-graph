# upload_hd_to_commons.R
# Uploads HD versions of Bolivia municipality locator maps to Wikimedia Commons,
# replacing existing files with new versions. For files not yet on Commons,
# uploads them as new files.
#
# Source files: output/locator_maps/muni-maps-hd/
# Wikitext update: adds COD-AB data attribution to all files.
#
# Prerequisites (same as upload_to_commons.R):
#   ~/.Renviron:
#     COMMONS_BOT_USER=Carwil@YourBotName
#     COMMONS_BOT_PASSWORD=your_bot_password
#     COMMONS_AUTHOR=Carwil
#
#   In session:
#     commons_upload_full    — from previous upload run (upload_to_commons.R)
#     muni_id_lookup_table   — maps muni names across sources
#     dupe_muni_names        — character vector of duplicated municipality names

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
HD_DIR      <- "output/locator_maps/muni-maps-hd"

stopifnot(
  "COMMONS_BOT_USER not set in .Renviron"     = nzchar(BOT_USER),
  "COMMONS_BOT_PASSWORD not set in .Renviron" = nzchar(BOT_PASS),
  "COMMONS_AUTHOR not set in .Renviron"       = nzchar(AUTHOR)
)


# ==============================================================================
# §1 — BUILD HD UPLOAD METADATA TABLE
# ==============================================================================

# Duplicate muni_anexo names (those needing department disambiguator in filename)
dupe_anexo_names <- muni_id_lookup_table |>
  count(muni_anexo) |>
  filter(n > 1) |>
  pull(muni_anexo)

# Reconstruct the hd_stem each entry produces (matches generate_locator_maps_workbench.R §6)
hd_stem_tbl <- muni_id_lookup_table |>
  mutate(
    clean_name = stri_trans_general(muni_anexo, "Latin-ASCII"),
    clean_dept = stri_trans_general(department,  "Latin-ASCII"),
    hd_stem = if_else(
      muni_anexo %in% dupe_anexo_names,
      gsub("[^a-zA-Z0-9_()-]", "_", paste0(clean_name, "_(", clean_dept, ")")),
      gsub("[^a-zA-Z0-9_-]",   "_", clean_name)
    )
  ) |>
  select(id_muni, muni_gadm, muni_anexo, department, hd_stem)

# Enumerate HD files and join to lookup
hd_files_df <- tibble(
  hd_file = list.files(HD_DIR, pattern = "\\.svg$", full.names = TRUE)
) |>
  mutate(hd_stem = sub("_muni_locator_map\\.svg$", "", basename(hd_file)))

upload_meta <- hd_files_df |>
  left_join(hd_stem_tbl, by = "hd_stem") |>
  # Attach existing Commons metadata (commons_filename, mid, status) from prior upload
  left_join(
    commons_upload_full |>
      select(id_muni, commons_filename, commons_url, mid, qid,
             upload_date, status),
    by = "id_muni"
  ) |>
  mutate(
    municipality = muni_anexo,
    # For files not previously uploaded, derive commons_filename now
    commons_filename = if_else(
      is.na(commons_filename),
      if_else(
        muni_anexo %in% dupe_muni_names,
        paste0(muni_anexo, " (", department, ") muni locator map.svg"),
        paste0(muni_anexo, " muni locator map.svg")
      ),
      commons_filename
    )
  )

# Sanity check: all HD files matched?
n_unmatched <- sum(is.na(upload_meta$id_muni))
if (n_unmatched > 0) {
  cat("WARNING:", n_unmatched, "HD files could not be matched to the lookup table:\n")
  upload_meta |> filter(is.na(id_muni)) |> pull(hd_stem) |> cat(sep = "\n")
  cat("\n")
}

# All 339 files are confirmed on Commons (some were uploaded before the log was started).
# Report how many have log entries for reference only.
n_logged   <- sum(!is.na(upload_meta$upload_date))
n_unlogged <- sum(is.na(upload_meta$upload_date))
cat(sprintf("HD upload plan: %d files (all version updates; %d have prior log entries, %d do not)\n",
            nrow(upload_meta), n_logged, n_unlogged))

# Name-change check: does the expected commons_filename match what was logged?
name_diffs <- upload_meta |>
  filter(!is.na(upload_date)) |>
  mutate(
    expected_commons_filename = if_else(
      muni_anexo %in% dupe_muni_names,
      paste0(muni_anexo, " (", department, ") muni locator map.svg"),
      paste0(muni_anexo, " muni locator map.svg")
    )
  ) |>
  filter(commons_filename != expected_commons_filename)

if (nrow(name_diffs) > 0) {
  cat("\nNAME CHANGES DETECTED (", nrow(name_diffs), " files):\n", sep = "")
  cat("These files were uploaded under a different name than the lookup table now suggests.\n")
  cat("They will be uploaded under the ORIGINAL name (no rename on Commons).\n\n")
  name_diffs |>
    select(id_muni, muni_gadm, department, commons_filename, expected_commons_filename) |>
    print()
} else {
  cat("Name check: no discrepancies between lookup table and previously uploaded filenames.\n")
}


# ==============================================================================
# §2 — WIKITEXT BUILDER (updated with COD-AB attribution)
# ==============================================================================

# Catalan elision: "de X" → "d'X" when X begins with a vowel.
ca_prep <- function(name) {
  if (grepl("^[AEIOUaeiouÀÈÌÒÙàèìòùÁÉÍÓÚáéíóú]", name)) {
    paste0("d\u2019", name)
  } else {
    paste0("de ", name)
  }
}

build_descriptions <- function(municipality) {
  list(
    en = paste0("Locator map showing ", municipality,
                " Municipality in a map of Bolivian municipalities, provinces, and departments"),
    es = paste0("Mapa de localización que muestra el municipio de ", municipality,
                " en un mapa de los municipios, provincias y departamentos de Bolivia"),
    ca = paste0("Mapa localitzador que mostra el municipi ", ca_prep(municipality),
                " en un mapa dels municipis, prov\u00edncies i departaments de Bol\u00edvia."),
    qu = paste0(municipality,
                " Munisipiyuta rikuchiq tarina mapa, Bolivia suyuq munisipiyunkunata,",
                " pruwinkunata, departamentunkunatapas rikuchispa.")
  )
}

build_wikitext <- function(municipality, date, author) {
  desc <- build_descriptions(municipality)
  en <- desc$en; es <- desc$es; ca <- desc$ca; qu <- desc$qu

  paste0(
    "=={{int:filedesc}}==\n",
    "{{Information\n",
    "|description={{en|1=", en, "}}\n",
    "{{es|1=", es, "}}\n",
    "{{ca|1=", ca, "}}\n",
    "{{qu|1=", qu, "}}\n",
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
    "[[Category:Locator maps of municipalities in Bolivia]]"
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

file_exists_on_commons <- function(filename) {
  resp <- commons_req() |>
    req_url_query(action = "query", format = "json",
                  titles = paste0("File:", filename)) |>
    req_perform() |>
    resp_body_json()
  page <- resp$query$pages[[1]]
  !"missing" %in% names(page)
}

# Upload a new file version (always with ignorewarnings to overwrite existing).
upload_file <- function(local_path, commons_filename, wikitext, csrf_token) {
  commons_req() |>
    req_method("POST") |>
    req_body_multipart(
      action          = "upload",
      format          = "json",
      filename        = commons_filename,
      text            = wikitext,
      comment         = paste0("Upload HD version — updated COD-AB data attribution (", TODAY, ")"),
      token           = csrf_token,
      ignorewarnings  = "true",
      file            = curl::form_file(local_path, type = "image/svg+xml")
    ) |>
    req_timeout(120) |>
    req_perform() |>
    resp_body_json()
}

# Edit the description page only (used as fallback when upload detects a duplicate SVG).
edit_file_description <- function(commons_filename, wikitext, csrf_token) {
  commons_req() |>
    req_method("POST") |>
    req_body_form(
      action  = "edit",
      format  = "json",
      title   = paste0("File:", commons_filename),
      text    = wikitext,
      summary = paste0("Add COD-AB data attribution to source field (", TODAY, ")"),
      token   = csrf_token
    ) |>
    req_perform() |>
    resp_body_json()
}

# Structured-data helpers (unchanged from upload_to_commons.R)
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

add_sdc_for_file <- function(mid, qid, csrf_token) {
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P180", qid,        csrf_token)  # depicts
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P275", "Q6938433", csrf_token)  # copyright license: CC0 1.0
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P6216", "Q19652",  csrf_token)  # copyright status: public domain
}

add_sdc_captions <- function(mid, municipality, csrf_token) {
  descs <- build_descriptions(municipality)
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
    is_update <- !is.na(row$upload_date)
    cat("---", row$commons_filename, if (is_update) "[UPDATE]" else "[NEW]", "---\n")
    cat(build_wikitext(row$municipality, TODAY, AUTHOR), "\n\n")
  }
  cat("\nMetadata table (first 10 rows):\n")
  print(upload_meta |>
          select(municipality, department, commons_filename, hd_file, upload_date) |>
          mutate(action = if_else(is.na(upload_date), "NEW", "UPDATE")) |>
          select(-upload_date) |>
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

  # Verify local HD file exists
  if (!file.exists(row$hd_file)) {
    cat(sprintf("[%3d/%d] SKIP — HD file not found: %s\n", i, nrow(upload_meta), row$hd_file))
    upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                              status = "file_not_found", commons_filename = row$commons_filename)
    next
  }

  # Refresh CSRF token every 50 uploads
  if (i %% 50 == 1) csrf <- get_csrf_token()

  # Upload new HD version; fall back to description edit if SVG is identical.
  wt     <- build_wikitext(row$municipality, TODAY, AUTHOR)
  resp   <- tryCatch(
    upload_file(row$hd_file, row$commons_filename, wt, csrf),
    error = \(e) list(error = list(info = conditionMessage(e)))
  )

  # Commons returns an error for exact-duplicate files; edit the description instead.
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
      upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                                status = "error", message = edit_resp$error$info,
                                commons_filename = row$commons_filename)
      next
    }
    action_label <- "EDT"  # description edited, no new file version
    page_id <- NULL         # pageid not returned by action=edit; look it up below
  } else if (!is.null(resp$error)) {
    cat(sprintf("[%3d/%d] ERROR: %s — %s\n",
                i, nrow(upload_meta), row$commons_filename, resp$error$info))
    upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
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

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eta     <- (elapsed / i) * (nrow(upload_meta) - i)
  cat(sprintf("[%3d/%d] %s %-55s  (ETA %s)\n",
              i, nrow(upload_meta), action_label, row$commons_filename,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))

  commons_url <- paste0("https://commons.wikimedia.org/wiki/File:",
                        gsub(" ", "_", row$commons_filename))

  upload_log[[i]] <- tibble(
    municipality     = row$municipality,
    department       = row$department,
    id_muni          = row$id_muni          %||% NA_character_,
    qid              = row$qid              %||% NA_character_,
    commons_filename = row$commons_filename,
    commons_url      = commons_url,
    mid              = mid,
    local_file       = row$hd_file,
    upload_date      = TODAY,
    status           = if (action_label == "EDT") "desc_edited" else "updated"
  )

  Sys.sleep(1.5)  # ~40 uploads/minute — well within bot limits
}


# ==============================================================================
# §5b — DESCRIPTION-ONLY EDIT PASS
# Run this section independently after the upload loop when file content is
# already correct but the wikitext needs updating (e.g. adding attribution).
# Acasio and Achacachi (rows 1–2) were already edited; start from row 3.
# ==============================================================================

desc_edit_start <- 3   # First row to edit (1-indexed into upload_meta)

desc_edit_meta  <- upload_meta[desc_edit_start:nrow(upload_meta), ]

commons_login()
csrf <- get_csrf_token()

desc_edit_log <- vector("list", nrow(desc_edit_meta))
t0 <- Sys.time()

for (i in seq_len(nrow(desc_edit_meta))) {
  row <- desc_edit_meta[i, ]

  # Refresh CSRF token every 50 edits
  if (i %% 50 == 1) csrf <- get_csrf_token()

  wt   <- build_wikitext(row$municipality, TODAY, AUTHOR)
  resp <- tryCatch(
    edit_file_description(row$commons_filename, wt, csrf),
    error = \(e) list(error = list(info = conditionMessage(e)))
  )

  if (!is.null(resp$error)) {
    cat(sprintf("[%3d/%d] ERROR: %s — %s\n",
                i, nrow(desc_edit_meta), row$commons_filename, resp$error$info))
    desc_edit_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
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

  desc_edit_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                                commons_filename = row$commons_filename,
                                revid = resp$edit$newrevid %||% NA_integer_,
                                status = if (is_nochange) "nochange" else "desc_edited")

  Sys.sleep(1)  # description edits are lighter than uploads; 60/min is fine
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
  "\nDone in %.0f min — %d new versions uploaded, %d description-only edits, %d not found, %d errors\n",
  as.numeric(difftime(Sys.time(), t0, units = "mins")),
  sum(upload_df$status == "updated"),
  sum(upload_df$status == "desc_edited"),
  sum(upload_df$status == "file_not_found"),
  sum(upload_df$status == "error")
))

commons_hd_full <- upload_meta |>
  left_join(
    upload_df |> select(municipality, department, commons_url, mid, upload_date, status),
    by = c("municipality", "department")
  )

out_dir  <- HD_DIR
rds_path <- file.path(out_dir, "commons_hd_upload_log.rds")
csv_path <- file.path(out_dir, "commons_hd_upload_log.csv")

saveRDS(commons_hd_full, rds_path)
write.csv(commons_hd_full, csv_path, row.names = FALSE)
cat("Log written to", csv_path, "\n")
cat("RDS written to", rds_path, "\n")
