from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).parent
CURRENT = ROOT / "current-example-wide.png"
TARGET = ROOT / "visual-target-native-primary.png"
OUTPUT = ROOT / "annotated-current-vs-native-target.png"


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "Arial Bold.ttf" if bold else "Arial.ttf"
    return ImageFont.truetype(
        f"/System/Library/Fonts/Supplemental/{name}",
        size,
    )


def marker(
    draw: ImageDraw.ImageDraw,
    position: tuple[int, int],
    number: int,
    color: str,
) -> None:
    x, y = position
    radius = 14
    draw.ellipse(
        (x - radius, y - radius, x + radius, y + radius),
        fill=color,
        outline="white",
        width=2,
    )
    label = str(number)
    bounds = draw.textbbox((0, 0), label, font=font(16, bold=True))
    draw.text(
        (x - (bounds[2] - bounds[0]) / 2, y - 10),
        label,
        fill="white",
        font=font(16, bold=True),
    )


current = Image.open(CURRENT).convert("RGB")
target = Image.open(TARGET).convert("RGB")
current.thumbnail((768, 512), Image.Resampling.LANCZOS)
target = target.resize((768, 512), Image.Resampling.LANCZOS)

header_height = 48
legend_top = 570
canvas = Image.new("RGB", (1536, 770), "#f7f8f8")
canvas.paste(current, (0, header_height + (512 - current.height) // 2))
canvas.paste(target, (768, header_height))
draw = ImageDraw.Draw(canvas)

draw.rectangle((0, 0, 767, header_height), fill="#202526")
draw.rectangle((768, 0, 1536, header_height), fill="#11656b")
draw.text((24, 13), "CURRENT IMPLEMENTATION", fill="white", font=font(18, bold=True))
draw.text((792, 13), "IMAGEGEN VISUAL TARGET", fill="white", font=font(18, bold=True))
draw.line((768, 0, 768, legend_top - 10), fill="#c9d0d0", width=2)

current_points = [(58, 70), (700, 70), (165, 100), (82, 235), (390, 310), (670, 520)]
target_points = [(845, 70), (1438, 70), (945, 104), (835, 235), (1110, 295), (1400, 548)]
for index, point in enumerate(current_points, 1):
    marker(draw, point, index, "#c24b57")
for index, point in enumerate(target_points, 1):
    marker(draw, point, index, "#167b82")

draw.rectangle((0, legend_top, 1536, 770), fill="white")
draw.line((0, legend_top, 1536, legend_top), fill="#d8dede", width=2)
draw.text((24, legend_top + 16), "ANNOTATED DIFFERENCES", fill="#202526", font=font(18, bold=True))

notes = [
    "Chrome: clear identity, integrated traffic lights, no oversized icon tile.",
    "Actions: flat Mac toolbar controls replace Material-style filled pills.",
    "Tabs: wider targets with native dividers, close controls, and dirty dots.",
    "Sidebar: 300 px hierarchy with compact rows and a short teal locator.",
    "Canvas: 760 px editorial measure, larger type, deliberate left anchor.",
    "System feedback: persistent status bar plus a canvas-only drop state.",
]
for index, note in enumerate(notes):
    column = index % 2
    row = index // 2
    x = 24 + column * 756
    y = legend_top + 54 + row * 42
    marker(draw, (x + 14, y + 10), index + 1, "#167b82")
    draw.text((x + 38, y), note, fill="#354043", font=font(16))

canvas.save(OUTPUT)
print(OUTPUT)
