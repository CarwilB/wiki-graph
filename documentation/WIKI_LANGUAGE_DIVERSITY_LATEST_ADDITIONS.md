# Latest Additions to wiki-language-diversity-v2.qmd

**Date**: March 7, 2026  
**File**: `wiki-language-diversity-v2.qmd`

## Three Additional Languages Now Mapped

### 1. Antankarana Malagasy (xmv)
- **Speakers**: 25 million
- **Macrolanguage**: Malagasy (mg)
- **Mapping**: `xmv → mg` (Malagasy Wikipedia)
- **Articles available**: 102,259 (via Malagasy Wikipedia)
- **Status**: Now appears in output table with article counts

### 2. Northeastern Thai (tts)
- **Speakers**: 17 million
- **Language family**: Tai (standalone, not a macrolanguage)
- **Mapping**: `tts → th` (Thai Wikipedia)
- **Articles available**: 180,368 (via Thai Wikipedia)
- **Status**: Now appears in output table with article counts

### 3. Lahnda (lah)
- **Speakers**: 93 million
- **Status**: Macrolanguage itself (not a member of another macro)
- **Mapping**: `lah → pnb` (Western Punjabi Wikipedia, largest Lahnda-family member)
- **Articles available**: 75,213 (via Western Punjabi Wikipedia)
- **Status**: Now appears in output table with article counts

## Implementation Details

### Code Location
Added to `wp_to_bcp47_extra` mapping vector in `wiki-language-diversity-v2.qmd`, lines 118–123:

```r
  "azj"     = "az",    # North Azerbaijani → Azerbaijani Wikipedia
  "kpv"     = "ku",    # Southern Kurdish → Kurdish Wikipedia
  # Additional macrolanguage mappings
  "xmv"     = "mg",   # Antankarana Malagasy → Malagasy Wikipedia
  "tts"     = "th",   # Northeastern Thai → Thai Wikipedia
  "lah"     = "pnb"   # Lahnda (macrolanguage) → Western Punjabi Wikipedia
)
```

### Rationale

These three languages previously had **zero Wikipedia articles** because their BCP-47 codes didn't match any Wikipedia edition code. All three map to existing Wikipedia editions:

- **Antankarana Malagasy** is a dialect member of the Malagasy macrolanguage, so uses the parent's Wikipedia
- **Northeastern Thai** is related to standard Thai; both share the Thai Wikipedia
- **Lahnda** is a macrolanguage with 7 members; Western Punjabi (113M speakers) is the largest and has the most comprehensive Wikipedia edition

### Impact

- **Total additional speakers now represented**: ~135 million
- **Wikipedia articles now accessible**: 102,259 (Malagasy) + 180,368 (Thai) + 75,213 (Punjabi) = 357,840 articles
- **Languages table now includes**: Antankarana Malagasy, Northeastern Thai, and Lahnda with proper article/speaker ratios

### Additional Context (7 Mar 2026 - Critical Fix)

Initial implementation had a **critical join logic error** (see `documentation/JOIN_LOGIC_CORRECTION_7MAR2026.md`). The mapping was applied in the wrong direction:

**Before fix**: Languages showed 0 articles despite having mappings
**After fix**: All mappings now properly connect linguameta codes to Wikipedia codes

Result: 11 languages mapped across 1.7B speakers with 10.3M+ Wikipedia articles accessible

## Documentation Updated

- `documentation/ZERO_ARTICLES_REFERENCE.md` — Added all three languages to reference table and mapping code block
- Status tracker added to macrolanguages table (✓ Mapped for all three)

## Testing

Verified in R console:
```r
wp_to_bcp47_extra["xmv"]  # "mg"
wp_to_bcp47_extra["tts"]  # "th"
wp_to_bcp47_extra["lah"]  # "pnb"
```

All mappings tested against `wiki` dataframe; Wikipedia editions exist and contain articles.

## Next Steps

Consider mapping remaining unmapped languages if data becomes available:
- Nepali (nep) — 16M speakers, zero articles
- Gheg Albanian (aln) — related to Standard Albanian, could map to `sq`
- Malay varieties (msa macrolanguage) — 3 varieties without specific Wikipedia

---

**Related files**:
- Primary: `wiki-language-diversity-v2.qmd`
- Reference: `documentation/ZERO_ARTICLES_REFERENCE.md`
- Analysis: `documentation/WIKI_LANGUAGE_DIVERSITY_MACROLANGUAGE_ANALYSIS.md`
