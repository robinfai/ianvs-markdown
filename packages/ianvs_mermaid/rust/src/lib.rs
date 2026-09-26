use serde_json::{json, Value};
use std::{
    collections::hash_map::DefaultHasher,
    ffi::{c_char, CString},
    hash::{Hash, Hasher},
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{Arc, Mutex, OnceLock},
};
use usvg::{fontdb, FontResolver};

const VERSION: &str = "ianvs-svg/1;usvg/0.45.1;font-policy/1";
const MAX_INPUT: usize = 8 * 1024 * 1024;
const MAX_OUTPUT: usize = 16 * 1024 * 1024;

struct Fonts {
    db: Arc<fontdb::Database>,
    family: String,
    fingerprint: String,
}

// Font discovery happens once, on the Dart rendering worker, never the UI
// isolate. Font files remain on the user's system and are not redistributed.
fn fonts() -> Result<&'static Fonts, String> {
    static FONTS: OnceLock<Result<Fonts, String>> = OnceLock::new();
    FONTS
        .get_or_init(|| {
            let mut db = fontdb::Database::new();
            db.load_system_fonts();
            let candidates = [
                "Hiragino Sans GB",
                "PingFang SC",
                "Microsoft YaHei",
                "Noto Sans CJK SC",
                "Noto Sans",
                "Arial",
                "DejaVu Sans",
            ];
            let family = candidates
                .iter()
                .find(|name| {
                    db.query(&fontdb::Query {
                        families: &[fontdb::Family::Name(name)],
                        ..Default::default()
                    })
                    .is_some()
                })
                .ok_or("No usable system fonts found for Mermaid diagrams")?
                .to_string();
            db.set_sans_serif_family(&family);
            db.set_serif_family(&family);
            let mut inventory: Vec<String> = db
                .faces()
                .map(|face| {
                    let (source, _) = db.face_source(face.id).unwrap();
                    let (path, metadata) = match &source {
                        fontdb::Source::File(path) | fontdb::Source::SharedFile(path, _) => (
                            path.to_string_lossy().into_owned(),
                            std::fs::metadata(path)
                                .ok()
                                .map(|m| (m.len(), m.modified().ok())),
                        ),
                        _ => ("memory".into(), None),
                    };
                    format!("{path}:{:?}:{}:{metadata:?}", face.families, face.index)
                })
                .collect();
            inventory.sort();
            let mut hash = DefaultHasher::new();
            inventory.hash(&mut hash);
            family.hash(&mut hash);
            Ok(Fonts {
                db: Arc::new(db),
                family,
                fingerprint: format!("{:016x}", hash.finish()),
            })
        })
        .as_ref()
        .map_err(Clone::clone)
}

fn environment() -> Result<Value, String> {
    let fonts = fonts()?;
    Ok(
        json!({"version": VERSION, "fontFingerprint": fonts.fingerprint, "fontFamily": fonts.family}),
    )
}

fn check_features(svg: &str, expanded: bool) -> Result<(), String> {
    let document = roxmltree::Document::parse(svg).map_err(|e| e.to_string())?;
    for node in document.descendants().filter(|n| n.is_element()) {
        // These require rendering semantics not supported by this Flutter path.
        // Do not silently discard them or introduce an unrequested bitmap fallback.
        let tag = node.tag_name().name();
        if matches!(
            tag,
            "foreignObject" | "image" | "script" | "animate" | "animateTransform"
        ) || (expanded && matches!(tag, "filter" | "mask" | "pattern"))
        {
            return Err(format!(
                "Unsupported SVG feature in Mermaid vector rendering: {tag}"
            ));
        }
    }
    for text in document
        .descendants()
        .filter_map(|n| n.text().filter(|_| n.is_text()))
    {
        if text
            .chars()
            .any(|c| matches!(c as u32, 0x1F000..=0x1FAFF | 0xFE0F | 0x200D))
        {
            return Err(
                "Color emoji and emoji sequences are not supported by Mermaid vector rendering"
                    .into(),
            );
        }
    }
    Ok(())
}

