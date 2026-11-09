"""Which microphone to record from: the one saved in settings, or the system default.

sounddevice is imported on first use, not at import: importing it starts PortAudio, which fails with no audio
server (a Linux session without PulseAudio/PipeWire, CI). The functions take `lib` so tests can pass a fake.
"""

# PortAudio's stand-ins for "whatever Windows picks"; the settings window offers that choice as «Predeterminado».
MAPPERS = {"Microsoft Sound Mapper - Input", "Primary Sound Capture Driver"}


def _sd():
    import sounddevice

    return sounddevice


def _inputs(lib):
    return [(i, d) for i, d in enumerate(lib.query_devices()) if d["max_input_channels"] > 0]


def input_devices(lib=None):
    """[(name to save, name to show)] for the microphones of the default host API.

    Windows' default API (MME) cuts names at 31 characters: show the longest name another API gives the same mic.
    """
    lib = lib or _sd()
    api, inputs, out = lib.default.hostapi, _inputs(lib), []
    for _, d in inputs:
        name = d["name"]
        if d["hostapi"] != api or name in MAPPERS or any(name == saved for saved, _ in out):
            continue
        full = max((e["name"] for _, e in inputs if e["name"].startswith(name)), key=len)
        out.append((name, full))
    return out


def resolve_device(name, lib=None):
    """PortAudio index for a saved name, or None (system default) if it is empty or no longer plugged in."""
    if not name:
        return None
    lib = lib or _sd()
    for i, d in _inputs(lib):
        if d["hostapi"] == lib.default.hostapi and d["name"] == name:
            return i
    return None


def refresh(lib=None):
    """Re-scan devices (~13 ms). PortAudio only sees what was plugged in when it started.

    Only call it with no stream open.
    """
    lib = lib or _sd()
    lib._terminate()
    lib._initialize()
