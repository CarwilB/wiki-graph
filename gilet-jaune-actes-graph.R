# Load necessary libraries
library(ggplot2)
library(readr)
library(dplyr)
library(tidyr)
library(lubridate)

# Read the CSV
df <- read_csv("../wiki-graph/gilet-jaune-actes.csv")

# Convert the 'Date' column to ISO format (YYYY-MM-DD), assuming all are 2000s
df <- df %>%
  mutate(
    Date_ISO = dmy(Date),
    # Fix year for dates that are in the 1900s (e.g., 18/11/24 -> 2018-11-24)
    Date_ISO = if_else(year(Date_ISO) < 2000, Date_ISO + years(100), Date_ISO)
  )

# Gather the counts into long format for plotting
df_long <- df %>%
  pivot_longer(
    cols = c(`Ministère de l'Intérieur`, `Nombre Jaune`, `France Police`),
    names_to = "Source",
    values_to = "Nombre"
  )

# Plot as bar chart
ggplot(df_long, aes(x = Date_ISO, y = Nombre, fill = Source)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.9), width = 0.25) +
  labs(
    title = "Nombre de manifestants par acte",
    x = "Date",
    y = "Nombre de manifestants",
    fill = "Source"
  ) +
  theme_minimal(base_size = 13) +
  scale_x_date(date_breaks = "2 weeks", date_labels = "%Y-%m-%d") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
