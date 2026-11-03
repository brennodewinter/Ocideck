# Runtimebudget releaseherstel — meting 3 november 2026

## Bewezen configuratie

Pawprint draait Forgejo 16.0.5 en runner-image `data.forgejo.org/forgejo/runner:13`. De effectieve daemonstart noemt `/data/config.yml`. Algemene runner: capacity 4, timeout 3h; seriële runner: capacity 1, timeout 3h. In de onderzochte `[actions]`-sectie en geselecteerde environment overrides staat geen ENDLESS_TASK_TIMEOUT. Forgejo documenteert daarvoor standaard 3h. De toepassing van deze standaard volgt uit de configuratie; een daadwerkelijke timeout op exact 180 minuten is niet met een verspillende proef uitgelokt.

De onderzochte kanaalworkflow vraagt 960 minuten; Mac/consumers vragen 240 minuten. Een ruimere workflowwaarde heft de kortere runnergrens niet op. Effectief jobbudget is maximaal 180 minuten op deze runners; daarnaast bestaan instancebewaking en eventuele staplimieten. Dit is geen bewijs dat een historische Windows lost-communication fout door deze grens ontstond.

Bronnen: https://forgejo.org/docs/latest/user/actions/reference/#jobsjob_idtimeout-minutes ; https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/ (actions ENDLESS_TASK_TIMEOUT); https://forgejo.org/docs/latest/admin/actions/configuration/ .

## Werkelijk gemeten middelen

Server: 8 CPU, circa31GB RAM. Voorbereidingsmetingen wisselden tussen 0–78% CPU idle; vrije capaciteit is geen constante. Native fullgatecontainers kregen 2 CPU,8GB,TEST_JOBS2; eerste volledige95run duurde 11:19:28–14:00:51UTC (161m24) en eindigde EXIT2 bij ShellCheck0.9.0. Hoofd15083/pakket1238/Python128proeven slaagden. De zeven resterende native doelen slaagden later op dezelfde bron met officieel geverifieerde ShellCheck0.11.0 in een aparte container16:50:19–16:59:05 (8m46 incl1m39voorbereiding). Dit is geen oorspronkelijke makecheckfull EXIT0.

Een oorspronkelijke focusedrun compileerde OpenCV ongeveer37min koud. Hergebruik van passende pub/.dart_tool/native_assets cache voorkwam die herhaling. Een snapshot van3,24GB writablelayer kostte ruim15min zonder resultaat en werd alleen aan de clientkant afgebroken. Daemonafwikkeling was onbekend. Gerichte proeven zijn daardoor niet uitgevoerd. Nieuwe remainderbron+cachevoorbereiding zonder snapshot kostte1m39.

Preparedconsumerbuilds zijn expliciet2CPU/4GB via classicbuilder; werkelijke intermediateHostConfig100000period/200000quota/4294967296memory bevestigd. Een clientcontainerlimiet alleen begrenst daemonbuildstappen niet.

## Nog onbekend

- Geen causaal bewijs dat IO de tiktellertest liet falen. Identieke test/productcode faalde in59 en slaagde in95; de geplande gecontroleerde125msflushproef is niet uitgevoerd.
- Geen procesprofiel of netwerk/IOcorrelatie waarmee crawlerbelasting als oorzaak is bewezen.
- Windows lost-communication root cause blijft onbekend; geen blind retry of opgelostclaim.
- Geen bewezen Macrunnerbudget uit Macconfig; Pawprint3h mag niet zonder meting op Mac worden geprojecteerd.

## Kleinste begrensde aanpak

