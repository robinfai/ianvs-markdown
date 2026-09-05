from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).parent
REFERENCE = ROOT / "visual-target-native-primary.png"
IMPLEMENTATION = ROOT / "implementation-native-final.jpeg"
OUTPUT = ROOT / "qa-focused-chrome-and-document-final.png"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        size,
    )


implementation = Image.open(IMPLEMENTATION).convert("RGB")
reference = ImageOps.fit(
    Image.open(REFERENCE).convert("RGB"),
    implementation.size,
    method=Image.Resampling.LANCZOS,
    centering=(0.5, 0.5),
)

crop_height = 390
reference = reference.crop((0, 0, reference.width, crop_height))
implementation = implementation.crop((0, 0, implementation.width, crop_height))

header = 42
width = implementation.width
canvas = Image.new("RGB", (width * 2, crop_height + header), "white")
canvas.paste(reference, (0, header))
canvas.paste(implementation, (width, header))
draw = ImageDraw.Draw(canvas)
draw.rectangle((0, 0, width - 1, header), fill="#11656b")
draw.rectangle((width, 0, width * 2, header), fill="#202526")
draw.text((16, 10), "REFERENCE · CHROME + FIRST VIEW", fill="white", font=font(15))
draw.text(
    (width + 16, 10),
    "IMPLEMENTATION · CHROME + FIRST VIEW",
    fill="white",
    font=font(15),
)
draw.line((width, 0, width, crop_height + header), fill="#9aa5a6", width=2)
canvas.save(OUTPUT)
print(OUTPUT)
