// Jupyter notebook -> Markdown.
//
// A notebook is JSON with an ordered list of cells. Markdown cells pass
// through; code cells become fenced blocks so headings and code survive into
// the section tree. Output cells are dropped on purpose: they are usually
// noise for documentation retrieval and can be huge (tables, images, tracebacks).

///|
fn cell_source(cell : Json) -> String {
  match cell {
    Json::Object(obj) =>
      match obj.get("source") {
        Some(Json::Array(lines)) => {
          let sb = StringBuilder::StringBuilder()
          for line in lines {
            match line {
              Json::String(s) => sb.write_string(s)
              _ => ()
            }
          }
          sb.to_string()
        }
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn cell_type(cell : Json) -> String {
  match cell {
    Json::Object(obj) =>
      match obj.get("cell_type") {
        Some(Json::String(t)) => t
        _ => ""
      }
    _ => ""
  }
}

///|
fn notebook_language(root : Json) -> String {
  match root {
    Json::Object(obj) =>
      match obj.get("metadata") {
        Some(Json::Object(meta)) =>
          match meta.get("kernelspec") {
            Some(Json::Object(spec)) =>
              match spec.get("language") {
                Some(Json::String(lang)) => lang
                _ => ""
              }
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
/// Convert a `.ipynb` document to Markdown. Returns `None` when the JSON is
/// malformed, so callers can fall back instead of indexing an empty document.
pub fn ipynb_to_markdown(source : String) -> String? {
  let root = @json.parse(source) catch { _ => return None }
  let cells = match root {
    Json::Object(obj) =>
      match obj.get("cells") {
        Some(Json::Array(items)) => items
        _ => return None
      }
    _ => return None
  }
  let language = notebook_language(root)
  let out = StringBuilder::StringBuilder()
  for cell in cells {
    let body = cell_source(cell)
    if body.trim() == "" {
      continue
    }
    match cell_type(cell) {
      "markdown" => {
        if out.to_string() != "" {
          out.write_string("\n\n")
        }
        out.write_string(body)
      }
      "code" => {
        if out.to_string() != "" {
          out.write_string("\n\n")
        }
        out.write_string("```\{language}\n")
        out.write_string(body)
        if !body.has_suffix("\n") {
          out.write_char('\n')
        }
        out.write_string("```")
      }
      _ => ()
    }
  }
  Some(out.to_string())
}
