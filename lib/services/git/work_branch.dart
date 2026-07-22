import '../../models/git_settings.dart';
import 'git_forge.dart';

/// Op welke branch een opslag landt, en of hij daar zelf van aftakt.
///
/// Een record in plaats van vier losse teruggaven, omdat de vier bij elkaar
/// horen: wie `workBranch` gebruikt zonder `forkFrom` takt niet af, en wie
/// `baseSha` gebruikt zonder `midRound` weet niet of die basis ergens tegenaan
/// kán botsen.
typedef WorkBranchChoice = ({
  String workBranch,
  String? forkFrom,
  bool midRound,
  String baseSha,
});

/// D3: bewerken gebeurt op een werkbranch, nooit rechtstreeks op de
/// standaardbranch. Zit dit tabblad al midden in een ronde op zo'n branch —
/// zelfde repo, zelfde deck, andere branch — dan blijft het daar en is er
/// niets af te takken. Anders start (of hervat) het de ronde van vandaag op
/// `decks/<naam>/<datum>`. De naam wordt gegenereerd, niet getypt; de UI
/// spreekt van "concept".
WorkBranchChoice workBranchFor({
  required GitOrigin? origin,
  required GitRepoConfig config,
  required String deckDir,
  required String deckName,
  required String branch,
  required DateTime? now,
}) {
  // Hetzelfde deck in dezelfde repo: dan is [GitOrigin.baseSha] de commit waar
  // dít werk tegenaan gelezen is, en dus de gemeenschappelijke voorouder.
  final sameDeck =
      origin != null && origin.matchesRepo(config) && origin.deckDir == deckDir;
  final midRound = sameDeck && origin.branch != branch;
  if (midRound) {
    return (
      workBranch: origin.branch,
      forkFrom: null,
      midRound: true,
      // Alleen midden in een ronde is er een basis om tegen te botsen; bij een
      // verse ronde bestaat de branch nog niet.
      baseSha: origin.baseSha,
    );
  }
  final generated = GitRepoLayout.workBranch(deckName, now ?? DateTime.now());
  if (generated == null) {
    throw const GitForgeException(
      GitForgeError.malformed,
      'Kon geen geldige werkbranch-naam maken',
    );
  }
  return (
    workBranch: generated,
    forkFrom: branch,
    midRound: false,
    // De gelezen basis reist óók bij een verse ronde mee. De werkbranch draagt
    // alleen een datum, dus die van vandaag kán al bestaan — een tweede ronde
    // op dezelfde dag, of een collega die eerder was. Dan is dit de voorouder
    // waar de guard op botst en waarmee de driewegs-merge kan werken. Leeg
    // blijft het alleen voor een deck dat nog nooit uit deze repo is gelezen.
    baseSha: sameDeck ? origin.baseSha : '',
  );
}

/// De commit waar een opslag tegenaan botst, of de reden dat hij niet doorgaat.
///
/// Precies één van beide is gevuld. Een null [baseSha] is geen fout maar een
/// uitkomst: er valt niets te botsen en niets samen te voegen, en [blocked]
/// vertelt de gebruiker in gewone taal waarom.
typedef RoundBase = ({String? baseSha, String? blocked});

/// De commit waar deze opslag tegenaan botst — de kern van de guard.
///
/// Midden in een ronde is dat de gelezen basis. Bij een verse ronde takken we
/// de werkbranch net af, en dan ís zijn kop onze basis. Bestaat die branch al
/// — de werkbranchnaam draagt alleen een datum, dus een tweede ronde op
/// dezelfde dag of een collega die eerder was — dan nemen we zijn kop juist
/// **niet** over: de guard zou dan per definitie tevreden zijn en we schreven
/// weg wat daar staat. De gelezen basis is dan de gemeenschappelijke
/// voorouder, zodat het botst en de driewegs-merge zijn werk kan doen.
///
/// Is er geen gelezen basis én bestaat de branch al, dan valt er niets te
/// botsen en niets samen te voegen; `baseSha` is dan null en [blocked] legt
/// uit waarom de opslag niet doorgaat.
Future<RoundBase> roundBaseSha(
  GitForge forge, {
  required bool midRound,
  required String roundBase,
  required String workBranch,
  required String branch,
}) async {
  if (midRound) return (baseSha: roundBase, blocked: null);
  final branches = await forge.listBranches();
  if (branches.every((b) => b.name != workBranch)) {
    final created = await forge.createBranch(workBranch, fromRef: branch);
    return (baseSha: created.sha, blocked: null);
  }
  if (roundBase.isNotEmpty) return (baseSha: roundBase, blocked: null);
  return (
    baseSha: null,
    blocked:
        'Er staat al een concept van vandaag op $workBranch, en dit deck '
        'komt daar niet uit voort. Open dat concept eerst, of geef dit deck '
        'een andere naam.',
  );
}
