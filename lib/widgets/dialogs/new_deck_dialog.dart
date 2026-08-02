import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/deck_template.dart';
import '../../models/settings.dart';
import '../../services/template_content_service.dart';
import '../../state/info_safety_provider.dart';
import '../../state/procesverbetering_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';

/// Uitkomst van de nieuwe-presentatie-wizard: titel, het gekozen
/// stijlprofiel en het startsjabloon. Het profiel staat hier bewust naast de
/// titel — veel gebruikers denken in vormen ("een nette briefing"), niet in
/// een instellingenscherm.
class NewDeckChoice {
  final String title;
  final String profileName;
  final DeckTemplate template;

  const NewDeckChoice({
    required this.title,
    required this.profileName,
    required this.template,
  });
}

/// Sjablonen in weergavevolgorde: "Leeg deck" (`empty`) blijft bovenaan als
/// startpunt-vanaf-nul, de rest alfabetisch op [displayTitle] — de getoonde,
/// vertaalde titel — via [AppLocalizations.sortKey], zodat zoeken en scannen in
/// elke taal logisch verloopt (diacrieten en andere schriften vouwen mee).
List<DeckTemplate> sortTemplatesForDisplay(
  Iterable<DeckTemplate> items,
  String Function(DeckTemplate template) displayTitle,
) {
  final list = items.toList();
  list.sort((a, b) {
    if (a.id == 'empty') return b.id == 'empty' ? 0 : -1;
    if (b.id == 'empty') return 1;
    return AppLocalizations.sortKey(
      displayTitle(a),
    ).compareTo(AppLocalizations.sortKey(displayTitle(b)));
  });
  return list;
}

/// De nieuwe-presentatie-wizard: vraagt een titel, laat een stijlprofiel
/// kiezen en een [DeckTemplate] waarvan de voorbeeldslides het verse deck
/// vullen.
class NewDeckDialog extends ConsumerStatefulWidget {
  const NewDeckDialog({super.key});

  static Future<NewDeckChoice?> show(BuildContext context) {
    return showDialog<NewDeckChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewDeckDialog(),
    );
  }

  @override
  ConsumerState<NewDeckDialog> createState() => _NewDeckDialogState();
}

/// Picker icons per [DeckTemplate.icon] key. Lives here (not in the model) so
/// the model layer stays Flutter-free, mirroring the slide-type registry.
/// Public zodat een guardtest kan afdwingen dat elk sjabloon een icoon heeft.
const Map<String, IconData> templatePickerIcons = {
  'empty': Icons.crop_landscape_outlined,
  'briefing': Icons.summarize_outlined,
  'securityGuardBriefing': Icons.security,
  'policeBriefing': Icons.local_police_outlined,
  'enforcementBriefing': Icons.badge_outlined,
  'status': Icons.speed_outlined,
  'kickoff': Icons.rocket_launch_outlined,
  'communication': Icons.forum_outlined,
  'projectTimeline': Icons.timeline_outlined,
  'rasci': Icons.admin_panel_settings_outlined,
  'securityTasks': Icons.shield_outlined,
  'certification': Icons.verified_outlined,
  'training': Icons.school_outlined,
  'report': Icons.insert_chart_outlined,
  'postIncidentReview': Icons.manage_history,
  'privacyIncident': Icons.privacy_tip_outlined,
  'dpia': Icons.policy_outlined,
  'riskRegister': Icons.warning_amber_outlined,
  'continuityTest': Icons.settings_backup_restore,
  'tabletopExercise': Icons.groups_outlined,
  'bobCrisis': Icons.crisis_alert,
  'releaseReadiness': Icons.fact_check_outlined,
  'steeringUpdate': Icons.gavel,
  'auditFollowup': Icons.rule,
  'vendorRisk': Icons.handshake_outlined,
  'architectureDecision': Icons.account_tree_outlined,
  'policyRollout': Icons.campaign_outlined,
  'handover': Icons.swap_horiz_outlined,
  'retrospective': Icons.replay,
  'research': Icons.travel_explore_outlined,
  'technical': Icons.code_outlined,
  'quiz': Icons.quiz_outlined,
  'jobInterview': Icons.record_voice_over_outlined,
  'performanceReview': Icons.rate_review_outlined,
  'salaryNegotiation': Icons.payments_outlined,
  'moreResponsibility': Icons.trending_up,
  'raiseWorkplaceIssue': Icons.flag_outlined,
  'resolveConflict': Icons.diversity_3,
  'giveReceiveFeedback': Icons.reviews_outlined,
  'deliverBadNews': Icons.sentiment_dissatisfied_outlined,
  'setBoundaries': Icons.front_hand_outlined,
  'strainedRelationship': Icons.heart_broken_outlined,
  'clientConversation': Icons.support_agent,
  'salesConversation': Icons.sell_outlined,
  'supplierNegotiation': Icons.inventory_2_outlined,
  'pitch': Icons.tips_and_updates_outlined,
  'meetingToGetBuyIn': Icons.how_to_vote_outlined,
  'pplFlightPrep': Icons.flight_takeoff,
  'sbarHandover': Icons.medical_information_outlined,
  'mistHandover': Icons.emergency_outlined,
  'mdtMeeting': Icons.groups_2_outlined,
  'surgicalChecklist': Icons.health_and_safety_outlined,
  'nursingHandover': Icons.local_hospital_outlined,
  'onboardingPlan': Icons.waving_hand_outlined,
  'firstDayInduction': Icons.meeting_room_outlined,
  'buddyMentor': Icons.diversity_1,
  'offboarding': Icons.logout,
  'imsafeCheck': Icons.monitor_heart_outlined,
  'crewBriefing': Icons.connecting_airports_outlined,
  'occurrenceReport': Icons.assignment_late_outlined,
  'toolboxTalk': Icons.handyman_outlined,
  'eventSafety': Icons.festival_outlined,
  'evacuationDrill': Icons.directions_run,
  'permitToWork': Icons.assignment_turned_in_outlined,
  'methaneReport': Icons.sos,
  'gripEscalation': Icons.signal_cellular_alt,
  'bridgePassageBriefing': Icons.directions_boat_outlined,
  'businessCase': Icons.request_quote_outlined,
  'budgetPresentation': Icons.account_balance_wallet_outlined,
  'decisionMeeting': Icons.ballot_outlined,
  'sprintReview': Icons.autorenew,
  'threatModeling': Icons.gpp_maybe_outlined,
  'conversationPrep': Icons.chat_outlined,
  'crucialConversation': Icons.psychology_outlined,
  'familyCareConversation': Icons.family_restroom,
  'socialCaseReview': Icons.volunteer_activism_outlined,
  'worksCouncilRequest': Icons.balance,
  'fireServiceBriefing': Icons.local_fire_department_outlined,
  'afterActionReview': Icons.history_edu_outlined,
  'councilProposal': Icons.account_balance_outlined,
  'residentsMeeting': Icons.holiday_village_outlined,
  'parentsEvening': Icons.escalator_warning,
  'internshipPresentation': Icons.co_present_outlined,
  'membersAssembly': Icons.groups_3_outlined,
  'flightDebrief': Icons.flight_land,
  'passengerBriefing': Icons.airline_seat_recline_normal,
  'miauwReport': Icons.bug_report_outlined,
  'procesverbeteringDmaic': Icons.trending_up,
  'procesverbeteringSipoc': Icons.account_tree_outlined,
};

