# import-albo-romero.R
#
# Imports Albó & Romero (2009) "Autonomías Indígenas en la Realidad Boliviana y
# su Nueva Constitución", Anexo 1: municipal CEL scale and indigenous-origin
# criteria for all 327 (2001-era) Bolivian municipalities.
#
# Source: data-raw/Albo_Romero_autonomias-indigenas_anexo_1.pdf (5 pages)
# Output: data-raw/albo_romero_autonomias_anexo1.rds
#         data-raw/albo_romero_autonomias_anexo1.csv
#
# Column layout (left side, merged in PDF):
#   codigo      — 6-digit INE municipal code (matches cod.mun in ine_geog_2013)
#   department  — department name, taken from ine_geog_2013 (properly cased with accents)
#   province    — province name, taken from ine_geog_2013 (full name, not PDF abbreviation)
#   sec         — municipal section number ("Cp" for departmental capitals, else "1"–"N")
#   municipality — municipality name (as printed; may be abbreviated)
#
# Numeric columns (commas in PDF converted to decimal points):
#   cel_0_nnn  through cel_7_sss  — 8 CEL scale categories (% horizontal)
#   crit_orig_5a7, crit_orig_4a7, crit_orig_2a7  — indigenous-origin criteria indices
#
# Text columns:
#   pueblos_orig  — indigenous people code(s) (e.g. "Q", "Ay", "G(Q)"); NA when blank
#   observaciones — free-text notes
#
# Known issues (from PDF text extraction):
#   - Municipality names are often abbreviated (e.g. "SPedro" for "San Pedro")
#   - 11 province names are merged with the section ordinal in the PDF
#     (e.g. "Villarr1ª s." instead of "Villarr 1ª s.") — handled by the parser
#   - 12 post-2001 municipalities present in ine_geog_2013 are absent from this table

library(tidyverse)
library(pdftools)


# ── 1. Read raw PDF text ──────────────────────────────────────────────────────

raw <- pdf_text("data-raw/Albo_Romero_autonomias-indigenas_anexo_1.pdf")

# Extract data lines: lines beginning with optional whitespace then a 6-digit
# code starting with 0 and a non-zero second digit
all_data_lines <- unlist(lapply(raw, function(p) strsplit(p, "\n")[[1]]))
all_data_lines <- all_data_lines[grepl("^\\s*0[1-9]\\d{4}\\s", all_data_lines)]


# ── 2. Parse left side (code + geographic fields) ────────────────────────────

parse_line <- function(line) {
  # Split at the first decimal-comma number to separate text from numerics
  m        <- regexpr("\\d+,\\d+", line)
  split_at <- as.integer(m) - 1
  left     <- trimws(substr(line, 1, split_at))
  right    <- substr(line, as.integer(m), nchar(line))

  codigo <- regmatches(left, regexpr("0[1-9]\\d{4}", left))
  rest   <- trimws(sub(codigo, "", left, fixed = TRUE))

  # Department header: ALL-CAPS block followed by separator, then capital city name
  # Patterns seen: "DEPT. Cp. City", "DEPT. City", "DEPT. Capital City",
  #                "DEPT, Capital City", "DEPT. Cap. City", "DEPT. Cp City"
  dept_match <- regmatches(rest, regexec(
    "^([A-ZÁÉÍÓÚ][A-ZÁÉÍÓÚ ]+?)[.,]\\s+(.+)$",
    rest, perl = TRUE
  ))[[1]]
  if (length(dept_match) > 0 && nchar(dept_match[2]) >= 4) {
    dept_name <- trimws(dept_match[2])
    city_part <- trimws(dept_match[3])
    # Strip capital indicator prefix; "Capital" must precede "Cap" in alternation
    city_name <- trimws(sub("^(?:Capital|Cp\\.?|Cap\\.?)\\s*", "", city_part, perl = TRUE))
    return(list(codigo = codigo, dept_raw = dept_name, prov_raw = NA_character_,
                sec = "Cp", municipality = city_name, right = right))
  }

  # Province + section ordinal (allow no space between province and ordinal —
  # PDF sometimes merges them, e.g. "Villarr1ª s.")
  parts <- regmatches(rest, regexec(
    "^(.*?)\\s*(\\d+)(ª\\s*s\\.\\s*)(.*)", rest, perl = TRUE
  ))[[1]]
  if (length(parts) > 0) {
    prov_part <- trimws(parts[2])
    sec       <- parts[3]
    mun_part  <- trimws(parts[5])
    return(list(codigo = codigo, dept_raw = NA_character_,
                prov_raw = if (nchar(prov_part) > 0) prov_part else NA_character_,
                sec = sec, municipality = mun_part, right = right))
  }

  list(codigo = codigo, dept_raw = NA_character_, prov_raw = NA_character_,
       sec = NA_character_, municipality = rest, right = right)
}

