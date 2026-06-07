# OciDeck — Bestandsformaat

OciDeck slaat presentaties op als **standaard [Marp](https://marp.app/) Markdown** (`.md`).
Er is geen eigen binair formaat: een opgeslagen presentatie kan direct met de
Marp CLI of VS Code Marp-extensie verwerkt worden. OciDeck-specifieke informatie
wordt meegeschreven op manieren die Marp negeert (front-matter-sleutels en
HTML-commentaar), zodat het bestand zowel volledig Marp-compatibel is als een
verliesvrije round-trip in OciDeck oplevert.

Daarnaast bestaan er twee afgeleide vormen:

- een **projectmap** rond het `.md`-bestand met gekopieerde assets, en
- een **draagbaar pakket** (`.ocideck`, een zip) om een presentatie als één
  bestand uit te wisselen.

---

## 1. Projectmap-indeling

Bij opslaan (`Opslaan` / `Opslaan als…`) schrijft OciDeck niet alleen de `.md`,
maar legt het ook een vaste mapstructuur ernaast aan en kopieert het alle
gebruikte assets erheen. Paden in de Markdown zijn daarna **relatief** ten
opzichte van de map van het `.md`-bestand.

```
mijn_presentatie/
├── Mijn_presentatie.md          # de presentatie (Marp Markdown)
├── Mijn_presentatie.ink.json    # annotatielaag-sidecar (zie §6.2)
├── images/                      # gekopieerde afbeeldingen
│   ├── foto.png
│   └── .ocideck_captions.json   # bijschriften-sidecar (zie §6.1)
├── data/                        # gekoppelde grafiek-CSV's (zie §6.3)
│   └── omzet.csv
├── logos/                       # gekopieerd logo van het stijlprofiel
│   └── logo.png
├── media/                       # video/audio (alleen in het pakket, zie §7)
└── themes/
    └── ocideck.css              # gegenereerde thema-CSS (zie §5)
```

> De bestandsnaam van de `.md` wordt afgeleid van de presentatietitel: niet-
> alfanumerieke tekens worden verwijderd en spaties worden `_`.

De mappen `images/`, `logos/`, `themes/` (en `node_modules/`, `build/`, `.git/`,
`.dart_tool/`) worden overgeslagen wanneer OciDeck een map scant op
presentaties.

> Naast de `.md` staan **sidecars** die bewust géén onderdeel van de Marp-
> Markdown zijn (zodat het `.md` puur en uitwisselbaar blijft): de
> annotatielaag (`<naam>.ink.json`, §6.2), bijschriften (`.ocideck_captions.json`,
> §6.1) en gekoppelde grafiekdata (`data/*.csv`, §6.3).

---

## 2. Markdown-structuur op hoofdlijnen

```markdown
---
marp: true
theme: ocideck
paginate: true
... (overige metadata) ...
ocideck_style_profile: <base64url(JSON)>
---

<!-- _class: title -->

# Eerste slide

---

<!-- _class: ... -->

(tweede slide)
```

- Het document begint met **YAML front matter** tussen `---`-regels (§3).
- Slides worden gescheiden door een regel met exact `---` (intern gesplitst op
  `\n---\n`).
- Elke slide begint optioneel met een `<!-- _class: … -->`-regel die het
  slidetype en gedrag bepaalt (§4).

---

## 3. Front matter

| Sleutel | Type | Betekenis |
| --- | --- | --- |
| `marp` | `true` | Vaste Marp-marker. |
| `theme` | string | Themanaam; standaard `ocideck`. Verwijst naar `themes/<theme>.css`. |
| `paginate` | `true`/afwezig | Wordt alleen geschreven als paginering aanstaat. |
| `author` | string | Auteur. |
| `organization` | string | Organisatie. |
| `version` | string | Versie. |
| `date` | string | Datum (vrije tekst). |
| `description` | string | Beschrijving. |
| `keywords` | string | Trefwoorden. |
| `tlp` | enum | Traffic Light Protocol-niveau (§3.1). Alleen geschreven als ≠ `none`. |
| `ocideck_style_profile` | base64url | Volledig stijlprofiel als JSON (§3.2). |

De metadatavelden worden alleen geschreven wanneer ze niet leeg zijn. Tekst
wordt als YAML-scalar geschreven en alleen tussen dubbele quotes gezet wanneer
dat nodig is (lege waarde, rand-witruimte, of speciale tekens zoals `: # "` of
een YAML-indicator aan het begin). Bij het lezen wordt geen volwaardige
YAML-parser gebruikt maar een eenvoudige regel-voor-regel-parser; houd de front
matter dus plat (één sleutel per regel).

### 3.1 TLP-niveaus

Opgeslagen onder de sleutel `tlp` met deze stabiele waarden:

| `tlp` waarde | Markering op slide |
| --- | --- |
| `none` *(niet geschreven)* | — |
| `clear` | `TLP:CLEAR` |
| `green` | `TLP:GREEN` |
| `amber` | `TLP:AMBER` |
| `amber+strict` | `TLP:AMBER+STRICT` |
| `red` | `TLP:RED` |

### 3.2 `ocideck_style_profile` (stijlprofiel)

Het complete visuele profiel wordt als JSON geserialiseerd, ge-UTF-8'd en
**base64url**-gecodeerd op één regel. Decodeer met base64url → UTF-8 → JSON. De
JSON heeft deze velden (met standaardwaarden):

| Veld | Standaard | Betekenis |
| --- | --- | --- |
| `name` | `"Standaard"` | Profielnaam. |
| `slideBackgroundColor` | `#FFFFFF` | Achtergrond gewone slide. |
| `textColor` | `#222222` | Tekstkleur. |
| `accentColor` | `#2E7D64` | Accent (bullets-marker, tabelranden/-kop). |
| `tableTextColor` | = `textColor` | Tekstkleur in tabellen. |
| `tableHeaderTextColor` | `#FFFFFF` | Tekstkleur tabelkop. |
| `titleBackgroundColor` | `#1C2B47` | Achtergrond titelslide. |
| `titleTextColor` | `#FFFFFF` | Tekst op titel-/sectieslide. |
| `sectionBackgroundColor` | `#2E7D64` | Achtergrond sectieslide. |
| `logoPath` | `null` | Pad naar logo (relatief in `logos/`). |
| `logoPosition` | `bottom-right` | `top-left`/`top-right`/`bottom-left`/`bottom-right`. |
| `logoSize` | `96` | Logogrootte in px. |
| `fontFamily` | `Arial` | Lettertype van de presentatie. |
| `footerText` | `""` | Vrije footertekst; tokens: `{page}`, `{total}`, `{date}`, `{title}`. |
| `footerShowPageNumbers` | `false` | Toon "pagina / totaal" rechtsonder. |
| `footerPosition` | `right` | `left`/`center`/`right`. |
| `closingSlideEnabled` | `false` | Voeg automatisch een slotslide toe bij presenteren/exporteren. |
| `closingSlideMarkdown` | `"# Bedankt\n\nVragen?"` | Markdown van die slotslide. |

Onbekende/ontbrekende velden vallen terug op de standaardwaarden, dus oudere
bestanden migreren probleemloos.

---

## 4. Slide-classes en gedrag

Direct na de scheiding kan een slide een class-commentaar bevatten:

```markdown
<!-- _class: <typeclass> [logo-safe] [no-logo] [no-footer] [eigen-classes] -->
```

De eerste class bepaalt (samen met de inhoud) het **slidetype**:

| Type | `_class` token | Detectie zonder token |
| --- | --- | --- |
| Titelpagina | `title` | — |
| Tussentitel (sectie) | `section` | — |
| Twee bulletkolommen | `two-bullets` | — |
| Bullets + afbeelding | `split` | bullets **en** afbeelding aanwezig |
| Quote | `quote` | een `>`-regel aanwezig |
| Video | `video` | een `<video>`-tag aanwezig |
| Tabel | `table` | alleen een tabel, geen kop/bullets/tekst |
| Broncode | `code` | — |
| Grafiek | `chart` | — |
| Alleen bullets | *(geen)* | bullets aanwezig |
| Twee afbeeldingen | *(geen)* | twee achtergrond-afbeeldingen |
| Grote afbeelding | *(geen)* | één afbeelding, geen bullets |
| Vrije Markdown | *(geen)* | geen kop/bullets/afbeelding/quote |

> `code`- en `chart`-slides bevatten een fenced codeblok dat de generieke
> regel-parser zou verstoren; ze worden daarom apart herkend aan hun `_class`.

Extra gedragsklassen:

- `logo-safe` — gereserveerde ruimte zodat het logo de inhoud niet overlapt.
  Wordt automatisch toegevoegd als er een logo is **en** de slide het logo toont.
- `no-logo` — verberg het logo op deze slide (`showLogo = false`).
- `no-footer` — verberg de footer op deze slide (`showFooter = false`).
  Ontbreekt dit token (oudere bestanden), dan blijft de footer zichtbaar.

Bij het inlezen worden de type- en gedragsklassen herkend en verwijderd; wat
overblijft, wordt bewaard als de eigen `cssClass` van de slide.

---

## 5. Per slidetype: Markdown-weergave

Hieronder de gegenereerde vorm per type. Afbeeldings-bijschriften (§6) worden
waar van toepassing als `<div class="image-caption">…</div>` direct onder de
afbeelding geschreven.

**Titel** (`title`)
```markdown
![bg 60% opacity:.45](images/achtergrond.png)   <!-- optionele achtergrond -->
# Titel
## Ondertitel
```

**Sectie** (`section`)
```markdown
# Sectietitel

Optionele toelichtende paragraaf
```

**Bullets** (geen class) — inspringen met tabs in het model → 2 spaties per
niveau in Markdown:
```markdown
# Kop

- Eerste punt
  - Subpunt
```

**Twee bulletkolommen** (`two-bullets`) — naast de zichtbare HTML-grid worden de
twee kolommen ook **canoniek opgeslagen** in commentaar (base64url van een JSON-
array), zodat ze verliesvrij teruggelezen worden:
```markdown
<!-- ocideck_two_bullets_left: <base64url(JSON[])> -->
<!-- ocideck_two_bullets_right: <base64url(JSON[])> -->
<div class="ocideck-two-bullets" style="…">
<ul>…</ul>
<ul>…</ul>
</div>
```

**Bullets + afbeelding** (`split`) — paneelbreedte en tekstschaal staan in een
`_style`-commentaar; de afbeelding zit in een `split-image`-div:
```markdown
<!-- _style: --image-width: 40%; --split-text-scale: 1.85; -->

<div class="split-text" style="font-size: 1.85em">

# Kop

- Punt

</div>

<div class="split-image">

![](images/foto.png)

</div>
```

**Twee afbeeldingen** (geen class) — als links/rechts achtergronden:
```markdown
![bg left:50%](images/links.png)
![bg right:50%](images/rechts.png)

# Optionele kop
```

**Grote afbeelding** (geen class)
```markdown
![bg 80%](images/foto.png)

# Optionele kop
```

**Video** (`video`)
```markdown
# Optionele kop

<video src="media/clip.mp4" controls autoplay muted loop style="…"></video>
```

**Quote** (`quote`)
```markdown
![bg 50% opacity:.45](images/achtergrond.png)   <!-- optioneel -->
> De quote-tekst

— Auteur
```

**Tabel** (`table`) — GitHub-flavoured Markdown; eerste rij is de kop. In cellen
worden `|` als `\|` en regeleindes als `<br>` weggeschreven:
```markdown
# Optionele kop

| Kop 1 | Kop 2 |
| --- | --- |
| a | b |
```

**Vrije Markdown** (geen class) — de inhoud wordt letterlijk weggeschreven.

**Broncode** (`code`) — een optionele kop plus een fenced codeblok; de
info-string is de programmeertaal (highlight.js-id, leeg = platte tekst). De
code zelf staat verbatim in het blok:
````markdown
# Optionele kop

```dart
void main() => print('hi');
```
````

**Grafiek** (`chart`) — een fenced ```chart```-blok met de grafiekspecificatie
als **JSON**. Kleine grafieken bewaren hun data inline; data-gedreven grafieken
verwijzen via `source` naar een CSV in `data/` (zie §6.3). Bij opslaan wordt de
inline data weggelaten zodra er een `source` is (de CSV is dan de bron); bij
openen wordt die weer ingelezen.
````markdown
```chart
{
  "type": "bar",            // bar | line | pie
  "title": "Omzet",
  "source": "data/omzet.csv",  // optioneel; anders inline x/series
  "x": ["Q1", "Q2"],
  "series": [ { "name": "2025", "data": [10, 14] } ]
}
```
````

### Afbeeldingsgrootte (`imageSize`)
Eén integer-veld met typeafhankelijke betekenis: bij `image`/`title`/`quote` het
achtergrond-percentage (`![bg N%]`), bij `split` de paneelbreedte (geklemd
20–70%), bij twee afbeeldingen de `left:`/`right:`-verdeling. `0` = automatisch.

---

## 6. Sidecars en losse data

Drie soorten gegevens staan bewust náást het `.md` in plaats van erin, zodat de
Marp-Markdown puur en uitwisselbaar blijft.

### 6.1 Afbeeldings-bijschriften (captions)

Bijschriften worden op **twee** plaatsen bewaard:

1. **In de Markdown**, als zichtbare regel onder de afbeelding:
   ```markdown
   <div class="image-caption">Mijn bijschrift</div>
   ```
   Bij twee afbeeldingen worden beide bijschriften samengevoegd met ` | `.
   HTML-tekens worden ge-escaped.

2. **Als JSON-sidecar** `\.ocideck_captions.json` in de map van de afbeelding,
   zodat het bijschrift aan het *bestand* hangt (en gedeeld kan worden tussen
   presentaties). Formaat — sleutel is de bestandsnaam, waarde het bijschrift:
   ```json
   {
     "foto.png": "Mijn bijschrift",
     "grafiek.png": "Omzet per kwartaal"
   }
   ```
   Een lege caption verwijdert de sleutel; een leeg bestand wordt verwijderd.

### 6.2 Annotatielaag (`<naam>.ink.json`)

Vrije-hand-annotaties (pen, markeerstift) die tijdens het presenteren worden
gemaakt, staan in een aparte JSON-sidecar naast de `.md` (en in het pakket, §7).
De Marp-`.md` wordt er nooit door aangeraakt.

- Coördinaten zijn **genormaliseerd** (0–1) binnen het 16:9-vlak, zodat een
  streek identiek schaalt op laptop en beamer.
- Omdat slide-id's bij elke keer inlezen opnieuw worden gegenereerd, worden
  strekken op schijf **per slide verankerd op volgorde + een inhoud-fingerprint**.
  Bij heropenen worden ze her-gekoppeld aan de slide met dezelfde fingerprint
  (bij voorkeur dezelfde index); strekken van een gewijzigde/verwijderde slide
  vervallen.

```json
{
  "version": 1,
  "slides": [
    {
      "index": 2,
      "fp": "a1b2c3d4",
      "strokes": [
        { "tool": "pen", "color": 4294198070, "width": 0.004,
          "points": [0.1, 0.2, 0.15, 0.22] }
      ]
    }
  ]
}
```

`points` is een platte lijst `[x0, y0, x1, y1, …]`; `color` is een ARGB-int;
`tool` is `pen` of `highlighter` (laser-aanwijzingen zijn vluchtig en worden niet
bewaard).

### 6.3 Grafiekdata (`data/*.csv`)

Een grafiek-slide (§5) kan zijn data inline in het `chart`-blok houden óf via
`"source": "data/<naam>.csv"` verwijzen naar een CSV in de aparte **`data/`**-map
naast het deck. Die map houdt alle gekoppelde databestanden bij elkaar,
gescheiden van `images/`/`media/`. De CSV is dan de bron van waarheid: hij wordt
los bewerkt (bijv. in een spreadsheet), bij opslaan/`Opslaan als…` meegekopieerd,
en in het pakket meegenomen (§7). Bij openen wordt de CSV ingelezen en de data
in het geheugen aan de grafiek gehangen; in de `.md` blijft alleen de
`source`-verwijzing staan.

CSV-vorm: eerste rij = reeksnamen (eerste cel = labelkolom), elke volgende rij is
`label, waarde1, waarde2, …`.

---

## 7. Draagbaar pakket (`.ocideck`)

`Pakket exporteren` schrijft één **zip-bestand** (extensie `.ocideck`; ook `.zip`
wordt bij import geaccepteerd) met de presentatie en alle gebruikte assets,
onderling met relatieve paden. Werkt ook als het deck nog niet is opgeslagen.

```
<titel>.ocideck   (zip)
├── <titel>.md                # Marp Markdown
├── <titel>.ink.json          # annotatielaag (indien aanwezig, §6.2)
├── images/…                  # alle gebruikte afbeeldingen
├── data/…                    # gekoppelde grafiek-CSV's (§6.3)
├── media/…                   # gebruikte video/audio
├── logos/…                   # logo uit het stijlprofiel
└── themes/<theme>.css        # gegenereerde thema-CSS (Marp/CLI-bruikbaar)
```

Bij import:

- De zip wordt uitgepakt in een **nieuwe**, unieke submap (naam afgeleid van de
  hoofd-`.md`; bij botsing `naam (2)`, `naam (3)`, …).
- Als hoofdbestand wordt de `.md` met het **ondiepste** pad gekozen.
- Een pakket kan ook van een URL worden geïmporteerd: begint de download met de
  zip-magie `PK\x03\x04` dan wordt het als pakket behandeld, anders als platte
  Markdown opgeslagen.

---

## 8. Speciale per-slide-commentaren (overzicht)

Naast `_class` gebruikt OciDeck deze HTML-commentaren (allemaal door Marp
genegeerd, op presenter-notities na):

| Commentaar | Betekenis |
| --- | --- |
| `<!-- _class: … -->` | Slidetype + gedrag (§4). |
| `<!-- _style: --image-width: N%; --split-text-scale: x; -->` | Layout van een `split`-slide. |
| `<!-- ocideck_two_bullets_left/right: <base64url> -->` | Canonieke opslag van de twee bulletkolommen. |
| `<!-- advance: N.N -->` | Auto-doorschakelen na N,N seconden (0 = uit). |
| `<!-- skip -->` | Slide overslaan bij presenteren én exporteren. |
| `<!-- tlp: <key> -->` | Per-slide TLP-niveau (zie §3.1). De slide wordt achtergehouden als het presentatie-TLP lager is. Alleen geschreven als ≠ `none`. |
| `<!-- … (vrije tekst) … -->` | **Presenter-notities** (elk overig commentaar dat niet met `_` begint). |

---

## 9. Round-trip en compatibiliteit

- **Verliesvrij in OciDeck:** alles wat de editor kan instellen wordt of als
  echte Markdown, of als OciDeck-commentaar/front-matter-sleutel bewaard en bij
  het openen weer ingelezen. De parse is "best effort": mislukt het volledig,
  dan geeft de parser `null`; een leeg document levert één lege titelslide op.
- **Marp-compatibel:** het bestand blijft geldige Marp Markdown. Externe tools
  zien gewone koppen, bullets, tabellen, achtergrond-afbeeldingen en HTML; de
  OciDeck-extra's staan in genegeerd commentaar en in eigen front-matter-
  sleutels.
- **Voorwaartse migratie:** ontbrekende front-matter-velden en
  stijlprofiel-velden vallen terug op standaardwaarden, en het ontbreken van het
  `no-footer`-token betekent (voor oudere bestanden) "footer zichtbaar".
