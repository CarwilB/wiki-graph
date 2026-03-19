# Quick Reference: Zero-Article Languages & Macrolanguage Members

## The Problem in 30 Seconds

**102 languages in `linguameta_with_wiki` have 0 Wikipedia articles.**  
**51 of these are members of macrolanguages** where other members DO have Wikipedia articles.

**Root cause**: Wikipedia represents macrolanguages with single codes (e.g., `ar` for all Arabic), but linguameta distinguishes dialects (arz, arq, apd, etc.). Missing codes → zero articles.

---

## Critical Mappings Needed (for `wiki-language-diversity-v2.qmd`)

Add these to `wp_to_bcp47_extra` in `wiki-language-diversity-v2.qmd`:

```r
wp_to_bcp47_extra <- c(
  # ... existing mappings ...
  
  # MANDARIN (1.3B speakers!)
  "cmn"     = "zh",    # Mandarin Chinese → Chinese Wikipedia
  
  # ARABIC DIALECTS (>250M speakers)
  "arz"     = "ar",    # Egyptian Arabic → Arabic Wikipedia
  "arq"     = "ar",    # Algerian Arabic → Arabic Wikipedia
  "apd"     = "ar",    # Sudanese Arabic → Arabic Wikipedia
  "aec"     = "ar",    # Saidi Arabic → Arabic Wikipedia
  "acm"     = "ar",    # Mesopotamian Arabic → Arabic Wikipedia
  "acw"     = "ar",    # Hijazi Arabic → Arabic Wikipedia
  "acx"     = "ar",    # Omani Arabic → Arabic Wikipedia
  "ayp"     = "ar",    # North Mesopotamian Arabic → Arabic Wikipedia
  "ayh"     = "ar",    # Hadrami Arabic → Arabic Wikipedia
  "ayl"     = "ar",    # Libyan Arabic → Arabic Wikipedia
  "ayn"     = "ar",    # Sanaani Arabic → Arabic Wikipedia
  "abh"     = "ar",    # Tajiki Arabic → Arabic Wikipedia
  "acy"     = "ar",    # Cypriot Arabic → Arabic Wikipedia
  
  # CHINESE VARIANTS (>160M speakers)
  "cjy"     = "zh",    # Jinyu Chinese → Chinese Wikipedia
  "hsn"     = "zh",    # Xiang Chinese → Chinese Wikipedia
  
  # OTHER MACROLANGUAGES & VARIANTS
  "azj"     = "az",    # North Azerbaijani → Azerbaijani Wikipedia
  "xmv"     = "mg",    # Antankarana Malagasy → Malagasy Wikipedia
  "tts"     = "th",    # Northeastern Thai → Thai Wikipedia
  "lah"     = "pnb",   # Lahnda (macrolanguage) → Western Punjabi Wikipedia
)
```

---

## Affected Languages (Highest Speakers First)

| Language | Speakers | Macro | Wikipedia Code | Current Articles |
|----------|----------|-------|---|---|
| Mandarin Chinese | 1.3B | zho | cmn → **zh** | 0 |
| Egyptian Arabic | 78M | ara | arz → **ar** | 0 |
| Sudanese Arabic | 37M | ara | apd → **ar** | 0 |
| Algerian Arabic | 36M | ara | arq → **ar** | 0 |
| Jinyu Chinese | 63M | zho | cjy → **zh** | 0 |
| Xiang Chinese | 40M | zho | hsn → **zh** | 0 |
| North Azerbaijani | 24M | aze | azj → **az** | 0 |
| Saidi Arabic | 25M | ara | aec → **ar** | 0 |
| Antankarana Malagasy | 25M | mga | xmv → **mg** | 0 |
| Sanaani Arabic | 13M | ara | ayn → **ar** | 0 |
| Mesopotamian Arabic | 17M | ara | acm → **ar** | 0 |
| Hijazi Arabic | 11M | ara | acw → **ar** | 0 |
| Lahnda | 93M | lah (macro) | lah → **pnb** | 0 |
| Northeastern Thai | 17M | — | tts → **th** | 0 |

**Total speakers affected**: ~1.6+ billion (mostly Mandarin + Lahnda)

---

## Macrolanguages with Mixed Coverage (8 total)

These have some members WITH articles and some WITH ZERO:

| Macro | With Wiki | With Zero | Members | Issue | Status |
|-------|---:|---:|---:|---|---|
| **Arabic** [ara] | 2 | 11 | 13 | 11 dialects without specific Wikipedia | ✓ Mapped |
| **Chinese** [zho] | 6 | 4 | 10 | Mandarin + 3 variants unmapped | ✓ Mapped |
| **Malay** [msa] | 2 | 3 | 5 | 3 Malay varieties without Wikipedia | — |
| **Azerbaijani** [aze] | 1 | 1 | 2 | North Azerbaijani unmapped | ✓ Mapped |
| **Kurdish** [kur] | 1 | 1 | 2 | Southern Kurdish unmapped | ✓ Mapped |
| **Lahnda** [lah] | 2 | 1 | 3 | Lahnda itself unmapped | ✓ Mapped |
| **Malagasy** [mga] | 1 | 1+ | 2+ | Antankarana Malagasy unmapped | ✓ Mapped |
| **Thai** [tai] | 1 | 1+ | 2+ | Northeastern Thai unmapped | ✓ Mapped |
| **Nepali** [nep] | 1 | 1 | 2 | Nepali (16M speakers) unmapped | — |
| **Albanian** [sqi] | 1 | 1 | 2 | Gheg Albanian unmapped | — |

---

## Solution: Which Approach?

### Option A: Simple Fallback (Recommended for quick fix)
```r
# Add missing codes to wp_to_bcp47_extra
# Pro: 5-minute fix, captures all 1.3B Mandarin speakers
# Con: Obscures dialect-specific patterns
```

### Option B: Proportional Distribution
```r
# If mapping cmn→zh, distribute articles by speaker population
# Pro: Fairer representation of speakers
# Con: More complex logic, harder to interpret
```

### Option C: Hybrid + Annotation (Recommended for production)
```r
# Use mapping but mark as "derived_from_macrolanguage"
# Pro: Transparent, allows downstream filtering
# Con: More columns in output
```

---

## For Future Reference

**Full analysis**: See `documentation/WIKI_LANGUAGE_DIVERSITY_MACROLANGUAGE_ANALYSIS.md`

**Data source**: `macrolanguages_final.rds` (63 macrolanguages, 459 members)

**Analysis date**: 2026-03-07

**Generated from**: `wiki-language-diversity-v2.qmd` + macrolanguages analysis
