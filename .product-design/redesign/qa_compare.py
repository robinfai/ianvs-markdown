from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).parent
REFERENCE = ROOT / "visual-target-native-primary.png"
IMPLEMENTATION = ROOT / "implementation-native-final.jpeg"
OUTPUT = ROOT / "qa-reference-vs-implementation-final.png"


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "Arial Bold.ttf" if bold else "Arial.ttf"
    return ImageFont.truetype(
        f"/System/Library/Fonts/Supplemental/{name}",
        size,
    )


implementation = Image.open(IMPLEMENTATION).convert("RGB")
reference = Image.open(REFERENCE).convert("RGB")
reference = ImageOps.fit(
    reference,
    implementation.size,
    method=Image.Resampling.LANCZOS,
    centering=(0.5, 0.5),
)

header = 44
width, height = implementation.size
canvas = Image.new("RGB", (width * 2, height + header), "white")
canvas.paste(reference, (0, header))
canvas.paste(implementation, (width, header))

draw = ImageDraw.Draw(canvas)
draw.rectangle((0, 0, width - 1, header), fill="#11656b")
draw.rectangle((width, 0, width * 2, header), fill="#202526")
draw.text((18, 11), "REFERENCE · IMAGEGEN", fill="white", font=font(16, bold=True))
draw.text(
    (width + 18, 11),
    "IMPLEMENTATION · NATIVE APP",
    fill="white",
    font=font(16, bold=True),
)
draw.line((width, 0, width, height + header), fill="#9aa5a6", width=2)

canvas.save(OUTPUT)
print(OUTPUT)
