library(readr)

linguameta_root_path <- "../url-nlp/linguameta"
linguameta_data_path <- "../url-nlp/linguameta/data"
linguameta_metadata <- read_tsv(file = file.path(linguameta_root_path, "linguameta.tsv"))

linguameta_metadata |>
  arrange(desc(estimated_number_of_speakers)) |>
  select(1,3,5, 10, 11) |>
  print(n=100)
names(linguameta_metadata)


langs_df <- read_csv('data/data-Mww3K.csv')
langs_df

