# source("wikiblame.R")
# source("get-wikipedia-text.R")
# source("highlight-changes.R")


txt1 <- get_wikitext_from_url("https://en.wikipedia.org/wiki/Margaret_Mead")
txt2 <- get_wikitext_from_url("https://en.wikipedia.org/w/index.php?title=Margaret_Mead&oldid=1316523564")
margaret_mead_2025_before_revid <- 1316523564

margaret_mead_map <- get_revision_history_map("Margaret Mead", "en")
result <- find_sentence_insertion("Margaret Mead", "since it claimed that females are dominant",
                                  lang = "en", history_map = margaret_mead_map)


sentences_mm_2024 <- extract_clean_fragments(txt2, keep_link_text = TRUE)
sentences_mm_2024_8words <- stringr::word(sentences_mm_2024, 1, 8)


mm_problem_sentence_blame <- track_wikipedia_sentences("Margaret Mead", c("reports detailing the attitudes towards sex", "after Mead's divorce from Cressman", "a close friend of her instructor", "the relationship between Benedict and Mead was partly sexual", "a close personal and professional collaboration", "the book tackled the question of nature versus nurture", "became influential within the ", "Mead identified two types of sex relations: love affairs and adultery", "it claimed that females are dominant in the Tchambuli", "both men and women were peaceful in temperament", "spent their time decorating themselves while the women", "as far back in history as there is evidence (1850s)", "Mundugumor women hazed each other less than men hazed", "on the basis that it contributes to infantilizing women"))
mm_problem_sentence_blame <- mm_problem_sentence_blame %>%
  mutate(day_added= as_date(date_added),
         link = paste0("https://en.wikipedia.org/w/index.php?title=Margaret_Mead&oldid=",revision_id),
         revision = paste0("[",revision_id,"](",link,")")) 

mm_problem_sentence_blame %>%
  select(original_sentence, date_added, added_by, revision) %>%
  arrange(date_added) %>%
  kableExtra::kable()

margaret_mead_history <- margaret_mead_history %>% mutate(date <- as_date(timestamp))
margaret_mead_map[412,]$revid -> mragaret_mead_2007_revid

txt_2007 <- get_wikitext_from_url("https://en.wikipedia.org/w/index.php?title=Margaret_Mead&oldid=85796476")


margaret_mead_history[1100,]$revid -> margaret_mead_2010_revid

text_current_plain <- get_plain_text(title = "Margaret Mead")
text_2025_plain <- get_plain_text_revid(revision_id = margaret_mead_2025_before_revid )
text_2010_plain <- get_plain_text_revid(revision_id = margaret_mead_2010_revid)
text_2007_plain <- get_plain_text_revid(revision_id = mragaret_mead_2007_revid)

# Output to console with yellow text
result_console <- highlight_prior_segments(text_current_plain, text_2025_plain, format = "console")
cat(result_console)

# Output to HTML (ideal for viewing in RStudio Viewer or a browser)
result_html <- highlight_prior_segments(text_2025_plain, text_2010_plain, format = "html")
result_html <- highlight_prior_segments(text_current_plain, text_2025_plain, format = "html")
# In RStudio, you can view this with:
htmltools::browsable(htmltools::HTML(result_html))

my_additions_console <- highlight_new_segments(text_current_plain, text_2025_plain, format = "console")
cat(my_additions_console)
