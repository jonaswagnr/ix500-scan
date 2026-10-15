#!/usr/bin/env python3
"""Liest den Kopplungsschlüssel aus einem pcap-Mitschnitt (tcpdump -w) des
VENS-Handshakes auf TCP 53219 und speichert ihn in ~/.config/scansnap/key.

Der Schlüssel steht an Offset 52 (12 Byte ASCII) im 128-Byte-Paket mit
Kommando 0x11, das ScanSnap Home an den Scanner schickt.
"""
import os, struct, sys

KEY_PATH = os.path.expanduser("~/.config/scansnap/key")


def packets(path):
    with open(path, "rb") as f:
        data = f.read()
    magic = data[:4]
    endian = "<" if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    off = 24
    while off + 16 <= len(data):
        incl = struct.unpack(endian + "I", data[off + 8:off + 12])[0]
        yield linktype, data[off + 16:off + 16 + incl]
        off += 16 + incl


HOSTID_PATH = os.path.expanduser("~/.config/scansnap/hostid")


def find_keys(path):
    """Liefert (Schlüssel, HostID-Hex) aus jedem 128-Byte-Handshake."""
    for linktype, frame in packets(path):
        # 1 = Ethernet, 0 = BSD loopback/null; wir suchen das VENS-Paket einfach im Frame
        i = frame.find(b"\x00\x00\x00\x80VENS\x00\x00\x00\x11")
        if i >= 0 and len(frame) >= i + 116:
            key = frame[i + 52:i + 64].rstrip(b"\x00")
            if key:
                yield key, frame[i + 108:i + 116].hex()


def main():
    if len(sys.argv) != 2:
        sys.exit(f"Aufruf: {sys.argv[0]} mitschnitt.pcap")
    keys = list(dict.fromkeys(find_keys(sys.argv[1])))
    if not keys:
        sys.exit("Kein Handshake mit Schlüssel im Mitschnitt gefunden.")
    key, hostid = keys[0]
    os.makedirs(os.path.dirname(KEY_PATH), exist_ok=True)
    for path, value in ((KEY_PATH, key.decode()), (HOSTID_PATH, hostid)):
        with open(path, "w") as f:
            f.write(value)
        os.chmod(path, 0o600)
    print(f"Schlüssel und HostID gespeichert in {os.path.dirname(KEY_PATH)}/")
    if len(keys) > 1:
        print(f"Hinweis: {len(keys)} verschiedene Schlüssel im Mitschnitt, erster wurde genommen.")


if __name__ == "__main__":
    main()
