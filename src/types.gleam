// Core type definitions for the MTG engine

import gleam/option.{type Option}

// Zones where cards can exist
pub type Zone {
  Hand
  Battlefield
  Graveyard
  Library
  Stack
  Exile
}

// Turn steps (organized by phase)
pub type Step {
  // Beginning phase
  Untap
  Upkeep
  Draw
  // Pre-combat main phase
  PreCombatMain
  // Combat phase
  BeginCombat
  DeclareAttackers
  DeclareBlockers
  CombatDamage
  EndCombat
  // Post-combat main phase
  PostCombatMain
  // End phase
  EndStep
  Cleanup
}

// Mana colors
pub type Color {
  White
  Blue
  Black
  Red
  Green
  Colorless
}

// Card types in MTG
pub type CardType {
  Land
  Creature
  Instant
  Sorcery
  Artifact
  Enchantment
}

// Mana cost representation (list of colors)
pub type ManaCost {
  ManaCost(
    generic: Int,
    white: Int,
    blue: Int,
    black: Int,
    red: Int,
    green: Int,
    colorless: Int,
  )
}

// Mana production/pool tracking each color of mana
pub type ManaProduced {
  ManaProduced(
    white: Int,
    blue: Int,
    black: Int,
    red: Int,
    green: Int,
    colorless: Int,
  )
}

// Card representation
pub type Card {
  Card(
    id: String,
    name: String,
    card_type: CardType,
    mana_cost: ManaCost,
    // Optional fields for creatures
    power: Option(Int),
    toughness: Option(Int),
    // Track tapped state for permanents on battlefield
    tapped: Bool,
    // Track when permanent entered battlefield (for summoning sickness)
    // None for cards not on battlefield, Some(turn) for permanents
    entered_battlefield_turn: Option(Int),
  )
}

// Stack item representation - represents a spell or ability on the stack
pub type StackItem {
  StackItem(
    card: Card,
    controller_id: Int,
    // Targets will be added in later phases when targeting is implemented
  )
}

// Player state
pub type Player {
  Player(
    id: Int,
    life: Int,
    mana_pool: ManaProduced,
    lands_played_this_turn: Int,
    hand: List(Card),
    battlefield: List(Card),
    graveyard: List(Card),
    library: List(Card),
    exile: List(Card),
  )
}

// Overall game state
pub type GameState {
  GameState(
    players: List(Player),
    active_player_id: Int,
    priority_player_id: Int,
    current_step: Step,
    consecutive_passes: Int,
    turn_number: Int,
    stack: List(StackItem),
  )
}

// Error type for invalid game actions
pub type Error {
  InvalidAction(String)
}

// Action type for game actions
pub type Action {
  PassPriority
  ProduceMana(player_id: Int, mana: ManaProduced)
  PlayLand(player_id: Int, card_id: String)
  TapLandForMana(player_id: Int, card_id: String)
  CastCreature(player_id: Int, card_id: String)
}
