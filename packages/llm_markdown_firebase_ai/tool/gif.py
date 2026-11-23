"""Turns doc/frames/*.png (from tool/record.dart) into doc/firebase_ai.gif."""
import glob
import os
import shutil

from PIL import Image

WIDTH = 390
paths = sorted(glob.glob("doc/frames/*.png"))
frames = []
for path in paths:
    image = Image.open(path).convert("RGB")
    height = round(image.height * WIDTH / image.width)
    frames.append(image.resize((WIDTH, height), Image.LANCZOS))
palette = frames[len(frames) // 2].quantize(colors=128, method=Image.MEDIANCUT)
frames = [f.quantize(palette=palette, dither=Image.NONE) for f in frames]
frames[0].save(
    "doc/firebase_ai.gif",
    save_all=True,
    append_images=frames[1:],
    duration=100,
    loop=0,
    optimize=True,
)
shutil.rmtree("doc/frames")
print(len(frames), "frames,", os.path.getsize("doc/firebase_ai.gif") // 1024, "KB")
