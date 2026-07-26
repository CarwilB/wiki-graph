# Skill: Wikitext Preview Block

Render a side-by-side HTML preview kable and copyable wikitext block in a
Quarto HTML document, following the pattern used in the wiki-graph municipality
generator.

## When to use

Use this pattern whenever you want to display a rendered HTML table alongside
its Wikipedia wikitext equivalent, with a copy-to-clipboard button, inside a
Quarto `results: asis` chunk.

## Required setup

Source **both** helper files in your setup chunk:

```r
library(htmltools)
library(kableExtra)
source("src/gh-copy-assets.R")       # copy-btn CSS/JS + copy_to_clipboard_button_wt()
source("src/muni-article-functions.R") # process_for_display(), refs_footnotes(), wikitext_block()
```

Then call `include_table_assets()` in a `results: asis` chunk near the top of
the document to inject the CSS and JavaScript that the copy buttons depend on:

```r
#| results: asis
include_table_assets()
```

Without this call the copy buttons will be unstyled and non-functional.

## Core functions (defined in muni-article-functions.R)

### `process_for_display(text, ref_offset = 0L, lang = "en")`

Converts raw wikitext into an HTML-safe preview string:

- `<ref>…</ref>` → numbered superscript `[ref1]`, `[ref2]`, …
- `[[Article|Label]]` and `[[Article]]` → clickable `<a>` links to Wikipedia
- Everything else HTML-escaped

Returns `list(html = <escaped string>, refs = <character vector of ref bodies>)`.

### `refs_footnotes(refs, ref_offset = 0L)`

Renders the extracted `refs` vector as small numbered footnotes beneath a
wikitext block. Returns `NULL` when `refs` is empty (safe to use unconditionally).

### `wikitext_block(id, label, content, lang = "en")`

All-in-one wikitext display widget:

1. A copy button (`class = "copy-btn"`) wired to `copyTableToClipboard(id, this)`
2. A `<pre>` block showing `process_for_display(content)` as rendered HTML
   (links clickable, refs as superscripts)
3. `refs_footnotes()` below the pre block
4. A hidden `<textarea id=id>` storing the raw wikitext for clipboard copying

`id` must be unique within the page. Use a stable string (e.g., `"poverty_wt_1"`)
or generate one with `paste0("wt_", sample(1e5:9e5, 1))`.

## Side-by-side layout pattern

The canonical pattern — a rendered HTML table on the left, a wikitext block on
the right — mirrors what `muni_block()` does for council, identity, and poverty
tables:

```r
tags$div(
  style = "display:flex; gap:14px; align-items:flex-start; font-size:12px; margin-bottom:8px;",
  tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
           HTML(as.character(my_kable))),          # ← must wrap kable in HTML()
  tags$div(style = "flex:1 1 0; min-width:0;",
           wikitext_block("my_unique_id", "Copy Wikitable", wikitable_text, lang))
)
```

**Critical**: pass the kable as `HTML(as.character(kable_object))`, not bare.
kableExtra returns an HTML string; without `HTML()` it will be escaped and
rendered as plain text.

## Rendering from a chunk

Build a `tagList()` and return it directly from the chunk — do **not** use
`print()` inside a `for` loop or `cat()` around tag objects:

```r
#| echo: false
#| results: asis

tagList(lapply(my_list, function(item) {
  # build kable and wikitext_text for this item …
  tagList(
    tags$h3(item$title),
    tags$div(
      style = "display:flex; gap:14px; align-items:flex-start; font-size:12px; margin-bottom:8px;",
      tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
               HTML(as.character(html_kable))),
      tags$div(style = "flex:1 1 0; min-width:0;",
               wikitext_block(paste0("wt_", item$id), "Copy Wikitable",
                              wikitable_text, "en"))
    )
  )
}))
```

Returning a single `tagList()` lets knitr render the entire HTML tree in one
pass. Mixing `print()` / `cat()` with tag objects causes the HTML to appear as
escaped text.

## Live example

`bolivia_poverty_trends.qmd` — the `render-muni-examples` chunk renders six
municipalities, each showing:
- Left: a `kable_classic` HTML table (poverty + water + sanitation)
- Right: the equivalent Wikipedia wikitable with shade-colored cells and a
  "Copy Wikitable" button
