# Wikipedia–Macrolanguage Mismatch Analysis

## Overview

The `wiki-language-diversity-v2.qmd` analysis creates a table (`linguameta_with_wiki`) that matches Wikipedia language editions to linguameta language records. **102 languages have zero Wikipedia articles**, but analysis shows that **51 of these are members of macrolanguages** where other members DO have Wikipedia articles.

The root cause: **Wikipedia represents macrolanguages as single unified Wikipedias** (e.g., `ar` for all Arabic), while **linguameta distinguishes dialect-specific member languages** (arz, arq, apd, etc.). This creates a systematic gap.

---

## The Problem: Zero Articles for High-Speaker Languages

### High-Impact Examples

| Language | Speakers | Wikipedia Code | Status | Notes |
|----------|----------|---|--------|-------|
| **Mandarin Chinese** | 1.29 billion | `cmn` → no mapping | 0 articles | Largest unmapped language; linguameta code is `cmn`, but Wikipedia uses generic `zh` |
| **Egyptian Arabic** | 78 million | `arz` → no mapping | 0 articles | Largest Arabic dialect; no `arz` Wikipedia exists |
| **Sudanese Arabic** | 37 million | `apd` → no mapping | 0 articles | No dialect-specific Wikipedia |
| **Jinyu Chinese** | 63 million | `cjy` → no mapping | 0 articles | Chinese variant with no Wikipedia |
| **North Azerbaijani** | 24 million | `azj` → no mapping | 0 articles | Member of Azerbaijani macrolanguage |

### Macrolanguages Affected (8 total with mixed coverage)

These macrolanguages have **some members with Wikipedia articles** but **other members with zero**:

| Macro | Members with Wiki | Members with Zero | Total Members | Key Missing Member |
|-------|---:|---:|---:|---|
| **Arabic** [ara] | 2 | 11 | 13 | Egyptian (78M), Sudanese (37M), Algerian (36M) |
| **Chinese** [zho] | 6 | 4 | 10 | Mandarin (1.3B), Jinyu (63M), Xiang (40M) |
| **Malay** [msa] | 2 | 3 | 5 | Pattani (3.4M), Musi, Bukit |
| **Azerbaijani** [aze] | 1 | 1 | 2 | North Azerbaijani (24M) |
| **Kurdish** [kur] | 1 | 1 | 2 | Southern Kurdish (3.1M) |
| **Lahnda** [lah] | 2 | 1 | 3 | Northern Hindko (4M) |
| **Nepali** [nep] | 1 | 1 | 2 | Nepali (16M) |
| **Albanian** [sqi] | 1 | 1 | 2 | Gheg Albanian (4.1M) |

---

## Root Cause: Wikipedia vs. Linguameta Code Mismatch

### Three Layers of Complexity

#### 1. Macro-Only Wikipedias

Wikipedia has a single Wikipedia edition for the entire macrolanguage:
- `ar` = Arabic (covers Egyptian, Sudanese, Algerian, etc. as dialects, not separate languages)
- `zh` = Chinese (covers Mandarin, Cantonese, Min Nan, etc. as variants)
- `ms` = Malay (covers multiple Malay varieties)

**Linguameta's approach**: Distinguishes each dialect as a separate **member language**:
- `arz` = Egyptian Arabic
- `cmn` = Mandarin Chinese
- `zlm` = Malay (but different from `ms`)

**Result**: No linguistic entity for linguameta's specific members → zero articles.

#### 2. No Dialect-Specific Wikipedias

Many dialect pairs lack their own Wikipedia edition:
- Egyptian Arabic (78M speakers) → No `arz` Wikipedia; articles in parent `ar` Wikipedia
- Xiang Chinese (40M speakers) → No `hsn` Wikipedia
- Pattani Malay (3.4M speakers) → No `ptt` Wikipedia

#### 3. ISO Code Fragmentation

The same linguistic entity can have different ISO 639 codes:

- **Mandarin Chinese**:
  - ISO 639-3: `cmn` (used by linguameta)
  - BCP-47: `zh` (used by Wikipedia)
  - Problem: They're the same language but different codes

- **Azerbaijani dialects**:
  - Macrolanguage: `aze`
  - Members: `azj` (North) and `azb` (South)
  - Wikipedia has `az` (generic)

---

## Structural Relationship Diagram

