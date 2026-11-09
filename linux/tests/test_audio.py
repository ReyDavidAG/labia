from types import SimpleNamespace

from labia.audio import input_devices, resolve_device

DEVICES = [
    {"name": "Microsoft Sound Mapper - Input", "hostapi": 0, "max_input_channels": 2},
    {"name": "Headset Microphone (3- DualSens", "hostapi": 0, "max_input_channels": 2},
    {"name": "Speakers (Realtek)", "hostapi": 0, "max_input_channels": 0},
    {"name": "Micrófono USB", "hostapi": 0, "max_input_channels": 1},
    {"name": "Primary Sound Capture Driver", "hostapi": 1, "max_input_channels": 2},
    {"name": "Headset Microphone (3- DualSense Wireless Controller)", "hostapi": 1, "max_input_channels": 2},
    {"name": "Micrófono USB", "hostapi": 2, "max_input_channels": 1},
]
LIB = SimpleNamespace(query_devices=lambda: DEVICES, default=SimpleNamespace(hostapi=0))


def test_lists_default_api_mics_with_full_names():
    assert input_devices(LIB) == [
        ("Headset Microphone (3- DualSens", "Headset Microphone (3- DualSense Wireless Controller)"),
        ("Micrófono USB", "Micrófono USB"),
    ]


def test_resolves_saved_mic_or_falls_back_to_default():
    assert resolve_device("Micrófono USB", LIB) == 3
    assert resolve_device("", LIB) is None
    assert resolve_device("Headset Microphone (3- DualSense Wireless Controller)", LIB) is None  # not the MME name
    assert resolve_device("Audífonos que ya no están", LIB) is None