1. Vóór duur werk runner-, instance-, job- en stapbudget vergelijken en onuitvoerbare combinaties melden; niet pas na drie uur.
2. Onveranderlijke source en preparedcontainerdigests gebruiken; packageinstallatie uit iedere release halen. Eén OS/kanaal per publicatie, expliciete receipts en hervatten van dezelfde bytes.
3. Producttestpoort, bouwen, consumerproeven en publiceren als afzonderlijke jobs onder hun effectieve budget meten. Een guard vereist terminal kwaliteitsbewijs van exact dezelfde bron.
4. Capaciteit begrenzen per daadwerkelijke buildcontainer, niet alleen de Dockerclient. Geen gelijktijdige koude nativebuilds bij hoge load.
5. Alleen wanneer een gemeten noodzakelijke fase ondanks voorbereiding langer dan het budget is: dedicatedrunner en instancebudget in één onderhoudsstap afstemmen, na lopende jobs, met terugrol en readback. Geen algemene blinde timeoutverhoging.
6. Serverlokale30swatcher legt machinewaarneming apart van menselijke detectie vast; Dockerstate en volledige foutenlog zijn gezaghebbend. Codexwachttijd is geen livenessbewijs.

## Uitvoerbaar budgetvoorstel — nog geen configuratiewijziging

Een generieke afwijzing van960minlostdeWindowswachtroute niet op. Splits daadwerkelijke rekentijd en wachten op externe diensten:

| Fase | Voorgesteld jobbudget | Hervatbare toestand |
| --- | --- | --- |
| Windowsdispatch/identiteit | 10min | operation-ID, volledigebronSHA, workflow/ref en ontvangen upstreamrun-ID duurzaam bewaren vóór vervolgstap |
| Windowspoll | maximaal20min per aanroep | dezelfde operation/run-ID alleen volgen; bij nog lopende externe bouw statuspending bewaren; volgende expliciete hervatting dispatcht niets nieuws |
| Windowsartifact ophalen/controleren | 30min | terminalupstreamsucces, bronidentiteit en archivehash verifiëren; dezelfde bytes opnieuw downloadbaar |
| Macbouwen/tekenen | maximaal150min bij bewezenpassendeMacrunner | app/archivehashes bewaren; niet opnieuw tekenen bij hervatten |
| Appleinzending | 15min | submission-ID, bronSHA, bundle/app/ziphashes duurzaam vastleggen |
| Applepoll | maximaal20min per aanroep | bestaande submission volgen via `--resume-notary`; geen rebuild/sign/nieuwesubmission |
| Staple/package/controle | 30min | dezelfde geaccepteerde inzending en appbytes, daarnaartefactreceipt |
| Voorbereide Linuxconsumer | 45min | gepindeconsumerdigest en exacte kandidaatarchivehash; geen apt/runtimeinstallatie per release |

Deze waarden zijn begrensde beginbudgetten voor aanroepen, geen snelheidsbelofte. De bestaande Windowsopslag en notarysubmissionherstart vormen de basis; een tijdslimiet mag geen eigenaarschap of state verliezen. Een 'pending' externe taak is geen afgeronde publicatie. Publicatie vereist later terminalsucces plus echte artefacten. De externe Windowsbuild mag zijn eigen240minbudget behouden: de Forgejopolljob hoeft niet240min een runner vast te houden. Als de controller nog alleen een lange blockingfetch ondersteunt is daarvoor een kleine dispatch/status/fetchscheiding nodig; alleen YAMLtimeoutaanpassen is onvoldoende.

Macrunnerconfig moet afzonderlijk worden gelezen voordat150min als passend wordt aangenomen. De lokale Macbron/job240min is geen bewijs van zijn werkelijke runner/serverlimiet. Een eventueel noodzakelijke grotere rekenfase krijgt een afzonderlijke dedicatedrunner met afgestemde servergrens na review; niet de gedeeldecapacity4runner stilzwijgend verruimen.

De beoogde totale releasehandeling volgt één gekozen OS/kanaal, met dezelfde onveranderlijkebron en candidatebytes. Een andereOSjob die nogpendingis verhindert geen afgerond kanaal, maar het publieke statusoverzicht noemt perOS eerlijk beschikbaar/pending/gefaald.