parsed <- lapply(all_data_lines, parse_line)


# ── 3. Build geographic metadata with forward-fill ───────────────────────────

geo_meta <- bind_rows(lapply(parsed, function(x) {
  tibble(codigo = x$codigo, dept_raw = x$dept_raw, prov_raw = x$prov_raw,
         sec = x$sec, municipality = x$municipality, right = x$right)
})) |>
  # Forward-fill department globally
  mutate(department = if_else(!is.na(dept_raw), dept_raw, NA_character_)) |>
  fill(department, .direction = "down") |>
  # Forward-fill province within each department; capitals have no province
  group_by(department) |>
  mutate(
    province = if_else(!is.na(prov_raw), prov_raw, NA_character_),
    province = if_else(sec == "Cp", NA_character_, province)
  ) |>
  fill(province, .direction = "down") |>
  mutate(province = if_else(sec == "Cp", NA_character_, province)) |>
  ungroup()


# ── 4. Parse right side (numeric columns + text fields) ──────────────────────

parse_right <- function(right) {
  # Convert comma decimals to dots
  r <- gsub(",", ".", right)

  num_matches <- gregexpr("\\d+\\.\\d+|\\d+(?!\\.)", r, perl = TRUE)
  nums        <- as.numeric(regmatches(r, num_matches)[[1]])

  # Text tail: everything after the last number
  last_end  <- tail(num_matches[[1]] + attr(num_matches[[1]], "match.length") - 1, 1)
  text_tail <- trimws(substr(r, last_end + 1, nchar(r)))
  toks      <- Filter(nchar, strsplit(text_tail, "\\s+")[[1]])

  # pueblos_orig: first token only if it starts with a capital letter and
  # contains no digits, %, or ª (guards against blank-pueblos rows in Tarija,
  # Beni, Pando where observaciones text would otherwise be misread as pueblos)
  first_tok       <- if (length(toks) >= 1) toks[1] else NA_character_
  first_tok_clean <- if (!is.na(first_tok))
    sub("[^A-Za-záéíóúÁÉÍÓÚ)]+$", "", first_tok) else NA_character_

  is_pueblos <- !is.na(first_tok_clean) &&
    nchar(first_tok_clean) > 0 &&
    grepl("^[A-ZÁÉÍÓÚM]", first_tok_clean) &&
    !grepl("[0-9%ª]", first_tok_clean)

  pueblos  <- if (is_pueblos) first_tok_clean else NA_character_
  obs_toks <- if (is_pueblos) toks[-1] else toks
  obs      <- if (length(obs_toks) > 0) paste(obs_toks, collapse = " ") else NA_character_
  if (!is.na(obs) && !nzchar(trimws(obs))) obs <- NA_character_

  if (length(nums) < 11) nums <- c(nums, rep(NA_real_, 11L - length(nums)))

  list(
    cel_0_nnn     = nums[1],
    cel_1_nsn     = nums[2],
    cel_2_nss     = nums[3],
    cel_3_nss     = nums[4],
    cel_4_snn     = nums[5],
    cel_5_ssnc    = nums[6],
    cel_6_sssc    = nums[7],
    cel_7_sss     = nums[8],
    crit_orig_5a7 = nums[9],
    crit_orig_4a7 = nums[10],
    crit_orig_2a7 = nums[11],
    pueblos_orig  = pueblos,
    observaciones = obs
  )
}

numeric_cols <- bind_rows(lapply(geo_meta$right, parse_right))


# ── 5. Assemble ───────────────────────────────────────────────────────────────

albo_romero <- bind_cols(
  geo_meta |> select(codigo, department, province, sec, municipality),
  numeric_cols
)


# ── 6. Replace department and province with ine_geog_2013 values ─────────────
#
# The PDF abbreviates province names (e.g. "HSiles", "N Cinti") and uses
# inconsistent casing/accents for departments. ine_geog_2013 has full, canonical
# names for every cod.mun, including the 9 departmental capitals whose province
# was NA in the raw parse. All 327 codes match; the only substantive difference
# is "POTOSÍ" (PDF) vs "Potosi" (INE) — not a conflict.

ine_mun <- ine_geog_2013 |>
  select(cod.mun, department, province) |>
  distinct()

albo_romero <- albo_romero |>
  left_join(ine_mun, by = c("codigo" = "cod.mun"), suffix = c("_albo", "_ine")) |>
  mutate(
    department = department_ine,
    province   = province_ine
  ) |>
  select(-department_albo, -province_albo, -department_ine, -province_ine)


# ── 7. Export ─────────────────────────────────────────────────────────────────

saveRDS(albo_romero, "data-raw/albo_romero_autonomias_anexo1.rds")
write_csv(albo_romero, "data-raw/albo_romero_autonomias_anexo1.csv")

message(sprintf("Exported %d rows × %d columns", nrow(albo_romero), ncol(albo_romero)))
