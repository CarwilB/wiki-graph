# Examples and tests for create_quick_statement()
# Source the main function first
source("create_quick_statement.R")

# ============================================================================
# STRING EXAMPLES
# ============================================================================

# Basic string value (e.g., software version)
create_quick_statement("Q14579", "P348", "6.13.7")
# Q14579	P348	"6.13.7"

# String with URL
create_quick_statement("Q14579", "P856", "https://kernel.org/")
# Q14579	P856	"https://kernel.org/"

# ============================================================================
# MONOLINGUAL TEXT EXAMPLES
# ============================================================================

# Monolingual text in English
create_quick_statement("Q935", "P1559", "Isaac Newton", 
                      lang = "en", type = "monolingual")
# Q935	P1559	en:"Isaac Newton"

# Monolingual text in French
create_quick_statement("Q935", "P1559", "Isaac Newton", 
                      lang = "fr", type = "monolingual")
# Q935	P1559	fr:"Isaac Newton"

# ============================================================================
# LABEL EXAMPLES
# ============================================================================

# English label
create_quick_statement("Q1001", property = "L", "Mahatma Gandhi", 
                      lang = "en", type = "label")
# Q1001	Len	"Mahatma Gandhi"

# Portuguese label
create_quick_statement("Q1001", property = "L", "Mahatma Gandhi", 
                      lang = "pt", type = "label")
# Q1001	Lpt	"Mahatma Gandhi"

# ============================================================================
# DESCRIPTION EXAMPLES
# ============================================================================

# English description
create_quick_statement("Q1001", property = "D", 
                      "Indian independence activist (1869–1948)", 
                      lang = "en", type = "description")
# Q1001	Den	"Indian independence activist (1869–1948)"

# French description
create_quick_statement("Q1001", property = "D", 
                      "leader politique et religieux indien (1869–1948)", 
                      lang = "fr", type = "description")
# Q1001	Dfr	"leader politique et religieux indien (1869–1948)"

# ============================================================================
# ALIAS EXAMPLES
# ============================================================================

# Esperanto alias
create_quick_statement("Q1001", property = "A", "Mahatmo Gandho", 
                      lang = "eo", type = "alias")
# Q1001	Aeo	"Mahatmo Gandho"

# English alias
create_quick_statement("Q1001", property = "A", "Gandhi", 
                      lang = "en", type = "alias")
# Q1001	Aen	"Gandhi"

# ============================================================================
# WITH REFERENCES
# ============================================================================

# String with reference (default retrieved date = today)
create_quick_statement("Q42", "P856", "https://example.com",
                      add_reference = TRUE,
                      reference_url = "https://example.com")
# Q42	P856	"https://example.com"	S854	"https://example.com"	S813	+2026-02-19T00:00:00Z/11

# Item value with reference and custom retrieved date
create_quick_statement("Q42", "P19", "Q350", type = "item",
                      add_reference = TRUE,
                      reference_url = "https://britannica.com/douglas-adams",
                      retrieved_date = "2024-01-15")
# Q42	P19	Q350	S854	"https://britannica.com/douglas-adams"	S813	+2024-01-15T00:00:00Z/11

# Monolingual text with reference
create_quick_statement("Q935", "P1559", "Isaac Newton", 
                      lang = "en", type = "monolingual",
                      add_reference = TRUE,
                      reference_url = "https://example.com/newton")
# Q935	P1559	en:"Isaac Newton"	S854	"https://example.com/newton"	S813	+2026-02-19T00:00:00Z/11

# ============================================================================
# WITH QUALIFIERS
# ============================================================================

# String with qualifier
create_quick_statement("Q40269", "P1082", "1360590", type = "quantity",
                      qualifiers = list(
                        P585 = "+2000-08-01T00:00:00Z/11",
                        P459 = "Q39825"
                      ))
# Q40269	P1082	1360590	P585	+2000-08-01T00:00:00Z/11	P459	Q39825

# ============================================================================
# WITH EDIT SUMMARY
# ============================================================================

# String with comment
create_quick_statement("Q8023", "P18", "Nelson Mandela 1994.jpg",
                      comment = "Add image to Nelson Mandela")
# Q8023	P18	"Nelson Mandela 1994.jpg"	/* Add image to Nelson Mandela */

# ============================================================================
# COMPLETE EXAMPLE WITH EVERYTHING
# ============================================================================

# Full statement with qualifiers, reference, and comment
create_quick_statement("Q12418", "P276", "Q10292830", type = "item",
                      qualifiers = list(
                        P585 = "+2017-01-01T00:00:00Z/11"
                      ),
                      add_reference = TRUE,
                      reference_url = "http://cartelfr.louvre.fr/cartelfr/visite?srv=car_not_frame&idNotice=14153",
                      retrieved_date = "2017-09-23",
                      comment = "Update location of Mona Lisa")
# Q12418	P276	Q10292830	P585	+2017-01-01T00:00:00Z/11	S854	"http://..."	S813	+2017-09-23T00:00:00Z/11	/* Update location of Mona Lisa */

# ============================================================================
# USING WITH LAST (for newly created items)
# ============================================================================

# Create item commands
cat("CREATE\n")
create_quick_statement("LAST", property = "L", "New Item", 
                      lang = "en", type = "label")
create_quick_statement("LAST", property = "D", "A newly created item", 
                      lang = "en", type = "description")
create_quick_statement("LAST", "P31", "Q5", type = "item")

# ============================================================================
# BATCH CREATION EXAMPLE
# ============================================================================

# Create multiple commands at once
commands <- c(
  create_quick_statement("Q1001", property = "L", "Mahatma Gandhi", 
                        lang = "en", type = "label"),
  create_quick_statement("Q1001", property = "D", 
                        "Indian independence activist", 
                        lang = "en", type = "description"),
  create_quick_statement("Q1001", "P569", "+1869-10-02T00:00:00Z/11", 
                        type = "time"),
  create_quick_statement("Q1001", "P31", "Q5", type = "item")
)

# Print all commands
cat(paste(commands, collapse = "\n"))

# Or write to file for batch upload
# writeLines(commands, "quickstatements_batch.txt")
