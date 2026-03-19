# Join Logic Correction: Language Code Mapping (7 Mar 2026)

## The Problem

The original join logic was backwards:

```r
# WRONG: Apply mapping to Wikipedia codes, then join to linguameta
wiki_joined <- wiki |>
  mutate(
    bcp47_lookup = coalesce(wp_to_bcp47_extra[wp_code_clean], wp_code_clean)
  )

linguameta_with_wiki <- linguameta |>
  left_join(wiki_joined, by = c("bcp_47_code" = "bcp47_lookup"))
```

**What this did**: Tried to match linguameta's `cmn` (Mandarin Chinese) directly to `cmn` in Wikipedia, but Wikipedia uses `zh` (Chinese macrolanguage). Result: **zero articles**, even though the mapping existed.

**Root cause**: The mapping was meant to transform linguameta codes into Wikipedia codes, but it was being applied to the wrong side of the join.

---

## The Solution

Apply the mapping to **linguameta codes**, not Wikipedia codes:

```r
# RIGHT: Transform linguameta codes, then join to Wikipedia
wiki_joined <- wiki |>
  mutate(
    wp_code_clean = str_trim(str_remove(wp_code, "\\s*\\(.*"))
  ) |>
  select(wp_code_clean, wp_code, articles, ...)

linguameta_with_wiki <- linguameta |>
  # Transform linguameta codes using the mapping
  mutate(
    bcp47_wiki_lookup = coalesce(wp_to_bcp47_extra[bcp_47_code], bcp_47_code)
  ) |>
  # Now lah→pnb, cmn→zh, etc.
  left_join(wiki_joined, by = c("bcp47_wiki_lookup" = "wp_code_clean"))
```

**What this does**: 
- Mandarin Chinese (cmn) → looks up `wp_to_bcp47_extra["cmn"]` → gets `"zh"` 
- Joins linguameta row with `bcp47_wiki_lookup="zh"` to wiki row with `wp_code_clean="zh"`
- **Result: Gets Chinese Wikipedia's 1.5M+ articles**

---

## Files Modified

- `wiki-language-diversity-v2.qmd` lines 127–201:
  - `wiki_joined`: Removed `bcp47_lookup` calculation; now just cleans the Wikipedia codes
  - `linguameta_with_wiki`: Added `bcp47_wiki_lookup` before the join
  - `wiki_special`: Updated filter to use `wp_code_clean` instead of `bcp47_lookup`

---

## Verification

**Before fix** (cmn, lah, xmv, tts, arz all had 0 articles):
```
cmn  Mandarin Chinese    0 articles
lah  Lahnda              0 articles
xmv  Antankarana Malagasy 0 articles
tts  Northeastern Thai   0 articles
arz  Egyptian Arabic     0 articles
```

**After fix** (all now mapped correctly):
```
cmn  Mandarin Chinese    1,526,786 articles  ← Chinese Wikipedia
lah  Lahnda                 75,213 articles  ← Western Punjabi Wikipedia
xmv  Antankarana Malagasy  102,259 articles  ← Malagasy Wikipedia
tts  Northeastern Thai     180,368 articles  ← Thai Wikipedia
arz  Egyptian Arabic     1,303,043 articles  ← Arabic Wikipedia
```

---

## Remaining Zero-Article Languages

87 languages still have 0 articles because they lack Wikipedia editions:
- No direct Wikipedia (e.g., Twi/Akan, Bhojpuri, Haryanvi)
- Or require additional macrolanguage mappings not yet added (e.g., Nepali, Gheg Albanian)

These are candidates for future expansion if mapping coverage is desired.

---

## Key Insight

**Direction matters in language mappings:**
- ✗ Transform the reference (Wikipedia) to match the data (linguameta)
- ✓ Transform the data (linguameta) to match the reference (Wikipedia)

This is because linguameta is the source of truth (it defines what languages exist), and Wikipedia editions are the reference data we're enriching with.
