part of '../ociserve_courses_dialog.dart';

extension _OciServeCoursesDialogEvidence on _OciServeCoursesDialogState {
  Future<void> _loadEvidence() async {
    final org = _organizationId;
    if (org == null) return;
    _changePrivacy(() {
      _evidenceLoading = true;
      _evidenceError = null;
    });
    try {
      // The participant_id comes from the privacy-data response.
      // Fetch it first if we don't have it yet.
      var participantId = _privacyData?.participantId ?? '';
      if (participantId.isEmpty) {
        final privacy = await ref
            .read(ociServeProvider.notifier)
            .privacyData(org);
        if (!mounted || org != _organizationId) return;
        _changePrivacy(() => _privacyData = privacy);
        participantId = privacy.participantId;
      }
      if (participantId.isEmpty) {
        _changePrivacy(() {
          _evidenceLoading = false;
          _evidenceError = 'no_participant';
        });
        return;
      }
      final notifier = ref.read(ociServeProvider.notifier);
      final results = await Future.wait<Object>([
        notifier.listEvidence(
          organizationId: org,
          participantId: participantId,
        ),
        notifier.listQualifications(
          organizationId: org,
          participantId: participantId,
        ),
      ]);
      if (!mounted || org != _organizationId) return;
      _changePrivacy(() {
        _evidenceUploads = results[0] as List<EvidenceUpload>;
        _qualifications = results[1] as List<OciServeQualification>;
        _evidenceLoading = false;
      });
    } catch (error, stack) {
      logError('OciServe: bewijs laden', error.runtimeType, stack);
      if (!mounted || org != _organizationId) return;
      _changePrivacy(() {
        _evidenceLoading = false;
        _evidenceError = 'load_failed';
      });
    }
  }

  Widget _evidenceBody(
    AppLocalizations l10n,
    ThemeData theme,
    AppPalette palette,
  ) {
    if (_evidenceLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_evidenceError != null) {
      return _emptyView(
        l10n,
        theme,
        palette,
        Icons.cloud_off_outlined,
        _evidenceError == 'no_participant'
            ? l10n.d('Geen deelnemerprofiel gevonden voor deze organisatie.')
            : l10n.d('Kon uw bewijs niet laden. Probeer het opnieuw.'),
        action: OutlinedButton.icon(
          onPressed: _loadEvidence,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.d('Opnieuw proberen')),
        ),
      );
    }
    return OciServeEvidence(
      qualifications: _qualifications,
      evidenceUploads: _evidenceUploads,
      organizationId: _organizationId ?? '',
      onRefresh: _loadEvidence,
    );
  }
}
