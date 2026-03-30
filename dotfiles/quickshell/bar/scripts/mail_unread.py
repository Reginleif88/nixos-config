#!/usr/bin/env python3
"""Query Proton Mail unread count via Chrome DevTools Protocol.

Connects to the Electron app's CDP endpoint, finds the mail.proton.me
webContents, and reads the sidebar unread counter from the DOM.

Prints a single integer (the unread count) to stdout. Prints 0 on any error.
"""

import json
import os
import re
import socket
import struct
import subprocess
import sys
import base64
from urllib.request import urlopen


def find_cdp_port():
    """Find the CDP port from the electron process listening on localhost."""
    try:
        out = subprocess.check_output(
            ["ss", "-tlnp"], stderr=subprocess.DEVNULL, text=True
        )
        for line in out.splitlines():
            if "electron" in line:
                m = re.search(r"127\.0\.0\.1:(\d+)", line)
                if m:
                    return int(m.group(1))
    except Exception:
        pass
    return None


def get_ws_url(port):
    """Get the CDP websocket URL from the /json endpoint."""
    try:
        with urlopen(f"http://127.0.0.1:{port}/json", timeout=3) as r:
            targets = json.loads(r.read())
            for t in targets:
                if t.get("type") == "node":
                    return t["webSocketDebuggerUrl"]
    except Exception:
        pass
    return None


def ws_connect(url):
    """Minimal websocket handshake — returns connected socket."""
    m = re.match(r"ws://([^:]+):(\d+)(/.+)", url)
    if not m:
        return None
    host, port, path = m.group(1), int(m.group(2)), m.group(3)
    s = socket.create_connection((host, port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.send(req.encode())
    s.recv(4096)
    return s


def ws_send(s, msg):
    data = msg.encode()
    frame = bytearray([0x81])
    l = len(data)
    mask_key = os.urandom(4)
    if l < 126:
        frame.append(0x80 | l)
    elif l < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", l))
    frame.extend(mask_key)
    frame.extend(bytearray(b ^ mask_key[i % 4] for i, b in enumerate(data)))
    s.send(bytes(frame))


def ws_recv(s):
    s.settimeout(5)
    data = s.recv(65536)
    if len(data) < 2:
        return ""
    pl = data[1] & 0x7F
    off = 2
    if pl == 126:
        pl = struct.unpack(">H", data[2:4])[0]
        off = 4
    elif pl == 127:
        pl = struct.unpack(">Q", data[2:10])[0]
        off = 10
    return data[off : off + pl].decode()


def get_unread(s):
    """Find the mail webContents and query the DOM unread counter."""
    # Step 1: Find the mail.proton.me webContents ID
    expr_find = """
    (function() {
        var wc = process.mainModule.require('electron').webContents;
        var all = wc.getAllWebContents();
        for (var i = 0; i < all.length; i++) {
            if (all[i].getURL().indexOf('mail.proton.me') !== -1) {
                return all[i].id;
            }
        }
        return -1;
    })()
    """
    ws_send(s, json.dumps({
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {"expression": expr_find},
    }))
    r = json.loads(ws_recv(s))
    wc_id = r.get("result", {}).get("result", {}).get("value", -1)
    if wc_id == -1:
        return 0

    # Step 2: Execute JS in that webContents to read the unread counter
    expr_count = f"""
    (async function() {{
        var wc = process.mainModule.require('electron').webContents.fromId({wc_id});
        if (!wc) return '0';
        var result = await wc.executeJavaScript(
            "(document.querySelector('.navigation-counter-item')?.textContent?.trim()) || '0'"
        );
        return result;
    }})()
    """
    ws_send(s, json.dumps({
        "id": 2,
        "method": "Runtime.evaluate",
        "params": {"expression": expr_count, "awaitPromise": True},
    }))
    r = json.loads(ws_recv(s))
    val = r.get("result", {}).get("result", {}).get("value", "0")
    try:
        return int(val)
    except (ValueError, TypeError):
        return 0


def main():
    try:
        port = find_cdp_port()
        if not port:
            print(0)
            return

        ws_url = get_ws_url(port)
        if not ws_url:
            print(0)
            return

        s = ws_connect(ws_url)
        if not s:
            print(0)
            return

        try:
            count = get_unread(s)
            print(count)
        finally:
            s.close()
    except Exception:
        print(0)


if __name__ == "__main__":
    main()
