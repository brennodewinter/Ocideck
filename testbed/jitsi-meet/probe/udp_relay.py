#!/usr/bin/env python3
"""UDP<->TCP relay voor het testbed (#2535).

lima (colima) forwardt alleen TCP naar de macOS-host — de UDP-mediapoort
van de JVB is daarmee onbereikbaar voor élke client op de host (bewezen:
een UDP-echo op de guest antwoordt lokaal, nooit via de forward). Dit
relais draagt elke UDP-flow over een geframede TCP-verbinding door de
werkende TCP-forward, zodat clients onveranderd UDP naar
127.0.0.1:10000 sturen. Twee helften, één bestand:

    guest (container op meet.jitsi): TCP :11000 -> UDP jvb:10000
    host  (macOS, via run.sh):        UDP 127.0.0.1:10000 -> TCP 127.0.0.1:11000

Elke client-flow (UDP-bronadres) krijgt een eigen TCP-verbinding én een
eigen UDP-socket aan de guest-kant — de JVB leert ze als aparte
peer-reflexive adressen, precies zoals een NAT. De pakketten zelf
(STUN/DTLS/SRTP) gaan byte-voor-byte mee; het relais leest of schrijft
geen media-inhoud.
"""

import socket
import struct
import sys
import threading
import time

_FRAME = struct.Struct('!H')  # [u16be len][payload] — TCP heeft geen datagramgrenzen
_BUF = 65535
_IDLE_S = 120  # stille flow mag weg — relay is per-run testgereedschap
_MAX_FLOWS = 64


def _recv_exact(conn: socket.socket, n: int) -> bytes | None:
    buf = b''
    while len(buf) < n:
        try:
            chunk = conn.recv(n - len(buf))
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
    return buf


# ── guest: TCP-listener -> per-conn UDP-socket naar de JVB ──────────────────


def _guest_flow(conn: socket.socket) -> None:
    usock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    usock.settimeout(5)
    usock.connect(('jvb', 10000))  # compose-servicenaam op meet.jitsi
    stop = threading.Event()

    def tcp_to_udp() -> None:
        while not stop.is_set():
            hdr = _recv_exact(conn, 2)
            if hdr is None:
                break
            data = _recv_exact(conn, _FRAME.unpack(hdr)[0])
            if data is None:
                break
            try:
                usock.send(data)
            except OSError:
                break
        stop.set()

    threading.Thread(target=tcp_to_udp, daemon=True).start()
    try:
        while not stop.is_set():
            try:
                data = usock.recv(_BUF)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                conn.sendall(_FRAME.pack(len(data)) + data)
            except OSError:
                break
    finally:
        stop.set()
        conn.close()
        usock.close()


def guest(bind: str, port: int) -> None:
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind((bind, port))
    ls.listen(_MAX_FLOWS)
    print(f'[relay] guest tcp {bind}:{port} -> udp jvb:10000', flush=True)
    while True:
        conn, peer = ls.accept()
        print(f'[relay] flow open vanaf {peer}', flush=True)
        threading.Thread(target=_guest_flow, args=(conn,), daemon=True).start()


# ── host: UDP-listener -> per-source geframede TCP-conn ─────────────────────


class _Flow:
    """Eén client-bron (ip:port) -> één TCP-conn naar de guest-relay."""

    def __init__(
        self,
        usock: socket.socket,
        src: tuple[str, int],
        upstream: tuple[str, int],
    ) -> None:
        self._usock = usock
        self._src = src
        self._dead = False
        self.last = time.monotonic()
        self._tcp = socket.create_connection(upstream, timeout=5)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        while True:
            hdr = _recv_exact(self._tcp, 2)
            if hdr is None:
                break
            data = _recv_exact(self._tcp, _FRAME.unpack(hdr)[0])
            if data is None:
                break
            try:
                # Antwoord komt van 127.0.0.1:10000 — de candidate die de
                # client verwacht, dus de ICE-paar-check valideert.
                self._usock.sendto(data, self._src)
            except OSError:
                break
        self._dead = True
        self._tcp.close()

    def send(self, data: bytes) -> None:
        self.last = time.monotonic()
        self._tcp.sendall(_FRAME.pack(len(data)) + data)


def host(bind: str, port: int, upstream: tuple[str, int]) -> None:
    usock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    usock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    usock.bind((bind, port))
    print(
        f'[relay] host udp {bind}:{port} -> tcp {upstream[0]}:{upstream[1]}',
        flush=True,
    )
    flows: dict[tuple[str, int], _Flow] = {}
    while True:
        try:
            data, src = usock.recvfrom(_BUF)
        except OSError:
            break
        flow = flows.get(src)
        if flow is not None and flow._dead:
            del flows[src]
            flow = None
        if flow is None:
            if len(flows) >= _MAX_FLOWS:
                continue
            try:
                flow = _Flow(usock, src, upstream)
            except OSError as e:
                print(f'[relay] upstream faalde voor {src}: {e}', flush=True)
                continue
            flows[src] = flow
            print(f'[relay] flow open voor {src}', flush=True)
        try:
            flow.send(data)
        except OSError:
            del flows[src]
        # Zijdelings opruimen van stille flows.
        for s, f in list(flows.items()):
            if f._dead or time.monotonic() - f.last > _IDLE_S:
                flows.pop(s, None)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    if mode == 'guest':
        guest('0.0.0.0', 11000)
    elif mode == 'host':
        host('127.0.0.1', 10000, ('127.0.0.1', 11000))
    else:
        print('gebruik: udp_relay.py guest|host', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
