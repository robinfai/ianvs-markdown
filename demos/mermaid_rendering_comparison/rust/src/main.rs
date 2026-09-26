use resvg::{tiny_skia, usvg};
use serde_json::{json, Value};
use std::{env, fs, path::PathBuf, time::Instant};

fn median(mut samples: Vec<f64>) -> f64 {
    samples.sort_by(f64::total_cmp);
    samples[samples.len() / 2]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(env::args().nth(1).unwrap_or_else(|| "assets".into()));
    let mut cases: Vec<Value> = serde_json::from_slice(&fs::read(root.join("cases.json"))?)?;
    let font_start = Instant::now();
    let mut options = usvg::Options::default();
    options
        .fontdb_mut()
        .load_font_file("/System/Library/Fonts/Hiragino Sans GB.ttc")?;
    options
        .fontdb_mut()
        .load_font_file("/System/Library/Fonts/Helvetica.ttc")?;
    options
        .fontdb_mut()
        .load_font_file("/System/Library/Fonts/Supplemental/Arial.ttf")?;
    options
        .fontdb_mut()
        .set_sans_serif_family("Hiragino Sans GB");
    options.fontdb_mut().set_serif_family("Hiragino Sans GB");
    options.font_family = "Hiragino Sans GB".into();
    let font_ms = font_start.elapsed().as_secs_f64() * 1000.0;
    for item in &mut cases {
        let id = item["id"].as_str().unwrap().to_owned();
        let svg = fs::read_to_string(root.join(format!("{id}/input.svg")))?;
        let mut parse_times = Vec::new();
        for _ in 0..11 {
            let start = Instant::now();
            let tree = usvg::Tree::from_str(&svg, &options)?;
            std::hint::black_box(&tree);
            parse_times.push(start.elapsed().as_secs_f64() * 1000.0);
        }
        let tree = usvg::Tree::from_str(&svg, &options)?;
        let start = Instant::now();
        let normalized = tree.to_string(&usvg::WriteOptions::default());
        let serialize_ms = start.elapsed().as_secs_f64() * 1000.0;
        fs::write(root.join(format!("{id}/vector.svg")), &normalized)?;
        let width = 640_u32;
        let height = (width as f32 * tree.size().height() / tree.size().width()).ceil() as u32;
        if height > 4096 {
            return Err(format!("{id}: oversized comparison fixture ({height}px)").into());
        }
        let mut raster_metrics = Vec::new();
        for ratio in [1, 2, 4] {
            let mut times = Vec::new();
            let mut pixmap = tiny_skia::Pixmap::new(width * ratio, height * ratio).unwrap();
            let transform = tiny_skia::Transform::from_scale(
                (width * ratio) as f32 / tree.size().width(),
                (width * ratio) as f32 / tree.size().width(),
            );
            for _ in 0..11 {
                pixmap.fill(tiny_skia::Color::WHITE);
                let start = Instant::now();
                resvg::render(&tree, transform, &mut pixmap.as_mut());
                times.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            let start = Instant::now();
            let png = pixmap.encode_png()?;
            let encode_ms = start.elapsed().as_secs_f64() * 1000.0;
            fs::write(root.join(format!("{id}/raster-{ratio}x.png")), &png)?;
            raster_metrics.push(
                json!({"ratio":ratio, "width":width*ratio, "height":height*ratio,
                "render_median_ms":median(times[1..].to_vec()), "png_encode_ms":encode_ms,
                "png_bytes":png.len(), "rgba_bytes":pixmap.data().len()}),
            );
        }
        item["rust"] = json!({"resvg_version":"0.45.1", "font_load_once_ms":font_ms,
            "parse_median_ms":median(parse_times[1..].to_vec()), "serialize_ms":serialize_ms,
            "input_bytes":svg.len(), "vector_bytes":normalized.len(),
            "width":width, "height":height, "raster":raster_metrics});
        println!(
            "{id}: {} → {} bytes; {width} × {height}",
            svg.len(),
            normalized.len()
        );
    }
    fs::write(
        root.join("cases.json"),
        serde_json::to_string_pretty(&cases)?,
    )?;
    Ok(())
}
