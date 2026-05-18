# upload_to_commons.R
# Uploads Bolivia municipality locator maps to Wikimedia Commons.
#
# Prerequisites:
#   Add to ~/.Renviron (then restart R):
#     COMMONS_BOT_USER=Carwil@YourBotName    # bot password login (MainAccount@BotName)
#     COMMONS_BOT_PASSWORD=your_bot_password  # from Special:BotPasswords
#     COMMONS_AUTHOR=Carwil                   # display name for wikitext author field
#
#   In session:
#     results_df             — from generate_locator_maps_workbench.R
#     municipalities_wd_ine  — Wikidata QIDs keyed by INE code
#     muni_id_lookup_table   — maps GADM name + department to id_muni
#     dupe_muni_names        — character vector of duplicated municipality names

library(httr2)
library(dplyr)
library(tibble)
library(jsonlite)

COMMONS_API <- "https://commons.wikimedia.org/w/api.php"
TODAY       <- format(Sys.Date(), "%Y-%m-%d")
BOT_USER    <- Sys.getenv("COMMONS_BOT_USER")
BOT_PASS    <- Sys.getenv("COMMONS_BOT_PASSWORD")
AUTHOR      <- Sys.getenv("COMMONS_AUTHOR")

stopifnot(
  "COMMONS_BOT_USER not set in .Renviron"    = nzchar(BOT_USER),
  "COMMONS_BOT_PASSWORD not set in .Renviron" = nzchar(BOT_PASS),
  "COMMONS_AUTHOR not set in .Renviron"       = nzchar(AUTHOR)
)


# ==============================================================================
# §1 — BUILD UPLOAD METADATA TABLE
# ==============================================================================

upload_meta <- results_df |>
  as_tibble() |>
  left_join(
    muni_id_lookup_table |> select(id_muni, muni_gadm, department),
    by = c("municipality" = "muni_gadm", "department" = "department")
  ) |>
  left_join(
    municipalities_wd_ine |> select(qid, ine_code),
    by = c("id_muni" = "ine_code")
  ) |>
  mutate(
    muni_gadm = municipality, # Preserve original GADM name for tracking
    municipality = muni_anexo,  # Prefer our list of names
    # Commons filename mirrors the local naming convention, with original
    # accents restored and spaces instead of underscores (Commons normalises).
    commons_filename = if_else(
      municipality %in% dupe_muni_names,
      paste0(municipality, " (", department, ") muni locator map.svg"),
      paste0(municipality, " muni locator map.svg")
    )
  )

# Report missing QIDs before starting
n_missing <- sum(is.na(upload_meta$qid))
if (n_missing > 0) {
  cat("WARNING:", n_missing, "municipalities have no Wikidata QID:\n")
  upload_meta |> filter(is.na(qid)) |> pull(municipality) |> cat(sep = "\n")
  cat("\n")
}


# ==============================================================================
# §2 — WIKITEXT BUILDER
# ==============================================================================

