# wiki-language-diversity-v2.qmd Refinements

## Changes Made

### 1. Reverted Speaker Count Formatting
**Removed**: Abbreviated notation (1.29B, 78.00M, 3.40M, etc.)  
**Restored**: Raw comma-formatted numbers (1,288,700,000, 78,000,000, 3,400,000, etc.)

**Rationale**: Raw numbers are easier to compare intuitively without mental conversion. Abbreviated notation adds cognitive load when trying to make sense of magnitude differences.

**Implementation**:
- Removed `format_speakers()` function
- Removed `speakers_fmt` pre-calculation in data pipeline
- Now calculated in `render_table()` with: `format(speakers, big.mark = ",")`
- Removed white text styling from speaker column (blue background only)

---

### 2. Fixed Wikipedia Edition Mapping with "In" Prefix

**Rule**: Only languages that are mapped to their macrolanguage Wikipedia (not having their own) get the "In" prefix.

**Example**:
- **Mandarin Chinese** (mapped member): "In Chinese / 中文"
- **Chinese** (macrolanguage itself): "Chinese / 中文"
- **English** (independent, no mapping): "English"

**Implementation**:
- Added hardcoded list of mapped codes: `cmn, cjy, hsn, arz, arq, apd, aec, acm, acw, acx, ayp, ayh, ayl, ayn, abh, acy, azj, kpv`
- In `format_for_display()`, check if `bcp_47_code %in% mapped_codes`
- If mapped, prepend "In " to the Wikipedia edition display
- If not mapped (macro itself or independent), use display as-is

**Code snippet**:
```r
wiki_edition_fmt = if_else(
  !is.na(wp_edition_display),
  if_else(
    is_mapped,
    paste0("In ", wp_edition_display),
    wp_edition_display
  ),
  "—"
)
```

**Result**: No redundant double-listing; Egyptian Arabic shows "In Arabic" once, not "In Arabic" and also "Egyptian Arabic"

---

### 3. Line Breaks Before Parentheses in Endonyms

**Rule**: Insert `<br>` before any opening parenthesis in endonyms.

**Examples**:
- Input: `Português (Brasil)`
- Output: `Português<br>(Brasil)`

- Input: `Español (España)`
- Output: `Español<br>(España)`

**Implementation**:
In the wiki scraping, when building `wp_edition_display`:
```r
str_replace(wiki_name_native, '\\s*\\(', '<br>\\(')
```

This removes whitespace before the parenthesis and replaces it with an HTML line break.

---

## Summary of Display Format

### Top 250 Languages Table
| Column | Content | Example |
|--------|---------|---------|
| Language | Rank + Name + Endonym | 1. Mandarin Chinese<br>普通话 |
| Description | Wikidata definition | Most widely spoken form of Chinese |
| Speakers | Raw comma numbers | 1,288,700,000 |
| Articles | Comma numbers | 665,262 |
| Wikipedia | "In [Macro]" or direct | In Chinese<br>中文 |

### Mapped vs. Non-Mapped Examples

**Mapped Dialects** (with "In" prefix):
- Mandarin Chinese → "In Chinese / 中文"
- Egyptian Arabic → "In Arabic / العربية"
- Jinyu Chinese → "In Chinese / 中文"
- North Azerbaijani → "In Azerbaijani / Azərbaycanca"

**Non-Mapped** (no prefix):
- English → "English"
- Arabic (the macrolanguage itself) → "Arabic / العربية"
- Chinese (the macrolanguage itself) → "Chinese / 中文"

**Non-Macrolanguage Members** (no prefix):
- Filipino → "Filipino / Wikang Pilipino"
- Odia → "Odia / ଓଡ଼ିଆ"

---

## Code Changes Summary

File: `wiki-language-diversity-v2.qmd`

**Removed**:
- Lines 106-128: `format_speakers()` function
- Line 139: `speakers_fmt` column calculation
- Line 282 & 330: `color = "white"` from speaker column styling

**Modified**:
- Lines 64-72: Updated wiki_name_native replacement logic with line break before `(`
- Lines 216-240: Updated `format_for_display()` with "In" prefix logic
- Lines 266 & 313: Added `speakers_fmt` calculation directly in render functions
- Lines 269 & 316: Changed column selection to use `speakers_fmt` (comma-formatted)
- Lines 282 & 330: Removed color specification from speaker column

---

## Testing

✓ Speaker formatting reverted to raw comma numbers (e.g., 1,288,700,000)
✓ "In" prefix applies only to mapped dialects (cmn, arz, azj, etc.)
✓ Macrolanguages themselves (ara, zho, aze) display without "In" prefix
✓ Line breaks insert before parentheses in endonyms (e.g., "Português<br>(Brasil)")
✓ No white text on speaker column
✓ All five columns display correctly in both tables

---

**Updated**: 2026-03-07  
**Related**: `WIKI_LANGUAGE_DIVERSITY_UPDATES.md`, `ZERO_ARTICLES_REFERENCE.md`
