# OciDeck fetch-hulppunt

De webversie van OciDeck kan presentaties van elke `http(s)`-URL openen. De
browser staat cross-origin lezen echter alleen toe als de bronserver
CORS-headers stuurt — en de meeste doen dat niet. Dit hulppunt lost dat op:
de webapp probeert eerst direct te fetchen en valt stil terug op het
same-origin pad `/fetch-proxy?url=<encoded>`, waarna deze dienst het bestand
server-zijdig ophaalt en de bytes doorgeeft. Alle inhoudelijke validatie
(magic bytes, zip-bom-verdediging, veiligheidsscan, marp-controle) blijft in
de app zelf gebeuren; het hulppunt geeft alleen begrensde ruwe bytes door.

## Beveiliging

Een server-side fetcher is per definitie een SSRF-doelwit. De regels spiegelen
`NetGuard` (lib/utils/net_guard.dart) van de app:

- alleen `http`/`https`;
- de doelhost wordt éérst geresolved en **elk** adres moet publiek
  routeerbaar zijn — loopback, RFC1918, link-local (169.254/16, dus ook
  cloud-metadata), CGNAT 100.64/10, ULA fc00::/7, multicast, unspecified én
  in IPv6 ge-embedde IPv4 (mapped/compatible/NAT64) worden geweigerd;
- de verbinding wordt **gepind** op het gevalideerde adres (DNS-rebind kan
  de socket niet meer verleggen); TLS valideert via SNI tegen de échte
  hostnaam;
- redirects worden niet gevolgd (een 3xx kan naar binnen wijzen);
- de respons is hard begrensd (standaard 512 MiB) en wordt gestreamd;
- optioneel een Origin/Referer-allowlist tegen gebruik door derden.

## Installatie (Ubuntu + Apache)

1. Bestand plaatsen en een eigen gebruiker geven:

   ```sh
   sudo install -o www-data -g www-data -m 0755 \
     ocideck_fetch_proxy.py /usr/local/bin/ocideck_fetch_proxy.py
   ```

2. systemd-unit `/etc/systemd/system/ocideck-fetch-proxy.service`:

   ```ini
   [Unit]
   Description=OciDeck fetch-hulppunt (SSRF-bewaakte URL-fetcher voor de webversie)
   After=network-online.target

   [Service]
   ExecStart=/usr/bin/python3 /usr/local/bin/ocideck_fetch_proxy.py
   Environment=OCIDECK_PROXY_ALLOWED_ORIGINS=https://ocideck.librekat.nl
   User=www-data
   Group=www-data
   NoNewPrivileges=yes
   ProtectSystem=strict
   ProtectHome=yes
   PrivateTmp=yes
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target
   ```

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now ocideck-fetch-proxy
   ```

3. Apache-vhost van de webversie (naast de bestaande configuratie):

   ```apache
   ProxyPass        "/fetch-proxy" "http://127.0.0.1:8123/"
   ProxyPassReverse "/fetch-proxy" "http://127.0.0.1:8123/"
   ```

   ```sh
   sudo a2enmod proxy proxy_http && sudo systemctl reload apache2
   ```

4. Controleren:

   ```sh
   # publieke bron zonder CORS → 200
   curl -s -o /dev/null -w '%{http_code}\n' \
     'https://ocideck.librekat.nl/fetch-proxy?url=https%3A%2F%2Fpawprint.vigilis.online%2FLibreKAT%2FOcideck%2Fraw%2Fbranch%2Fmain%2FREADME.md'
   # intern adres → 403
   curl -s 'https://ocideck.librekat.nl/fetch-proxy?url=http%3A%2F%2F192.168.1.1%2F'
   ```

## Instellingen (omgevingsvariabelen)

| Variabele | Standaard | Betekenis |
| --- | --- | --- |
| `OCIDECK_PROXY_BIND` | `127.0.0.1` | Bind-adres (achter de webserver laten) |
| `OCIDECK_PROXY_PORT` | `8123` | Poort |
| `OCIDECK_PROXY_MAX_BYTES` | `536870912` | Harde bytecap per opvraag |
| `OCIDECK_PROXY_ALLOWED_ORIGINS` | *(leeg = geen check)* | Komma-lijst; indien gezet moet `Origin` of `Referer` ermee beginnen |

Zonder gedeployd hulppunt blijft de webversie gewoon werken: direct fetchen
dekt same-origin en CORS-vriendelijke bronnen, en de foutmelding legt de
CORS-beperking uit.
