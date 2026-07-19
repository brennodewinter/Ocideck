import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/storage_connection.dart';
import '../../theme/app_theme.dart';

/// Kiest met welke bestandsverbinding een actie werkt.
///
/// De regel die deze dialoog bruikbaar houdt staat in [show]: bij precies één
/// bruikbare verbinding verschijnt er niets. Wie één Nextcloud heeft — de
/// meeste mensen — merkt van de hele keuze niets en houdt de flow van vroeger.
/// Pas wie er twee heeft, krijgt de vraag, en dan is hij ook echt nodig: naar
/// de verkeerde klant schrijven geeft geen foutmelding.
class StorageConnectionPicker extends StatelessWidget {
  const StorageConnectionPicker({super.key, required this.connections});

  final List<StorageConnection> connections;

  /// Kies een verbinding uit [connections].
  ///
  /// Levert `null` bij een lege lijst (de aanroeper meldt dan dat er niets is
  /// ingesteld) en bij annuleren. Bij één verbinding wordt die meteen
  /// teruggegeven zonder dialoog.
  static Future<T?> show<T extends StorageConnection>(
    BuildContext context,
    List<T> connections,
  ) async {
    if (connections.isEmpty) return null;
    if (connections.length == 1) return connections.single;
    return showDialog<T>(
      context: context,
      builder: (_) => StorageConnectionPicker(connections: connections),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Welke verbinding?')),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final connection in connections)
              ListTile(
                leading: Icon(_iconOf(connection)),
                title: Text(
                  connection.name.trim().isEmpty
                      ? connection.fallbackLabel
                      : connection.name,
                ),
                subtitle: Text(
                  connection.fallbackLabel,
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                ),
                onTap: () => Navigator.of(context).pop(connection),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
      ],
    );
  }

  /// Bewust hier en niet op het model: welk pictogram bij een soort hoort is
  /// een schermkeuze. De opslagsectie kent dezelfde afbeelding.
  IconData _iconOf(StorageConnection connection) => switch (connection) {
    LocalConnection() => Icons.folder_outlined,
    WebdavConnection() => Icons.cloud_outlined,
    S3Connection() => Icons.inventory_2_outlined,
    GitConnection() => Icons.account_tree_outlined,
  };
}
