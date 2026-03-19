source("src/str-equivalent.R")

muni_id_lookup_table <- readr::read_rds("data/muni_id_lookup_table.rds")

#' Rename Columns in a Dataframe for Standardization
#'
#' This function renames specific columns in a dataframe to standardize their names.
#' It ensures that the columns `municipality`, `province`, and `department` are present, renaming existing columns
#' (`municipio`, `provincia`, `departamento`) if necessary. Additionally, it renames any column starting with `codigo`
#' to `cod.mun`.
#'
#' @param dataframe A dataframe containing the columns to be standardized.
#'
#' @return A dataframe with standardized column names.
#'
#' @details
#' - The function checks for the presence of `municipality`, `province`, and `department`.
#'   If these columns are missing, it renames `municipio`, `provincia`, and `departamento` to their English equivalents.
#' - Any column name starting with `codigo` is renamed to `cod.mun`.
#'
#' @examples
#' # Example dataframe
#' df <- data.frame(
#'   municipio = c("La Paz", "Cochabamba"),
#'   provincia = c("Pedro Domingo Murillo", "Cercado"),
#'   departamento = c("La Paz", "Cochabamba"),
#'   codigo123 = c(101, 102)
#' )
#'
#' # Rename columns
#' renamed_df <- rename_anexo_columns(df)
#' print(names(renamed_df)) # Should include "municipality", "province", "department", "cod.mun"
#'
#' @importFrom dplyr rename rename_with starts_with pull mutate rowwise
#' @export
rename_anexo_columns <- function(dataframe) {
  # Check if destination columns are missing and perform renaming accordingly
  if (!"municipality" %in% names(dataframe)) {
    dataframe <- dataframe %>%
      dplyr::rename(municipality = municipio)
  }
  if (!"province" %in% names(dataframe)) {
    dataframe <- dataframe %>%
      dplyr::rename(province = provincia)
  }
  if (!"department" %in% names(dataframe)) {
    dataframe <- dataframe %>%
      dplyr::rename(department = departamento)
  }

  # Rename "codigo" columns to "cod.mun" without suffix
  dataframe <- dataframe %>%
    dplyr::rename_with(~ gsub("^codigo.*$", "cod.mun", .), .cols = dplyr::starts_with("codigo"))

  return(dataframe)
}

#' Get the ID of a municipality based on its name
#'
#' Returns the unique identifier for a municipality based on its name and
#' optionally the department. These identifiers are the codes used
#' in the Bolivian government databases, known as INE codes for the
#' Instituto Nacional de Estadística.
#'
#' The function will warn the user if a municipality name without
#' department corresponds to multiple municipalities. In this case, the first
#' municipality found will be returned. (There are about a dozen such cases in Bolivia.)
#'
#' `id_for_municipality_2` is a version of the function that handles lookup
#'   tables with lists of municipalities. It is relies on `muni_id_lookup_table`.
#'
#' @param municipality_i Name of the municipality to search for.
#' @param department_i Optional name of the department to filter by.
#' @param muni_list_table A data frame containing the municipality list table.
#'
#' @return The unique identifier for the municipality as listed in the `code` =
#'   column of the `muni_list_table`. If no match is found, returns an empty string.
#'
#' @export
#' @examples
#'  id_for_municipality("La Paz") # 020101
#'  id_for_municipality("La Paz", "La Paz") # 020101
#'  id_for_municipality("La Paz", "Cochabamba") # empty string
#'  id_for_municipality("Potosí", "Potosí") # 050101
#'  id_for_municipality("Potosi") # 050101
#'  id_for_municipality("San Ramón") # 071103
#'  id_for_municipality("San Ramón", "Santa Cruz") # 071103
#'  id_for_municipality("San Ramón", "Beni") # 080702
#'
#'  id_for_municipality_2("zudanez") # "010301"
#'  id_for_municipality_2("villa montes") # "060303"
#'  id_for_municipality_2("villamontes") # "060303"
#'  id_for_municipality_2("San Ignacio") # "070301"
#'  id_for_municipality_2("San Ignacio", "Beni") # "080501"
id_for_municipality <- function(municipality_i, department_i = "", muni_list_table = anexo_municipios) {
  if (is.na(municipality_i)){
    return(as.character(NA))
  }

  # Rename columns if necessary
  if ("municipio" %in% names(muni_list_table) && !"municipality" %in% names(muni_list_table)) {
    muni_list_table <- rename_anexo_columns(muni_list_table)
  }

  # Ensure the first column is named "code" and formatted as character with leading zeros
  names(muni_list_table)[1] <- "code"
  # reformat first column as a character with leading zero
  if (is.numeric(dplyr::pull(muni_list_table,1))){
    muni_list_table <- muni_list_table %>%
      dplyr::mutate(code = as.character(sprintf("%06d", code)))
  }

  # Filter by municipality
  municipality_row <- muni_list_table %>%
    dplyr::filter(str_equivalent(municipality, municipality_i))
  #  print((municipality_row))

  if (nrow(municipality_row) == 0) {
    warning(paste("Municipality", municipality_i, "not found. Returning empty string."))
    return("")
  }

  # Further filter by department if provided
  if (department_i != "") {
    municipality_row <- municipality_row %>%
      dplyr::filter(str_equivalent(department, department_i))
    if (nrow(municipality_row) == 0) {
      warning(paste("Municipality", municipality_i, "not found in department", department_i, ". Returning empty string."))
      return("")
    }
  }

  # Handle multiple results
  if (nrow(municipality_row) > 1) {
    warning(paste("Multiple municipalities found for", municipality_i,
                  if (department_i != "") paste("in department", department_i) else "without department",
                  ". Returning first ID found."))
  }

  return(unname(municipality_row$code[1]))
}

