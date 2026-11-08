"""Read every keyboard with evdev (needs the `input` group) and turn keys into GestureMachine events."""
import select
import time

import evdev
from evdev import ecodes as e

from . import core


def keyboards():
    devs = [evdev.InputDevice(p) for p in evdev.list_devices()]
    return [d for d in devs if e.KEY_A in d.capabilities().get(e.EV_KEY, []) and d.name != "labia-keyboard"]


def to_gesture(code, value, hotkey):
    """evdev (code, value) -> gesture event or None. value: 1 down, 0 up, 2 auto-repeat."""
    if value == 2:
        return None
    if code == hotkey:
        return core.KEY_DOWN if value else core.KEY_UP
    if value == 1:
        return core.ESCAPE if code == e.KEY_ESC else core.OTHER_KEY
    return None


def events(hotkey_name, tick=0.1):
    """Yield (gesture event, time) forever; TICK every `tick` seconds of silence."""
    hotkey = e.ecodes[hotkey_name]
    devs = {d.fd: d for d in keyboards()}
    if not devs:
        raise SystemExit("No keyboard readable. Add yourself to the `input` group (see linux/README.md).")
    # ponytail: keyboards plugged in after start are not seen; restart labia (or add udev monitoring)
    while True:
        ready, _, _ = select.select(devs, [], [], tick)
        for fd in ready:
            for ev in devs[fd].read():
                if ev.type == e.EV_KEY and (g := to_gesture(ev.code, ev.value, hotkey)):
                    yield g, time.monotonic()
        yield core.TICK, time.monotonic()
