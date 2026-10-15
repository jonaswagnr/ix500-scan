#!/usr/bin/env python3
"""Horcht, was der iX500 per WLAN schickt, wenn man die Scan-Taste drückt.

Meldet sich wie ScanSnap Home beim Scanner an (Registrierung + Handshake mit
Rückkanal-Port 55265) und lauscht dann auf UDP 55264/55265/53220 und TCP 55265.
"""
import os, select, socket, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vens"))
import scansnap as ss  # noqa: E402

ip = sys.argv[1] if len(sys.argv) > 1 else "192.168.2.149"
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 90
my_ip = ss.local_ip_toward(ip)
mac, _ = ss.wifi_mac_toward(ip)
key = ss.load_key()

socks = {}
for port in (55264, 55265, 53220):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    s.bind(("", port))
    socks[s] = f"udp/{port}"
t = socket.socket()
t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
t.bind(("", 55265)); t.listen(5)
socks[t] = "tcp/55265"

def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)

def announce():
    ss.register_rounds(ip, mac, my_ip)
    err, _ = ss.handshake_code(ip, mac, my_ip, key)
    ss.handshake_aux(ip, mac, 2); ss.handshake_aux(ip, mac, 3)
    return err

err = announce()
log(f"angemeldet (handshake err={err}), lausche {duration:.0f}s ... JETZT Scan-Taste drücken")
end, next_announce = time.time() + duration, time.time() + 20
tcp_conns = {}
while time.time() < end:
    r, _, _ = select.select(list(socks) + list(tcp_conns), [], [], 1)
    for s in r:
        if s is t:
            c, addr = t.accept()
            tcp_conns[c] = addr
            log(f"TCP-Verbindung von {addr} auf 55265")
            try: c.send(ss.VENS_HELLO)
            except OSError: pass
        elif s in tcp_conns:
            data = s.recv(4096)
            if not data:
                log(f"TCP {tcp_conns.pop(s)} geschlossen"); s.close(); continue
            log(f"TCP-Daten von {tcp_conns[s]} ({len(data)} B): {data.hex()}")
        else:
            data, addr = s.recvfrom(4096)
            if socks[s] == "udp/53220" and len(data) == 48:
                continue  # normale Discovery-Broadcasts ausblenden
            log(f"{socks[s]} von {addr} ({len(data)} B): {data.hex()}")
    if time.time() > next_announce:
        announce(); next_announce = time.time() + 20
ss.d6_release(ip, mac)
log("fertig")
