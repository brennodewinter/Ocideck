/// Welk onderdeel van een brondia een [ConversionIssue] betreft.
///
/// **Diagnostisch, niet zichtbaar.** Deze categorie stuurt de logging en de
/// groepering van probleemdia's; hij belandt níet in de vertaalde notitietekst
/// (die blijft de vaste bronstrings in [ConversionIssue.feature]/[description],
/// #806). Zo hoeft een nieuwe categorie geen 31 vertalingen — en tegelijk kan de
/// foutgrens in de importers een verlies benoemen zonder broninhoud te lekken.
enum IssueComponent {
  /// De hele dia kon niet worden geparseerd.
  slide,
  chart,
  table,

  /// Een relatie (`.rels`, `r:id`) die niet oploste.
  relation,

  /// Ingesloten of gelinkte media (afbeelding, video, audio).
  media,

  /// Sprekersnotities.
  notes,
  theme,
}

/// Waaróm een onderdeel niet kon worden overgenomen — de oorzaakcategorie.
///
/// Net als [IssueComponent] diagnostisch: voor logging en groepering, niet voor
/// de zichtbare notitietekst.
enum IssueCause {
  /// Onleesbare of ongeldige XML/structuur.
  malformedXml,

  /// Een verwacht onderdeel (part, relatie-doel) ontbrak.
  missingPart,

  /// Een onverwachte fout die geen van bovenstaande categorieën dekt.
  unexpected,
}

/// A feature from a source slide that the import could not map to OciDeck.
///
/// The pipeline collects these per slide and, after the converted slide,
/// emits a free-Markdown "not converted" slide listing them — so the user
/// always knows what was dropped and nothing disappears silently.
///
/// ## De teksten hierin zijn vertaalsleutels, geen eindtekst
///
/// [feature], [description] en [salvagedAs] zijn Nederlandse bronstrings die
/// [UnconvertedTracker] door een vertaalfunctie haalt vóór ze in het document
/// van de gebruiker belanden (#806). Dit is inhoud en geen interface: de
/// notitiedia wordt op importmoment in de taal van de gebruiker geschreven en
/// zó opgeslagen — een Griekse gebruiker hield anders permanent Nederlandse
/// alinea's in zijn eigen `.md`, die meereizen naar elk ander Marp-gereedschap.
///
/// Daarom moet elke waarde een **vaste** string zijn: een sleutel die met een
/// bestandsnaam of een getal erin gebakken zit, vindt geen vertaling. Wat
/// variabel is gaat door [args] en staat als `{naam}` in de sleutel, zodat de
/// vertaling zelf bepaalt waar het terechtkomt — "{n} slides" en "{n} dia's"
/// zetten het getal op dezelfde plek, maar lang niet elke taal doet dat.
class ConversionIssue {
  const ConversionIssue({
    required this.slideIndex,
    required this.feature,
    required this.description,
    this.salvagedAs,
    this.args = const {},
    this.component,
    this.cause,
  });

  /// 0-based index of the source slide this issue belongs to.
  final int slideIndex;

  /// Short label of the source feature, e.g. `SmartArt`, `merged cells`.
  final String feature;

  /// Human-readable explanation of what was not converted and why.
  final String description;

  /// If part of the feature was salvaged (e.g. SmartArt text → bullets),
  /// a short note of where it went. Null means nothing was salvaged.
  final String? salvagedAs;

  /// Waarden voor de `{naam}`-plaatshouders in [feature], [description] en
  /// [salvagedAs], ingevuld ná het vertalen.
  ///
  /// Twee soorten: een aantal (`{n}`) en tekst uit het bróndocument — een
  /// bestandsnaam, de tekst van een koppeling. Dat laatste wordt bewust niet
  /// vertaald: het is van de gebruiker.
  final Map<String, String> args;

  /// Welk brononderdeel dit betreft — diagnostisch, zie [IssueComponent].
  /// `null` voor de klassieke classifier-/salvage-issues die geen parse-fout
  /// zijn.
  final IssueComponent? component;

  /// De oorzaakcategorie — diagnostisch, zie [IssueCause]. `null` als het geen
  /// parse-fout betreft.
  final IssueCause? cause;

  /// Whether any part of the feature was salvaged.
  bool get isSalvaged => salvagedAs != null && salvagedAs!.isNotEmpty;
}
