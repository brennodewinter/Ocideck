import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/models/slide_failure_policy.dart';
import '../../services/import/pipeline/problem_slide.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// De voorkeursleutel: eenmaal weggeklikt met "niet meer vragen" beslist de
/// import voortaan zelf (best-effort). Nooit hernoemen.
const _skipAskingKey = 'importDecisionSkipAsking';

/// De uitkomst van het beslismoment: het beleid per bron-diaindex, of `null`
/// wanneer de gebruiker de hele import afbreekt.
typedef ImportDecisions = Map<int, SlideFailurePolicy>?;

/// Vraagt per probleemdia wat er moet gebeuren (#812).
///
/// Verschijnt alleen bij een enkelvoudige import, en alleen als er dia's zijn
/// die écht iets kwijtraken. De bulk-wachtrij vraagt bewust niets: tien
/// bestanden maal een vraag per dia is geen route, en die kiest altijd
/// best-effort.
///
/// Waarom dit een vraag is en geen instelling vooraf: wát je met een
/// halfgeslaagde dia wilt, hangt af van díé dia. Een dia waarvan de vormgeving
/// de boodschap droeg is beter overgeslagen dan half overgenomen; een dia die
/// vooral één plaat was, red je met alleen die plaat. Dat weet je pas als je
/// ziet wat er misging — vandaar de lijst met redenen erbij.
class ImportDecisionDialog extends StatefulWidget {
  const ImportDecisionDialog({super.key, required this.problems});

  final List<ProblemSlide> problems;

  /// Toont de dialoog wanneer dat zinvol is en geeft het gekozen beleid terug.
  ///
  /// Geeft een lege map (dus: overal best-effort) zonder iets te tonen wanneer
  /// er geen probleemdia's zijn of de gebruiker eerder "niet meer vragen" koos.
  /// Geeft `null` als de gebruiker de import afbreekt.
  static Future<ImportDecisions> ask(
    BuildContext context,
    List<ProblemSlide> problems,
  ) async {
    if (problems.isEmpty) return const {};
    if (await _skipAsking()) return const {};
    if (!context.mounted) return const {};
    // Null blijft null: zowel "Import afbreken" als het venster wegklikken
    // betekent afbreken. Dat níét doorlaten — en er stilletjes toch een deck
    // van maken — zou de vraag tot een schijnvertoning maken.
    return showDialog<Map<int, SlideFailurePolicy>>(
      context: context,
      builder: (_) => ImportDecisionDialog(problems: problems),
    );
  }

  @override
  State<ImportDecisionDialog> createState() => _ImportDecisionDialogState();
}

class _ImportDecisionDialogState extends State<ImportDecisionDialog> {
  /// Elke dia begint op best-effort — de veilige keuze, en precies wat de
  /// uitleg erboven belooft.
  ///
  /// Hier stond eerst het "voorstel" uit `ProblemSlide`, dat bij een dia mét
  /// afbeelding `imageOnly` was. Dat maakte de standaardhandeling destructief:
  /// wie niets aanraakte en op Importeren drukte, verloor de tekst van juist
  /// die dia's, terwijl de zin erboven het tegendeel beloofde. Een voorstel dat
  /// tegelijk de standaard is, is geen voorstel maar een besluit dat voor je
  /// genomen is.
  late final Map<int, SlideFailurePolicy> _choices = {
    for (final p in widget.problems)
      p.sourceSlideNumber - 1: SlideFailurePolicy.bestEffort,
  };
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Wat doen we met deze dia’s?')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Deze dia’s konden niet volledig worden omgezet. Kies per dia wat er moet gebeuren; wat u niet aanraakt wordt zo volledig mogelijk overgenomen, met een notitie erbij over wat er ontbreekt.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 12),
            _applyToAllRow(l10n),
            const Divider(height: 20),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.problems.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (_, i) => _problemRow(l10n, widget.problems[i]),
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _dontAskAgain,
              onChanged: (v) => setState(() => _dontAskAgain = v ?? false),
              title: Text(l10n.d('Niet meer vragen')),
              subtitle: Text(
                l10n.d('Voortaan alles zo volledig mogelijk overnemen.'),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.d('Import afbreken')),
        ),
        FilledButton(onPressed: _confirm, child: Text(l10n.d('Importeren'))),
      ],
    );
  }

  /// Eén keuze voor alles. Bij twintig probleemdia's is per stuk beslissen geen
  /// hulp meer, en dit is de uitweg die dat draaglijk houdt.
  ///
  /// Een `Wrap` en geen `Row`: het label plus drie knoppen past niet altijd op
  /// één regel, en zeker niet in de talen die er meer woorden voor nodig hebben
  /// (de teksten leven in 31 vertalingen). Een rij die overloopt is geen
  /// opmaakdetail — hij maakt de laatste knop onbereikbaar.
  Widget _applyToAllRow(AppLocalizations l10n) => Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        l10n.d('Voor alle dia’s:'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      for (final policy in SlideFailurePolicy.values)
        OutlinedButton(
          onPressed: () => setState(() {
            for (final key in _choices.keys) {
              _choices[key] = policy;
            }
          }),
          child: Text(_label(l10n, policy)),
        ),
    ],
  );

  Widget _problemRow(AppLocalizations l10n, ProblemSlide p) {
    final index = p.sourceSlideNumber - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.title == null
              ? '${l10n.d('Dia')} ${p.sourceSlideNumber}'
              : '${l10n.d('Dia')} ${p.sourceSlideNumber} — ${p.title}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        // De redenen erbij: zonder te weten wát er misging is de keuze een gok.
        for (final reason in p.issueDescriptions)
          Text(
            '• $reason',
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final policy in SlideFailurePolicy.values)
              // Alleen-de-afbeelding heeft een afbeelding nodig; zonder er een
              // aanbieden is een knop die liegt.
              if (policy != SlideFailurePolicy.imageOnly || p.hadImage)
                ChoiceChip(
                  label: Text(_label(l10n, policy)),
                  selected: _choices[index] == policy,
                  onSelected: (_) => setState(() => _choices[index] = policy),
                ),
          ],
        ),
      ],
    );
  }

  String _label(AppLocalizations l10n, SlideFailurePolicy policy) =>
      switch (policy) {
        SlideFailurePolicy.bestEffort => l10n.d('Zo volledig mogelijk'),
        SlideFailurePolicy.imageOnly => l10n.d('Alleen de afbeelding'),
        SlideFailurePolicy.skip => l10n.d('Overslaan'),
      };

  Future<void> _confirm() async {
    if (_dontAskAgain) await _setSkipAsking();
    if (!mounted) return;
    Navigator.of(context).pop(_choices);
  }
}

Future<bool> _skipAsking() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipAskingKey) ?? false;
  } catch (e, s) {
    // Onleesbare voorkeuren: dan liever wél vragen dan stil beslissen.
    logError('ImportDecisionDialog: read preference', e, s);
    return false;
  }
}

Future<void> _setSkipAsking() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipAskingKey, true);
  } catch (e, s) {
    logError('ImportDecisionDialog: persist preference', e, s);
  }
}
