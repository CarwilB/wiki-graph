# Language Diversity: Linguameta → Wikipedia Mapping

Map linguameta language codes (ISO 639-3) to Wikipedia editions. Main document: `wiki-language-diversity-v2.qmd`.

## Status (March 2026)

**Zero-article languages reduced from 87 to 47 (46% reduction)** after three rounds of mapping:

- **Round 1** (early Mar 2026): 3 new mappings (135M speakers, 357K articles)
- **Round 2** (continued): 22 additional mappings (283M speakers, 6.35M+ articles)
- **Round 3** (continued): 17 more + code fixes (121M speakers, 1.26M+ articles)

## Macrolanguage Mappings: `wp_to_bcp47_extra`

### Chinese (zho)
- `cmn` → `zh` (Mandarin, 1.29B speakers → 1.5M articles)
- `cjy` → `zh` (Jinyu, 63M)
- `hsn` → `zh` (Xiang, 40M)
- `yue` → `zh-yue` (Cantonese, 79M → 149K articles)
- `nan` → `zh-min-nan` (Min Nan, 42M → 434K articles)
- `czh` → `zh` (Huizhou, ...)

### Arabic (ara)
- `arz` → `ar` (Egyptian Arabic, 78M → 1.3M articles)
- `arq` → `ar` (Algerian, 36M)
- `apd` → `ar` (Sudanese, 37M)
- `aec` → `ar` (Saidi, 25M)
- `acm`, `acw`, `acx`, `ayp`, `ayh`, `ayl`, `ayn`, `abh`, `acy` → `ar` (other dialects, ~50M combined)
- Plus additional dialect variants

### Asian languages
- `azj` → `az` (North Azerbaijani, 24M)
- `tts` → `th` (Northeastern Thai, 17M → 180K articles)
- `kpv` → `kv` (Komi-Zyrian; was wrongly mapped to `ku`)
- `fil` → `tl` (Filipino/Tagalog)
- `bho` → `bh` (Bhojpuri)
- `bik` → `bcl` (Bikol)
- `hno` → `pnb` (Northern Hindko)
- `kok` → `gom` (Konkani → Goan Konkani)

### African & other languages
- `lah` → `pnb` (Lahnda, 93M → Western Punjabi, 75K articles)
- `xmv` → `mg` (Antankarana Malagasy, 25M → 102K articles)
- `mui` → `ms` (Musi)
- `fuv`, `fuc` → `ff` (Fulfulde)
- `gug` → `gn` (Guaraní)
- `kng` → `kg` (Koongo)
- `sdh` → `ku` (Southern Kurdish)
- `prs` → `fa` (Dari/Persian)
- `tzm` → `zgh` (Tamazight → Standard Moroccan Amazigh)
- `nb` → `no` (Norwegian Bokmål, 10.5M → 679K articles)

**Additional second-round mappings** for Uzbek, Persian/Pashto, Javanese, Thai, Odia, Nepali, Swahili, German, Malay, Oromo, Mongolian, Dinka, Albanian, and others.

## Critical Fix: Join Logic (7 Mar 2026)

**The Problem**: The join was backwards. `wp_to_bcp47_extra` was being applied to Wikipedia codes instead of linguameta codes.

**Original (broken)**:
```r
wiki_joined <- wiki |> mutate(bcp47_lookup = coalesce(wp_to_bcp47_extra[wp_code_clean], wp_code_clean))
linguameta_with_wiki <- linguameta |> left_join(wiki_joined, by = c("bcp_47_code" = "bcp47_lookup"))
```
Result: cmn tried to match cmn (not zh) → 0 articles

**Fixed**:
```r
linguameta_with_wiki <- linguameta |>
  mutate(bcp47_wiki_lookup = coalesce(wp_to_bcp47_extra[bcp_47_code], bcp_47_code)) |>
  left_join(wiki_joined, by = c("bcp47_wiki_lookup" = "wp_code_clean"))
```
Result: cmn→zh, lah→pnb, etc. All mappings now work correctly.

## Documentation Files

- `documentation/ZERO_ARTICLES_REFERENCE.md` — Updated Mar 2026 with all new languages
- `documentation/WIKI_LANGUAGE_DIVERSITY_LATEST_ADDITIONS.md` — Detailed notes on round 1 additions (7 Mar 2026)
- `documentation/COMPREHENSIVE_LANGUAGE_MAPPINGS_7MAR2026.md` — Round 2 mappings
- `documentation/JOIN_LOGIC_CORRECTION_7MAR2026.md` — Critical join fix explanation
