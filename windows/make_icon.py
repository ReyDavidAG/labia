"""docs/icon.png (1024 px) -> linux/labia/labia.ico, the Windows icon (tray, settings window, Start menu).

    linux\\.venv\\Scripts\\python windows\\make_icon.py

Needs Pillow (`pip install pillow`, only to regenerate the icon; Labia does not use it).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]  # 20 and 40: tray at 125 % and 250 % scaling

img = Image.open(ROOT / "docs" / "icon.png").convert("RGBA")
out = ROOT / "linux" / "labia" / "labia.ico"
img.save(out, sizes=[(s, s) for s in SIZES])
print(f"{out.relative_to(ROOT)}: {out.stat().st_size // 1024} KB")
