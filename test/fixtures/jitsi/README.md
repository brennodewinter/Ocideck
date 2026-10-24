# Jitsi wire-fixtures (#2534)

Letterlijk opgevangen Jingle-verkeer uit de gepinde testbed
(`testbed/jitsi-meet`, stable-11248), vastgelegd via CDP-WebSocket-events in
de probe met twee echte Chrome-clients. Niets is opgeschoond of gemodelleerd —
als de parser dit aankan, werkt hij op wat Jicofo werkelijk stuurt.

- `session-initiate.xml` — het `<jingle>`-element uit de `<iq set>` die
  `wire63040@muc.meet.jitsi/focus` aan de gast stuurde: audio/video/data
  contents, BUNDLE-group, ice-udp transport met de JVB-kandidaten, sha-256
  DTLS-fingerprint, sctpmap en de `json-message` met jvb-sources.
