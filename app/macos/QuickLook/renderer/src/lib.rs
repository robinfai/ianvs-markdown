use base64::{engine::general_purpose::STANDARD, Engine};
use pulldown_cmark::{html, CodeBlockKind, CowStr, Event, Options, Parser, Tag, TagEnd};
use std::{
    collections::{HashMap, HashSet},
    panic::catch_unwind,
    slice,
};

const MAX_SOURCE_BYTES: usize = 2 * 1024 * 1024;
const MAX_HTML_BYTES: usize = 16 * 1024 * 1024;
const MAX_DIAGRAMS: usize = 32;

// The C ABI is shared with the app's locked merman package (ABI version 1).
#[repr(C)]
pub struct PreviewBuffer {
    pub data: *mut u8,
    pub len: usize,
}

#[repr(C)]
struct MermanResult {
    code: i32,
    data: PreviewBuffer,
}

extern "C" {
    fn merman_abi_version() -> u32;
    fn merman_buffer_struct_size() -> usize;
    fn merman_result_struct_size() -> usize;
    fn merman_render_svg(
        source: *const u8,
        source_len: usize,
        options: *const u8,
        options_len: usize,
    ) -> MermanResult;
    fn merman_buffer_free(buffer: PreviewBuffer);
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn page(body: &str) -> String {
    format!(
        "<!doctype html><html><head><meta charset=\"utf-8\">\
         <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\
         <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; \
         img-src data: cid:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">\
         <title>Linefold Markdown Preview</title><style>{}</style></head><body>{body}</body></html>",
        include_str!("../style.css")
    )
}

fn notice(message: &str) -> String {
    page(&format!("<p class=\"notice\">{}</p>", escape(message)))
}

fn diagram(source: &str, index: usize) -> Result<String, &'static str> {
    if index >= MAX_DIAGRAMS || source.len() > 128 * 1024 {
        return Err("Diagram exceeds the Quick Look preview limit.");
    }
    // Quick Look displays SVG in an image document; it supports markers and text
    // directly, so the Flutter-specific usvg/path conversion is unnecessary here.
    let options = format!(
        r##"{{"version":1,"site_config":{{"theme":"default","securityLevel":"strict","themeVariables":{{"fontFamily":"Helvetica, PingFang SC, sans-serif"}}}},"resources":{{"profile":"interactive","max_source_bytes":131072,"max_svg_bytes":2097152,"max_flowchart_nodes":256,"max_flowchart_edges":512}},"svg":{{"pipeline":"resvg-safe","diagram_id":"linefold-ql-{index}","root_background_color":"#ffffff"}}}}"##
    );
    unsafe {
        if merman_abi_version() != 1
            || merman_buffer_struct_size() != std::mem::size_of::<PreviewBuffer>()
            || merman_result_struct_size() != std::mem::size_of::<MermanResult>()
        {
            return Err("The bundled diagram renderer has an incompatible version.");
        }
        let result = merman_render_svg(
            source.as_ptr(),
            source.len(),
            options.as_ptr(),
            options.len(),
        );
        let output = if result.code == 0 && !result.data.data.is_null() {
            let bytes = slice::from_raw_parts(result.data.data, result.data.len);
            Ok(format!(
                "<figure class=\"diagram\"><img alt=\"Mermaid diagram\" \
                 src=\"data:image/svg+xml;base64,{}\"></figure>",
                STANDARD.encode(bytes)
            ))
        } else {
            Err("This Mermaid diagram could not be rendered. Its source is shown below.")
        };
        merman_buffer_free(result.data);
        output
    }
}

fn allowed_link(destination: &str) -> bool {
    let normalized = destination.trim().to_ascii_lowercase();
    !normalized.chars().any(char::is_control)
        && (normalized.starts_with("https://")
            || normalized.starts_with("http://")
            || normalized.starts_with("mailto:")
            || normalized.starts_with('#'))
}

