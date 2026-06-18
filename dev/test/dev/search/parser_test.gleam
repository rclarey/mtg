import dev/search/parser

pub fn color_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("c:red")
  assert tokens == [parser.Op("c", parser.Colon, "red")]
}

pub fn color_equals_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("color=red")
  assert tokens == [parser.Op("color", parser.Eq, "red")]
}

pub fn type_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("t:goblin")
  assert tokens == [parser.Op("t", parser.Colon, "goblin")]
}

pub fn mana_value_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("mv>=3")
  assert tokens == [parser.Op("mv", parser.Gte, "3")]
}

pub fn set_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("e:war")
  assert tokens == [parser.Op("e", parser.Colon, "war")]
}

pub fn power_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("pow>=8")
  assert tokens == [parser.Op("pow", parser.Gte, "8")]
}

pub fn single_word_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("bolt")
  assert tokens == [parser.Word("bolt")]
}

pub fn multiple_words_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("lightning bolt")
  assert tokens == [parser.Word("lightning"), parser.Word("bolt")]
}

pub fn negation_operator_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("-t:goblin")
  assert tokens == [parser.Neg, parser.Op("t", parser.Colon, "goblin")]
}

pub fn negation_word_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("-goblin")
  assert tokens == [parser.Neg, parser.Word("goblin")]
}

pub fn quoted_phrase_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("\"draw a card\"")
  assert tokens == [parser.Phrase("draw a card")]
}

pub fn parentheses_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("(t:goblin or t:elf)")
  assert tokens
    == [
      parser.LParen,
      parser.Op("t", parser.Colon, "goblin"),
      parser.OrKeyword,
      parser.Op("t", parser.Colon, "elf"),
      parser.RParen,
    ]
}

pub fn or_keyword_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("t:goblin or t:elf")
  assert tokens
    == [
      parser.Op("t", parser.Colon, "goblin"),
      parser.OrKeyword,
      parser.Op("t", parser.Colon, "elf"),
    ]
}

pub fn multiple_spaces_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("  bolt   strike  ")
  assert tokens == [parser.Word("bolt"), parser.Word("strike")]
}

pub fn regex_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("/\\d+/")
  assert tokens == [parser.Regex("\\d+")]
}

pub fn combined_query_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("c:red t:goblin -t:legend mv>=3")
  assert tokens
    == [
      parser.Op("c", parser.Colon, "red"),
      parser.Op("t", parser.Colon, "goblin"),
      parser.Neg,
      parser.Op("t", parser.Colon, "legend"),
      parser.Op("mv", parser.Gte, "3"),
    ]
}

pub fn name_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("bolt")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "name LIKE '%bolt%' ESCAPE '\\'"
}

pub fn phrase_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("\"draw a card\"")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "name LIKE '%draw a card%' ESCAPE '\\'"
}

pub fn color_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("c:red")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "color_identity LIKE '%\"R\"%'"
}

pub fn color_equals_noncolor_sql_test() {
  let assert Ok(tokens) = parser.tokenize("color=2")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "color_identity LIKE '%\"2\"%'"
}

pub fn type_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("t:goblin")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "type_line LIKE '%goblin%' ESCAPE '\\'"
}

pub fn oracle_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("o:\"draw a card\"")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "oracle_text LIKE '%draw a card%' ESCAPE '\\'"
}

pub fn mana_value_equal_sql_test() {
  let assert Ok(tokens) = parser.tokenize("mv=3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc = 3"
}

pub fn mana_value_gte_sql_test() {
  let assert Ok(tokens) = parser.tokenize("mv>=5")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc >= 5"
}

pub fn mana_value_lt_sql_test() {
  let assert Ok(tokens) = parser.tokenize("mv<2")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc < 2"
}

pub fn mana_value_lte_sql_test() {
  let assert Ok(tokens) = parser.tokenize("mv<=4")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc <= 4"
}

pub fn power_gte_sql_test() {
  let assert Ok(tokens) = parser.tokenize("pow>=8")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "CAST(COALESCE(power, '0') AS REAL) >= 8"
}

pub fn toughness_lt_sql_test() {
  let assert Ok(tokens) = parser.tokenize("tou<3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "CAST(COALESCE(toughness, '0') AS REAL) < 3"
}

pub fn rarity_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("r:rare")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "rarity = 'rare'"
}

pub fn set_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("e:war")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "set = 'war'"
}

pub fn format_legal_sql_test() {
  let assert Ok(tokens) = parser.tokenize("f:pauper")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "legalities LIKE '%\"pauper\":\"legal\"%'"
}

