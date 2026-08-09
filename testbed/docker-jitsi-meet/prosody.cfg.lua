pidfile = "/var/run/prosody/prosody.pid"
log = { debug = "*console" }
data_path = "/var/lib/prosody"
modules_enabled = {
  "roster";
  "saslauth";
  "tls";
  "dialback";
  "disco";
  "posix";
}
allow_registration = false
c2s_require_encryption = false
s2s_require_encryption = false
authentication = "anonymous"
consider_websocket_secure = true
cross_domain_websocket = { "*" }

ssl = {
  key = "/var/lib/prosody/localhost.key";
  certificate = "/var/lib/prosody/localhost.crt";
}

VirtualHost "meet.jitsi"
  authentication = "anonymous"
  modules_enabled = { "websocket" }

Component "conference.meet.jitsi" "muc"
  restrict_room_creation = false
  muc_room_locking = false
  modules_enabled = {}
