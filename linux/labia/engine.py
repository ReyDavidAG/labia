"""faster-whisper on CUDA when there is a GPU, CPU otherwise."""
import ctypes
import glob
import os
import sys


def _preload_cuda_libs():
    # pip's nvidia-* wheels are not on the loader path; CTranslate2 dlopens them by soname.
    if sys.platform != "linux":
        return
    for pattern in ("nvidia/cublas/lib/libcublas*.so.*", "nvidia/cudnn/lib/libcudnn*.so.*"):
        for base in sys.path:
            for lib in sorted(glob.glob(os.path.join(base, pattern))):
                try:
                    ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
                except OSError:
                    pass


def load(model="large-v3-turbo"):
    _preload_cuda_libs()
    import ctranslate2
    from faster_whisper import WhisperModel

    if ctranslate2.get_cuda_device_count() > 0:
        return WhisperModel(model, device="cuda", compute_type="float16")
    return WhisperModel(model, device="cpu", compute_type="int8")


def transcriber(model, language="es"):
    """Returns transcribe(samples, prompt) -> [(start, end, text)] for stream.Session."""

    def transcribe(samples, prompt):
        segments, _ = model.transcribe(
            samples,
            language=language,
            initial_prompt=prompt,
            beam_size=1,
            temperature=0,
            word_timestamps=True,
            condition_on_previous_text=False,
            vad_filter=False,
        )
        return [(w.start, w.end, w.word) for s in segments for w in (s.words or [])]

    return transcribe
