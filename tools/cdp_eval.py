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
targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
page = next(t for t in targets if t["type"] == "page" and "deezer.com" in t["url"])
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
