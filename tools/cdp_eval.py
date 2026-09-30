#!/usr/bin/env python3
"""Evaluate a JavaScript expression in the widget's hidden Deezer page.

The widget must run with QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:<port>
(9333 by default, override with CDP_PORT). The expression is read from stdin;
promises are awaited and the result is printed as JSON.

    echo 'JSON.parse(__dzPlasmoid.snapshot())' | tools/cdp_eval.py
"""
import json
import os
import sys
import urllib.request

import websocket  # python3-websocket (websocket-client)

port = os.environ.get("CDP_PORT", "9333")
try:
    targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
except OSError as e:
    sys.exit(f"cdp_eval: nothing on port {port} ({e}); is the widget running with "
             f"QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:{port}?")
pages = [t for t in targets if t["type"] == "page"]
# The widget's own page is www.deezer.com; a sign-in window (account.deezer.com,
# Google, Apple) can be listed first and has none of its state.
main = [t for t in pages if t["url"].startswith("https://www.deezer.com/")]
if not main:
    urls = ", ".join(t["url"] or "about:blank" for t in pages) or "none"
    sys.exit(f"cdp_eval: no www.deezer.com page on port {port} (pages: {urls})")
page = main[0]
ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                    "params": {"expression": sys.stdin.read(), "awaitPromise": True, "returnByValue": True,
                               "userGesture": True}}))
while True:
    msg = json.loads(ws.recv())
    if msg.get("id") == 1:
        break
res = msg.get("result", {})
print(json.dumps(res.get("result", {}).get("value", res), indent=1, ensure_ascii=False))
