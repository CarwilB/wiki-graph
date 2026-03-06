library(tidyverse)
library(pdftools)

# Parse all data lines
all_lines <- unlist(lapply(raw, function(p) strsplit(p, "\n")[[1]]))
data_lines <- all_lines[grepl("^\\s{2}0[1-9]\\d{4}", all_lines)]

# Also there's "ª s." with no space between province and ordinal.
# And "SPedro Cuarahuara" — "S" merged with municipality name.
# Let me fix the parser to allow optional space before ordinal number.

parse_line_final <- function(line) {
  m <- regexpr("\\d+,\\d+", line)
  split_at <- as.integer(m) - 1
  left  <- trimws(substr(line, 1, split_at))
  right <- substr(line, as.integer(m), nchar(line))

  codigo <- regmatches(left, regexpr("0[1-9]\\d{4}", left))
  rest   <- trimws(sub(codigo, "", left, fixed = TRUE))

  # Detect dept line
  dept_match <- regmatches(rest, regexec(
    "^([A-ZÁÉÍÓÚ][A-ZÁÉÍÓÚ ]+?)[.,]\\s+(.+)$",
    rest, perl = TRUE
  ))[[1]]
  if (length(dept_match) > 0 && nchar(dept_match[2]) >= 4) {
    dept_name <- trimws(dept_match[2])
    city_part <- trimws(dept_match[3])
    city_name <- trimws(sub("^(?:Capital|Cp\\.?|Cap\\.?)\\s*", "", city_part, perl = TRUE))
    return(list(codigo = codigo, dept_raw = dept_name, prov_raw = NA_character_,
                sec = "Cp", municipality = city_name, right = right))
  }

  # Detect province + section ordinal (allow no space before ordinal)
  parts <- regmatches(rest, regexec("^(.*?)\\s*(\\d+)(ª\\s*s\\.\\s*)(.*)", rest, perl=TRUE))[[1]]
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

# Test on the problematic merged lines
for (ml in merged_lines) {
  p <- parse_line_final(ml)
  cat(sprintf("%-8s prov=%-20s sec=%-3s mun=%s\n", p$codigo, p$prov_raw %||% "NA", p$sec %||% "?", p$municipality))
}# Good - province and sec are now parsed correctly. Municipality names still abbreviated
# (SPedro, GMendoza, SP Buenavista, SPablo) but that matches the source PDF.
# These match the name_compare issues we already documented.

# Now run the full final parse
parsed_final <- lapply(all_data_lines, parse_line_final)

parsed_meta_final <- bind_rows(lapply(parsed_final, function(x) {
  tibble(codigo = x$codigo, dept_raw = x$dept_raw, prov_raw = x$prov_raw,
         sec = x$sec, municipality = x$municipality, right = x$right)
})) |>
  mutate(department = if_else(!is.na(dept_raw), dept_raw, NA_character_)) |>
  fill(department, .direction = "down") |>
  group_by(department) |>
  mutate(
    province = if_else(!is.na(prov_raw), prov_raw, NA_character_),
    province = if_else(sec == "Cp", NA_character_, province)
  ) |>
  fill(province, .direction = "down") |>
  mutate(province = if_else(sec == "Cp", NA_character_, province)) |>
  ungroup()

numeric_final <- bind_rows(lapply(parsed_meta_final$right, parse_right))

albo_romero <- bind_cols(
  parsed_meta_final |> select(codigo, department, province, sec, municipality),
  numeric_final
)

# Verify 021801
albo_romero |> filter(codigo == "021801") |> select(codigo, department, province, sec, municipality)

# Summary
cat("\nRows:", nrow(albo_romero), "\n")
albo_romero |> count(department)# Almost perfect. Two remaining issues:
# Row 4 (060301 Yacuiba): pueblo="G." — trailing period from PDF. Should strip trailing punctuation.
# Row 19 (080304 Rurrenabaque): obs="AyQ takana..." — "AyQ" looks like pueblos but it was
#   embedded inside a longer obs string: "O AyQ takana..."
#   Wait — the raw was "O AyQ takana, chimán, reyesano" so O=pueblos, "AyQ takana..."=obs.
#   That's actually correct! "O" is the primary pueblo, "AyQ" qualifies.
# Row 4: "G." — the period in obs leaked into the token. Strip trailing non-alpha from pueblos.

parse_right_fixed <- function(right) {
  r <- gsub(",", ".", right)

  num_matches <- gregexpr("\\d+\\.\\d+|\\d+(?!\\.)", r, perl = TRUE)
  nums <- as.numeric(regmatches(r, num_matches)[[1]])

  last_num_end <- tail(num_matches[[1]] + attr(num_matches[[1]], "match.length") - 1, 1)
  text_tail <- trimws(substr(r, last_num_end + 1, nchar(r)))

  toks <- strsplit(text_tail, "\\s+")[[1]]
  toks <- toks[nchar(toks) > 0]

  first_tok <- if (length(toks) >= 1) toks[1] else NA_character_

  # Strip trailing non-alphabetic from candidate pueblos token (e.g. "G." -> "G")
  first_tok_clean <- if (!is.na(first_tok)) sub("[^A-Za-záéíóúÁÉÍÓÚ)]+$", "", first_tok) else NA_character_

  is_pueblos <- !is.na(first_tok_clean) &&
    nchar(first_tok_clean) > 0 &&
    grepl("^[A-ZÁÉÍÓÚM]", first_tok_clean) &&
    !grepl("[0-9%ª]", first_tok_clean)

  pueblos <- if (is_pueblos) first_tok_clean else NA_character_
  obs_toks <- if (is_pueblos) toks[-1] else toks
  obs <- if (length(obs_toks) > 0) paste(obs_toks, collapse = " ") else NA_character_
  if (!is.na(obs) && nchar(trimws(obs)) == 0) obs <- NA_character_

  if (length(nums) < 11) nums <- c(nums, rep(NA_real_, 11 - length(nums)))

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

# Verify all 45 Tarija/Beni/Pando rows again
results2 <- lapply(test_rights, parse_right_fixed)
tibble(
  codigo = parsed_meta_final$codigo[parsed_meta_final$department %in% c("TARIJA","BENI","PANDO")],
  mun    = parsed_meta_final$municipality[parsed_meta_final$department %in% c("TARIJA","BENI","PANDO")],
  pueblo = sapply(results2, `[[`, "pueblos_orig"),
  obs    = sapply(results2, `[[`, "observaciones")
) |> print(n = 50)# That looks correct. Now rerun the full parse with the fixed function and resave.
numeric_final_fixed <- bind_rows(lapply(parsed_meta_final$right, parse_right_fixed))

albo_romero <- bind_cols(
  parsed_meta_final |> select(codigo, department, province, sec, municipality),
  numeric_final_fixed
)

write_csv(albo_romero, "data-raw/albo_romero_autonomias_anexo1.csv")
saveRDS(albo_romero, "data-raw/albo_romero_autonomias_anexo1.rds")

cat("Saved. Quick check of pueblos_orig across all departments:\n")
albo_romero |>
  count(department, pueblos_is_na = is.na(pueblos_orig)) |>
  pivot_wider(names_from = pueblos_is_na, values_from = n, names_prefix = "na_") |>
  rename(has_pueblo = `na_FALSE`, no_pueblo = `na_TRUE`)
