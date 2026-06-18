-- Scryfall Card Database Schema
-- Based on https://scryfall.com/docs/api/cards
-- Each Scryfall card field is mapped to a SQLite column.

-- Cards table: stores all card printings
CREATE TABLE IF NOT EXISTS cards (
    -- Core identifiers
    id TEXT PRIMARY KEY,
    arena_id INTEGER,
    lang TEXT NOT NULL DEFAULT 'en',
    mtgo_id INTEGER,
    mtgo_foil_id INTEGER,
    multiverse_ids TEXT,
    tcgplayer_id INTEGER,
    tcgplayer_etched_id INTEGER,
    cardmarket_id INTEGER,
    object TEXT NOT NULL DEFAULT 'card',
    layout TEXT NOT NULL DEFAULT 'normal',
    oracle_id TEXT,
    prints_search_uri TEXT NOT NULL DEFAULT '',
    rulings_uri TEXT NOT NULL DEFAULT '',
    scryfall_uri TEXT NOT NULL DEFAULT '',
    uri TEXT NOT NULL DEFAULT '',

    -- Gameplay fields
    cmc REAL NOT NULL DEFAULT 0.0,
    color_identity TEXT NOT NULL DEFAULT '[]',
    color_indicator TEXT,
    colors TEXT,
    defense TEXT,
    edhrec_rank INTEGER,
    game_changer INTEGER NOT NULL DEFAULT 0,
    hand_modifier TEXT,
    keywords TEXT NOT NULL DEFAULT '[]',
    legalities TEXT NOT NULL DEFAULT '{}',
    life_modifier TEXT,
    loyalty TEXT,
    mana_cost TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL,
    oracle_text TEXT,
    penny_rank INTEGER,
    power TEXT,
    produced_mana TEXT,
    reserved INTEGER NOT NULL DEFAULT 0,
    toughness TEXT,
    type_line TEXT NOT NULL DEFAULT '',

    -- Print fields
    artist TEXT,
    artist_ids TEXT,
    attraction_lights TEXT,
    booster INTEGER NOT NULL DEFAULT 0,
    border_color TEXT NOT NULL DEFAULT 'black',
    card_back_id TEXT,
    collector_number TEXT NOT NULL DEFAULT '',
    content_warning INTEGER,
    digital INTEGER NOT NULL DEFAULT 0,
    finishes TEXT NOT NULL DEFAULT '[]',
    flavor_name TEXT,
    flavor_text TEXT,
    frame_effects TEXT,
    frame TEXT NOT NULL DEFAULT '',
    full_art INTEGER NOT NULL DEFAULT 0,
    games TEXT NOT NULL DEFAULT '[]',
    highres_image INTEGER NOT NULL DEFAULT 0,
    illustration_id TEXT,
    image_status TEXT NOT NULL DEFAULT '',
    image_uris TEXT,
    oversized INTEGER NOT NULL DEFAULT 0,
    prices TEXT NOT NULL DEFAULT '{}',
    printed_name TEXT,
    printed_text TEXT,
    printed_type_line TEXT,
    promo INTEGER NOT NULL DEFAULT 0,
    promo_types TEXT,
    purchase_uris TEXT,
    rarity TEXT NOT NULL DEFAULT 'common',
    related_uris TEXT NOT NULL DEFAULT '{}',
    released_at TEXT NOT NULL DEFAULT '',
    reprint INTEGER NOT NULL DEFAULT 0,
    scryfall_set_uri TEXT NOT NULL DEFAULT '',
    set_name TEXT NOT NULL DEFAULT '',
    set_search_uri TEXT NOT NULL DEFAULT '',
    set_type TEXT NOT NULL DEFAULT '',
    set_uri TEXT NOT NULL DEFAULT '',
    set TEXT NOT NULL DEFAULT '',
    set_id TEXT NOT NULL DEFAULT '',
    story_spotlight INTEGER NOT NULL DEFAULT 0,
    textless INTEGER NOT NULL DEFAULT 0,
    variation INTEGER NOT NULL DEFAULT 0,
    variation_of TEXT,
    security_stamp TEXT,
    watermark TEXT,

    -- Preview sub-object
    previewed_at TEXT,
    preview_source_uri TEXT,
    preview_source TEXT
);

-- Card faces for multiface cards (transform, modal DFCs, split, flip, etc.)
CREATE TABLE IF NOT EXISTS card_faces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id TEXT NOT NULL REFERENCES cards(id),
    face_index INTEGER NOT NULL,
    artist TEXT,
    artist_id TEXT,
    cmc REAL,
    color_indicator TEXT,
    colors TEXT,
    defense TEXT,
    flavor_text TEXT,
    illustration_id TEXT,
    image_uris TEXT,
    layout TEXT,
    loyalty TEXT,
    mana_cost TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL,
    object TEXT NOT NULL DEFAULT 'card_face',
    oracle_id TEXT,
    oracle_text TEXT,
    power TEXT,
    printed_name TEXT,
    printed_text TEXT,
    printed_type_line TEXT,
    toughness TEXT,
    type_line TEXT,
    watermark TEXT
);

-- Related card parts (tokens, meld parts, combo pieces)
CREATE TABLE IF NOT EXISTS card_parts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id TEXT NOT NULL REFERENCES cards(id),
    part_id TEXT NOT NULL,
    object TEXT NOT NULL DEFAULT 'related_card',
    component TEXT NOT NULL,
    name TEXT NOT NULL,
    type_line TEXT NOT NULL,
    uri TEXT NOT NULL
);

-- Indexes for common search patterns
CREATE INDEX IF NOT EXISTS idx_cards_name ON cards(name);
CREATE INDEX IF NOT EXISTS idx_cards_set ON cards(set);
CREATE INDEX IF NOT EXISTS idx_cards_oracle_id ON cards(oracle_id);
CREATE INDEX IF NOT EXISTS idx_cards_rarity ON cards(rarity);
CREATE INDEX IF NOT EXISTS idx_cards_type_line ON cards(type_line);
CREATE INDEX IF NOT EXISTS idx_cards_cmc ON cards(cmc);
CREATE INDEX IF NOT EXISTS idx_cards_released_at ON cards(released_at);
CREATE INDEX IF NOT EXISTS idx_card_faces_card_id ON card_faces(card_id);
CREATE INDEX IF NOT EXISTS idx_card_parts_card_id ON card_parts(card_id);