fn preprocess(svg: &str, max_output: usize) -> Result<Value, String> {
    if svg.len() > MAX_INPUT {
        return Err("SVG exceeds the 8 MiB input limit".into());
    }
    check_features(svg, false)?;
    let fonts = fonts()?;
    let missing = Mutex::new(Vec::new());
    let select_font = FontResolver::default_font_selector();
    let select_fallback = FontResolver::default_fallback_selector();
    let options = usvg::Options {
        fontdb: fonts.db.clone(),
        font_family: fonts.family.clone(),
        font_resolver: FontResolver {
            select_font,
            select_fallback: Box::new(|c, excluded, db| {
                let id = select_fallback(c, excluded, db);
                if id.is_none() {
                    missing.lock().unwrap().push(c);
                }
                id
            }),
        },
        // Never resolve a file/URL from generated SVG.
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_data: Box::new(|_, _, _| None),
            resolve_string: Box::new(|_, _| None),
        },
        ..Default::default()
    };
    let tree = usvg::Tree::from_str(svg, &options).map_err(|e| e.to_string())?;
    let missing = missing.lock().unwrap();
    if !missing.is_empty() {
        return Err(format!(
            "System fonts lack these Mermaid characters: {missing:?}"
        ));
    }
    let output = tree.to_string(&usvg::WriteOptions::default());
    // Also reject features introduced by text conversion (e.g. bitmap glyphs).
    // Unused Mermaid filter definitions have now been pruned by usvg. Only
    // features actually needed to draw the result are rejected here.
    check_features(&output, true)?;
    if output.len() > max_output.min(MAX_OUTPUT) {
        return Err("Expanded SVG exceeds the configured output limit".into());
    }
    Ok(json!({"svg": output, "width": tree.size().width(), "height": tree.size().height()}))
}

fn response(f: impl FnOnce() -> Result<Value, String>) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(f));
    let value = match result {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => json!({"error": error}),
        Err(_) => json!({"error": "SVG preprocessing failed inside the native bridge"}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn ianvs_svg_environment() -> *mut c_char {
    response(environment)
}

/// # Safety
/// The caller owns a valid `len`-byte buffer until this synchronous call returns.
/// The returned UTF-8 JSON must be released with `ianvs_svg_free` exactly once.
#[no_mangle]
pub unsafe extern "C" fn ianvs_svg_preprocess(
    data: *const u8,
    len: usize,
    max_output: usize,
) -> *mut c_char {
    response(|| {
        if data.is_null() || len > MAX_INPUT {
            return Err("Invalid SVG input buffer or input limit exceeded".into());
        }
        let svg = std::str::from_utf8(std::slice::from_raw_parts(data, len))
            .map_err(|e| e.to_string())?;
        preprocess(svg, max_output)
    })
}

/// # Safety
/// Release only non-null pointers returned by this library, exactly once.
#[no_mangle]
pub unsafe extern "C" fn ianvs_svg_free(data: *mut c_char) {
    if !data.is_null() {
        drop(CString::from_raw(data));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_markers_and_cjk_text() {
        let output = preprocess(r##"<svg xmlns="http://www.w3.org/2000/svg" width="300" height="100"><defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="5" refY="5"><path d="M0 0L10 5L0 10z"/></marker></defs><path d="M10 50H200" stroke="black" marker-end="url(#arrow)"/><text x="10" y="30">中文 English</text></svg>"##, MAX_OUTPUT).unwrap();
        let svg = output["svg"].as_str().unwrap();
        assert!(!svg.contains("<text"));
        assert!(!svg.contains("<marker"));
        // usvg combines the glyph contours into one path per text span.
        assert!(svg.matches("<path").count() >= 3);
        assert!(svg.len() > 1000, "Text outlines must not disappear");
        assert_eq!(output["width"], 300.0);
    }

    #[test]
    fn fails_explicitly_for_uncovered_features() {
        for tag in ["image", "foreignObject"] {
            assert!(preprocess(&format!("<svg><{tag}/></svg>"), MAX_OUTPUT)
                .unwrap_err()
                .contains(tag));
        }
        assert!(preprocess(r##"<svg width="20" height="20"><defs><filter id="f"><feGaussianBlur stdDeviation="2"/></filter></defs><rect width="20" height="20" filter="url(#f)"/></svg>"##, MAX_OUTPUT).unwrap_err().contains("filter"));
        assert!(preprocess(r##"<svg width="20" height="20"><defs><mask id="m"><rect width="10" height="10" fill="white"/></mask></defs><rect width="20" height="20" mask="url(#m)"/></svg>"##, MAX_OUTPUT).unwrap_err().contains("mask"));
        assert!(preprocess("<svg><text>😀</text></svg>", MAX_OUTPUT)
            .unwrap_err()
            .contains("emoji"));
        assert!(preprocess("not SVG", MAX_OUTPUT).is_err());
        assert!(preprocess("<svg width='10' height='10'/>", 1).is_err());
    }

    #[test]
    fn keeps_gradients_and_clips() {
        let output = preprocess(r##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><defs><linearGradient id="g"><stop stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><clipPath id="c"><circle cx="20" cy="20" r="10"/></clipPath></defs><rect width="40" height="40" fill="url(#g)" clip-path="url(#c)"/></svg>"##, MAX_OUTPUT).unwrap();
        assert!(output["svg"].as_str().unwrap().contains("linearGradient"));
        assert!(output["svg"].as_str().unwrap().contains("clipPath"));
    }
}
