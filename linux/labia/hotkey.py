"""Read every keyboard with evdev (needs the `input` group) and turn keys into GestureMachine events.

Keyboards are grabbed and re-emitted through a uinput clone, minus the hotkey when used alone.
Otherwise apps see the held hotkey as a modifier: Right Alt + our Shift+Insert paste is not a paste,
so nothing would appear until release. Hotkey + another key (AltGr+Q = @) is passed through untouched.
"""
import select
import time

import evdev
from evdev import ecodes as e

from . import core


def keyboards():
    devs = [evdev.InputDevice(p) for p in evdev.list_devices()]
    return [d for d in devs if e.KEY_A in d.capabilities().get(e.EV_KEY, []) and not d.name.startswith("labia")]


def to_gesture(code, value, hotkey):
    """evdev (code, value) -> gesture event or None. value: 1 down, 0 up, 2 auto-repeat."""
    if value == 2:
        return None
    if code == hotkey:
        return core.KEY_DOWN if value else core.KEY_UP
    if value == 1:
        return core.ESCAPE if code == e.KEY_ESC else core.OTHER_KEY
    return None


def _grab(dev):
    while dev.active_keys():  # grabbing with a key down (Enter that started us) leaves it stuck in the compositor
        time.sleep(0.05)
    clone = evdev.UInput.from_device(dev, name=f"labia-{dev.name}"[:79])
    dev.grab()  # released by the kernel if we exit or crash
    return clone


def events(hotkey_name, tick=0.1):
    """Yield (gesture event, time) forever; TICK every `tick` seconds of silence."""
    hotkey = e.ecodes[hotkey_name]
    devs = {d.fd: (d, _grab(d), core.Passthrough(hotkey)) for d in keyboards()}
    if not devs:
        raise SystemExit("No keyboard readable. Add yourself to the `input` group (see linux/README.md).")
    # ponytail: keyboards plugged in after start are not seen; restart labia (or add udev monitoring)
    while True:
        ready, _, _ = select.select(devs, [], [], tick)
        for fd in ready:
            dev, clone, gate = devs[fd]
            for ev in dev.read():
                if ev.type != e.EV_KEY:
                    clone.write_event(ev)  # SYN, MSC scan codes, LEDs
                    continue
                for code, value in gate.filter(ev.code, ev.value):
                    clone.write(e.EV_KEY, code, value)
                if g := to_gesture(ev.code, ev.value, hotkey):
                    yield g, time.monotonic()
        yield core.TICK, time.monotonic()
