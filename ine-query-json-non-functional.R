library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

get_bolivia_community_coords <- function(ine_code) {
  # Base URL for the INE ArcGIS MapServer (Update layer ID as needed)
  # Layer 0 is often the point/community layer
  base_url <- "https://geoportal.ine.gob.bo/arcgis/rest/services/CENSO2024/MapServer/0/query"
  
  # Construct the request
  req <- request(base_url) %>%
    req_url_query(
      # The 'where' clause filters by your INE community code field
      where = paste0("COD_COMUNIDAD = '", ine_code, "'"),
      outFields = "COD_COMUNIDAD, NOMBRE_COMUNIDAD",
      returnGeometry = "true",
      f = "json"
    )
  
  # Perform the request
  resp <- req %>% req_perform()
  
  # Parse the JSON results
  data <- resp %>% resp_body_json()
  data <- resp %>% resp_body_html()
  
  if (length(data$features) > 0) {
    feature <- data$features[[1]]
    return(tibble(
      ine_code = feature$attributes$COD_COMUNIDAD,
      name = feature$attributes$NOMBRE_COMUNIDAD,
      lon = feature$geometry$x,
      lat = feature$geometry$y
    ))
  } else {
    return(NULL)
  }
}

# Example Usage for a list of codes
community_list <- c("01010100001", "01010103006")
results <- map_df(community_list, get_bolivia_community_coords)

print(results)