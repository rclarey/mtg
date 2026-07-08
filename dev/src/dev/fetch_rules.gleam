import gleam/bool
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

type Section =
  #(String, String)

pub fn main() -> Nil {
  case fetch_and_split_rules() {
    Ok(_) -> io.println("Success!")
    Error(e) -> io.println("Error: " <> e)
  }
}

/// Fetches the MTG comprehensive rules from the official website,
/// splits them into sections, and saves them as markdown files.
pub fn fetch_and_split_rules() -> Result(Nil, String) {
  use html <- result.try(fetch("https://magic.wizards.com/en/rules"))
  use txt_url <- result.try(extract_txt_link(html))
  use rules_content <- result.try(fetch(txt_url))
  // fix new lines and drop BOM char from beginning
  let rules_content =
    string.replace(rules_content, each: "\r\n", with: "\n")
    |> string.crop(before: "Magic")

  let sections = split_into_sections(rules_content)

  use _ <- result.try(create_rules_directory())

  // Save each section
  use _ <- result.try(
    sections
    |> list.try_each(fn(section) {
      let #(filename, content) = section
      save_section(filename, content)
    }),
  )

  save_section("README.md", "Retrieved from " <> txt_url)
}

/// Fetches string content from the given URL
fn fetch(url: String) -> Result(String, String) {
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { "Failed to create request for: " <> url }),
  )

  use response <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { "Failed to fetch from: " <> url }),
  )

  Ok(response.body)
}

/// Extracts the TXT file URL from the HTML content
fn extract_txt_link(html: String) -> Result(String, String) {
  // Look for links containing "MagicCompRules" and ending with ".txt"
  case find_txt_url_in_html(html) {
    Ok(url) -> Ok(url)
    Error(_) -> Error("Could not find comprehensive rules TXT link in HTML")
  }
}

/// Helper to find TXT URL in HTML
fn find_txt_url_in_html(html: String) -> Result(String, Nil) {
  html
  |> string.split("href=\"")
  |> list.find(fn(part) {
    string.contains(part, "MagicCompRules") && string.contains(part, ".txt")
  })
  |> result.map(fn(part) {
    part
    |> string.split("\"")
    |> list.first
    |> result.unwrap("")
    |> string.replace(" ", "%20")
  })
}

/// Splits the rules content into sections
fn split_into_sections(content: String) -> List(#(String, String)) {
  let blocks =
    string.split(content, "\n\n")
    |> list.map(string.trim)
    |> list.filter(fn(s) { s != "" })

  let #(preamble_section, blocks) = get_preamble(blocks)

  // Split remaining content into numbered sections
  let numbered_sections = get_numbered_sections(blocks)

  [preamble_section, ..numbered_sections]
}

fn get_preamble(blocks: List(String)) -> #(Section, List(String)) {
  let #(preamble_blocks, blocks) =
    list.split_while(blocks, fn(l) { l != "Credits" })
  // drop "Credits" block
  let blocks = list.drop(blocks, 1)
  let #(blocks, credits_blocks) =
    list.split_while(blocks, fn(l) { l != "Credits" })

  let preamble_content =
    list.append(preamble_blocks, credits_blocks)
    |> list.flat_map(string.split(_, "\n"))
    |> list.map(string.trim)
    |> list.filter(fn(l) { l != "" })
    |> format_preamble_as_markdown([])

  #(#("000-contents.md", preamble_content), blocks)
}

fn not_section_start(line: String) {
  use <- bool.guard(line == "Glossary", False)
  string.split_once(line, ". ")
  |> result.map(fn(res) {
    let #(x, _) = res
    case string.length(x) {
      3 -> False
      _ -> True
    }
  })
  |> result.unwrap(True)
}

/// Recursively extracts numbered sections from the content, tracking which sections we've seen
fn get_numbered_sections(blocks: List(String)) -> List(Section) {
  // drop lines leading up to 3 digit number section
  let blocks = list.drop_while(blocks, not_section_start)
  get_numbered_sections_loop(blocks, [])
}