pub fn render(source: &str) -> String {
    if source.len() > MAX_SOURCE_BYTES {
        return notice(
            "This document is larger than the 2 MiB Quick Look limit. Open it in Linefold.",
        );
    }
    if source.trim().is_empty() {
        return notice("This Markdown document is empty.");
    }
    let options = Options::ENABLE_TABLES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_FOOTNOTES
        | Options::ENABLE_YAML_STYLE_METADATA_BLOCKS
        | Options::ENABLE_GFM;
    let mut parser = Parser::new_ext(source, options).peekable();
    let mut events = Vec::new();
    let mut link_stack = Vec::new();
    let mut diagrams = 0;
    let mut generated_bytes = 0;
    let mut heading: Option<(usize, String)> = None;
    let mut heading_ids = HashSet::new();
    let mut heading_suffixes = HashMap::new();
    while let Some(event) = parser.next() {
        match &event {
            Event::Start(Tag::Heading { .. }) => heading = Some((events.len(), String::new())),
            Event::Text(text) | Event::Code(text) => {
                if let Some((_, title)) = &mut heading {
                    title.push_str(text);
                }
            }
            Event::End(TagEnd::Heading(_)) => {
                if let Some((index, title)) = heading.take() {
                    let slug: String = title
                        .to_lowercase()
                        .chars()
                        .filter_map(|ch| {
                            if ch.is_whitespace() {
                                Some('-')
                            } else if ch.is_alphanumeric() || ch == '-' || ch == '_' {
                                Some(ch)
                            } else {
                                None
                            }
                        })
                        .collect();
                    let slug = if slug.is_empty() {
                        "section".to_owned()
                    } else {
                        slug
                    };
                    let suffix = heading_suffixes.entry(slug.clone()).or_insert(0);
                    let mut unique = if *suffix == 0 {
                        slug.clone()
                    } else {
                        format!("{slug}-{suffix}")
                    };
                    while !heading_ids.insert(unique.clone()) {
                        *suffix += 1;
                        unique = format!("{slug}-{suffix}");
                    }
                    *suffix += 1;
                    if let Event::Start(Tag::Heading { id, .. }) = &mut events[index] {
                        *id = Some(unique.into());
                    }
                }
            }
            _ => {}
        }
        match event {
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(ref language)))
                if language
                    .split_whitespace()
                    .next()
                    .is_some_and(|name| name.eq_ignore_ascii_case("mermaid")) =>
            {
                let mut code = String::new();
                for inner in parser.by_ref() {
                    match inner {
                        Event::End(TagEnd::CodeBlock) => break,
                        Event::Text(text) => code.push_str(&text),
                        _ => {}
                    }
                }
                let markup = diagram(&code, diagrams).unwrap_or_else(|error| {
                    format!(
                        "<p class=\"notice\">{}</p><pre><code>{}</code></pre>",
                        escape(error),
                        escape(&code)
                    )
                });
                generated_bytes += markup.len();
                if generated_bytes > MAX_HTML_BYTES {
                    return notice(
                        "This document exceeds the Quick Look preview limit. Open it in Linefold.",
                    );
                }
                events.push(Event::Html(markup.into()));
                diagrams += 1;
            }
            // User HTML is text, never executable markup. This also prevents a
            // document from changing our styles, CSP, base URL or image policy.
            Event::Html(text) | Event::InlineHtml(text) => events.push(Event::Text(text)),
            Event::Start(Tag::Link { ref dest_url, .. }) => {
                let allowed = allowed_link(dest_url);
                link_stack.push(allowed);
                if allowed {
                    events.push(event);
                }
            }
            Event::End(TagEnd::Link) => {
                if link_stack.pop().unwrap_or(false) {
                    events.push(event);
                }
            }
            Event::Start(Tag::Image { .. }) => {
                events.push(Event::Html(CowStr::Borrowed(
                    "<span class=\"image-placeholder\">Image: ",
                )));
                // Image descriptions are plain text; never render nested links,
                // HTML or additional images as children of this placeholder.
                let mut depth = 1;
                for inner in parser.by_ref() {
                    match inner {
                        Event::Start(Tag::Image { .. }) => depth += 1,
                        Event::End(TagEnd::Image) => {
                            depth -= 1;
                            if depth == 0 {
                                break;
                            }
                        }
                        Event::Text(text) | Event::Code(text) => events.push(Event::Text(text)),
                        Event::SoftBreak | Event::HardBreak => events.push(Event::Text(" ".into())),
                        _ => {}
                    }
                }
                events.push(Event::Html(" (not loaded in Quick Look)</span>".into()));
            }
            _ => events.push(event),
        }
    }
    let mut body = String::new();
    html::push_html(&mut body, events.into_iter());
    if body.len() > MAX_HTML_BYTES {
        return notice("This document exceeds the Quick Look preview limit. Open it in Linefold.");
    }
    page(&body)
}

/// Returns an owned UTF-8 buffer. The caller must release it exactly once with
/// linefold_preview_free. No Rust panic crosses the C boundary.
///
/// # Safety
/// For `len <= MAX_SOURCE_BYTES`, `source` must point to `len` readable bytes,
/// or be null when `len` is zero. Oversized input is rejected without reading it.
#[no_mangle]
pub unsafe extern "C" fn linefold_preview_render(source: *const u8, len: usize) -> PreviewBuffer {
    let output = catch_unwind(|| {
        if len > MAX_SOURCE_BYTES {
            return notice(
                "This document is larger than the 2 MiB Quick Look limit. Open it in Linefold.",
            );
        }
        if source.is_null() {
            return notice(if len == 0 {
                "This Markdown document is empty."
            } else {
                "Unable to read this document."
            });
        }
        match std::str::from_utf8(slice::from_raw_parts(source, len)) {
            Ok(text) => render(text),
            Err(_) => notice("This document is not valid UTF-8 text."),
        }
    })
    .unwrap_or_else(|_| notice("Unable to render this document. Open it in Linefold."));
    let mut bytes = output.into_bytes().into_boxed_slice();
    let result = PreviewBuffer {
        data: bytes.as_mut_ptr(),
        len: bytes.len(),
    };
    std::mem::forget(bytes);
    result
}

