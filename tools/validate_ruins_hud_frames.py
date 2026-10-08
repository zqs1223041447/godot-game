#!/usr/bin/env python3
"""Short native frame smoke on an existing private X11 display, using OS clicks."""
import argparse
import ctypes as C
import ctypes.util
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--display', default=':98')
args = parser.parse_args()
qa = ROOT / 'docs/qa/ruins-hud-retry'
qa.mkdir(parents=True, exist_ok=True)
x11 = C.CDLL(ctypes.util.find_library('X11'))
xtst = C.CDLL(ctypes.util.find_library('Xtst'))
x11.XOpenDisplay.argtypes = [C.c_char_p]
x11.XOpenDisplay.restype = C.c_void_p
x11.XDefaultRootWindow.argtypes = [C.c_void_p]
x11.XDefaultRootWindow.restype = C.c_ulong
x11.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
x11.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
x11.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
x11.XMapRaised.argtypes = [C.c_void_p, C.c_ulong]
x11.XFree.argtypes = [C.c_void_p]
x11.XFlush.argtypes = [C.c_void_p]
x11.XCloseDisplay.argtypes = [C.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
display = x11.XOpenDisplay(args.display.encode())
if not display:
    raise SystemExit('Private X11 display unavailable; no native click claim')


def focus_own_window():
    root = x11.XDefaultRootWindow(display)
    returned_root, parent, count = C.c_ulong(), C.c_ulong(), C.c_uint()
    children = C.POINTER(C.c_ulong)()
    if not x11.XQueryTree(display, root, C.byref(returned_root), C.byref(parent), C.byref(children), C.byref(count)):
        raise RuntimeError('Cannot locate native window on private display')
    try:
        for index in range(count.value):
            window = children[index]
            geometry_root, x, y = C.c_ulong(), C.c_int(), C.c_int()
            width, height, border, depth = C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
            if x11.XGetGeometry(display, window, C.byref(geometry_root), C.byref(x), C.byref(y), C.byref(width), C.byref(height), C.byref(border), C.byref(depth)) and width.value >= 100 and height.value >= 100:
                x11.XMapRaised(display, window)
                x11.XSetInputFocus(display, window, 1, 0)
                return
        raise RuntimeError('No Godot-sized native window on private display')
    finally:
        x11.XFree(children)


clicks = []
try:
    with tempfile.TemporaryDirectory(prefix='godot-m1-ruins-hud-frames.', dir='/tmp') as temporary:
        folder = Path(temporary)
        env = dict(os.environ, DISPLAY=args.display, LIBGL_ALWAYS_SOFTWARE='1')
        for variable, child in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            path = folder / child
            path.mkdir()
            env[variable] = str(path)
        request = folder / 'click.json'
        env['RUINS_HUD_CLICK_REQUEST'] = str(request)
        env['RUINS_HUD_FRAMES_REPORT'] = str(qa / 'normal-frames.json')
        command = [os.environ.get('GODOT_BIN', 'godot'), '--path', str(ROOT), '--display-driver', 'x11', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/ruins_hud_retry_frames_smoke.gd']
        with (qa / 'normal-frames.log').open('w') as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 45
            try:
                while process.poll() is None:
                    if time.monotonic() > deadline:
                        raise TimeoutError('Native frame smoke exceeded its 45-second limit')
                    try:
                        message = json.loads(request.read_text())
                    except (FileNotFoundError, json.JSONDecodeError):
                        message = None
                    if message and message['sequence'] > len(clicks):
                        if message['sequence'] != len(clicks) + 1:
                            raise RuntimeError('Unexpected click sequence')
                        focus_own_window()
                        xtst.XTestFakeMotionEvent(display, 0, message['x'], message['y'], 0)
                        xtst.XTestFakeButtonEvent(display, 1, 1, 0)
                        x11.XFlush(display)
                        time.sleep(0.04)
                        xtst.XTestFakeButtonEvent(display, 1, 0, 0)
                        x11.XFlush(display)
                        clicks.append(message)
                    time.sleep(0.01)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        (qa / 'native-clicks.json').write_text(json.dumps({'display': args.display, 'method': 'X11 XTest OS mouse events; private display contains only this smoke window', 'clicks': clicks, 'exit_code': process.returncode}, ensure_ascii=False, indent=2) + '\n')
        if process.returncode != 0:
            raise SystemExit(f'Native smoke exit {process.returncode}; inspect normal-frames.log')
        report = json.loads((qa / 'normal-frames.json').read_text())
        if report['failures'] or len(clicks) != 4:
            raise SystemExit('Native frame smoke failed or did not deliver four clicks')
        print(f"Normal frames: {report['checks']} checks, 0 failures; four native OS clicks; screenshot {report['screenshot']}")
finally:
    x11.XCloseDisplay(display)
