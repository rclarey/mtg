import argv
import dev/search/parser
import envoy
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import simplifile
import sqlight
import temporary

pub type Card {
  Card(
    id: String,
    oracle_id: Option(String),
    name: String,
    mana_cost: String,
    cmc: Float,
    type_line: String,
    oracle_text: Option(String),
    power: Option(String),
    toughness: Option(String),
    loyalty: Option(String),
    colors: Option(String),
    color_identity: String,
    layout: String,
    set: String,
    set_name: String,
    collector_number: String,
    rarity: String,
    artist: Option(String),
    flavor_text: Option(String),
    watermark: Option(String),
    border_color: String,
    frame: String,
    full_art: Bool,
    digital: Bool,
    promo: Bool,
    reprint: Bool,
    reserved: Bool,
    finishes: String,
    games: String,
    prices: String,
    legalities: String,
    image_uris: Option(String),
    released_at: String,
    edhrec_rank: Option(Int),
    scryfall_uri: String,
    keywords: String,
  )
}

const select_columns = "id, oracle_id, name, mana_cost, cmc, type_line, oracle_text, power, toughness, loyalty, colors, color_identity, layout, `set`, set_name, collector_number, rarity, artist, flavor_text, watermark, border_color, frame, full_art, digital, promo, reprint, reserved, finishes, games, prices, legalities, image_uris, released_at, edhrec_rank, scryfall_uri, keywords"

const create_cards_table_sql = "CREATE TABLE IF NOT EXISTS cards (
    id TEXT PRIMARY KEY,
    oracle_id TEXT,
    name TEXT NOT NULL,
    mana_cost TEXT NOT NULL DEFAULT '',
    cmc REAL NOT NULL DEFAULT 0.0,
    type_line TEXT NOT NULL DEFAULT '',
    oracle_text TEXT,
    power TEXT,
    toughness TEXT,
    loyalty TEXT,
    colors TEXT,
    color_identity TEXT NOT NULL DEFAULT '[]',
    layout TEXT NOT NULL DEFAULT 'normal',
    `set` TEXT NOT NULL DEFAULT '',
    set_name TEXT NOT NULL DEFAULT '',
    collector_number TEXT NOT NULL DEFAULT '',
    rarity TEXT NOT NULL DEFAULT 'common',
    artist TEXT,
    flavor_text TEXT,
    watermark TEXT,
    border_color TEXT NOT NULL DEFAULT 'black',
    frame TEXT NOT NULL DEFAULT '',
    full_art INTEGER NOT NULL DEFAULT 0,
    digital INTEGER NOT NULL DEFAULT 0,
    promo INTEGER NOT NULL DEFAULT 0,
    reprint INTEGER NOT NULL DEFAULT 0,
    reserved INTEGER NOT NULL DEFAULT 0,
    finishes TEXT NOT NULL DEFAULT '[]',
    games TEXT NOT NULL DEFAULT '[]',
    prices TEXT NOT NULL DEFAULT '{}',
    legalities TEXT NOT NULL DEFAULT '{}',
    image_uris TEXT,
    released_at TEXT NOT NULL DEFAULT '',
    edhrec_rank INTEGER,
    scryfall_uri TEXT NOT NULL DEFAULT '',
    keywords TEXT NOT NULL DEFAULT '[]'
  )"

