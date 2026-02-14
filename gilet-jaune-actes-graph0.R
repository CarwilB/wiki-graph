# Load necessary library
library(ggplot2)
library(tidyr)

# Create the data
actes <- paste0("A", 1:33)
ministere <- c(287700,166000,136000,136000,66000,38600,32000,50000,84000,84000,69000,58600,51400,41500,46600,39300,28600,32300,40500,33700,22300,31000,27900,23600,18900,18600,15500,12500,9500,10300,7000,11800,5800)
nombre_jaune <- c(0,0,0,0,0,0,68100,123440,159160,147370,123150,115900,118220,104070,123090,96430,90470,0,126250,105080,73290,91280,98180,60710,42860,45240,42130,40240,23540,19490,18500,27440,10730)
france_police <- c(1300000,750000,809500,700000,0,300000,0,300000,360000,350000,330000,290000,240000,230000,200000,200000,160000,290000,90000,120000,110000,90000,90000,60000,60000,60000,55000,55000,40000,40000,35000,40000,0)

# Combine into a data frame
df <- data.frame(
  Acte = factor(actes, levels = actes),
  `Ministère de l'Intérieur` = ministere,
  `Nombre Jaune` = nombre_jaune,
  `France Police` = france_police
)

# Reshape the data for ggplot
df_long <- pivot_longer(df, cols = -Acte, names_to = "Source", values_to = "Nombre")

# Plot
ggplot(df_long, aes(x = Acte, y = Nombre, color = Source, group = Source)) +
  geom_line(size=1.2) +
  geom_point(size=2) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Nombre de manifestants par acte",
    x = "Acte",
    y = "Nombre de manifestants",
    color = "Source"
  ) +
  scale_color_manual(values = c("Ministère de l'Intérieur"="blue", "Nombre Jaune"="yellow", "France Police"="brown")) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
