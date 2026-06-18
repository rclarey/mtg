import gleam/int
import gleam/list
import gleam/string

fn escape_like(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("'", "''")
  |> string.replace("%", "\\%")
  |> string.replace("_", "\\_")
}

fn escape_sql(s: String) -> String {
  string.replace(s, "'", "''")
}

pub type Token {
  Word(String)
  Phrase(String)
  Regex(String)
  Neg
  OrKeyword
  LParen
  RParen
  Op(String, Compare, String)
}

pub type Compare {
  Colon
  Eq
  Gt
  Lt
  Gte
  Lte
  Neq
}

pub type Expr {
  And(Expr, Expr)
  Or(Expr, Expr)
  Not(Expr)
  Group(Expr)
  Leaf(Term)
}

pub type Term {
  Name(String)
  PhraseSearch(String)
  RegexSearch(String)
  OpSearch(OpName, Compare, String)
}

pub type OpName {
  Color
  ColorIdentity
  Type
  Oracle
  FullOracle
  ManaValue
  Power
  Toughness
  Loyalty
  Rarity
  Set
  Format
  Is
  Has
  Year
  Artist
  Flavor
  Watermark
  Keyword
  Mana
  Border
  Frame
  Game
  Block
  SetType
  CollectorNumber
  Devotion
  Produces
  EDHRECRank
  USD
  EUR
  Tix
  Prints
  Sets
  Date
  Unknown(String)
}

pub fn tokenize(input: String) -> Result(List(Token), String) {
  tokenize_loop(string.to_graphemes(input), [])
}

fn tokenize_loop(
  chars: List(String),
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Ok(list.reverse(tokens))
    [c, ..rest] -> {
      case c {
        " " | "\n" | "\r" | "\t" -> tokenize_loop(rest, tokens)
        "(" -> tokenize_loop(rest, [LParen, ..tokens])
        ")" -> tokenize_loop(rest, [RParen, ..tokens])
        "\"" -> tokenize_phrase(rest, "", tokens)
        "/" -> tokenize_regex(rest, "", tokens)
        "-" -> tokenize_after_dash(rest, tokens)
        _ -> tokenize_word(chars, "", tokens)
      }
    }
  }
}

fn tokenize_after_dash(
  chars: List(String),
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Ok(list.reverse([Word("-"), ..tokens]))
    [" ", ..rest] -> {
      tokenize_loop(rest, [Neg, ..tokens])
    }
    _ -> {
      tokenize_loop(chars, [Neg, ..tokens])
    }
  }
}

fn read_phrase(chars: List(String)) -> Result(#(String, List(String)), String) {
  read_phrase_loop(chars, "")
}

fn read_phrase_loop(
  chars: List(String),
  acc: String,
) -> Result(#(String, List(String)), String) {
  case chars {
    [] -> Error("Unterminated string literal")
    ["\"", ..rest] -> Ok(#(acc, rest))
    [c, ..rest] -> read_phrase_loop(rest, acc <> c)
  }
}

fn tokenize_phrase(
  chars: List(String),
  acc: String,
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Error("Unterminated string literal")
    ["\"", ..rest] -> tokenize_loop(rest, [Phrase(acc), ..tokens])
    [c, ..rest] -> tokenize_phrase(rest, acc <> c, tokens)
  }
}

fn tokenize_regex(
  chars: List(String),
  acc: String,
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Error("Unterminated regex literal")
    ["/", ..rest] -> tokenize_loop(rest, [Regex(acc), ..tokens])
    [c, ..rest] -> tokenize_regex(rest, acc <> c, tokens)
  }
}