/// # Safety
/// `buffer` must be a live result from linefold_preview_render, freed only once.
#[no_mangle]
pub unsafe extern "C" fn linefold_preview_free(buffer: PreviewBuffer) {
    if !buffer.data.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
            buffer.data,
            buffer.len,
        )));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markdown_structure_and_unicode() {
        let html = render("# 中文标题\n\n**粗体** 和 ~~删除~~\n\n- [x] 完成\n- [ ] 待办\n\n| 项目 | 状态 |\n| --- | --- |\n| 预览 | 支持 |\n\n> 引用\n\n```rust\nlet x = 1 < 2;\n```\n");
        for expected in [
            "<h1 id=\"中文标题\">中文标题</h1>",
            "<strong>粗体</strong>",
            "<del>删除</del>",
            "checked=\"\"",
            "<table>",
            "<blockquote>",
            "1 &lt; 2",
        ] {
            assert!(html.contains(expected), "missing {expected}");
        }
    }

    #[test]
    fn untrusted_html_links_and_images_are_inert() {
        let html = render("<script>alert(1)</script>\n\n[bad](javascript:alert%281%29) [file](file:///etc/passwd) [good](https://example.com)\n\n![外部图片](https://example.com/tracker.png)\n\n<iframe src=\"https://example.com\"></iframe>");
        assert!(!html.contains("<script>"));
        assert!(!html.contains("<iframe"));
        assert!(!html.contains("href=\"javascript:"));
        assert!(!html.contains("href=\"file:"));
        assert!(!html.contains("<img"));
        assert!(html.contains("href=\"https://example.com\""));
        assert!(html.contains("外部图片"));
        assert!(html.contains("default-src 'none'"));
    }

    #[test]
    fn mermaid_uses_real_native_svg_and_keeps_surrounding_text() {
        let html = render("Before\n\n```mermaid\nflowchart LR\n A[开始] --> B[完成]\n```\n\nAfter");
        assert!(html.contains("<p>Before</p>"));
        assert!(html.contains("data:image/svg+xml;base64,"), "{html}");
        let encoded = html
            .split("base64,")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap();
        let svg = String::from_utf8(STANDARD.decode(encoded).unwrap()).unwrap();
        assert!(svg.contains("<svg"));
        assert!(svg.contains("开始"));
        assert!(svg.contains("marker"));
        assert!(html.contains("<p>After</p>"));
    }

    #[test]
    fn broken_diagrams_preserve_source_and_rest_of_document() {
        let html = render("```mermaid\nnot a diagram <script>\n```\n\n# Still visible");
        assert!(html.contains("could not be rendered"));
        assert!(html.contains("not a diagram &lt;script&gt;"));
        assert!(html.contains(">Still visible</h1>"));
    }

    #[test]
    fn limits_and_empty_documents_are_explained() {
        assert!(render("").contains("document is empty"));
        assert!(render(&"x".repeat(MAX_SOURCE_BYTES + 1)).contains("2 MiB"));
        assert!(diagram("flowchart LR\nA-->B", MAX_DIAGRAMS).is_err());
        assert!(diagram(&"x".repeat(128 * 1024 + 1), 0).is_err());
    }

    #[test]
    fn ffi_result_can_be_read_and_released() {
        unsafe {
            for bytes in [b"# Preview".as_slice(), &[0xff], &[]] {
                let buffer = linefold_preview_render(bytes.as_ptr(), bytes.len());
                assert!(
                    std::str::from_utf8(slice::from_raw_parts(buffer.data, buffer.len))
                        .unwrap()
                        .contains("<!doctype html>")
                );
                linefold_preview_free(buffer);
            }
        }
    }

    #[test]
    fn front_matter_is_hidden_and_headings_have_unique_link_targets() {
        let html = render("---\ntitle: Metadata only\n---\n\n# 中文标题\n\n[跳转](#中文标题)\n\n# 中文标题\n\n---\n\n正文");
        assert!(!html.contains("Metadata only"));
        assert!(html.contains("id=\"中文标题\""));
        assert!(html.contains("id=\"中文标题-1\""));
        assert!(html.contains("href=\"#%E4%B8%AD%E6%96%87%E6%A0%87%E9%A2%98\""));
        assert!(html.contains("<hr />"));
        assert!(html.contains("正文"));
        assert!(render("---\ntitle: Unclosed metadata").contains("Unclosed metadata"));
    }

    #[test]
    fn repeated_heading_suffixes_do_not_restart_at_one() {
        let source = format!("# same-1\n\n{}", "# same\n\n".repeat(10_000));
        let html = render(&source);
        assert_eq!(html.matches("<h1 id=").count(), 10_001);
        assert_eq!(html.matches("id=\"same-1\"").count(), 1);
        assert!(html.contains("id=\"same-10000\""));
    }
}
