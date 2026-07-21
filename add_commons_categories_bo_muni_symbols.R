# add_commons_categories.R
#
# Adds 95 flag files and 2 coat-of-arms files to their respective Commons
# categories. These files are already linked in Wikidata (P41 / P94) but were
# absent from the Commons categories used during the flag/coat matching pass.
#
# Categories being added:
#   Flags:       [[Category:Flags of municipalities of Bolivia]]
#   Coats:       [[Category:Coats of arms of municipalities of Bolivia]]
#
# Prerequisites (same as upload_to_commons.R):
#   Add to ~/.Renviron (then restart R):
#     COMMONS_BOT_USER=Carwil@YourBotName
#     COMMONS_BOT_PASSWORD=your_bot_password
#
# Source wd_flags_not_in_commons and wd_coats_not_in_commons must be in the
# global environment (loaded by sourcing the review RDS or running the analysis).

library(httr2)
library(dplyr)
library(tibble)

COMMONS_API <- "https://commons.wikimedia.org/w/api.php"
BOT_USER    <- Sys.getenv("COMMONS_BOT_USER")
BOT_PASS    <- Sys.getenv("COMMONS_BOT_PASSWORD")

stopifnot(
  "COMMONS_BOT_USER not set in .Renviron"     = nzchar(BOT_USER),
  "COMMONS_BOT_PASSWORD not set in .Renviron" = nzchar(BOT_PASS)
)

CAT_FLAGS <- "Flags of municipalities of Bolivia"
CAT_COATS <- "Coats of arms of municipalities of Bolivia"


# ==============================================================================
# §1 — SESSION HELPERS (same pattern as upload_to_commons.R)
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


# ==============================================================================
# §2 — CATEGORY HELPERS
# ==============================================================================

# Returns TRUE if `category` (without "Category:" prefix) is already on the file.
file_has_category <- function(filename, category) {
  resp <- commons_req() |>
    req_url_query(
      action       = "query",
      format       = "json",
      titles       = paste0("File:", filename),
      prop         = "categories",
      clcategories = paste0("Category:", category)
    ) |>
    req_perform() |>
    resp_body_json()

  page <- resp$query$pages[[1]]
  if ("missing" %in% names(page)) {
    warning("File not found on Commons: ", filename)
    return(NA)
  }
  length(page$categories) > 0
}

# Appends a category wikilink to a file page if it isn't already there.
# Returns one of: "skipped" | "added" | "not_found" | "error:<msg>"
add_category_to_file <- function(filename, category, csrf_token) {
  already <- file_has_category(filename, category)

  if (is.na(already)) return("not_found")
  if (already)        return("skipped")

  summary_text <- paste0(
    "Adding [[Category:", category, "]] ",
    "(file linked from Wikidata P41/P94 but absent from category)"
  )

  resp <- commons_req() |>
    req_method("POST") |>
    req_body_form(
      action     = "edit",
      format     = "json",
      title      = paste0("File:", filename),
      appendtext = paste0("\n[[Category:", category, "]]"),
      summary    = summary_text,
      bot        = "1",
      token      = csrf_token
    ) |>
    req_perform() |>
    resp_body_json()

  if (!is.null(resp$error))
    return(paste0("error:", resp$error$info))

  if (resp$edit$result == "Success") "added" else paste0("unexpected:", resp$edit$result)
}


# ==============================================================================
# §3 — BUILD WORK TABLE
# ==============================================================================

work_flags <- wd_flags_not_in_commons |>
  select(ine_code, muni_name, department, qid, file = flag_file) |>
  mutate(category = CAT_FLAGS)

work_coats <- wd_coats_not_in_commons |>
  select(ine_code, muni_name, department, qid, file = coat_file) |>
  mutate(category = CAT_COATS)

work <- bind_rows(work_flags, work_coats)
cat("Files to process:", nrow(work),
    paste0("(", nrow(work_flags), " flags, ", nrow(work_coats), " coats)\n"))


# ==============================================================================
# §4 — DRY RUN (inspect before committing)
# ==============================================================================
# Run this block to preview the files and categories without making any edits.

cat("\n--- DRY RUN: files that will be categorised ---\n")
work |>
  select(muni_name, department, file, category) |>
  print(n = Inf)


# ==============================================================================
# §5 — LIVE RUN
# ==============================================================================
# Uncomment and run the block below after reviewing the dry run output above.

commons_login()
csrf <- get_csrf_token()

results <- work |>
  mutate(outcome = NA_character_)

for (i in seq_len(nrow(results))) {
  row <- results[i, ]
  cat(sprintf("[%d/%d] %-45s ... ", i, nrow(results), row$file))

  outcome <- tryCatch(
    add_category_to_file(row$file, row$category, csrf),
    error = function(e) paste0("error:", conditionMessage(e))
  )

  results$outcome[i] <- outcome
  cat(outcome, "\n")

  # Refresh CSRF token every 50 edits
  if (i %% 50 == 1 && i > 1) csrf <- get_csrf_token()

  Sys.sleep(1)
}

cat("\n--- Summary ---\n")
print(table(results$outcome))

saveRDS(results, here::here("data", "commons_category_add_results.rds"))
readr::write_csv(results, here::here("data", "commons_category_add_results.csv"))
cat("Results saved.\n")
