#!/usr/bin/env python3
"""Hintergrunddienst für die ScanSnap-Lite-App.

Hält eine WLAN-Sitzung zum iX500, fragt 4x/s den Hardware-Status (0xC2) ab
und scannt, wenn die Scan-Taste gedrückt wird oder die App es verlangt.

Protokoll mit der App, je Zeile ein JSON-Objekt:
  stdout (Ereignisse): status, button, scan_started, page, processing, done, error, notice
  stdin  (Befehle):    {"cmd": "scan"} | {"cmd": "pause"} | {"cmd": "resume"} | {"cmd": "quit"}
Einstellungen liest der Dienst vor jedem Scan neu aus pipeline.SETTINGS_PATH.
"""
import json, os, queue, socket, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vens"))
sys.path.insert(0, HERE)
import scansnap as ss  # noqa: E402
import pipeline  # noqa: E402

POLL_INTERVAL = 0.25
SESSION_REFRESH = 30      # Scanner beendet Sitzungen nach ~40 s von sich aus
PAPER_BYTE, PAPER_EMPTY = 43, 0x80
BUTTON_BYTE, BUTTON_BIT = 44, 0x01
D6 = "00000006000000000000000000000000d6000000000000000000000000000000"

_out_lock = threading.Lock()


def emit(event, **kw):
    with _out_lock:
        sys.stdout.write(json.dumps({"event": event, **kw}) + "\n")
        sys.stdout.flush()


class Daemon:
    def __init__(self):
        self.cmds = queue.Queue()
        self.conn = None
        self.ip = self.mac = self.my_ip = None
        self.key = ss.load_key()
        self.paper = None
        self.state = None
        self.paused = False
        self.session_since = 0

    # ── Zustand ────────────────────────────────────────────────────────────
    def set_state(self, state, **kw):
        if state != self.state or kw:
            self.state = state
            emit("status", state=state, ip=self.ip, paper=self.paper, **kw)

    # ── Verbindung ─────────────────────────────────────────────────────────
    def resolve(self):
        ip = pipeline.load_settings()["scanner_ip"].strip()
        if not ip:
            self.set_state("searching")
            found = ss.find_scanners(listen=1.0)
            ip = next(iter(sorted(found)), None)
        if not ip:
            return False
        if ip != self.ip:
            self.ip = ip
            self.my_ip = ss.local_ip_toward(ip)
            self.mac, _ = ss.wifi_mac_toward(ip)
        return True

    def connect(self):
        if not self.key or not ss.load_hostid():
            self.set_state("nokey", message="Schlüssel/HostID fehlen in ~/.config/scansnap/")
            return False
        if not self.resolve():
            self.set_state("offline", message="Kein Scanner im WLAN gefunden")
            return False
        if not ss.grab_session(self.ip, self.mac, self.my_ip, self.key, tries=3):
            self.set_state("offline", message="Scanner belegt oder nicht erreichbar")
            return False
        c = socket.socket(); c.settimeout(6)
        try:
            c.connect((self.ip, ss.SCAN_PORT)); c.recv(16)
            for lbl in ("06+12", "E7"):
                c.send(ss.vens_pkt(self.mac, ss.QUERY_CMDS[lbl]))
                ss.recv_vens(c)
        except OSError:
            c.close()
            return False
        self.conn, self.session_since = c, time.time()
        return True

    def disconnect(self):
        if self.conn:
            try:
                self.conn.send(ss.vens_pkt(self.mac, D6)); ss.recv_vens(self.conn, 2)
            except OSError:
                pass
            self.conn.close()
            self.conn = None
            ss.d6_release(self.ip, self.mac)

    def poll(self):
        """Gibt (paper, button) zurück oder None bei Verbindungsproblem."""
        try:
            self.conn.send(ss.vens_pkt(self.mac, ss.QUERY_CMDS["C2"]))
            r = ss.recv_vens(self.conn, 3)
        except OSError:
            r = None
        if not r or len(r) <= BUTTON_BYTE:
            return None
        return (not r[PAPER_BYTE] & PAPER_EMPTY, bool(r[BUTTON_BYTE] & BUTTON_BIT))

    # ── Scannen ────────────────────────────────────────────────────────────
    def do_scan(self, source):
        settings = pipeline.load_settings()
        if self.paper is False:
            emit("notice", message="Kein Papier im Einzug")
            return
        self.disconnect()
        self.set_state("scanning")
        emit("scan_started", source=source)
        try:
            raw = ss.scan(self.ip, self.key, on_page=lambda n: emit("page", n=n))
            if not raw:
                raise RuntimeError("Keine Seiten empfangen")
            out, n, removed = pipeline.build_pdf(raw, settings, emit=emit)
            emit("done", file=out, pages=n, removed=removed)
            if settings["open_after"]:
                subprocess.run(["open", out])
        except Exception as e:  # noqa: BLE001 - Fehler an die App melden, Dienst läuft weiter
            emit("error", message=str(e))
        finally:
            self.state = None

    # ── Hauptschleife ──────────────────────────────────────────────────────
    def handle_cmd(self, cmd):
        c = cmd.get("cmd")
        if c == "quit":
            self.disconnect(); sys.exit(0)
        if c == "pause":
            self.paused = True; self.disconnect(); self.set_state("paused")
        elif c == "resume":
            self.paused = False; self.state = None
        elif c == "scan" and not self.paused:
            if not self.conn and not self.connect():
                emit("error", message="Keine Verbindung zum Scanner"); return
            p = self.poll()
            if p:
                self.paper = p[0]
            self.do_scan("app")

    def run(self):
        threading.Thread(target=self.read_stdin, daemon=True).start()
        last_button, backoff = False, 1
        while True:
            try:
                while True:
                    self.handle_cmd(self.cmds.get_nowait())
            except queue.Empty:
                pass
            if self.paused:
                time.sleep(POLL_INTERVAL); continue

            if not self.conn:
                if not self.connect():
                    self.wait(backoff); backoff = min(backoff * 2, 15); continue
                backoff = 1
            elif time.time() - self.session_since > SESSION_REFRESH:
                self.disconnect()
                continue

            p = self.poll()
            if p is None:
                self.conn.close(); self.conn = None
                continue
            paper, button = p
            if paper != self.paper:
                self.paper = paper
                self.state = None
            self.set_state("ready")
            if button and not last_button:
                emit("button")
                if pipeline.load_settings()["button_scan"]:
                    self.do_scan("button")
                    last_button = False
                    continue
            last_button = button
            time.sleep(POLL_INTERVAL)

    def wait(self, seconds):
        """Warten, aber auf Befehle reagieren."""
        try:
            self.handle_cmd(self.cmds.get(timeout=seconds))
        except queue.Empty:
            pass

    def read_stdin(self):
        for line in sys.stdin:
            try:
                self.cmds.put(json.loads(line))
            except ValueError:
                pass
        self.cmds.put({"cmd": "quit"})  # App weg -> Dienst beenden


if __name__ == "__main__":
    Daemon().run()