fn get_numbered_sections_loop(
  blocks: List(String),
  sections: List(Section),
) -> List(Section) {
  case blocks {
    [] -> list.reverse(sections)
    [heading, ..blocks] -> {
      let #(section_blocks, blocks) =
        list.split_while(blocks, not_section_start)
      let section_content = case heading {
        "Glossary" ->
          format_glossary_as_markdown([heading, ..section_blocks], [])
        _ -> format_section_as_markdown([heading, ..section_blocks], [])
      }
      let section = #(create_filename(heading), section_content)
      get_numbered_sections_loop(blocks, [section, ..sections])
    }
  }
}

/// Creates a filename from section heading line
fn create_filename(line: String) -> String {
  let #(num, title) = case line {
    "Glossary" -> #("000", "glossary")
    _ -> {
      let assert Ok(res) = string.split_once(line, ". ")
      res
    }
  }
  let kebab_title =
    title
    |> string.lowercase
    |> string.replace(" ", "-")
    |> string.replace(",", "")
    |> string.replace("'", "")
    |> string.replace("(", "")
    |> string.replace(")", "")
    |> string.replace(".", "")
    |> string.replace("/", "-")
    |> string.replace("\"", "")

  num <> "-" <> kebab_title <> ".md"
}

type MarkdownNode {
  H1(String)
  H2(String)
  H3(String)
  ListItem(char: String, content: String)
  Text(String)
}

fn format_preamble_as_markdown(
  lines: List(String),
  nodes: List(MarkdownNode),
) -> String {
  case lines {
    [] -> render_markdown(list.reverse(nodes))
    [line, ..rest] -> {
      let node = case line {
        "Magic: The Gathering Comp" <> _ -> H1(line)
        "Introduction" | "Contents" | "Credits" -> H2(line)
        "Glossary" -> H3("[Glossary](./000-glossary.md)")
        _ -> {
          case string.split(line, ". ") {
            [x, _] ->
              case string.length(x) {
                1 -> H3(line)
                3 ->
                  ListItem(
                    "-",
                    "[" <> line <> "](./" <> create_filename(line) <> ")",
                  )
                _ -> Text(line)
              }
            _ -> Text(line)
          }
        }
      }
      format_preamble_as_markdown(rest, [node, ..nodes])
    }
  }
}

fn format_section_as_markdown(
  blocks: List(String),
  nodes: List(MarkdownNode),
) -> String {
  case blocks {
    [] -> render_markdown(list.reverse(nodes))
    [block, ..rest] -> {
      let lines =
        string.split(block, "\n")
        |> list.map(string.trim)
        |> list.filter(fn(l) { l != "" })
      let more_nodes = case lines {
        [line] -> format_section_subrule(line)
        [line, ..rest] ->
          list.map(rest, Text) |> list.append(format_section_subrule(line))
        _ -> panic as "???"
      }
      format_section_as_markdown(rest, list.append(more_nodes, nodes))
    }
  }
}

type RuleType {
  MainRule
  SubRule
  Lettered
  NotARule
}

fn is_digit(c: String) -> Bool {
  string.contains("0123456789", c)
}

fn is_digit_or_period(c: String) -> Bool {
  is_digit(c) || c == "."
}