# Catalan elision: "de X" → "d'X" when X begins with a vowel.
ca_prep <- function(name) {
  if (grepl("^[AEIOUaeiouÀÈÌÒÙàèìòùÁÉÍÓÚáéíóú]", name)) {
    paste0("d\u2019", name)   # right single quotation mark, as on Commons
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
    "|source={{own}}\n",
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

# Persistent cookie file keeps the session alive across requests.
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

upload_file <- function(local_path, commons_filename, wikitext, csrf_token) {
  commons_req() |>
    req_method("POST") |>
    req_body_multipart(
      action   = "upload",
      format   = "json",
      filename = commons_filename,
      text     = wikitext,
      comment  = paste0("Bolivia municipality locator map — ", TODAY),
      token    = csrf_token,
      file     = curl::form_file(local_path, type = "image/svg+xml")
    ) |>
    req_timeout(120) |>
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

add_sdc_for_file <- function(mid, qid, csrf_token) {
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P180", qid,        csrf_token)  # depicts
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P275", "Q6938433", csrf_token)  # copyright license: CC0 1.0
  Sys.sleep(0.5)
  add_sdc_claim(mid, "P6216", "Q19652",  csrf_token)  # copyright status: public domain
}

# Set captions (SDC labels) in all four languages.
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
    cat("---", row$commons_filename, "---\n")
    cat(build_wikitext(row$municipality, TODAY, AUTHOR), "\n\n")
  }
  cat("\nMetadata table (first 10 rows):\n")
  print(upload_meta |> select(municipality, department, qid, commons_filename, file) |> head(10))
  stop("Dry run complete. Set dry_run <- FALSE and re-run to upload.", call. = FALSE)
}

# upload_meta <- head(upload_meta, 10)  # For testing: limit to first 10 rows. Remove or comment out for full upload.)
upload_meta <- upload_meta[20:339,]
# ==============================================================================
# §5 — UPLOAD LOOP
# ==============================================================================

commons_login()
csrf <- get_csrf_token()

upload_log <- vector("list", nrow(upload_meta))
t0 <- Sys.time()

for (i in seq_len(nrow(upload_meta))) {
  row <- upload_meta[i, ]

  # Verify local file exists
  if (!file.exists(row$file)) {
    cat(sprintf("[%3d/%d] SKIP — file not found: %s\n", i, nrow(upload_meta), row$file))
    upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                              status = "file_not_found", commons_filename = row$commons_filename)
    next
  }

  # Skip if already on Commons
  if (file_exists_on_commons(row$commons_filename)) {
    cat(sprintf("[%3d/%d] SKIP — already exists: %s\n", i, nrow(upload_meta), row$commons_filename))
    upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                              status = "already_exists", commons_filename = row$commons_filename)
    next
  }

  # Refresh CSRF token every 50 uploads (guards against long-running sessions)
  if (i %% 50 == 1) csrf <- get_csrf_token()

  wt   <- build_wikitext(row$municipality, TODAY, AUTHOR)
  resp <- tryCatch(
    upload_file(row$file, row$commons_filename, wt, csrf),
    error = \(e) list(error = list(info = conditionMessage(e)))
  )

  if (!is.null(resp$error)) {
    cat(sprintf("[%3d/%d] ERROR: %s — %s\n",
                i, nrow(upload_meta), row$commons_filename, resp$error$info))
    upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                              status = "error", message = resp$error$info,
                              commons_filename = row$commons_filename)
    next
  }

  page_id <- resp$upload$pageid

  # Upload API doesn't always return pageid; fall back to a title query.
  if (is.null(page_id)) {
    lookup  <- commons_req() |>
      req_url_query(action = "query", format = "json",
                    titles = paste0("File:", row$commons_filename)) |>
      req_perform() |>
      resp_body_json()
    page_id <- lookup$query$pages[[1]]$pageid
  }

  mid <- paste0("M", page_id)

  # Add structured data claims (depicts, license, copyright status) and captions
  if (!is.null(page_id)) {
    if (!is.na(row$qid)) add_sdc_for_file(mid, row$qid, csrf)
    add_sdc_captions(mid, row$municipality, csrf)
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eta     <- (elapsed / i) * (nrow(upload_meta) - i)
  cat(sprintf("[%3d/%d] OK  %-55s  (ETA %s)\n",
              i, nrow(upload_meta), row$commons_filename,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))

  commons_url <- paste0("https://commons.wikimedia.org/wiki/File:",
                        gsub(" ", "_", row$commons_filename))

  upload_log[[i]] <- tibble(municipality = row$municipality, department = row$department,
                             id_muni = row$id_muni %||% NA_character_,
                             qid = row$qid %||% NA_character_,
                             commons_filename = row$commons_filename,
                             commons_url = commons_url,
                             mid = mid,
                             local_file = row$file,
                             upload_date = TODAY,
                             status = "uploaded")

  Sys.sleep(1.5)  # ~40 uploads/minute — well within bot limits
}

# ==============================================================================
# §6 — SUMMARY AND SAVE
# ==============================================================================

upload_df <- bind_rows(Filter(Negate(is.null), upload_log))
cat(sprintf(
  "\nDone in %.0f min — %d uploaded, %d skipped (exist), %d not found, %d errors\n",
  as.numeric(difftime(Sys.time(), t0, units = "mins")),
  sum(upload_df$status == "uploaded"),
  sum(upload_df$status == "already_exists"),
  sum(upload_df$status == "file_not_found"),
  sum(upload_df$status == "error")
))

# Full record: upload_meta columns + Commons identifiers and upload date.
# Non-uploaded rows (errors, skips) have NA for Commons-specific fields.
commons_upload_full <- upload_meta |>
  left_join(
    upload_df |> select(municipality, department, commons_url, mid, upload_date, status),
    by = c("municipality", "department")
  )

out_dir  <- "output/locator_maps/muni-maps-final"
rds_path <- file.path(out_dir, "commons_upload_log.rds")
csv_path <- file.path(out_dir, "commons_upload_log.csv")

saveRDS(commons_upload_full, rds_path)
write.csv(commons_upload_full, csv_path, row.names = FALSE)
cat("Log written to", csv_path, "\n")
cat("RDS written to", rds_path, "\n")