#' Add an unique identifier for municipality (id_muni) column to a dataset
#'
#' @param dataset A dataframe with a column containing the name of the
#'   municipality, named `municipality`.
#' @param id_variable_name The name of the new column to be created. Default is
#'   `id_muni`.
#' @param muni_table A data frame containing the municipality list table.
#' @param overwrite A boolean indicating whether to overwrite an existing
#'   column.
#'
#' @return A dataframe with a new column `id_muni` containing the unique
#'   identifier for the municipality, placed before the `municipality` column.
#'
#' @export
#'
#' @examples
#' id_for_municipality("Villa Ricardo Mugia - Icla", muni_list_table = muni_gb2014_lookup)
#' id_for_municipality_2("Villa Ricardo Mugia - Icla", "Chuquisaca")
add_id_for_municipality <- function(dataset,
                                    id_variable_name = "id_muni",
                                    muni_table = anexo_municipios,
                                    overwrite = FALSE){
  if (!"municipality" %in% names(dataset)) {
    stop("The dataset does not contain the 'municipality' column.")
  }
  if (id_variable_name %in% names(dataset) &
      overwrite == FALSE) {
    warning(paste("The dataset already contains the specified municipality id column. ",
                  "Call add_id_for_event() with overwrite = TRUE to replace it."))
    return(dataset)
  }

  # dataset[[id_variable_name]] <- vapply(dataset$municipality, function(x) id_for_municipality(x, "", muni_table),
  #                                       FUN.VALUE = character(1))
  if ("muni_list" %in% names(muni_table)) {
    # If the table has a list of municipalities, use id_for_municipality_2
    dataset[[id_variable_name]] <- vapply(seq_len(nrow(dataset)), function(i) {
      id_for_municipality_2(dataset$municipality[i], dataset$department[i], muni_table)
    }, FUN.VALUE = character(1))
  } else {
    # Otherwise, use id_for_municipality
    dataset[[id_variable_name]] <- vapply(seq_len(nrow(dataset)), function(i) {
      id_for_municipality(dataset$municipality[i], dataset$department[i], muni_table)
    }, FUN.VALUE = character(1))
  }

  dataset <- dataset %>%
    dplyr::relocate(!!rlang::sym(id_variable_name), .before = municipality)

  return(dataset)
}


#' @rdname id_for_municipality
#' @export
id_for_municipality_2 <- function(municipality_i, department_i = "", muni_list_table = muni_id_lookup_table) {
  if (is.na(municipality_i)){
    return(as.character(NA))
  }

  assertthat::assert_that(
    is.character(municipality_i),
    is.character(department_i),
    is.data.frame(muni_list_table),
    "muni_list" %in% names(muni_list_table)
  )

  # Filter by municipality
  municipality_row <- muni_list_table %>%
    dplyr::rowwise() %>%
    dplyr::filter(str_equivalent_list(municipality_i, muni_list))

  # Check if no rows match the municipality
  if (nrow(municipality_row) == 0) {
    warning(paste("Municipality", municipality_i, "not found. Returning empty string."))
    return("")
  }

  # Further filter by department if provided
  if (department_i != "") {
    municipality_row <- municipality_row %>%
      dplyr::filter(str_equivalent(department, department_i))
    if (nrow(municipality_row) == 0) {
      warning(paste("Municipality", municipality_i, "not found in department", department_i, ". Returning empty string."))
      return("")
    }
  }

  # Handle multiple results
  if (nrow(municipality_row) > 1) {
    warning(paste("Multiple municipalities found for", municipality_i,
                  if (department_i != "") paste("in department", department_i) else "without department",
                  ". Returning first ID found."))
  }

  # Return the first matching id_muni
  return(unname(municipality_row$id_muni[1]))
}

