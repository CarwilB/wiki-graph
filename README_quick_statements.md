# QuickStatements R Function

An R function to generate QuickStatements V1 syntax commands for Wikidata batch editing.

## Overview

The `create_quick_statement()` function creates properly formatted QuickStatements commands for:
- **Strings** (including URLs, file names, external IDs)
- **Monolingual text** with language codes
- **Labels** with language specification
- **Descriptions** with language specification
- **Aliases** with language specification
- **References** with automatic retrieved date (defaults to current system date)
- **Qualifiers** for statements
- **Edit summaries**

## Installation

Simply source the function file:

```r
source("create_quick_statement.R")
```

## Basic Usage

### String Values

```r
# Software version
create_quick_statement("Q14579", "P348", "6.13.7")
# Output: Q14579	P348	"6.13.7"

# URL
create_quick_statement("Q14579", "P856", "https://kernel.org/")
# Output: Q14579	P856	"https://kernel.org/"
```

### Monolingual Text

```r
create_quick_statement("Q935", "P1559", "Isaac Newton", 
                      lang = "en", type = "monolingual")
# Output: Q935	P1559	en:"Isaac Newton"
```

### Labels

```r
create_quick_statement("Q1001", property = "L", "Mahatma Gandhi", 
                      lang = "en", type = "label")
# Output: Q1001	Len	"Mahatma Gandhi"
```

### Descriptions

```r
create_quick_statement("Q1001", property = "D", 
                      "Indian independence activist (1869–1948)", 
                      lang = "en", type = "description")
# Output: Q1001	Den	"Indian independence activist (1869–1948)"
```

### Aliases

```r
create_quick_statement("Q1001", property = "A", "Gandhi", 
                      lang = "en", type = "alias")
# Output: Q1001	Aen	"Gandhi"
```

## Advanced Features

### Adding References

By default, references use the current system date as the retrieved date:

```r
create_quick_statement("Q42", "P19", "Q350", type = "item",
                      add_reference = TRUE,
                      reference_url = "https://example.com")
# Output: Q42	P19	Q350	S854	"https://example.com"	S813	+2026-02-19T00:00:00Z/11
```

You can specify a custom retrieved date:

```r
create_quick_statement("Q42", "P856", "https://example.com",
                      add_reference = TRUE,
                      reference_url = "https://example.com",
                      retrieved_date = "2024-01-15")
# Output: Q42	P856	"https://example.com"	S854	"https://example.com"	S813	+2024-01-15T00:00:00Z/11
```

### Adding Qualifiers

```r
create_quick_statement("Q40269", "P1082", "1360590",
                      qualifiers = list(
                        P585 = "+2000-08-01T00:00:00Z/11",
                        P459 = "Q39825"
                      ))
# Output: Q40269	P1082	"1360590"	P585	+2000-08-01T00:00:00Z/11	P459	Q39825
```

### Adding Edit Summaries

```r
create_quick_statement("Q8023", "P18", "Nelson Mandela 1994.jpg",
                      comment = "Add image to Nelson Mandela")
# Output: Q8023	P18	"Nelson Mandela 1994.jpg"	/* Add image to Nelson Mandela */
```

### Complete Example

Combine qualifiers, references, and comments:

```r
create_quick_statement("Q12418", "P276", "Q10292830", type = "item",
                      qualifiers = list(
                        P585 = "+2017-01-01T00:00:00Z/11"
                      ),
                      add_reference = TRUE,
                      reference_url = "http://cartelfr.louvre.fr/example",
                      retrieved_date = "2017-09-23",
                      comment = "Update location of Mona Lisa")
# Output: Q12418	P276	Q10292830	P585	+2017-01-01T00:00:00Z/11	S854	"http://..."	S813	+2017-09-23T00:00:00Z/11	/* Update location of Mona Lisa */
```

## Function Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `qid` | Character | Yes | Wikidata item ID (e.g., "Q42") or "LAST" for newly created items |
| `property` | Character | Yes | Property ID (e.g., "P31") or "L"/"D"/"A" for labels/descriptions/aliases |
| `value` | Character | Yes | The value to add |
| `lang` | Character | Conditional* | Language code (required for monolingual text, labels, descriptions, aliases) |
| `type` | Character | No | Value type: "string" (default), "monolingual", "label", "description", "alias", "item", "time", "quantity", "coordinate" |
| `add_reference` | Logical | No | Whether to add a reference (default: FALSE) |
| `retrieved_date` | Character/Date | No | Retrieved date for reference (default: current system date) |
| `reference_url` | Character | Conditional** | Reference URL (P854) - required if add_reference is TRUE |
| `qualifiers` | List | No | Named list of qualifier property-value pairs |
| `comment` | Character | No | Edit summary comment |

\* Required when `type` is "monolingual", "label", "description", or "alias"  
\*\* Required when `add_reference` is TRUE

## Batch Processing

Create multiple commands at once:

```r
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

# Print to console
cat(paste(commands, collapse = "\n"))

# Or write to file for batch upload
writeLines(commands, "quickstatements_batch.txt")
```

## Working with Newly Created Items

Use "LAST" to refer to the previously created item:

```r
commands <- c(
  "CREATE",
  create_quick_statement("LAST", property = "L", "New Item", 
                        lang = "en", type = "label"),
  create_quick_statement("LAST", property = "D", "A newly created item", 
                        lang = "en", type = "description"),
  create_quick_statement("LAST", "P31", "Q5", type = "item")
)

cat(paste(commands, collapse = "\n"))
```

## Value Type Examples

For different value types, format the `value` parameter as follows:

- **String**: Just the string (function adds quotes)
- **Item/Property**: Entity ID (e.g., "Q5", "P31")
- **Time**: "+YYYY-MM-DDTHH:MM:SSZ/precision" (e.g., "+2000-01-15T00:00:00Z/11")
- **Quantity**: Number with optional tolerance or bounds (e.g., "1360590", "100~5U11573")
- **Coordinate**: "@LAT/LON" (e.g., "@-33.903469/18.411102")
- **Monolingual**: Text with language (handled by function when type = "monolingual")

## Notes

- The function automatically formats strings with double quotes
- TAB characters are used as separators (standard QuickStatements format)
- Retrieved dates default to the current system date
- References cannot be added to labels, descriptions, or aliases (warning issued)
- Commands can be uploaded to QuickStatements 3.0 at https://qs-dev.toolforge.org

## Resources

- [QuickStatements 3.0 Documentation](https://meta.wikimedia.org/wiki/QuickStatements_3.0/Documentation/User_guide)
- [QuickStatements Tool](https://qs-dev.toolforge.org)
- [Wikidata Property List](https://www.wikidata.org/wiki/Wikidata:List_of_properties)

## Examples File

See `quick_statement_examples.R` for comprehensive usage examples.
