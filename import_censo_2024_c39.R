
library(tidyverse)

# Raw data from Cuadro 39
raw_lines <- c(
  # idioma, 2012_total, 2012_hombres, 2012_mujeres, 2012_urbana, 2012_rural, 2024_total, 2024_hombres, 2024_mujeres, 2024_urbana, 2024_rural
  "BOLIVIA,8756348,4354435,4401913,5927116,2829232,10216385,5094971,5121414,7094525,3121860",
  # --- Idiomas oficiales ---
  "Idiomas oficiales,7675076,3813496,3861580,5139179,2535897,10071583,5019588,5051995,7041013,3030570",
  "Afroboliviano,NA,NA,NA,NA,NA,428,207,221,52,376",
  "Araona,24,9,15,2,22,99,57,42,2,97",
  "Aymara,836570,404543,432027,329450,507120,576798,267372,309426,143706,433092",
  "Baure,21,11,10,15,6,10,4,6,6,4",
  "Bésiro,2401,1209,1192,602,1799,1341,727,614,443,898",
  "Canichana,7,4,3,1,6,7,6,1,3,4",
  "Castellano,5424685,2725785,2698900,4312320,1112365,8385257,4220637,4164620,6612138,1773119",
  "Cayubaba,12,8,4,3,9,5,2,3,3,2",
  "Chácobo,806,429,377,41,765,1037,531,506,46,991",
  "Ese ejja,676,336,340,18,658,1175,611,564,263,912",
  "Guaraní,39307,19692,19615,10331,28976,36174,18086,18088,5246,30928",
  "Guarasu've,0,0,0,0,0,0,0,0,0,0",
  "Gwarayu,6980,3466,3514,5965,1015,6503,3272,3231,5589,914",
  "Itonama,29,17,12,26,3,34,19,15,32,2",
  "Joaquiniano,NA,NA,NA,NA,NA,7,3,4,5,2",
  "Kabineña,733,377,356,114,619,891,481,410,51,840",
  "Leco,53,33,20,17,36,76,49,27,25,51",
  "Macha'juyay kallawaya,1,0,1,1,0,9,8,1,0,9",
  "Machineri,9,6,3,0,9,9,7,2,0,9",
  "Maropa,116,67,49,43,73,25,16,9,13,12",
  "Mojeño-ignaciano,1051,591,460,693,358,277,157,120,191,86",
  "Mojeño-trinitario,2585,1380,1205,864,1721,1400,722,678,377,1023",
  "Moré,8,6,2,1,7,8,7,1,7,1",
  "Mosetén,757,414,343,48,709,739,386,353,41,698",
  "Movima,502,288,214,295,207,167,99,68,101,66",
  "Pacahuara,6,2,4,0,6,25,13,12,0,25",
  "Puquina,76,41,35,23,53,50,26,24,11,39",
  "Quechua,1339919,645546,694373,476530,863389,1033963,493205,540758,270951,763012",
  "Sirionó,160,76,84,16,144,66,40,26,7,59",
  "Tacana,812,470,342,198,614,548,314,234,77,471",
  "Tapiete,48,28,20,6,42,47,29,18,7,40",
  "Tsimane',8904,4727,4177,417,8487,15266,7983,7283,205,15061",
  "Uru-chipaya,1383,691,692,30,1353,1853,942,911,17,1836",
  "Weenhayek,3482,1776,1706,543,2939,4216,2062,2154,609,3607",
  "Yaminawa,127,63,64,5,122,102,51,51,9,93",
  "Yuqui,123,63,60,22,101,234,119,115,3,231",
  "Yurakaré,1345,653,692,64,1281,802,395,407,53,749",
  "Zamuco,1177,597,580,365,812,1589,774,815,711,878",
  "Otras declaraciones,181,92,89,110,71,346,169,177,13,333",
  "Lengua de señas,NA,NA,NA,NA,NA,1649,811,838,1380,269",
  # --- Idiomas extranjeros ---
  "Idiomas extranjeros,146772,78509,68263,98447,48325,90534,46826,43708,18378,72156",
  "Albanés,2,2,0,1,1,1,1,0,1,0",
  "Alemán,46901,23652,23249,4188,42713,69830,35466,34364,1222,68608",
  "Árabe,125,85,40,120,5,104,78,26,103,1",
  "Búlgaro,14,2,12,14,0,3,1,2,2,1",
  "Catalán,335,165,170,329,6,44,28,16,41,3",
  "Checo,0,0,0,0,0,10,3,7,8,2",
  "Chino,714,448,266,652,62,1279,920,359,971,308",
  "Coreano,371,192,179,363,8,317,150,167,309,8",
  "Croata,34,17,17,34,0,9,3,6,9,0",
  "Danés,24,13,11,20,4,18,11,7,17,1",
  "Finlandés,4,2,2,4,0,3,3,0,3,0",
  "Francés,2509,1217,1292,2392,117,560,324,236,499,61",
  "Gallego,0,0,0,0,0,0,0,0,0,0",
  "Griego,0,0,0,0,0,5,4,1,4,1",
  "Hebreo,0,0,0,0,0,11,10,1,11,0",
  "Holandés,214,120,94,192,22,96,52,44,57,39",
  "Húngaro,16,11,5,14,2,15,6,9,10,5",
  "Inglés,61686,33563,28123,60185,1501,4409,2641,1768,3838,571",
  "Italiano,1591,834,757,1486,105,360,203,157,324,36",
  "Japonés,1671,809,862,1428,243,617,255,362,436,181",
  "Latín,0,0,0,0,0,32,20,12,32,0",
  "Noruego,51,27,24,47,4,18,7,11,16,2",
  "Persa,0,0,0,0,0,42,21,21,42,0",
  "Polaco,0,0,0,0,0,55,23,32,51,4",
  "Portugués,28954,16513,12441,25804,3150,11863,6177,5686,9909,1954",
  "Rumano,31,16,15,30,1,9,2,7,9,0",
  "Ruso,664,338,326,415,249,590,270,320,240,350",
  "Serbio,12,7,5,9,3,7,4,3,7,0",
  "Sueco,184,100,84,151,33,42,28,14,38,4",
  "Suizo,61,30,31,0,61,4,1,3,3,1",
  "Tailandés,2,1,1,2,0,0,0,0,0,0",
  "Taiwanés,0,0,0,0,0,12,5,7,12,0",
  "Turco,12,9,3,11,1,32,27,5,29,3",
  "Ucraniano,8,4,4,7,1,20,8,12,18,2",
  "Valenciano,0,0,0,0,0,3,1,2,3,0",
  "Vasco,14,8,6,10,4,3,1,2,3,0",
  "Vietnamés,8,7,1,3,5,4,3,1,3,1",
  "Otro idioma extranjero,560,317,243,536,24,107,69,38,98,9",
  # --- Other categories ---
  "No habla,11944,6273,5671,6543,5401,18326,9981,8345,12129,6197",
  "Sin especificar,922556,456157,466399,682947,239609,34293,17765,16528,21625,12668"
)