pub fn artist_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("a:\"proce\"")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "artist LIKE '%proce%' ESCAPE '\\'"
}

pub fn keyword_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("kw:flying")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "keywords LIKE '%\"flying\"%'"
}

pub fn watermark_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("wm:orzhov")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "watermark = 'orzhov'"
}

pub fn year_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("year>=2020")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "CAST(SUBSTR(released_at, 1, 4) AS INTEGER) >= 2020"
}

pub fn border_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("border:black")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "border_color = 'black'"
}

pub fn frame_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("frame:2015")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "frame = '2015'"
}

pub fn game_arena_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("game:arena")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "games LIKE '%\"arena\"%'"
}

pub fn and_implicit_sql_test() {
  let assert Ok(tokens) = parser.tokenize("c:red t:goblin")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql
    == "(color_identity LIKE '%\"R\"%' AND type_line LIKE '%goblin%' ESCAPE '\\')"
}

pub fn or_explicit_sql_test() {
  let assert Ok(tokens) = parser.tokenize("t:goblin or t:elf")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql
    == "(type_line LIKE '%goblin%' ESCAPE '\\' OR type_line LIKE '%elf%' ESCAPE '\\')"
}

pub fn negation_sql_test() {
  let assert Ok(tokens) = parser.tokenize("-t:goblin")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "NOT (type_line LIKE '%goblin%' ESCAPE '\\')"
}

pub fn grouping_sql_test() {
  let assert Ok(tokens) = parser.tokenize("(t:goblin or t:elf) mv=3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql
    == "((type_line LIKE '%goblin%' ESCAPE '\\' OR type_line LIKE '%elf%' ESCAPE '\\') AND cmc = 3)"
}

pub fn is_foil_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:foil")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "finishes LIKE '%\"foil\"%'"
}

pub fn is_commander_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:commander")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql
    == "((type_line LIKE '%Legendary%' AND (type_line LIKE '%Creature%' OR type_line LIKE '%Planeswalker%')) OR oracle_text LIKE '%can be your commander%')"
}

pub fn is_transform_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:transform")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "layout = 'transform'"
}

pub fn is_creature_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:creature")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "type_line LIKE '%Creature%'"
}

pub fn is_reserved_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:reserved")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "reserved = 1"
}

pub fn is_reprint_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:reprint")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "reprint = 1"
}

pub fn is_unique_sql_test() {
  let assert Ok(tokens) = parser.tokenize("is:unique")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "reprint = 0"
}

pub fn has_indicator_sql_test() {
  let assert Ok(tokens) = parser.tokenize("has:indicator")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "color_indicator IS NOT NULL"
}

pub fn has_watermark_sql_test() {
  let assert Ok(tokens) = parser.tokenize("has:watermark")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "watermark IS NOT NULL"
}

pub fn full_oracle_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("fo:\"first strike\"")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql
    == "(oracle_text LIKE '%first strike%' ESCAPE '\\' OR flavor_text LIKE '%first strike%' ESCAPE '\\')"
}

pub fn cmc_alias_sql_test() {
  let assert Ok(tokens) = parser.tokenize("cmc=3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc = 3"
}

pub fn manavalue_alias_sql_test() {
  let assert Ok(tokens) = parser.tokenize("manavalue=3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "cmc = 3"
}

pub fn edition_alias_sql_test() {
  let assert Ok(tokens) = parser.tokenize("edition:war")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "set = 'war'"
}

pub fn oracle_text_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("oracle:\"draw a card\"")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "oracle_text LIKE '%draw a card%' ESCAPE '\\'"
}

pub fn flavor_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("ft:mishra")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "flavor_text LIKE '%mishra%' ESCAPE '\\'"
}

pub fn set_type_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("st:core")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "set_type = 'core'"
}

pub fn loyalty_search_sql_test() {
  let assert Ok(tokens) = parser.tokenize("loy=3")
  let assert Ok(expr) = parser.parse(tokens)
  let sql = parser.to_where_clause(expr)
  assert sql == "CAST(COALESCE(loyalty, '0') AS REAL) = 3"
}

pub fn empty_string_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("")
  assert tokens == []
}

pub fn whitespace_only_tokenize_test() {
  let assert Ok(tokens) = parser.tokenize("   ")
  assert tokens == []
}

pub fn unterminated_quote_error_test() {
  let result = parser.tokenize("\"draw a card")
  assert result == Error("Unterminated string literal")
}

pub fn empty_query_error_test() {
  let assert Ok(tokens) = parser.tokenize("")
  let result = parser.parse(tokens)
  assert result == Error("Empty query")
}
