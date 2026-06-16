muni_id_lookup_table <- read_rds("data/muni_id_lookup_table.rds")
prov_id_lookup_table <- read_rds("data/prov_id_lookup_table.rds")

dep_id_lookup_table <-
  muni_id_lookup_table |>
  mutate(id_dep = stringr::str_sub(id_muni, 1L, 2L)) |>
  distinct(id_dep, department)

prov_id_long <- prov_id_lookup_table |>
  select(-n_unique) |>
  pivot_longer(
    cols = starts_with("province_"),
    names_to = "prov_var",
    values_to = "prov_name"
  )

muni_id_long <- muni_id_lookup_table |>
  select(-muni_list) |>
  pivot_longer(
    cols = starts_with("muni_"),
    names_to = "muni_var",
    values_to = "muni_name"
  )


source("R/str-equivalent.R")

id_for_province_vec <- function(prov_vec, dept_vec = NULL, prov_lookup = prov_id_long) {

  # 1. Create a tibble of the inputs
  input_df <- tibble(
    prov_input = prov_vec,
    dept_input = if (is.null(dept_vec)) rep("", length(prov_vec)) else dept_vec,
    original_order = seq_along(prov_vec)
  )

  # 2. Perform the matching (Cross Join + Filter)
  matches <- input_df %>%
    cross_join(prov_lookup) %>%
    filter(str_equivalent(prov_name, prov_input)) %>%
    filter(dept_input == "" | str_equivalent(department, dept_input))

  # --- WARNING LOGIC START ---
  # Identify inputs that matched to more than one unique id_prov
  duplicates <- matches %>%
    group_by(original_order, prov_input, dept_input) %>%
    summarise(unique_ids = n_distinct(id_prov), .groups = "drop") %>%
    filter(unique_ids > 1)

  if (nrow(duplicates) > 0) {
    # Format a string of the first few problematic names to show in the warning
    problem_list <- duplicates %>%
      distinct(prov_input, dept_input) %>%
      mutate(desc = paste0("'", prov_input, "' in '", dept_input, "'")) %>%
      slice_head(n = 10) %>%
      pull(desc) %>%
      paste(collapse = ", ")

    warning(paste(
      "Multiple distinct IDs found for some inputs. Returning first match for:",
      problem_list, if(nrow(duplicates) > 10) "... [truncated]" else ""
    ))
  }
  # --- WARNING LOGIC END ---

  # 3. Resolve to one ID per input (taking the first match)
  resolved_matches <- matches %>%
    group_by(original_order) %>%
    slice(1) %>%
    ungroup()

  # 4. Join back to ensure the output vector is the same length as the input
  final_output <- input_df %>%
    left_join(resolved_matches, by = "original_order") %>%
    pull(id_prov)

  return(final_output)
}

id_for_municipality_vec <- function(muni_vec, dept_vec = NULL, muni_lookup = muni_id_long) {

  # 1. Create a tibble of the inputs
  input_df <- tibble(
    muni_input = muni_vec,
    dept_input = if (is.null(dept_vec)) rep("", length(muni_vec)) else dept_vec,
    original_order = seq_along(muni_vec)
  )

  # 2. Perform the matching (Cross Join + Filter)
  matches <- input_df %>%
    cross_join(muni_lookup) %>%
    filter(str_equivalent(muni_name, muni_input)) %>%
    filter(dept_input == "" | str_equivalent(department, dept_input))

  # --- WARNING LOGIC START ---
  # Identify inputs that matched to more than one unique id_muni
  duplicates <- matches %>%
    group_by(original_order, muni_input, dept_input) %>%
    summarise(unique_ids = n_distinct(id_muni), .groups = "drop") %>%
    filter(unique_ids > 1)

  if (nrow(duplicates) > 0) {
    # Format a string of the first few problematic names to show in the warning
    problem_list <- duplicates %>%
      distinct(muni_input, dept_input) %>%
      mutate(desc = paste0("'", muni_input, "' in '", dept_input, "'")) %>%
      slice_head(n = 10) %>%
      pull(desc) %>%
      paste(collapse = ", ")

    warning(paste(
      "Multiple distinct IDs found for some inputs. Returning first match for:",
      problem_list, if(nrow(duplicates) > 10) "... [truncated]" else ""
    ))
  }
  # --- WARNING LOGIC END ---

  # 3. Resolve to one ID per input (taking the first match)
  resolved_matches <- matches %>%
    group_by(original_order) %>%
    slice(1) %>%
    ungroup()

  # 4. Join back to ensure the output vector is the same length as the input
  final_output <- input_df %>%
    left_join(resolved_matches, by = "original_order") %>%
    pull(id_muni)

  return(final_output)
}
