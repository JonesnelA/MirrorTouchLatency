"""Simulator smoke check of the actual loopback listener (no input sent)."""
import json
import math
import socket
import sys

mode = "touch-only" if "--touch-only" in sys.argv else "tap"


def line(stream):
    data = stream.readline(4097)
    assert data.endswith(b"\n") and len(data) <= 4096, "Invalid reply frame"
    return json.loads(data)


def connected():
    sock = socket.create_connection(("127.0.0.1", 47091), timeout=5)
    sock.settimeout(5)
    stream = sock.makefile("rb")
    hello = line(stream)
    assert hello["type"] == "hello" and hello["version"] == 2
    assert hello["sequence"] == 0 and hello["white"] is False and hello["mode"] == mode
    assert len(hello["session"]) == 36
    if mode == 'touch-only':
        active = '--display-link' in sys.argv
        assert hello['appVersion'] == '1.4.0'
        assert hello['eventLoopMode'] == ('display-link' if active else 'static')
        assert isinstance(hello['screenMaximumFPS'], int) and hello['screenMaximumFPS'] > 0
        if active:
            assert hello['displayLinkActive'] is True and hello['displayLinkCallbackCount'] >= 8
            assert 0 < hello['displayLinkFrameIntervalMs'] < 1000
        else:
            assert hello['displayLinkActive'] is False and hello['displayLinkCallbackCount'] == 0
    return sock, stream, hello


sock, stream, hello = connected()
try:
    sock.sendall(b'{"type":"ping",')
    sock.sendall(b'"id":17}\n{"type":"ping","id":18}\n')
    previous = 0
    for number in (17, 18):
        pong = line(stream)
        assert pong["type"] == "pong" and pong["id"] == number
        assert math.isfinite(pong["receivedTime"]) and pong["sendTime"] >= pong["receivedTime"] >= previous
        previous = pong["sendTime"]
    # Unsupported input commands must not change the test UI or generate a touch.
    sock.sendall(b'not json\n{"type":"touch","x":0.5,"y":0.5}\n{"type":"ping","id":19}\n')
    assert line(stream)["id"] == 19
    sock.sendall(b"x" * 4097)
    assert stream.read(1) == b"", "Oversized request was not disconnected"
finally:
    stream.close(); sock.close()
sock, stream, after = connected()
assert after["session"] == hello["session"] and after["sequence"] == 0
stream.close(); sock.close()
print("PASS USB telemetry hello, fragmented/coalesced pings, clock ordering, read-only commands and bounded input")
