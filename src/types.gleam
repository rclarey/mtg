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
pub type ManaCost =
  List(Color)

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
  )
}

// Player state
pub type Player {
  Player(
    id: String,
    life: Int,
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
    active_player_id: String,
    priority_player_id: String,
    current_step: Step,
  )
}
