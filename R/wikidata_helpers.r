# ---- .resolve_property_names ------------------------------------------------
# Internal helper: resolve and pad/truncate property_names vectors to match
# the length of the property vector, issuing warnings if requested.

.resolve_property_names <- function(props, names, type_label = "property") {
  if (is.null(props) || length(props) == 0) return(NULL)
  
  props <- as.character(props)
  n_prop <- length(props)
  
  if (is.null(names)) {
    names <- props
  }
  
  n_names <- length(names)
  
  if (n_names > n_prop) {
    if (type_label == "property") {
      message("property_names has more entries (", n_names, ") than property (",
              n_prop, "); extra names will be ignored.")
    }
    names <- names[seq_len(n_prop)]
  } else if (n_names < n_prop) {
    if (n_names > 0 && type_label == "property") {
      message("property_names has fewer entries (", n_names, ") than property (",
              n_prop, "); falling back to property IDs for unnamed columns.")
    }
    names <- c(names, props[(n_names + 1):n_prop])
  }
  
  names
}

# ---- .validate_entity_props -------------------------------------------------
# Internal helper: Ensure that entity_props includes 'claims' when properties
# are requested.

.validate_entity_props <- function(property, numeric_list_properties, entity_props) {
  if (!is.null(property) && length(property) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("property=... requires entity_props to include 'claims' (so we can read property values).")
  }
  if (!is.null(numeric_list_properties) && length(numeric_list_properties) > 0 && !grepl("(^|\\|)claims(\\||$)", entity_props)) {
    stop("numeric_list_properties requires entity_props to include 'claims'.")
  }
}