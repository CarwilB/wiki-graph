# Wikipedia Citation Templates: Cross-Language Mapping

Reference document for implementing multilingual citation template parsing.
Created 6 Mar 2026.

## Template Names by Language

### English (`en`)

| Template | Zotero itemType |
|----------|----------------|
| `{{cite book}}` | book |
| `{{cite journal}}` | journalArticle |
| `{{cite web}}` | webpage |
| `{{cite news}}` | newspaperArticle |
| `{{cite encyclopedia}}` | encyclopediaArticle |
| `{{cite magazine}}` | magazineArticle |
| `{{cite thesis}}` | thesis |
| `{{cite conference}}` | conferencePaper |
| `{{cite report}}` | report |
| `{{cite press release}}` | newspaperArticle |
| `{{cite av media}}` | videoRecording |
| `{{cite podcast}}` | podcast |
| `{{cite speech}}` | presentation |
| `{{cite odnb}}` | encyclopediaArticle |
| `{{Cite EB1911}}` | encyclopediaArticle |
| `{{Citation}}` | (generic — infer from params) |
| `{{harvc}}` | bookSection |

### French (`fr`)

French Wikipedia uses its own template system (Module:Biblio), with
French-language parameter names.  English-language aliases (e.g. `last1`,
`first1`, `title`, `url`) are also accepted.

| Template | English equivalent | Zotero itemType |
|----------|--------------------|----------------|
| `{{Article}}` (alias `{{Périodique}}`) | `{{cite journal}}` | journalArticle |
| `{{Ouvrage}}` | `{{cite book}}` | book |
| `{{Lien web}}` (alias `{{Lien Web}}`) | `{{cite web}}` | webpage |
| `{{Chapitre}}` | `{{cite book}}` + chapter | bookSection |
| `{{Lien brisé}}` | (broken link wrapper) | webpage |

### Spanish (`es`)

Spanish Wikipedia wraps the same Lua citation module as English but with
Spanish template names and parameter aliases.

| Template | English equivalent | Zotero itemType |
|----------|--------------------|----------------|
| `{{Cita publicación}}` | `{{cite journal}}` | journalArticle |
| `{{Cita libro}}` | `{{cite book}}` | book |
| `{{Cita web}}` | `{{cite web}}` | webpage |
| `{{Cita noticia}}` | `{{cite news}}` | newspaperArticle |
| `{{Cita enciclopedia}}` | `{{cite encyclopedia}}` | encyclopediaArticle |
| `{{Cita conferencia}}` | `{{cite conference}}` | conferencePaper |
| `{{Cita episodio}}` | `{{cite episode}}` | videoRecording |
| `{{Cita entrevista}}` | `{{cite interview}}` | interview |
| `{{Obra citada}}` | `{{Citation}}` | (generic) |

## Parameter Mapping

### Core bibliographic fields

| Zotero field | English (`en`) | French (`fr`) | Spanish (`es`) |
|--------------|---------------|--------------|----------------|
| title | `title` | `titre` (alias: `title`) | `título` (alias: `title`) |
| subtitle | — | `sous-titre` | — |
| translatedTitle | `trans-title` | `traduction titre` (alias: `titre original`) | `títulotrad` (alias: `trans_title`) |
| publicationTitle | `journal`, `newspaper`, `website`, `work` | `périodique` (aliases: `revue`, `journal`) | `publicación` (alias: `journal`) |
| date | `date` | `date` (also: `jour`+`mois`+`année`) | `fecha` (alias: `date`) |
| year | `year` | `année` (alias: `year`) | `año` (alias: `year`) |
| volume | `volume` | `volume` | `volumen` (alias: `volume`) |
| issue | `issue` | `numéro` | `número` (alias: `issue`) |
| pages | `pages`, `page` | `pages` (aliases: `page`, `passage`, `p.`, `pp.`) | `páginas`, `página` (aliases: `pages`, `page`) |
| publisher | `publisher` | `éditeur` (alias: `publisher`) | `editorial` (alias: `publisher`) |
| place | `location` | `lieu` (aliases: `lieu édition`, `location`) | `ubicación` (aliases: `lugar`, `place`, `location`) |
| language | `language` | `langue` (aliases: `lang`, `language`) | `idioma` (alias: `language`) |
| edition | `edition` | — | `edición` (alias: `edition`) |
| series | `series` | `série` | `serie` |
| url | `url` | `lire en ligne` (aliases: `url`, `texte`, `url texte`) | `url` |
| accessDate | `access-date` | `consulté le` (alias: `accessdate`) | `fechaacceso` (aliases: `accessdate`, `access-date`) |

### Identifiers

| Zotero field | English (`en`) | French (`fr`) | Spanish (`es`) |
|--------------|---------------|--------------|----------------|
| ISBN | `isbn` | `isbn` (alias: `ISBN`) | `isbn` |
| ISSN | `issn` | `issn` (alias: `ISSN`) | `issn` |
| DOI | `doi` | `doi` | `doi` |
| PMID | — | `pmid` | `pmid` |
| OCLC | — | `oclc` | `oclc` |

