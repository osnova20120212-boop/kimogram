#!/usr/bin/env python3
"""Collects free MTProto proxies from public lists, keeps the ones that accept a TCP
connection, and writes them (fastest first) as tg://proxy links, one per line.

Used by .github/workflows/proxies.yml; the app reads the result from the `proxies` branch.
"""
import concurrent.futures
import socket
import sys
import time
import urllib.parse
import urllib.request

SOURCES = [
    "https://raw.githubusercontent.com/Argh94/Proxy-List/main/MTProto.txt",
    "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt",
    "https://raw.githubusercontent.com/ALIILAPRO/MTProtoProxy/main/mtproto.txt",
]
MAX_OUTPUT = 150
CONNECT_TIMEOUT = 3.0


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return response.read().decode("utf-8", "replace").splitlines()
    except Exception as error:  # a dead source must not break the others
        print(f"skip {url}: {error}", file=sys.stderr)
        return []


def parse(line):
    index = line.find("proxy?")
    if index < 0:
        return None
    query = urllib.parse.parse_qs(line[index + len("proxy?"):].strip())
    try:
        host = query["server"][0].strip().rstrip(".")
        port = int(query["port"][0])
        secret = query["secret"][0].strip()
    except (KeyError, IndexError, ValueError):
        return None
    if not host or not secret or not (0 < port < 65536):
        return None
    return host, port, secret


def probe(entry):
    host, port, _ = entry
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=CONNECT_TIMEOUT):
            return entry, time.monotonic() - start
    except OSError:
        return entry, None


def main():
    entries = {}
    for url in SOURCES:
        for line in fetch(url):
            parsed = parse(line)
            if parsed:
                entries.setdefault((parsed[0].lower(), parsed[1]), parsed)
    print(f"candidates: {len(entries)}", file=sys.stderr)

    alive = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=64) as pool:
        for entry, latency in pool.map(probe, entries.values()):
            if latency is not None:
                alive.append((latency, entry))
    alive.sort(key=lambda item: item[0])
    print(f"alive: {len(alive)}", file=sys.stderr)

    for _, (host, port, secret) in alive[:MAX_OUTPUT]:
        query = urllib.parse.urlencode({"server": host, "port": port, "secret": secret})
        print(f"tg://proxy?{query}")


if __name__ == "__main__":
    main()