```
                          Wikipedia                    Linguameta
                          =========                    ==========

                          ar ──────────┐
                       (Arabic Wiki)   │
                    1.64M articles ┌───┴─────────────────────────────┐
                                   │                                  │
                          ┌────────▼─────────┐              ┌────────▼──────────┐
                          │ Egyptian Arabic  │              │ Egyptian Arabic   │
                          │ (arz)            │              │ (arz)             │
                          │ 78M speakers     │              │ 78M speakers      │
                          │ GETS 0 ARTICLES  │              │ NEEDS MAPPING     │
                          └──────────────────┘              └───────────────────┘

                          zh ──────────┐
                       (Chinese Wiki)  │
                    665K articles  ┌───┴────────────────────────────┐
                                   │                                │
                          ┌────────▼──────────┐         ┌──────────▼──────────┐
                          │ Mandarin Chinese │         │ Mandarin Chinese   │
                          │ (cmn)            │         │ (cmn)              │
                          │ 1.3B speakers    │         │ 1.3B speakers      │
                          │ GETS 0 ARTICLES  │         │ NEEDS MAPPING      │
                          └──────────────────┘         └────────────────────┘
```

---

## Proposed Solutions

### A. **Macrolanguage-to-Wikipedia Fallback Mapping**

**Approach**: Extend `wp_to_bcp47_extra` with missing dialect-to-macro mappings.

**Implementation**:
```r
wp_to_bcp47_macro <- c(
  # Mandarin → Chinese
  "cmn" = "zh",
  
  # Jinyu & Xiang → Chinese
  "cjy" = "zh",
  "hsn" = "zh",
  
  # All Arabic dialects → Standard Arabic
  "arz" = "ar",  # Egyptian
  "arq" = "ar",  # Algerian
  "apd" = "ar",  # Sudanese
  "acm" = "ar",  # Mesopotamian
  "aec" = "ar",  # Saidi
  "acw" = "ar",  # Hijazi
  "acx" = "ar",  # Omani
  # ... etc for all remaining Arabic members
  
  # Other macrolanguages
  "azj" = "az",  # North Azerbaijani
  "kpv" = "ku",  # Southern Kurdish → Kurdish (kur)
)
```

**Pros**:
- ✓ Simple, one-line fix for each missing mapping
- ✓ Captures all 1.3B Mandarin speakers under Chinese Wikipedia
- ✓ Accounts for diaspora and cross-dialect readership

**Cons**:
- ✗ Obscures dialect-specific Wikipedia activity
- ✗ Can't distinguish Egyptian Arabic readers from Sudanese Arabic readers
- ✗ May overcount articles for less-covered dialects

---

### B. **Proportional Article Distribution**

**Approach**: When multiple members share one Wikipedia, distribute article count proportionally by speaker population.

**Implementation**:
```r
# For Arabic macrolanguage (11 members with zero, 2 with articles)
# ar Wikipedia has 1.64M articles
# Total Arabic speakers: ~375M (sum of all member languages)

# Egyptian Arabic gets: 1.64M × (78M / 375M) ≈ 341k articles
# Sudanese Arabic gets: 1.64M × (37M / 375M) ≈ 162k articles
```

**Pros**:
- ✓ Reflects speaker population proportions
- ✓ Fairer distribution than lumping all into one member
- ✓ Transparent calculation

**Cons**:
- ✗ More complex logic
- ✗ May misrepresent actual article content
- ✗ Can't track which articles actually cover which dialect

---

### C. **Hybrid: Mapping + Annotation**

**Approach**: Use macrolanguage fallback but mark articles as "derived" vs. "primary."

**Implementation**:
```r
linguameta_with_wiki <- linguameta |>
  mutate(
    # Primary: direct match to linguameta code
    articles_primary = articles,
    
    # Derived: from macrolanguage mapping (if no primary)
    articles_macro = if_else(
      is.na(articles_primary) & !is.na(macro_code),
      macro_wikipedia_articles[macro_code],
      NA_real_
    ),
    
    # Total: use primary; fall back to derived
    articles_final = coalesce(articles_primary, articles_macro),
    
    # Flag source
    article_source = case_when(
      !is.na(articles_primary) ~ "primary_wikipedia",
      !is.na(articles_macro) ~ "derived_from_macrolanguage",
      TRUE ~ "no_wikipedia"
    )
  )
```