class _NewDeckDialogState extends ConsumerState<NewDeckDialog> {
  final _ctrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _profileName;
  DeckTemplate _template = deckTemplates.first;

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Zegt in welke taal de voorbeelddia's staan, als dat niet de taal is die de
  /// gebruiker leest.
  ///
  /// De titel en de omschrijving van een sjabloon lopen door `l10n.d()` en
  /// verschijnen dus in de eigen taal; de dia-inhoud niet. Die is
  /// **deck-inhoud**: een document per taal in `assets/templates/` (nl en en,
  /// #622), geladen door `TemplateContentService`. Vertalen via l10n zou de
  /// inhoud van een document laten afhangen van de menutaal waarin het
  /// toevallig is aangemaakt — twee mensen die hetzelfde sjabloon kiezen,
  /// kregen dan onvergelijkbare bestanden.
  ///
  /// Nederlands en Engels krijgen dus hun eigen inhoud; elke andere taal krijgt
  /// de Engelse variant, en dát is wat deze regel meldt. Voor wie hem niet
  /// nodig heeft is hij ruis, en een melding die niets toevoegt leert mensen
  /// meldingen overslaan — daarom zwijgt hij in het Nederlands en het Engels.
  Widget _templateLanguageNotice(BuildContext context, AppLocalizations l10n) {
    if (TemplateContentService.languagesWithContent.contains(
      l10n.languageCode,
    )) {
      return const SizedBox.shrink();
    }
    return Padding(
      // Sleutel zodat een test op de aanwezigheid kan toetsen zonder de tekst in
      // 32 talen te hoeven kennen.
      key: const ValueKey('templateLanguageNotice'),
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.d(
          "De voorbeelddia's van een sjabloon staan in het Engels. Naam en omschrijving volgen je eigen taal; de inhoud pas je na het aanmaken aan.",
        ),
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// The catalogue narrowed by the search box and sorted for display. Matches
  /// the localised title, description and module badge, plus the Dutch source
  /// strings, so a term in either language finds the template.
  List<DeckTemplate> _filtered(AppLocalizations l10n) {
    final query = _searchCtrl.text.trim().toLowerCase();
    // Module-only templates stay hidden until their module is revealed.
    final secRevealed = ref.watch(infoSafetyRevealProvider);
    final impRevealed = ref.watch(procesverbeteringRevealProvider);
    bool matches(DeckTemplate t) {
      final terms = <String>[
        l10n.d(t.title),
        l10n.d(t.description),
        t.title,
        t.description,
        if (t.requiresInfoSafety) ...[
          l10n.d('Informatieveiligheid'),
          'Informatieveiligheid',
        ],
        if (t.requiresProcesverbetering) ...[
          l10n.d('Procesverbetering'),
          'Procesverbetering',
        ],
      ];
      return terms.any((text) => text.toLowerCase().contains(query));
    }

    final catalogue = deckTemplates.where(
      (template) => deckTemplateVisible(
        template,
        infoSafetyRevealed: secRevealed,
        procesverbeteringRevealed: impRevealed,
      ),
    );
    final base = query.isEmpty ? catalogue : catalogue.where(matches);
    return sortTemplatesForDisplay(base, (t) => l10n.d(t.title));
  }

  void _onSearchChanged() {
    setState(() {
      final l10n = context.l10n;
      final visible = _filtered(l10n);
      // Houd de selectie zichtbaar: verdwijnt die uit het filter, verspring
      // dan naar het eerste resultaat. Bij nul resultaten blijft de oude
      // selectie bewaard voor wanneer het filter wordt gewist, maar aanmaken
      // wordt uitgeschakeld en `_submit` controleert dit nogmaals.
      if (visible.isNotEmpty && !visible.contains(_template)) {
        _template = visible.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final profiles = settings.themeProfiles;
    final selected = _profileName ?? settings.selectedThemeProfileName;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Nieuwe presentatie')),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.d('Titel'),
                      hintText: l10n.d('Bijv. Kwartaalupdate Q4'),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.d('Vul een titel in')
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: profiles.any((p) => p.name == selected)
                        ? selected
                        : profiles.first.name,
                    decoration: InputDecoration(
                      labelText: l10n.t('styleProfile'),
                    ),
                    items: [
                      for (final profile in profiles)
                        DropdownMenuItem(
                          value: profile.name,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ThemeProfileSwatch(profile: profile),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  profile.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (name) => setState(() => _profileName = name),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.d(
                      'Bepaalt kleuren, lettertype en logo. Later aan te passen via de presentatie-eigenschappen of instellingen.',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.d('Sjabloon'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  _templateLanguageNotice(context, l10n),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('templateSearchField'),
                    controller: _searchCtrl,
                    onChanged: (_) => _onSearchChanged(),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: l10n.d('Zoek een sjabloon'),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.slate300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    // Reading-order tabbing through the tiles keeps the picker
                    // fully keyboard-operable (mirrors the slide-type dialog).
                    child: FocusTraversalGroup(
                      policy: ReadingOrderTraversalPolicy(),
                      child: _templateList(l10n),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: _filtered(l10n).contains(_template) ? _submit : null,
            child: Text(l10n.d('Aanmaken')),
          ),
        ],
      ),
    );
  }

  Widget _templateList(AppLocalizations l10n) {
    final visible = _filtered(l10n);
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            l10n.d('Geen sjablonen gevonden'),
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: visible.length,
      itemBuilder: (context, i) => _templateTile(visible[i]),
    );
  }

  Widget _templateTile(DeckTemplate template) {
    final l10n = context.l10n;
    final selected = template.id == _template.id;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => setState(() => _template = template),
        focusColor: AppTheme.accent.withValues(alpha: 0.14),
        hoverColor: AppTheme.accent.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: selected ? AppTheme.accent.withValues(alpha: 0.10) : null,
          child: Row(
            children: [
              Icon(
                templatePickerIcons[template.icon] ??
                    Icons.crop_landscape_outlined,
                size: 22,
                color: AppTheme.accentFg,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            l10n.d(template.title),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (template.requiresInfoSafety)
                          _moduleBadge(
                            template,
                            l10n.d('Informatieveiligheid'),
                          ),
                        if (template.requiresProcesverbetering)
                          _moduleBadge(template, l10n.d('Procesverbetering')),
                      ],
                    ),
                    Text(
                      l10n.d(template.description),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppTheme.accentFg : AppTheme.slate300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moduleBadge(DeckTemplate template, String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('templateModuleBadge-${template.id}'),
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        border: Border.all(color: colors.secondary, width: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onSecondaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _submit() {
    final l10n = context.l10n;
    if (!_filtered(l10n).contains(_template)) return;
    if (_formKey.currentState!.validate()) {
      final settings = ref.read(settingsProvider);
      Navigator.pop(
        context,
        NewDeckChoice(
          title: _ctrl.text.trim(),
          profileName: _profileName ?? settings.selectedThemeProfileName,
          template: _template,
        ),
      );
    }
  }
}

/// Mini-voorproef van een stijlprofiel: titelbalk-, accent- en
/// achtergrondkleur als drie blokjes. Genoeg om profielen op gevoel uit
/// elkaar te houden zonder de dialoog te verzwaren.
class ThemeProfileSwatch extends StatelessWidget {
  final ThemeProfile profile;

  const ThemeProfileSwatch({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final hex in [
          profile.titleBackgroundColor,
          profile.accentColor,
          profile.slideBackgroundColor,
        ])
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: AppTheme.parseHexColor(hex),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.black26, width: 0.5),
            ),
          ),
      ],
    );
  }
}