# reshape lookup table
muni_id_lookup_long <- muni_id_lookup_table %>%
  select(id_muni, department, muni_list) %>%
  unnest(muni_list) %>%
  rename(municipality_name = muni_list) %>%
  # Clean names to ensure matches (optional but recommended)
  mutate(municipality_name = trimws((municipality_name)),
         department = trimws((department)))

muni_id_long <- muni_id_lookup_table |>
  select(-muni_list) |>
  pivot_longer(
    cols = starts_with("muni_"),
    names_to = "muni_var",
    values_to = "muni_name"
  )

id_for_municipality_3 <- function(municipality_i, department_i = "", muni_list_table = muni_id_lookup_long) {
  if (is.na(municipality_i)){
    return(as.character(NA))
  }

  assertthat::assert_that(
    is.character(municipality_i),
    is.character(department_i),
    is.data.frame(muni_list_table),
    all(c("id_muni", "department", "municipality_name") %in% names(muni_list_table))
  )

  # Filter by municipality
  municipality_row <- muni_list_table %>%
    dplyr::filter(str_equivalent(municipality_name, municipality_i))

  # Check if no rows match the municipality
  if (nrow(municipality_row) == 0) {
    warning(paste("Municipality", municipality_i, "not found. Returning empty string."))
    return("")
  }

  # Further filter by department if provided
  if (department_i != "") {
    municipality_row <- municipality_row %>%
      dplyr::filter(str_equivalent(department, department_i))
    if (nrow(municipality_row) == 0) {
      warning(paste("Municipality", municipality_i, "not found in department", department_i, ". Returning empty string."))
      return("")
    }
  }

  # Handle multiple results
  if (nrow(municipality_row) > 1) {
    if (length(unique(municipality_row$id_muni)) > 1) {
      warning(paste("Multiple municipalities found for", municipality_i,
                    if (department_i != "") paste("in department", department_i) else "without department",
                    ". Returning first ID found."))
    } else {
      # If all rows the same ID, multiple matches aren't a problem.
    }
  }

  # Return the first matching id_muni
  return(unname(municipality_row$id_muni[1]))
}