fn card_decoder() -> decode.Decoder(Card) {
  use id <- decode.field(0, decode.string)
  use oracle_id <- decode.field(1, decode.optional(decode.string))
  use name <- decode.field(2, decode.string)
  use mana_cost <- decode.field(3, decode.string)
  use cmc <- decode.field(4, decode.float)
  use type_line <- decode.field(5, decode.string)
  use oracle_text <- decode.field(6, decode.optional(decode.string))
  use power <- decode.field(7, decode.optional(decode.string))
  use toughness <- decode.field(8, decode.optional(decode.string))
  use loyalty <- decode.field(9, decode.optional(decode.string))
  use colors <- decode.field(10, decode.optional(decode.string))
  use color_identity <- decode.field(11, decode.string)
  use layout <- decode.field(12, decode.string)
  use set <- decode.field(13, decode.string)
  use set_name <- decode.field(14, decode.string)
  use collector_number <- decode.field(15, decode.string)
  use rarity <- decode.field(16, decode.string)
  use artist <- decode.field(17, decode.optional(decode.string))
  use flavor_text <- decode.field(18, decode.optional(decode.string))
  use watermark <- decode.field(19, decode.optional(decode.string))
  use border_color <- decode.field(20, decode.string)
  use frame <- decode.field(21, decode.string)
  use full_art <- decode.field(22, sqlight.decode_bool())
  use digital <- decode.field(23, sqlight.decode_bool())
  use promo <- decode.field(24, sqlight.decode_bool())
  use reprint <- decode.field(25, sqlight.decode_bool())
  use reserved <- decode.field(26, sqlight.decode_bool())
  use finishes <- decode.field(27, decode.string)
  use games <- decode.field(28, decode.string)
  use prices <- decode.field(29, decode.string)
  use legalities <- decode.field(30, decode.string)
  use image_uris <- decode.field(31, decode.optional(decode.string))
  use released_at <- decode.field(32, decode.string)
  use edhrec_rank <- decode.field(33, decode.optional(decode.int))
  use scryfall_uri <- decode.field(34, decode.string)
  use keywords <- decode.field(35, decode.string)
  decode.success(Card(
    id:,
    oracle_id:,
    name:,
    mana_cost:,
    cmc:,
    type_line:,
    oracle_text:,
    power:,
    toughness:,
    loyalty:,
    colors:,
    color_identity:,
    layout:,
    set:,
    set_name:,
    collector_number:,
    rarity:,
    artist:,
    flavor_text:,
    watermark:,
    border_color:,
    frame:,
    full_art:,
    digital:,
    promo:,
    reprint:,
    reserved:,
    finishes:,
    games:,
    prices:,
    legalities:,
    image_uris:,
    released_at:,
    edhrec_rank:,
    scryfall_uri:,
    keywords:,
  ))
}

fn card_to_json(card: Card) -> String {
  json.object([
    #("id", json.string(card.id)),
    #("oracle_id", json.nullable(card.oracle_id, json.string)),
    #("name", json.string(card.name)),
    #("mana_cost", json.string(card.mana_cost)),
    #("cmc", json.float(card.cmc)),
    #("type_line", json.string(card.type_line)),
    #("oracle_text", json.nullable(card.oracle_text, json.string)),
    #("power", json.nullable(card.power, json.string)),
    #("toughness", json.nullable(card.toughness, json.string)),
    #("loyalty", json.nullable(card.loyalty, json.string)),
    #("colors", json.nullable(card.colors, json.string)),
    #("color_identity", json.string(card.color_identity)),
    #("layout", json.string(card.layout)),
    #("set", json.string(card.set)),
    #("set_name", json.string(card.set_name)),
    #("collector_number", json.string(card.collector_number)),
    #("rarity", json.string(card.rarity)),
    #("artist", json.nullable(card.artist, json.string)),
    #("flavor_text", json.nullable(card.flavor_text, json.string)),
    #("watermark", json.nullable(card.watermark, json.string)),
    #("border_color", json.string(card.border_color)),
    #("frame", json.string(card.frame)),
    #("full_art", json.bool(card.full_art)),
    #("digital", json.bool(card.digital)),
    #("promo", json.bool(card.promo)),
    #("reprint", json.bool(card.reprint)),
    #("reserved", json.bool(card.reserved)),
    #("finishes", json.string(card.finishes)),
    #("games", json.string(card.games)),
    #("prices", json.string(card.prices)),
    #("legalities", json.string(card.legalities)),
    #("image_uris", json.nullable(card.image_uris, json.string)),
    #("released_at", json.string(card.released_at)),
    #("edhrec_rank", json.nullable(card.edhrec_rank, json.int)),
    #("scryfall_uri", json.string(card.scryfall_uri)),
    #("keywords", json.string(card.keywords)),
  ])
  |> json.to_string
}

pub fn main() -> Nil {
  case run() {
    Ok(_) -> Nil
    Error(msg) -> io.println_error("Error: " <> msg)
  }
}