**Pros**:
- ✓ Captures all speakers under Wikipedia count
- ✓ Transparent about source and assumptions
- ✓ Allows downstream filtering/flagging
- ✓ Can be refined: e.g., only use macro for high-population languages

**Cons**:
- ✗ More complex table schema
- ✗ Adds a new categorical variable to track

---

## Recommended Next Steps

### Immediate (for `wiki-language-diversity-v2.qmd`)

1. **Add critical mappings** to `wp_to_bcp47_extra`:
   ```r
   wp_to_bcp47_extra <- c(
     # ... existing ...
     "cmn"     = "zh",    # Mandarin Chinese
     "cjy"     = "zh",    # Jinyu Chinese
     "hsn"     = "zh",    # Xiang Chinese
     "arz"     = "ar",    # Egyptian Arabic
     "arq"     = "ar",    # Algerian Arabic
     "apd"     = "ar",    # Sudanese Arabic
     "azj"     = "az",    # North Azerbaijani
   )
   ```

2. **Add footnote** explaining the mapping:
   - "Some languages map to their macrolanguage's Wikipedia when a dialect-specific edition doesn't exist"
   - "Article counts for [cmn, arz, etc.] are derived from parent language Wikipedia"

### Medium-term (Macrolanguage-specific analysis)

3. **Create a macrolanguage crosswalk**:
   ```r
   macro_wikipedia_mapping <- tibble(
     member_code = c("cmn", "arz", "arq", ...),
     member_name = c("Mandarin", "Egyptian Arabic", ...),
     macro_code = c("zho", "ara", "ara", ...),
     wp_code = c("zh", "ar", "ar", ...),
     reason = c("no cmn Wikipedia", "no arz Wikipedia", "no arq Wikipedia"),
     distribution_weight = c("by_speakers", "by_speakers", ...)
   )
   ```

4. **Document assumptions explicitly** in analysis output

### Long-term (Research direction)

5. **Investigate** whether dialect-specific Wikipedia articles exist but are unmapped:
   - E.g., does English Wikipedia have lengthy sections on Egyptian Arabic dialects?
   - Should we count those as "articles about" Egyptian Arabic?

6. **Consider cross-language analysis**:
   - Does Japanese Wikipedia have separate editions for these dialects?
   - Does German Wikipedia?
   - This may reveal more complete coverage

---

## Supporting Data

### Complete List: Macrolanguage Members with Zero Articles

**Arabic [ara]** (13 total members, 2 with articles):
- Egyptian Arabic (arz): 78M speakers → **0 articles**
- Sudanese Arabic (apd): 37M speakers → **0 articles**
- Algerian Arabic (arq): 36M speakers → **0 articles**
- Saidi Arabic (aec): 25M speakers → **0 articles**
- Sanaani Arabic (ayn): 13M speakers → **0 articles**
- Mesopotamian Arabic (acm): 17M speakers → 0 articles [note: has wiki data in original]
- Hijazi Arabic (acw): 11M speakers → 0 articles
- North Mesopotamian Arabic (ayp): 10M speakers → 0 articles
- Omani Arabic (acx): 3.2M speakers → 0 articles
- Hadrami Arabic (ayh): 5.1M speakers → 0 articles
- Libyan Arabic (ayl): 5.6M speakers → 0 articles
- Tajiki Arabic (abh): N/A → 0 articles
- Cypriot Arabic (acy): N/A → 0 articles

**Chinese [zho]** (10 total members, 6 with articles):
- Mandarin Chinese (cmn): **1.3B speakers** → **0 articles**
- Jinyu Chinese (cjy): 63M speakers → **0 articles**
- Xiang Chinese (hsn): 40M speakers → **0 articles**
- Huizhou Chinese: 4.6M speakers → 0 articles

**Malay [msa]** (5 total members, 2 with articles):
- Pattani Malay: 3.4M speakers → **0 articles**
- Musi: 3.1M speakers → 0 articles
- Bukit Malay: 4.1M speakers → 0 articles

**Others** (1 member each):
- Azerbaijani: North Azerbaijani (azj) 24M → **0 articles**
- Kurdish: Southern Kurdish 3.1M → **0 articles**
- Lahnda: Northern Hindko 4M → **0 articles**
- Nepali: Nepali 16M → **0 articles**
- Albanian: Gheg Albanian 4.1M → **0 articles**

---

**Generated**: 2026-03-07  
**Source Analysis**: `wiki-language-diversity-v2.qmd` + `macrolanguages_final.rds`