id_for_municipality_vec <- function(muni_vec, dept_vec = NULL, muni_lookup = muni_id_lookup_long) {

  # 1. Create a tibble of the inputs
  input_df <- tibble(
    muni_input = muni_vec,
    dept_input = if (is.null(dept_vec)) rep("", length(muni_vec)) else dept_vec,
    original_order = seq_along(muni_vec)
  )

  # 2. Perform the matching (Cross Join + Filter)
  matches <- input_df %>%
    cross_join(muni_lookup) %>%
    filter(str_equivalent(municipality_name, muni_input)) %>%
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

#' Get Municipality Details from ID Vector
#'
#' This function looks up municipality details (municipality, province, and department)
#' from a list of municipality IDs in the given `muni_list_table`.
#'
#' @param id_muni A character vector of municipality IDs to look up.
#' @param muni_list_table A tibble or dataframe containing municipality information.
#'                        The table must have columns `cod.mun`, `municipality`, `province`, and `department`.
#'
#' @return A list with three components:
#'   - `municipality`: A character vector of municipality names.
#'   - `province`: A character vector of province names.
#'   - `department`: A character vector of department names.
#'
#' @details
#' The function performs a lookup by matching the `id_muni` with the `cod.mun` column in `muni_list_table`.
#' If an ID is not found, the corresponding entries in the output list will be `NA`.
#'
#' @examples
#' # Example `muni_list_table`
#' anexo_municipios <- tibble::tibble(
#'   cod.mun = c("010101", "010102", "010103"),
#'   municipality = c("Sucre", "Yotala", "Poroma"),
#'   province = c("Oropeza", "Oropeza", "Oropeza"),
#'   department = c("Chuquisaca", "Chuquisaca", "Chuquisaca")
#' )
#'
#' # Lookup municipality details
#' ids <- c("010101", "010102", "010999")
#' result <- municipality_name_from_id(ids, anexo_municipios)
#' print(result)
#'
#' @export
municipality_vector_from_id <- function(id_muni, muni_list_table=anexo_municipios) {

  # Rename columns if necessary
  if ("municipio" %in% names(muni_list_table) && !"municipality" %in% names(muni_list_table)) {
    muni_list_table <- rename_anexo_columns(muni_list_table)
  }

  # Ensure the first column is named "code" and formatted as character with leading zeros
  names(muni_list_table)[1] <- "code"
  # reformat first column as a character with leading zero
  if (is.numeric(dplyr::pull(muni_list_table,1))){
    muni_list_table <- muni_list_table %>%
      dplyr::mutate(code = as.character(sprintf("%06d", code)))
  }
  # Check if id_muni is a character vector
  if (is.numeric(id_muni)) {
    id_muni <- as.character(sprintf("%06d", id_muni))
  }

  # Perform a lookup for each ID in the id_muni
  matched_rows <- muni_list_table[match(id_muni, muni_list_table$code), ]

  # Extract the required columns and handle missing matches
  municipality <- matched_rows$municipality
  province <- matched_rows$province
  department <- matched_rows$department

  # Replace missing values (rows not found) with NA
  municipality[is.na(matched_rows$code)] <- NA
  province[is.na(matched_rows$code)] <- NA
  department[is.na(matched_rows$code)] <- NA

  # Return the result as a list
  list(
    municipality = municipality,
    province = province,
    department = department
  )
}
# Get the geographic names from municipal ID
#
# These function retrieve the municipality, province, and department names
#' from the unique identifier (ID) of a municipality. The ID is a code used
#' in the Bolivian government databases, known as INE codes for the
#' Instituto Nacional de Estadística.
#'
#' @param id_muni A character vector of municipality IDs to look up.
#' @param muni_list_table A lookup dataframe containing municipality information.
#'
#' @return A string with the name of the municipality, province, or department.
#'
#' @rdname municipality_vector_from_id
#' @export
#'
#' @examples
#' municipality_name_from_id("020101") # "La Paz"
#' municipality_name_from_id("050101") # "Potosí"
#' municipality_name_from_id("071103") # "San Ramón"
#' municipality_name_from_id("080702") # "San Ramón"
#' municipality_name_from_id("010301") # "Villa Zudáñez"
#' province_name_from_id("020101") # "Murillo"
#' province_name_from_id("050101") # "Tomás Frías"
#' province_name_from_id("071103") # "Ñuflo de Chaves"
#' province_name_from_id("080702") # "Mamoré"
#' province_name_from_id("010301") # "Zudáñez"
#' province_name_from_id("060303") # "Gran Chaco"
#' province_name_from_id("070301") # "Velasco"
#' province_name_from_id("080501") # "Moxos"
#' department_name_from_id("020101") # "La Paz"
#' department_name_from_id("050101") # "Potosí"
#' department_name_from_id("071103") # "Santa Cruz"
#' department_name_from_id("080702") # "Beni"
#' department_name_from_id("010301") # "Chuquisaca"
#' department_name_from_id("060303") # "Tarija"
#' department_name_from_id("070301") # "Santa Cruz"
#' department_name_from_id("080501") # "Beni"
municipality_name_from_id <- function(id_muni, muni_list_table=anexo_municipios) {
  vector <- municipality_vector_from_id(id_muni, muni_list_table)
  # Return the municipality names
  vector$municipality
}

#' @rdname municipality_vector_from_id
#' @export
province_name_from_id <- function(id_muni, muni_list_table=anexo_municipios) {
  vector <- municipality_vector_from_id(id_muni, muni_list_table)
  # Return the province names
  vector$province
}

#' @rdname municipality_vector_from_id
#' @export
department_name_from_id <- function(id_muni, muni_list_table=anexo_municipios) {
  vector <- municipality_vector_from_id(id_muni, muni_list_table)
  # Return the department names
  vector$department
}

#' Add Municipality GB2014 Code from ID
#'
#' This function adds a column `muni_gb2014` to a dataframe based on the `id_muni` column.
#' It uses a lookup table to map `id_muni` to `muni_gb2014`.
#'
#' @param dataframe A dataframe containing a column `id_muni`.
#' @param muni_table A lookup table containing `id_muni` and `muni_gb2014` columns.
#' @return A dataframe with an additional column `muni_gb2014` containing the corresponding GB2014 codes.
#'
#' @export
add_muni_gb2014_from_id <- function(dataframe, muni_table = muni_id_lookup_table){
  # Check if the dataframe has a column named "id_muni"
  if (!"id_muni" %in% names(dataframe)) {
    stop("The dataframe does not contain a column named 'id_muni'.")
  }
  # Check if the muni_table has column named "id_muni" and "muni_gb2014"
  if (!"id_muni" %in% names(muni_table)) {
    stop("The lookup does not contain a column named 'id_muni'.")
  }
  if (!"muni_gb2014" %in% names(muni_table)) {
    stop("The lookup does not contain a column named 'muni_gb2014'.")
  }

  lookup_table <- muni_table %>%
    dplyr::select(id_muni, muni_gb2014) %>%
    dplyr::distinct()

  # Join the lookup table with the dataframe
  dataframe <- dataframe %>%
    dplyr::left_join(lookup_table, by = "id_muni")

  return(dataframe)
}

# deaths_aug24 %>% add_id_for_municipality() %>%
#   add_muni_gb2014_from_id() %>%
#   select(event_title, municipality, muni_gb2014) %>%
#   filter(municipality != muni_gb2014)
# de %>% add_id_for_municipality() %>%
#   add_muni_gb2014_from_id() %>%
#   select(event_title, municipality, muni_gb2014) %>%
#   filter(municipality != muni_gb2014) %>%
#   distinct(municipality, muni_gb2014)