fn run() -> Result(Nil, String) {
  let args = argv.load().arguments
  case args {
    ["--import", url, ..] -> do_import(url)
    _ -> search_query(string.trim(string.join(args, " ")))
  }
}

fn do_import(url: String) -> Result(Nil, String) {
  io.print("Fetching... ")

  use req <- result.try(case request.to(url) {
    Error(_) -> Error("Invalid URL: " <> url)
    Ok(req) -> Ok(req)
  })

  use resp <- result.try(case httpc.send(req) {
    Error(e) -> Error(http_error_to_string(e))
    Ok(resp) if resp.status != 200 ->
      Error("HTTP " <> int.to_string(resp.status))
    Ok(resp) -> Ok(resp)
  })

  io.println("done")
  let body = resp.body

  use _ <- result.try(
    case
      temporary.create(
        temporary.file() |> temporary.with_suffix(".json"),
        fn(path) {
          let _ = simplifile.write(to: path, contents: body)
          path
        },
      )
    {
      Error(e) -> Error("Temp file error: " <> simplifile.describe_error(e))
      Ok(temp_path) -> {
        io.println("Saved to " <> temp_path)
        Ok(Nil)
      }
    },
  )

  use cards <- result.try(parse_card_list(body))

  let db_path = get_db_path()
  io.print("Dropping existing cards... ")

  use conn <- sqlight.with_connection(db_path)

  use _ <- result.try(case sqlight.exec(create_cards_table_sql, on: conn) {
    Ok(_) -> Ok(Nil)
    Error(e) -> {
      let sqlight.SqlightError(_, msg, _) = e
      Error("Create table failed: " <> msg)
    }
  })

  use _ <- result.try(case sqlight.exec("DELETE FROM cards", on: conn) {
    Error(e) -> {
      let sqlight.SqlightError(_, msg, _) = e
      Error("Delete failed: " <> msg)
    }
    Ok(_) -> Ok(Nil)
  })

  io.println("done")

  let count = list.length(cards)
  io.println("Inserting " <> int.to_string(count) <> " cards...")

  use _ <- result.try(case sqlight.exec("BEGIN", on: conn) {
    Error(e) -> {
      let sqlight.SqlightError(_, msg, _) = e
      Error("Transaction error: " <> msg)
    }
    Ok(_) -> Ok(Nil)
  })

  let cols =
    "id, oracle_id, name, mana_cost, cmc, type_line, oracle_text, power, toughness, loyalty, colors, color_identity, layout, `set`, set_name, collector_number, rarity, artist, flavor_text, watermark, border_color, frame, full_art, digital, promo, reprint, reserved, finishes, games, prices, legalities, image_uris, released_at, edhrec_rank, scryfall_uri, keywords"
  let placeholders =
    "$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36"
  let insert_sql =
    "INSERT INTO cards (" <> cols <> ") VALUES (" <> placeholders <> ")"

  use count <- result.try(insert_cards_tx(conn, cards, insert_sql))

  io.println("Imported " <> int.to_string(count) <> " cards.")
  Ok(Nil)
}

fn insert_cards_tx(
  conn: sqlight.Connection,
  cards: List(dynamic.Dynamic),
  sql: String,
) -> Result(Int, String) {
  case insert_cards(conn, cards, sql) {
    Error(msg) -> {
      let _ = sqlight.exec("ROLLBACK", on: conn)
      Error(msg)
    }
    Ok(count) -> {
      case sqlight.exec("COMMIT", on: conn) {
        Ok(_) -> Ok(count)
        Error(e) -> {
          let sqlight.SqlightError(_, msg, _) = e
          Error("Commit failed: " <> msg)
        }
      }
    }
  }
}

fn insert_cards(
  conn: sqlight.Connection,
  cards: List(dynamic.Dynamic),
  sql: String,
) -> Result(Int, String) {
  insert_cards_loop(conn, cards, sql, 0)
}

