lang_use |>
  filter(mat_label != "Castellano") |>
  mutate(
    uso_group = case_when(
      uso_label == mat_label    ~ "Same indigenous language",
      uso_label == "Castellano" ~ "Castellano",
      uso_label %in% indigenous_langs ~ "Different indigenous language",
      uso_label == "No habla"   ~ "No habla",
      TRUE                      ~ "Other/foreign"
    )
  ) |>
  group_by(mat_label, uso_group) |>
  summarise(n = sum(n), .groups = "drop") |>
  group_by(mat_label) |>
  mutate(total = sum(n), pct = round(100 * n / total, 1)) |>
  ungroup() |>
  select(mat_label, uso_group, pct, total) |>
  pivot_wider(names_from = uso_group, values_from = pct, values_fill = 0) |>
  relocate(`Same indigenous language`, .after="total") |>
  arrange(desc(`Same indigenous language`)) -> lang_use_table

lang_use_table |> arrange(total)

