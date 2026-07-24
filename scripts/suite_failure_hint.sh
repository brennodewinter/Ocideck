#!/usr/bin/env bash
#
# Wordt aangeroepen wanneer een `flutter test` uit de Makefile omvalt, en zegt
# één ding dat de Flutter-uitvoer zelf niet zegt: dat de test die genoemd wordt
# onschuldig kan zijn.
#
# #798: `make check` viel twee keer op één dag om met
#
#     Failed to load "test/<wisselend>_test.dart":
#     type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>' in type cast
#
# op een test die los gedraaid groen was. Beide keren was het weg na het
# opruimen van build/test_cache, zonder verder iets te wijzigen. Wie dat niet
# weet gaat een gezonde test debuggen — dat is de kostenpost, niet de storing
# zelf.
#
# **Waarom dit erover heen praat en niet erdoorheen filtert.** De uitvoer van
# `flutter test` stroomt rechtstreeks naar het scherm. Er wordt niets
# afgevangen, niets weggelaten en niets herschreven: een echte laadfout
# wegpoetsen is precies wat een poort niet mag doen, en een pipe zou `flutter
# test` bovendien zijn voortgangsregel afnemen en er duizenden regels van maken.
# Deze tekst komt eróver.
#
# **Waarom het niet altijd praat.** Het argument is het pad van de kernelcache
# zoals de Makefile die zag *voordat* de suite begon (CARRIED_TEST_CACHE). Leeg
# betekent: die cache is pas door deze draai ontstaan, en dan slaat de
# aanwijzing nergens op — dan zwijgt dit. Zelf achteraf gaan kijken kan niet:
# `flutter test` schrijft de cache tijdens de draai, dus dan is het antwoord
# altijd ja en staat deze tekst onder élke rode test. Een aanwijzing die overal
# onder staat, leest niemand meer.
set -u

dill="${1:-}"
[ -n "$dill" ] && [ -f "$dill" ] || exit 0

size="$(du -h "$dill" 2>/dev/null | cut -f1 | tr -d ' ')"
stamp="$(date -r "$dill" '+%Y-%m-%d %H:%M' 2>/dev/null)"

cat >&2 <<EOF

── De suite viel om. Eén ding dat de melding hierboven niet zelf zegt ──────────
   Er lag al een kernelcache van een eerdere draai: build/test_cache
   (${size:-?}, ${stamp:-datum onbekend}).

   Staat er 'Failed to load "…_test.dart"' met een type-cast erachter, en is die
   test los gedraaid groen? Dan is die cache de eerste verdachte en niet je
   wijziging:

       make clean-test-cache

   Bij een gewone rode test slaat dit nergens op — negeer het dan.
   Wat hiervan wél en niet bewezen is, staat in docs/CHECKS.md.
───────────────────────────────────────────────────────────────────────────────
EOF
