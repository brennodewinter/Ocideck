import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

void main() {
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  test('supports Frisian and Papiamento language choices', () {
    expect(AppLocalizations.languageNames['fy'], 'Frysk');
    expect(AppLocalizations.languageNames['pap'], 'Papiamento');
    expect(AppLocalizations.supportedLocales, contains(const Locale('fy')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('pap')));
  });

  test('uses app translations while Material falls back safely', () {
    AppLocalizations.setActiveLanguageCode('fy');
    expect(const AppLocalizations(Locale('en')).t('settings'), 'Ynstellingen');
    expect(
      const AppLocalizations(Locale('en')).d('Toetsenlegenda'),
      'Toetsleginda',
    );
    expect(AppLocalizations.materialLocaleFor('fy'), const Locale('en'));

    AppLocalizations.setActiveLanguageCode('pap');
    expect(
      const AppLocalizations(Locale('en')).t('settings'),
      'Preferensianan',
    );
    expect(
      const AppLocalizations(Locale('en')).d('Toetsenlegenda'),
      'Legenda di tekla',
    );
    expect(AppLocalizations.materialLocaleFor('pap'), const Locale('en'));
  });
}
