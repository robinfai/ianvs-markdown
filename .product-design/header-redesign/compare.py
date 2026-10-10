"""Normalize existing captures for visual QA; never redraw application UI."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).parent
iteration = sys.argv[1]
reference = Image.open(root / "selected-target.png").convert("RGB")
implementation = Image.open(root / f"native-{iteration}.png").convert("RGB")
size = (1200, 780)
reference = reference.resize(size, Image.Resampling.LANCZOS)
implementation = implementation.resize(size, Image.Resampling.LANCZOS)
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
for name, height in [("full", 780), ("header", 180)]:
    canvas = Image.new("RGB", (2400, height + 32), "#ffffff")
    canvas.paste(reference.crop((0, 0, 1200, height)), (0, 32))
    canvas.paste(implementation.crop((0, 0, 1200, height)), (1200, 32))
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 8), "Selected design", fill="#222222", font=font)
    draw.text((1212, 8), "Native macOS implementation", fill="#222222", font=font)
    draw.line((1200, 0, 1200, height + 32), fill="#aaaaaa")
    canvas.save(root / f"comparison-{iteration}-{name}.png")
