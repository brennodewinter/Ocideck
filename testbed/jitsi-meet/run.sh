#!/usr/bin/env bash
# Bediening van de gepinde Jitsi-teststack (#2540). Zie README.md.
#
#   ./run.sh init     .env aanmaken + servicewachtwoorden genereren (eenmalig)
#   ./run.sh up       stack starten en wachten tot hij beantwoordt
#   ./run.sh users    testaccounts host/guest registreren in Prosody
#   ./run.sh status   containerstatus + gezondheidstonen
#   ./run.sh verify   rookproef: web-UI, WebSocket, jicofo/jvb-verbinding
#   ./run.sh down     stack stoppen (config en accounts blijven staan)
#   ./run.sh reset    alles weg: containers, config, accounts — daarna init+up
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE="docker compose"
XMPP_DOMAIN="meet.jitsi"
HOST_USER="host"
GUEST_USER="guest"

http_port() { grep -E '^HTTP_PORT=' .env | cut -d= -f2; }
ws_port() { grep -E '^PROSODY_WS_PORT=' .env | cut -d= -f2; }

require_env() {
  if [[ ! -f .env ]]; then
    echo "Geen .env — draai eerst: ./run.sh init" >&2
    exit 1
  fi
}

wait_url() {  # wait_url <url> <seconden> — wacht tot curl iets terugkrijgt
  local url="$1" budget="$2" waited=0
  until curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if (( waited >= budget )); then
      echo "Timeout na ${budget}s: $url reageert niet" >&2
      $COMPOSE ps >&2 || true
      return 1
    fi
  done
}

case "${1:-}" in
  init)
    if [[ ! -f .env ]]; then
      cp .env.example .env
    fi
    # Per-installatie wegwerpwachtwoorden voor de serviceaccounts — staan
    # nooit in git (.env is gitignored + in de secret-scan-allowlists).
    for var in JICOFO_AUTH_PASSWORD JICOFO_COMPONENT_SECRET JVB_AUTH_PASSWORD \
               TEST_HOST_PASSWORD TEST_GUEST_PASSWORD; do
      if ! grep -q "^${var}=." .env; then
        secret=$(openssl rand -hex 16)
        if grep -q "^${var}=" .env; then
          sed -i '' "s/^${var}=.*/${var}=${secret}/" .env
        else
          echo "${var}=${secret}" >> .env
        fi
      fi
    done
    echo "init: .env staat klaar (wachtwoorden gegenereerd)."
    ;;
  up)
    require_env
    $COMPOSE up -d
    echo "Wachten op web-UI en Prosody-WebSocket…"
    wait_url "http://localhost:$(http_port)/" 90
    wait_url "http://localhost:$(ws_port)/" 60 || \
      echo "Prosody-WS nog niet bereikbaar; web werkt wel (controleer ./run.sh status)" >&2
    echo "Stack draait: web-UI op $(grep -E '^PUBLIC_URL=' .env | cut -d= -f2-)"
    echo "Accounts aanmaken/indien nodig: ./run.sh users"
    ;;
  users)
    require_env
    host_pw=$(grep -E '^TEST_HOST_PASSWORD=' .env | cut -d= -f2)
    guest_pw=$(grep -E '^TEST_GUEST_PASSWORD=' .env | cut -d= -f2)
    for pair in "${HOST_USER} ${host_pw}" "${GUEST_USER} ${guest_pw}"; do
      set -- $pair
      # Twee keer proberen is goedkoper dan een --force-variant onderhouden:
      # prosodyctl faalt netjes als de account al bestaat. De image rendert de
      # config naar /run/prosody/config; zonder PROSODY_CONFIG zoekt prosodyctl
      # in /etc/prosody en faalt stilletjes.
      $COMPOSE exec -T \
        -e PROSODY_CONFIG=/run/prosody/config/prosody.cfg.lua \
        prosody prosodyctl register "$1" "$XMPP_DOMAIN" "$2" \
        >/dev/null 2>&1 || echo "account $1 bestond al of registratie faalde"
    done
    echo "Accounts: ${HOST_USER}@${XMPP_DOMAIN} en ${GUEST_USER}@${XMPP_DOMAIN}"
    echo "Wachtwoorden staan in .env (TEST_HOST_PASSWORD / TEST_GUEST_PASSWORD)."
    ;;
  status)
    require_env
    $COMPOSE ps
    ;;
  verify)
    require_env
    port=$(http_port)
    echo "— web-UI"
    curl -fsS -o /dev/null -w "  GET / -> %{http_code}\n" "http://localhost:${port}/"
    curl -fsS "http://localhost:${port}/config.js" \
      | grep -o "websocket *= *[^;]*" | head -1 | sed 's/^/  config./' || true
    echo "— prosody WebSocket (direct, poort $(ws_port))"
    curl -s -o /dev/null -w "  GET /xmpp-websocket -> %{http_code}\n" \
      "http://localhost:$(ws_port)/xmpp-websocket" || true
    echo "— jicofo: aan XMPP verbonden?"
    $COMPOSE logs jicofo 2>&1 | grep -c "Connected\|registered" | \
      sed 's/^/  matches: /'
    echo "— jvb: in brewery-MUC aangemeld?"
    $COMPOSE logs jvb 2>&1 | grep -c "joined\|Connected" | \
      sed 's/^/  matches: /'
    ;;
  down)
    $COMPOSE down
    ;;
  reset)
    $COMPOSE down --remove-orphans 2>/dev/null || true
    rm -rf ./config ./evidence
    echo "reset: containers en gegenereerde config verwijderd."
    ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