### Author fields

| Concept | English (`en`) | French (`fr`) | Spanish (`es`) |
|---------|---------------|--------------|----------------|
| Last name (1st) | `last`, `last1` | `nom1` (alias: `nom`, `last1`, `last`) | `apellidos` (aliases: `last1`, `last`, `apellido`) |
| First name (1st) | `first`, `first1` | `prénom1` (alias: `prénom`, `first1`, `first`) | `nombre` (aliases: `first1`, `first`, `nombres`) |
| Full author (1st) | `author`, `author1` | `auteur1` (alias: `auteur`, `author1`) | `autor` (alias: `author`, `authors`) |
| Last name (nth) | `last{n}` | `nom{n}` (alias: `last{n}`) | `apellidos{n}` (alias: `last{n}`) |
| First name (nth) | `first{n}` | `prénom{n}` (alias: `first{n}`) | `nombre{n}` (alias: `first{n}`) |
| Author link | `author-link` | `lien auteur1` | `enlaceautor` (alias: `authorlink`) |
| Institutional author | — | `auteur institutionnel` | — |
| Translator | — | `traducteur` (aliases: `trad`, `traduction`) | `otros` (freeform) |
| Editor last | `editor-last` | — | `apellidos-editor` (alias: `editor-last`) |
| Editor first | `editor-first` | — | `nombre-editor` (alias: `editor-first`) |

### Book-specific fields (French `{{Ouvrage}}` and `{{Chapitre}}`)

| Zotero field | English | French |
|---|---|---|
| bookTitle | (in `{{Citation}}`: `title` when `chapter=` present) | `titre ouvrage` (in `{{Chapitre}}`) |
| chapter / title | `chapter` | `titre chapitre` (in `{{Chapitre}}`); `chapitre` (in `{{Ouvrage}}`) |
| numPages | `pages` (for books) | `pages totales` |
| numberOfVolumes | — | `nombre de volumes` |

### French-specific notes

- `{{Article}}` is the primary journal citation template.  It requires
  `titre`, `périodique`, and `année`/`date`.  Field `nature article` is
  a free-text type indicator (e.g. "revue", "interview").
- `{{Ouvrage}}` handles books.  Key fields: `titre`, `éditeur`, `année`,
  `isbn`.  Has `passage` for page ranges.
- `{{Chapitre}}` is a dedicated bookSection template.  The chapter title
  goes in `titre chapitre`; the containing book in `titre ouvrage`.
- `{{Lien web}}` handles webpages.  Key fields: `titre`, `url`,
  `site` (= websiteTitle), `consulté le`.
- French templates auto-generate COinS, same as English.
- The French system allows up to 25+ numbered authors.

### Spanish-specific notes

- Spanish Wikipedia's citation templates wrap the same Lua `Module:Citation/CS1`
  as English, with Spanish aliases layered on top.
- `{{Cita publicación}}` (= cite journal) uses `publicación` for journal
  name, `volumen`/`número` for volume/issue.
- `{{Cita libro}}` (= cite book) uses `editorial` for publisher,
  `ubicación` for place, `edición` for edition.
- `{{Cita web}}` (= cite web) is nearly identical to English `cite web`
  with Spanish parameter aliases.
- `{{Cita enciclopedia}}` (= cite encyclopedia) uses `enciclopedia` for
  the encyclopedia title.
- Author numbering goes up to 9 (`apellidos1`–`apellidos9`).
- The `en` parameter in Spanish = the `at` parameter in English
  (position within source when pages are not applicable).

## Implementation Notes

### Regex pattern for multilingual extraction

For the JS and R extractors, the `cite_patterns` list should be extended
to include (case-insensitive):

```
# French
"Article", "Ouvrage", "Chapitre", "Lien web", "Lien Web"

# Spanish
"Cita publicación", "Cita libro", "Cita web", "Cita noticia",
"Cita enciclopedia", "Cita conferencia", "Cita episodio",
"Cita entrevista", "Obra citada"
```

### Parameter normalization strategy

Since French and Spanish templates accept English aliases, the simplest
approach is:

1. Detect the template name → determine language context.
2. Normalize localized parameter names to their English equivalents
   using the mapping tables above.
3. Feed the normalized params into the existing English parsing logic.

This avoids duplicating the entire parsing pipeline per language.  A
`normalize_params(params, lang)` function would handle the translation.

### Priority for next implementation phase

1. Add French and Spanish template names to `cite_patterns` / JS regex.
2. Implement `normalize_params()` for fr/es → en parameter translation.
3. Test on a handful of French and Spanish Wikipedia articles.
4. Also add `{{Citation}}` and `{{Cite EB1911}}` to the JS version
   (currently R-only).
