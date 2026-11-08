"""faster-whisper on CUDA when there is a GPU, CPU otherwise."""
import ctypes
import glob
import os
import sys


def _preload_cuda_libs():
    # pip's nvidia-* wheels are not on the loader path; CTranslate2 dlopens them by soname.
    if sys.platform == "win32":
        for base in sys.path:
            for d in glob.glob(os.path.join(base, "nvidia", "*", "bin")):
                os.add_dll_directory(d)
                os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]  # some DLLs load their siblings via PATH
        return
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
    """Returns transcribe(samples, prompt, beam, vad) -> [(start, end, text)] for stream.Session."""

    def transcribe(samples, prompt, beam=1, vad=False):
        segments, _ = model.transcribe(
            samples,
            language=language,
            initial_prompt=prompt,
            beam_size=beam,
            temperature=0,
            word_timestamps=True,
            condition_on_previous_text=False,
            vad_filter=vad,  # Silero VAD: no speech in, no text out (no «Gracias.» on silence)
        )
        return [(w.start, w.end, w.word) for s in segments for w in (s.words or [])]

    return transcribe