fn insert_cards_loop(
  conn: sqlight.Connection,
  cards: List(dynamic.Dynamic),
  sql: String,
  count: Int,
) -> Result(Int, String) {
  case cards {
    [] -> Ok(count)
    [card, ..rest] -> {
      let values = card_to_values(card)
      use _ <- result.try(
        case
          sqlight.query(sql, on: conn, with: values, expecting: decode.dynamic)
        {
          Ok(_) -> Ok(Nil)
          Error(e) -> {
            let sqlight.SqlightError(_, msg, _) = e
            Error("Insert failed: " <> msg)
          }
        },
      )
      insert_cards_loop(conn, rest, sql, count + 1)
    }
  }
}

fn parse_card_list(body: String) -> Result(List(dynamic.Dynamic), String) {
  use parsed <- result.try(case json.parse(body, using: decode.dynamic) {
    Error(e) -> Error(json_decode_error_to_string(e))
    Ok(parsed) -> Ok(parsed)
  })
  case decode.run(parsed, decode.list(decode.dynamic)) {
    Ok(cards) -> Ok(cards)
    _ -> {
      let decoder =
        decode.field("data", decode.list(decode.dynamic), decode.success)
      case decode.run(parsed, decoder) {
        Ok(cards) -> Ok(cards)
        _ -> Error("Expected JSON array or object with 'data' field")
      }
    }
  }
}

fn json_decode_error_to_string(e: json.DecodeError) -> String {
  case e {
    json.UnexpectedEndOfInput -> "Unexpected end of JSON input"
    json.UnexpectedByte(b) -> "Unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "Unexpected character: " <> s
    json.UnableToDecode(errors) -> {
      let msgs =
        list.map(errors, fn(e) {
          "Expected " <> e.expected <> " at " <> string.join(e.path, ".")
        })
      string.join(msgs, "; ")
    }
  }
}

fn http_error_to_string(e: httpc.HttpError) -> String {
  case e {
    httpc.InvalidUtf8Response -> "Response is not valid UTF-8"
    httpc.ResponseTimeout -> "Request timed out"
    httpc.FailedToConnect(ip4: _, ip6: _) -> "Failed to connect"
  }
}

fn card_to_values(card: dynamic.Dynamic) -> List(sqlight.Value) {
  [
    extract_text(card, "id"),
    extract_optional_text(card, "oracle_id"),
    extract_text(card, "name"),
    extract_text(card, "mana_cost"),
    sqlight.float(extract_float(card, "cmc", 0.0)),
    extract_text(card, "type_line"),
    extract_optional_text(card, "oracle_text"),
    extract_optional_text(card, "power"),
    extract_optional_text(card, "toughness"),
    extract_optional_text(card, "loyalty"),
    extract_json_array(card, "colors"),
    extract_json_array(card, "color_identity"),
    extract_text(card, "layout"),
    extract_text(card, "set"),
    extract_text(card, "set_name"),
    extract_text(card, "collector_number"),
    extract_text(card, "rarity"),
    extract_optional_text(card, "artist"),
    extract_optional_text(card, "flavor_text"),
    extract_optional_text(card, "watermark"),
    extract_text(card, "border_color"),
    extract_text(card, "frame"),
    sqlight.bool(extract_bool(card, "full_art", False)),
    sqlight.bool(extract_bool(card, "digital", False)),
    sqlight.bool(extract_bool(card, "promo", False)),
    sqlight.bool(extract_bool(card, "reprint", False)),
    sqlight.bool(extract_bool(card, "reserved", False)),
    extract_json_array(card, "finishes"),
    extract_json_array(card, "games"),
    extract_json_object(card, "prices"),
    extract_json_object(card, "legalities"),
    extract_json_object(card, "image_uris"),
    extract_text(card, "released_at"),
    extract_optional_int(card, "edhrec_rank"),
    extract_text(card, "scryfall_uri"),
    extract_json_array(card, "keywords"),
  ]
}

fn extract_text(card: dynamic.Dynamic, field: String) -> sqlight.Value {
  let decoder = decode.field(field, decode.string, decode.success)
  case decode.run(card, decoder) {
    Ok(val) -> sqlight.text(val)
    _ -> sqlight.text("")
  }
}

fn extract_optional_text(card: dynamic.Dynamic, field: String) -> sqlight.Value {
  let decoder =
    decode.field(field, decode.optional(decode.string), decode.success)
  case decode.run(card, decoder) {
    Ok(Some(val)) -> sqlight.text(val)
    _ -> sqlight.null()
  }
}

