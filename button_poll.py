#!/usr/bin/env python3
"""Fragt per WLAN laufend den Hardware-Status (0xC2) ab und zeigt jede Änderung.

Zum Finden des Bits für die Scan-Taste: laufen lassen, Taste drücken,
geänderte Bytes ablesen.
"""
import os, socket, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vens"))
import scansnap as ss  # noqa: E402

ip = sys.argv[1] if len(sys.argv) > 1 else "192.168.2.149"
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 90
my_ip = ss.local_ip_toward(ip)
mac, _ = ss.wifi_mac_toward(ip)
key = ss.load_key()
C2 = ss.QUERY_CMDS["C2"]


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def session():
    if not ss.grab_session(ip, mac, my_ip, key):
        raise RuntimeError("keine Sitzung")
    c = socket.socket(); c.settimeout(6)
    c.connect((ip, ss.SCAN_PORT)); c.recv(16)
    for lbl in ("06+12", "E7"):
        c.send(ss.vens_pkt(mac, ss.QUERY_CMDS[lbl])); ss.recv_vens(c)
    return c


c = session()
last, n = None, 0
end = time.time() + duration
log("frage Status ab ... JETZT Scan-Taste drücken (gern mehrmals, mit und ohne Papier)")
while time.time() < end:
    try:
        c.send(ss.vens_pkt(mac, C2))
        r = ss.recv_vens(c)
    except OSError as e:
        log(f"Verbindung weg ({e}), neu anmelden"); c.close(); c = session(); continue
    if r is None:
        log("keine Antwort, neu anmelden"); c.close(); c = session(); continue
    n += 1
    if last is None:
        log(f"Start ({len(r)} B): {r[32:].hex()}")
    elif r != last:
        diff = [f"[{i}] {last[i]:02x}->{r[i]:02x}" for i in range(min(len(r), len(last))) if r[i] != last[i]]
        log("Änderung: " + ", ".join(diff))
    last = r
    time.sleep(0.25)
try:
    c.send(ss.vens_pkt(mac, "00000006000000000000000000000000d6000000000000000000000000000000"))
    ss.recv_vens(c, 2); c.close()
except OSError:
    pass
ss.d6_release(ip, mac)
log(f"fertig, {n} Abfragen")
