// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `signOff` slide (PENTEST_MIAUW 1.6 / §8 A1): the truthfulness
/// statement, the rapporteur (name · role), certification and typed signature,
/// and the document seal status. The signature is the deck-level
/// [DocumentSignature] ([signature], threaded in by callers that hold the deck);
/// [sealedAt] is the deck's seal timestamp (empty = not yet sealed). Rendered
/// with `w`-scaled type so it sizes like the other security slides and stays
/// deterministic in an export isolate.
class _SignOffPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final DocumentSignature? signature;
  final String sealedAt;

  const _SignOffPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.signature,
    this.sealedAt = '',
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pad = w * 0.07;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final sig = signature;
    final heading = slide.title.isNotEmpty
        ? slide.title
        : l10n.d('Ondertekening');

    return Container(
      color: Colors.white,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                pad + safe.top,
                pad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heading,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.04,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  SizedBox(height: w * 0.03),
                  if (sig != null && sig.isNotEmpty)
                    _signatureBlock(context, sig)
                  else
                    Text(
                      l10n.d('Nog niet ondertekend'),
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.026,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ),
                  SizedBox(height: w * 0.035),
                  _sealBadge(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signatureBlock(BuildContext context, DocumentSignature sig) {
    final metaParts = <String>[
      if (sig.name.isNotEmpty) sig.name,
      if (sig.role.isNotEmpty) sig.role,
    ];
    final image = decodeEmbeddedSignatureImage(sig.imagePath);
    final mark = sig.typedSignature.isNotEmpty ? sig.typedSignature : sig.name;
    final markText = mark.isEmpty
        ? null
        : Text(
            mark,
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.05,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: AppTheme.navy,
              ),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sig.statement.isNotEmpty)
          Text(
            sig.statement,
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.026,
                fontStyle: FontStyle.italic,
                color: AppTheme.slate700,
              ),
            ),
          ),
        SizedBox(height: w * 0.03),
        // A drawn signature takes precedence over the typed name/mark.
        if (image != null)
          Image.memory(
            image,
            height: w * 0.09,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => markText ?? const SizedBox.shrink(),
          )
        else
          ?markText,
        SizedBox(height: w * 0.008),
        Container(width: w * 0.34, height: 1, color: AppTheme.slate300),
        SizedBox(height: w * 0.008),
        if (metaParts.isNotEmpty)
          Text(
            metaParts.join(' · '),
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.024,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate700,
              ),
            ),
          ),
        if (sig.certification.isNotEmpty)
          Text(
            sig.certification,
            style: _applyFont(
              font,
              TextStyle(fontSize: w * 0.02, color: AppTheme.slate500),
            ),
          ),
        if (sig.date.isNotEmpty)
          Text(
            sig.date,
            style: _applyFont(
              font,
              TextStyle(fontSize: w * 0.019, color: AppTheme.slate500),
            ),
          ),
      ],
    );
  }

  Widget _sealBadge(BuildContext context) {
    final l10n = context.l10n;
    final sealed = sealedAt.isNotEmpty;
    // The seal timestamp is ISO-8601 (UTC); show just the date part.
    final date = sealed ? sealedAt.split('T').first : '';
    final color = sealed ? AppTheme.scopeTested : AppTheme.slate500;
    final label = sealed
        ? '${l10n.d('Verzegeld op')} $date'
        : l10n.d('Nog niet verzegeld');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          sealed ? Icons.verified_user : Icons.lock_open_outlined,
          size: w * 0.028,
          color: color,
        ),
        SizedBox(width: w * 0.012),
        Text(
          label,
          style: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.022,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