fn extract_float(card: dynamic.Dynamic, field: String, default: Float) -> Float {
  let decoder = decode.field(field, decode.float, decode.success)
  case decode.run(card, decoder) {
    Ok(val) -> val
    _ -> default
  }
}

fn extract_bool(card: dynamic.Dynamic, field: String, default: Bool) -> Bool {
  let decoder = decode.field(field, decode.bool, decode.success)
  case decode.run(card, decoder) {
    Ok(val) -> val
    _ -> default
  }
}

fn extract_optional_int(card: dynamic.Dynamic, field: String) -> sqlight.Value {
  let decoder = decode.field(field, decode.optional(decode.int), decode.success)
  case decode.run(card, decoder) {
    Ok(Some(val)) -> sqlight.int(val)
    _ -> sqlight.null()
  }
}

fn extract_json_array(card: dynamic.Dynamic, field: String) -> sqlight.Value {
  let decoder = decode.field(field, decode.list(decode.string), decode.success)
  case decode.run(card, decoder) {
    Ok(items) ->
      sqlight.text(
        json.to_string(json.preprocessed_array(list.map(items, json.string))),
      )
    _ -> sqlight.text("[]")
  }
}

fn extract_json_object(card: dynamic.Dynamic, field: String) -> sqlight.Value {
  let decoder = decode.field(field, decode.dynamic, decode.success)
  case decode.run(card, decoder) {
    Ok(val) -> sqlight.text(dynamic_to_json_string(val))
    _ -> sqlight.text("{}")
  }
}

fn dynamic_to_json_string(dyn: dynamic.Dynamic) -> String {
  case decode.run(dyn, decode.string) {
    Ok(s) -> "\"" <> escape_json_string(s) <> "\""
    _ -> {
      case decode.run(dyn, decode.int) {
        Ok(i) -> int.to_string(i)
        _ -> {
          case decode.run(dyn, decode.float) {
            Ok(f) -> float.to_string(f)
            _ -> {
              case decode.run(dyn, decode.bool) {
                Ok(True) -> "true"
                Ok(False) -> "false"
                _ -> {
                  case decode.run(dyn, decode.list(decode.dynamic)) {
                    Ok(items) -> {
                      let strs = list.map(items, dynamic_to_json_string)
                      "[" <> string.join(strs, ",") <> "]"
                    }
                    _ -> {
                      case
                        decode.run(
                          dyn,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(d) -> {
                          let entries = dict.to_list(d)
                          let pairs =
                            list.map(entries, fn(pair) {
                              let #(key, val) = pair
                              "\""
                              <> escape_json_string(key)
                              <> "\":"
                              <> dynamic_to_json_string(val)
                            })
                          "{" <> string.join(pairs, ",") <> "}"
                        }
                        _ -> "null"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn escape_json_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

fn search_query(query: String) -> Result(Nil, String) {
  case query {
    "" -> Error("Empty query")
    _ -> {
      use tokens <- result.try(parser.tokenize(query))
      use expr <- result.try(parser.parse(tokens))
      let where_clause = parser.to_where_clause(expr)

      let full_sql = case where_clause {
        "" -> "SELECT " <> select_columns <> " FROM cards LIMIT 100"
        _ ->
          "SELECT "
          <> select_columns
          <> " FROM cards WHERE "
          <> where_clause
          <> " LIMIT 100"
      }

      let db_path = get_db_path()
      let decoder = card_decoder()

      use conn <- sqlight.with_connection(db_path)

      case sqlight.query(full_sql, on: conn, with: [], expecting: decoder) {
        Ok(cards) -> {
          cards
          |> list.map(card_to_json)
          |> string.join("\n")
          |> io.println
          Ok(Nil)
        }
        Error(err) -> {
          let sqlight.SqlightError(_, msg, _) = err
          Error("Database error: " <> msg)
        }
      }
    }
  }
}

fn get_db_path() -> String {
  case envoy.get("MTG_DB_PATH") {
    Ok(path) -> path
    _ -> "mtg_cards.db"
  }
}
