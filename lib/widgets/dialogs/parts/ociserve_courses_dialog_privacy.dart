part of '../ociserve_courses_dialog.dart';

extension _OciServeCoursesDialogPrivacy on _OciServeCoursesDialogState {
  Future<void> _loadPrivacyData() async {
    final org = _organizationId;
    if (org == null) return;
    _changePrivacy(() {
      _privacyLoading = true;
      _privacyError = null;
      _privacyData = null;
    });
    try {
      final value = await ref.read(ociServeProvider.notifier).privacyData(org);
      if (!mounted || org != _organizationId) return;
      _changePrivacy(() {
        _privacyData = value;
        _privacyLoading = false;
      });
    } catch (error, stack) {
      logError('OciServe: gegevensinzage laden', error.runtimeType, stack);
      if (!mounted || org != _organizationId) return;
      _changePrivacy(() {
        _privacyLoading = false;
        _privacyError = 'load_failed';
      });
    }
  }

  Widget _privacyBody(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
  ) {
    if (_privacyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_privacyError != null || _privacyData == null) {
      return _emptyView(
        l10n,
        theme,
        palette,
        Icons.cloud_off_outlined,
        l10n.d('Kon uw gegevens niet laden. Probeer het opnieuw.'),
        action: OutlinedButton.icon(
          onPressed: _loadPrivacyData,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.d('Opnieuw proberen')),
        ),
      );
    }
    final membership = ref
        .read(ociServeProvider)
        .memberships
        .where((item) => item.organizationId == _organizationId)
        .firstOrNull;
    return OciServeDataAccess(
      data: _privacyData!,
      organizationName: membership?.name ?? '',
    );
  }
}