fn classify_line(line: String) -> #(RuleType, String, String) {
  case string.split_once(line, " ") {
    Ok(#(raw_rule_num, content)) -> {
      let clean = case string.ends_with(raw_rule_num, ".") {
        True -> string.drop_end(raw_rule_num, 1)
        False -> raw_rule_num
      }
      let first_three = string.slice(clean, 0, 3)
      let is_3_digits =
        string.length(first_three) == 3
        && list.all(string.to_graphemes(first_three), is_digit)
      case is_3_digits {
        False -> #(NotARule, "", line)
        True -> {
          let assert Ok(#(last_char, _)) =
            string.reverse(clean) |> string.pop_grapheme()
          case string.contains("abcdefghijklmnopqrstuvwxyz", last_char) {
            True -> {
              let prefix = string.drop_end(clean, 1)
              case string.length(prefix) > 3
                && list.all(string.to_graphemes(prefix), is_digit_or_period) {
                True -> #(Lettered, clean, content)
                False -> #(NotARule, "", line)
              }
            }
            False ->
              case string.length(clean) {
                3 -> #(MainRule, clean, content)
                _ ->
                  case list.all(string.to_graphemes(clean), is_digit_or_period) {
                    True -> #(SubRule, clean, content)
                    False -> #(NotARule, "", line)
                  }
              }
          }
        }
      }
    }
    _ -> #(NotARule, "", line)
  }
}

fn format_section_subrule(line: String) {
  let #(rule_type, rule_num, content) = classify_line(line)
  case rule_type {
    MainRule -> [H1(line)]
    SubRule -> [Text(content), H2(rule_num)]
    Lettered -> {
      let assert Ok(#(letter, _)) =
        string.reverse(rule_num) |> string.pop_grapheme()
      [ListItem(letter, content)]
    }
    NotARule -> [Text(line)]
  }
}

fn format_glossary_as_markdown(
  blocks: List(String),
  nodes: List(MarkdownNode),
) -> String {
  case blocks {
    [] -> render_markdown(list.reverse(nodes))
    ["Glossary", ..rest] ->
      format_glossary_as_markdown(rest, [H1("Glossary"), ..nodes])
    [block, ..rest] -> {
      let assert [term, ..definition_lines] =
        string.split(block, "\n")
        |> list.map(string.trim)
        |> list.filter(fn(l) { l != "" })
      let nodes = [H3(term), ..nodes]
      let definition_nodes =
        list.reverse(definition_lines)
        |> list.map(fn(line) {
          case string.split_once(line, ". ") {
            Ok(#(x, text)) ->
              case string.length(x) {
                1 -> {
                  let assert Ok(#(num, _)) = string.pop_grapheme(x)
                  ListItem(num, text)
                }
                _ -> Text(line)
              }
            _ -> Text(line)
          }
        })

      format_glossary_as_markdown(rest, list.append(definition_nodes, nodes))
    }
  }
}

fn render_markdown(nodes: List(MarkdownNode)) -> String {
  // append a dummy Text node at the end so we render all real nodes
  list.window_by_2(list.append(nodes, [Text("")]))
  |> list.map(fn(pair) {
    case pair {
      #(H1(text), _) -> "# " <> text <> "\n"
      #(H2(text), _) -> "## " <> text <> "\n"
      #(H3(text), _) -> "### " <> text <> "\n"
      #(ListItem(char, text), ListItem(_, _)) -> {
        case char {
          "-" -> "- " <> text
          "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
            char <> ". " <> text
          _ -> "- " <> char <> ". " <> text
        }
      }
      #(ListItem(char, text), _) -> {
        case char {
          "-" -> "- " <> text <> "\n"
          "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
            char <> ". " <> text <> "\n"
          _ -> "- " <> char <> ". " <> text <> "\n"
        }
      }
      #(Text(text), _) -> text <> "\n"
    }
  })
  |> string.join("\n")
}

const rules_dir = "../core/rules"

/// Creates the rules directory if it doesn't exist
fn create_rules_directory() -> Result(Nil, String) {
  simplifile.create_directory(rules_dir)
  |> result.map_error(fn(_) { "Failed to create rules directory" })
  |> result.or(Ok(Nil))
}

/// Saves a section to a file
fn save_section(filename: String, content: String) -> Result(Nil, String) {
  let filepath = rules_dir <> "/" <> filename

  simplifile.write(filepath, content)
  |> result.map_error(fn(_) { "Failed to write file: " <> filepath })
}