fn tokenize_word(
  chars: List(String),
  acc: String,
  tokens: List(Token),
) -> Result(List(Token), String) {
  case chars {
    [] -> Ok(list.reverse([make_word_or_op(acc), ..tokens]))
    [c, ..rest] -> {
      case c {
        "\"" -> {
          case string.split_once(acc, ":") {
            Ok(#(key, "")) -> {
              case read_phrase(rest) {
                Ok(#(value, remaining)) ->
                  tokenize_loop(remaining, [
                    Op(string.lowercase(key), Colon, value),
                    ..tokens
                  ])
                Error(e) -> Error(e)
              }
            }
            _ -> tokenize_loop(chars, [make_word_or_op(acc), ..tokens])
          }
        }
        " " | "\n" | "\r" | "\t" | "(" | ")" ->
          tokenize_loop(chars, [make_word_or_op(acc), ..tokens])
        _ -> tokenize_word(rest, acc <> c, tokens)
      }
    }
  }
}

fn make_word_or_op(word: String) -> Token {
  case string.lowercase(word) {
    "or" -> OrKeyword
    _ -> {
      case parse_operator(word) {
        Ok(token) -> token
        Error(_) -> Word(word)
      }
    }
  }
}

fn parse_operator(word: String) -> Result(Token, Nil) {
  let comparators = [">=", "<=", "!=", ":", "=", ">", "<"]

  let found = list.find(comparators, fn(comp) { string.contains(word, comp) })

  case found {
    Ok(comp) -> {
      case string.split_once(word, comp) {
        Ok(#(key, value)) if key != "" && value != "" ->
          Ok(Op(string.lowercase(key), compare_from_string(comp), value))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn compare_from_string(s: String) -> Compare {
  case s {
    ":" -> Colon
    "=" -> Eq
    ">" -> Gt
    "<" -> Lt
    ">=" -> Gte
    "<=" -> Lte
    "!=" -> Neq
    _ -> Colon
  }
}

fn op_name_from_string(s: String) -> OpName {
  case s {
    "c" | "color" -> Color
    "id" | "identity" -> ColorIdentity
    "t" | "type" -> Type
    "o" | "oracle" -> Oracle
    "fo" | "fulloracle" -> FullOracle
    "mv" | "manavalue" | "cmc" -> ManaValue
    "pow" | "power" -> Power
    "tou" | "toughness" -> Toughness
    "loy" | "loyalty" -> Loyalty
    "r" | "rarity" -> Rarity
    "e" | "s" | "set" | "edition" -> Set
    "f" | "format" -> Format
    "is" -> Is
    "has" -> Has
    "year" -> Year
    "a" | "artist" -> Artist
    "ft" | "flavor" -> Flavor
    "wm" | "watermark" -> Watermark
    "kw" | "keyword" -> Keyword
    "m" | "mana" -> Mana
    "border" -> Border
    "frame" -> Frame
    "game" -> Game
    "b" | "block" -> Block
    "st" | "settype" -> SetType
    "cn" | "number" | "collectornumber" -> CollectorNumber
    "devotion" -> Devotion
    "produces" -> Produces
    "edhrecrank" | "edhrec" -> EDHRECRank
    "usd" -> USD
    "eur" -> EUR
    "tix" -> Tix
    "prints" -> Prints
    "sets" -> Sets
    "date" -> Date
    _ -> Unknown(s)
  }
}

pub fn parse(tokens: List(Token)) -> Result(Expr, String) {
  case tokens {
    [] -> Error("Empty query")
    _ -> {
      let #(expr, _rest) = parse_or(tokens)
      Ok(expr)
    }
  }
}

fn parse_or(tokens: List(Token)) -> #(Expr, List(Token)) {
  let #(left, tokens) = parse_and(tokens)

  case tokens {
    [OrKeyword, ..rest] -> {
      let #(right, remaining) = parse_or(rest)
      #(Or(left, right), remaining)
    }
    _ -> #(left, tokens)
  }
}

fn parse_and(tokens: List(Token)) -> #(Expr, List(Token)) {
  let #(left, tokens) = parse_unary(tokens)

  case tokens {
    [] -> #(left, tokens)
    [OrKeyword, ..] -> #(left, tokens)
    [RParen, ..] -> #(left, tokens)
    _ -> {
      let #(right, rest) = parse_and(tokens)
      #(And(left, right), rest)
    }
  }
}

fn parse_unary(tokens: List(Token)) -> #(Expr, List(Token)) {
  case tokens {
    [Neg, ..rest] -> {
      let #(expr, remaining) = parse_unary(rest)
      #(Not(expr), remaining)
    }
    _ -> parse_primary(tokens)
  }
}

fn parse_primary(tokens: List(Token)) -> #(Expr, List(Token)) {
  case tokens {
    [LParen, ..rest] -> {
      let #(expr, rest) = parse_or(rest)
      case rest {
        [RParen, ..remaining] -> #(Group(expr), remaining)
        _ -> #(expr, rest)
      }
    }
    [token, ..rest] -> #(Leaf(token_to_term(token)), rest)
    [] -> #(Leaf(Name("")), [])
  }
}

fn token_to_term(token: Token) -> Term {
  case token {
    Word(s) -> Name(s)
    Phrase(s) -> PhraseSearch(s)
    Regex(s) -> RegexSearch(s)
    Op(key, comp, value) -> OpSearch(op_name_from_string(key), comp, value)
    OrKeyword -> Name("or")
    Neg -> Name("-")
    LParen -> Name("(")
    RParen -> Name(")")
  }
}

pub fn to_where_clause(expr: Expr) -> String {
  expr_to_sql(expr)
}

fn expr_to_sql(expr: Expr) -> String {
  case expr {
    And(left, right) ->
      "(" <> expr_to_sql(left) <> " AND " <> expr_to_sql(right) <> ")"
    Or(left, right) ->
      "(" <> expr_to_sql(left) <> " OR " <> expr_to_sql(right) <> ")"
    Not(inner) -> "NOT (" <> expr_to_sql(inner) <> ")"
    Group(inner) -> expr_to_sql(inner)
    Leaf(term) -> term_to_sql(term)
  }
}

fn term_to_sql(term: Term) -> String {
  case term {
    Name(text) -> "name LIKE '%" <> escape_like(text) <> "%' ESCAPE '\\'"
    PhraseSearch(text) ->
      "name LIKE '%" <> escape_like(text) <> "%' ESCAPE '\\'"
    RegexSearch(pattern) -> "name REGEXP '" <> escape_sql(pattern) <> "'"
    OpSearch(Color, comp, value) -> color_sql(value, "color_identity", comp)
    OpSearch(ColorIdentity, comp, value) ->
      color_sql(value, "color_identity", comp)
    OpSearch(Type, _, value) ->
      "type_line LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(Oracle, _, value) ->
      "oracle_text LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(FullOracle, _, value) ->
      "(oracle_text LIKE '%"
      <> escape_like(value)
      <> "%' ESCAPE '\\' OR flavor_text LIKE '%"
      <> escape_like(value)
      <> "%' ESCAPE '\\')"
    OpSearch(ManaValue, comp, value) -> numeric_field_sql("cmc", comp, value)
    OpSearch(Power, comp, value) -> numeric_text_sql("power", comp, value)
    OpSearch(Toughness, comp, value) ->
      numeric_text_sql("toughness", comp, value)
    OpSearch(Loyalty, comp, value) -> numeric_text_sql("loyalty", comp, value)
    OpSearch(Rarity, _, value) -> "rarity = '" <> escape_sql(value) <> "'"
    OpSearch(Set, _, value) -> "set = '" <> escape_sql(value) <> "'"
    OpSearch(Format, _, value) ->
      "legalities LIKE '%\"" <> escape_sql(value) <> "\":\"legal\"%'"
    OpSearch(Is, _, value) -> is_to_sql(string.lowercase(value))
    OpSearch(Has, _, value) -> has_to_sql(string.lowercase(value))
    OpSearch(Year, comp, value) -> year_to_sql(comp, value)
    OpSearch(Artist, _, value) ->
      "artist LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(Flavor, _, value) ->
      "flavor_text LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(Watermark, _, value) -> "watermark = '" <> escape_sql(value) <> "'"
    OpSearch(Keyword, _, value) ->
      "keywords LIKE '%\"" <> escape_sql(value) <> "\"%'"
    OpSearch(Mana, _, value) ->
      "mana_cost LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(Border, _, value) -> "border_color = '" <> escape_sql(value) <> "'"
    OpSearch(Frame, _, value) -> "frame = '" <> escape_sql(value) <> "'"
    OpSearch(Game, _, value) -> "games LIKE '%\"" <> escape_sql(value) <> "\"%'"
    OpSearch(Block, _, value) -> "set = '" <> escape_sql(value) <> "'"
    OpSearch(SetType, _, value) -> "set_type = '" <> escape_sql(value) <> "'"
    OpSearch(CollectorNumber, comp, value) ->
      numeric_text_sql("collector_number", comp, value)
    OpSearch(Devotion, _, value) ->
      "mana_cost LIKE '%" <> escape_like(value) <> "%' ESCAPE '\\'"
    OpSearch(Produces, comp, value) -> color_sql(value, "produced_mana", comp)
    OpSearch(EDHRECRank, comp, value) ->
      numeric_field_sql("edhrec_rank", comp, value)
    OpSearch(USD, comp, value) -> price_sql("usd", comp, value)
    OpSearch(EUR, comp, value) -> price_sql("eur", comp, value)
    OpSearch(Tix, comp, value) -> price_sql("tix", comp, value)
    OpSearch(Prints, _comp, _value) -> "1 = 1"
    OpSearch(Sets, _, _) -> "1 = 1"
    OpSearch(Date, comp, value) ->
      "released_at " <> comp_sql(comp) <> " '" <> escape_sql(value) <> "'"
    OpSearch(Unknown(col), comp, value) ->
      col <> " " <> comp_sql(comp) <> " '" <> escape_sql(value) <> "'"
  }
}

fn comp_sql(comp: Compare) -> String {
  case comp {
    Colon -> "="
    Eq -> "="
    Gt -> ">"
    Lt -> "<"
    Gte -> ">="
    Lte -> "<="
    Neq -> "!="
  }
}

fn numeric_field_sql(field: String, comp: Compare, value: String) -> String {
  case int.parse(value) {
    Ok(n) -> field <> " " <> comp_sql(comp) <> " " <> int.to_string(n)
    _ -> "1 = 0"
  }
}

fn numeric_text_sql(field: String, comp: Compare, value: String) -> String {
  case int.parse(value) {
    Ok(n) ->
      "CAST(COALESCE("
      <> field
      <> ", '0') AS REAL) "
      <> comp_sql(comp)
      <> " "
      <> int.to_string(n)
    _ -> "1 = 0"
  }
}

fn color_sql(value: String, field: String, comp: Compare) -> String {
  let chars = string.to_graphemes(string.uppercase(value))

  let conditions =
    list.filter_map(chars, fn(c) {
      case c {
        "W" | "U" | "B" | "R" | "G" -> Ok(field <> " LIKE '%\"" <> c <> "\"%'")
        _ -> Error(Nil)
      }
    })

  case comp {
    Eq -> {
      case conditions {
        [] -> field <> " LIKE '%\"" <> string.uppercase(value) <> "\"%'"
        _ -> {
          let all = ["W", "U", "B", "R", "G"]
          let exclude =
            list.filter_map(all, fn(c) {
              case list.any(chars, fn(x) { x == c }) {
                True -> Error(Nil)
                False -> Ok(field <> " NOT LIKE '%\"" <> c <> "\"%'")
              }
            })
          string.join(list.append(conditions, exclude), " AND ")
        }
      }
    }
    _ -> {
      case conditions {
        [] -> field <> " LIKE '%\"" <> string.uppercase(value) <> "\"%'"
        _ -> string.join(conditions, " AND ")
      }
    }
  }
}

fn price_sql(field: String, comp: Compare, value: String) -> String {
  case value {
    "" -> "1 = 0"
    _ -> {
      let val = string.replace(value, ".", "")
      case int.parse(val) {
        Ok(_) ->
          "CAST(JSON_EXTRACT(prices, '$."
          <> field
          <> "') AS REAL) "
          <> comp_sql(comp)
          <> " "
          <> val
        _ -> "1 = 0"
      }
    }
  }
}

fn year_to_sql(comp: Compare, value: String) -> String {
  case int.parse(value) {
    Ok(n) ->
      "CAST(SUBSTR(released_at, 1, 4) AS INTEGER) "
      <> comp_sql(comp)
      <> " "
      <> int.to_string(n)
    _ -> "1 = 0"
  }
}

fn is_to_sql(value: String) -> String {
  case value {
    "commander" ->
      "((type_line LIKE '%Legendary%' AND (type_line LIKE '%Creature%' OR type_line LIKE '%Planeswalker%')) OR oracle_text LIKE '%can be your commander%')"
    "foil" -> "finishes LIKE '%\"foil\"%'"
    "nonfoil" -> "finishes LIKE '%\"nonfoil\"%'"
    "etched" -> "finishes LIKE '%\"etched\"%'"
    "digital" -> "digital = 1"
    "full" -> "full_art = 1"
    "promo" -> "promo = 1"
    "reprint" -> "reprint = 1"
    "reserved" -> "reserved = 1"
    "booster" -> "booster = 1"
    "oversized" -> "oversized = 1"
    "story_spotlight" | "spotlight" -> "story_spotlight = 1"
    "textless" -> "textless = 1"
    "unique" -> "reprint = 0"
    "transform" -> "layout = 'transform'"
    "modaldfc" | "mdfc" -> "layout = 'modal_dfc'"
    "split" -> "layout = 'split'"
    "flip" -> "layout = 'flip'"
    "meld" -> "layout = 'meld'"
    "leveler" -> "layout = 'leveler'"
    "dfc" -> "layout IN ('transform', 'modal_dfc', 'meld', 'flip')"
    "saga" -> "type_line LIKE '%Saga%'"
    "class" -> "type_line LIKE '%Class%'"
    "case" -> "type_line LIKE '%Case%'"
    "creature" -> "type_line LIKE '%Creature%'"
    "instant" -> "type_line LIKE '%Instant%'"
    "sorcery" -> "type_line LIKE '%Sorcery%'"
    "land" -> "type_line LIKE '%Land%'"
    "enchantment" -> "type_line LIKE '%Enchantment%'"
    "artifact" -> "type_line LIKE '%Artifact%'"
    "planeswalker" -> "type_line LIKE '%Planeswalker%'"
    "battle" -> "type_line LIKE '%Battle%'"
    "hybrid" -> "mana_cost LIKE '%/%'"
    "phyrexian" ->
      "(mana_cost LIKE '%{P}%' OR mana_cost LIKE '%{C/P}%' OR mana_cost LIKE '%{W/P}%' OR mana_cost LIKE '%{U/P}%' OR mana_cost LIKE '%{B/P}%' OR mana_cost LIKE '%{R/P}%' OR mana_cost LIKE '%{G/P}%')"
    "new" -> "frame NOT IN ('1993', '1997')"
    "old" -> "frame IN ('1993', '1997')"
    "hires" -> "image_status = 'highres_scan'"
    "alchemy" ->
      "games LIKE '%\"alchemy\"%' OR (games LIKE '%\"arena\"%' AND digital = 1)"
    _ -> "1 = 1"
  }
}

fn has_to_sql(value: String) -> String {
  case value {
    "indicator" -> "color_indicator IS NOT NULL"
    "watermark" -> "watermark IS NOT NULL"
    _ -> "1 = 1"
  }
}
