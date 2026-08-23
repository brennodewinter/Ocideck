import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/password_generator.dart';
import '../../utils/password_strength.dart';

/// Keuze uit [PackageEncryptDialog]: exporteren met of zonder versleuteling.
/// [password] is niet-null en niet-leeg als [encrypt] waar is.
class PackageEncryptChoice {
  final bool encrypt;
  final String? password;

  const PackageEncryptChoice({required this.encrypt, this.password});
}

/// Vraagt bij het exporteren van een `.ocideck`-pakket of het met een
/// wachtwoord (AES-256) beschermd moet worden. Versleuteling is optioneel
/// (schakelaar staat standaard uit). Toont een op-entropie-gebaseerde
/// sterktemeter (waarschuwt, blokkeert niet) en kan een sterk wachtwoord
/// genereren dat gekopieerd kan worden om door te geven.
class PackageEncryptDialog extends StatefulWidget {
  const PackageEncryptDialog({super.key});

  static Future<PackageEncryptChoice?> show(BuildContext context) {
    return showDialog<PackageEncryptChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PackageEncryptDialog(),
    );
  }

  @override
  State<PackageEncryptDialog> createState() => _PackageEncryptDialogState();
}

class _PackageEncryptDialogState extends State<PackageEncryptDialog> {
  final _ctrl = TextEditingController();
  bool _encrypt = false;
  bool _obscure = true;
  int _genLength = shortPasswordLength;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canExport => !_encrypt || _ctrl.text.isNotEmpty;

  void _generate() {
    setState(() {
      _ctrl.text = generatePassword(_genLength);
      _obscure = false; // net gegenereerd: laat zien zodat het te kopiëren is
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.d('Wachtwoord gekopieerd naar klembord.'))),
    );
  }

  void _submit() {
    if (!_canExport) return;
    Navigator.pop(
      context,
      PackageEncryptChoice(
        encrypt: _encrypt,
        password: _encrypt ? _ctrl.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Pakket exporteren')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _encrypt,
                onChanged: (v) => setState(() {
                  _encrypt = v;
                  // Zet het aan, dan staat er meteen een sterk wachtwoord.
                  //
                  // Dat is hier geen gemak maar de maatregel zélf. De
                  // sleutelafleiding van het AES-zip-formaat is PBKDF2-HMAC-SHA1
                  // met 1000 iteraties — vastgelegd door de WinZip-AES-spec en
                  // van hieruit niet te verhogen. Die iteratietelling is niet te
                  // repareren zonder het formaat te verlaten, en dan kan geen
                  // enkel ander zip-gereedschap het pakket meer openen. Wat wél
                  // in onze hand ligt is de entropie van het wachtwoord, en dat
                  // is precies waar een zwakke KDF op leunt.
                  //
                  // Een leeg veld nodigt uit tot iets wat de gebruiker kan
                  // onthouden. Een gegenereerd wachtwoord is minder werk én
                  // sterker; overtypen mag altijd nog.
                  if (v && _ctrl.text.isEmpty) {
                    _ctrl.text = generatePassword(_genLength);
                    _obscure = false; // te kopiëren, en zichtbaar dat het er is
                  }
                }),
                title: Text(l10n.d('Beschermen met een wachtwoord (AES-256)')),
                subtitle: Text(
                  l10n.d(
                    'Optioneel. Alleen wie het wachtwoord heeft, kan het pakket openen.',
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (_encrypt) ...[
                const SizedBox(height: 8),
                _passwordField(l10n),
                const SizedBox(height: 8),
                _StrengthMeter(password: _ctrl.text),
                const SizedBox(height: 12),
                _generatorRow(l10n),
                const SizedBox(height: 12),
                _lostPasswordWarning(l10n),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: _canExport ? _submit : null,
            child: Text(l10n.d('Exporteren')),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(AppLocalizations l10n) {
    return TextField(
      controller: _ctrl,
      autofocus: true,
      obscureText: _obscure,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        isDense: true,
        labelText: l10n.d('Wachtwoord'),
        prefixIcon: const Icon(Icons.lock_outline, size: 18),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _obscure
                  ? l10n.d('Wachtwoord tonen')
                  : l10n.d('Wachtwoord verbergen'),
              icon: Icon(
                _obscure ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            IconButton(
              tooltip: l10n.d('Kopiëren'),
              icon: const Icon(Icons.copy, size: 18),
              onPressed: _ctrl.text.isEmpty ? null : _copy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _generatorRow(AppLocalizations l10n) {
    return Row(
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: shortPasswordLength, label: Text('32')),
            ButtonSegment(value: longPasswordLength, label: Text('256')),
          ],
          selected: {_genLength},
          onSelectionChanged: (s) => setState(() => _genLength = s.first),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.casino_outlined, size: 18),
            label: Text(l10n.d('Genereer sterk wachtwoord')),
          ),
        ),
      ],
    );
  }

  Widget _lostPasswordWarning(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: AppTheme.amber700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.d(
              'Bewaar dit wachtwoord goed: raak je het kwijt, dan is dit pakket niet meer te openen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.amber700),
          ),
        ),
      ],
    );
  }
}

/// Balk + label die de geschatte sterkte van [password] toont. Puur informatief.
class _StrengthMeter extends StatelessWidget {
  final String password;

  const _StrengthMeter({required this.password});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (password.isEmpty) {
      return Text(
        l10n.d(
          'Tip: een lange wachtwoordzin is veiliger dan een kort wachtwoord met symbolen.',
        ),
        style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
      );
    }
    final result = estimatePasswordStrength(password);
    final color = _colorFor(result.category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: result.fraction,
            minHeight: 6,
            backgroundColor: AppTheme.slate300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _labelFor(l10n, result.category),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (result.isWeak) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d('Maak het langer voor betere bescherming.'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Color _colorFor(PasswordStrength s) => switch (s) {
    PasswordStrength.veryWeak => AppTheme.danger600,
    PasswordStrength.weak => AppTheme.danger600,
    PasswordStrength.fair => AppTheme.amber600,
    PasswordStrength.strong => AppTheme.successFg,
    PasswordStrength.veryStrong => AppTheme.successFg,
  };

  String _labelFor(AppLocalizations l10n, PasswordStrength s) => switch (s) {
    PasswordStrength.veryWeak => l10n.d('Zeer zwak'),
    PasswordStrength.weak => l10n.d('Zwak'),
    PasswordStrength.fair => l10n.d('Redelijk'),
    PasswordStrength.strong => l10n.d('Sterk'),
    PasswordStrength.veryStrong => l10n.d('Zeer sterk'),
  };
}