cuadro39 <- read_csv(
  paste(raw_lines, collapse = "\n"),
  col_names = c("idioma",
                "c2012_total", "c2012_hombres", "c2012_mujeres", "c2012_urbana", "c2012_rural",
                "c2024_total", "c2024_hombres", "c2024_mujeres", "c2024_urbana", "c2024_rural"),
  col_types = "cdddddddddd"
)

# cuadro39


# Save as both RDS and CSV
saveRDS(cuadro39, "../bolivia-data/Censo 2024/cuadro39_idioma_mayor_uso.rds")
write_csv(cuadro39, "../bolivia-data/Censo 2024/cuadro39_idioma_mayor_uso.csv")
cat("Saved. Rows:", nrow(cuadro39), "\n")
print(cuadro39, n = Inf)


base_path <- "data/"

tail_rows <- cuadro39[82:83, ]

cuadro39_nacional <- bind_rows(cuadro39[1:42, ], tail_rows)
cuadro39_extranjero <- bind_rows(cuadro39[c(1, 43:81), ], tail_rows)

saveRDS(cuadro39_nacional,   paste0(base_path, "cuadro39_nacional.rds"))
saveRDS(cuadro39_extranjero, paste0(base_path, "cuadro39_extranjero.rds"))
write_csv(cuadro39_nacional,   paste0(base_path, "cuadro39_nacional.csv"))
write_csv(cuadro39_extranjero, paste0(base_path, "cuadro39_extranjero.csv"))

cat("cuadro39_nacional:   ", nrow(cuadro39_nacional),   "rows\n")
cat("cuadro39_extranjero: ", nrow(cuadro39_extranjero), "rows\n")

get_wikidata_instances("Q34770", country = "Q750") -> langs_bo_wikidata

source(here::here(""))
