import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import mtg_engine/card
import mtg_engine/error

// Permanent representation - wraps a card on the battlefield with permanent-specific state
pub type Permanent {
  Permanent(
    card: card.Card,
    owner_id: Int,
    // Track tapped state
    tapped: Bool,
    // Track when permanent entered battlefield (for summoning sickness)
    entered_battlefield_cycle: Int,
    // Track damage marked on this permanent (cleared during cleanup step)
    damage: Int,
    // Track keywords temporarily granted by effects (e.g. PumpCreature)
    granted_keywords: List(String),
    // Track what this permanent is attached to (for Auras/Equipment)
    attached_to: Option(String),
    // Track static effect bonuses (reset on each dispatch)
    static_bonus_power: Int,
    static_bonus_toughness: Int,
    static_bonus_keywords: List(String),
  )
}

// Create a new permanent
pub fn from_card(
  card: card.Card,
  owner_id: Int,
  current_cycle: Int,
) -> Permanent {
  Permanent(
    card:,
    owner_id:,
    tapped: False,
    entered_battlefield_cycle: current_cycle,
    damage: 0,
    granted_keywords: [],
    attached_to: None,
    static_bonus_power: 0,
    static_bonus_toughness: 0,
    static_bonus_keywords: [],
  )
}

// Find a permanent on the battlefield by card ID
pub fn find(
  battlefield: Dict(String, Permanent),
  card_id: String,
) -> Result(Permanent, error.Error) {
  dict.get(battlefield, card_id)
  |> result.replace_error(error.InvalidAction("Permanent not found"))
}

// Update a permanent in the battlefield
pub fn update(
  battlefield: Dict(String, Permanent),
  permanent_id: String,
  f: fn(Permanent) -> Permanent,
) -> Dict(String, Permanent) {
  case dict.get(battlefield, permanent_id) {
    Ok(perm) -> dict.insert(battlefield, permanent_id, f(perm))
    Error(_) -> battlefield
  }
}

pub fn has_summoning_sickness(
  permanent: Permanent,
  current_cycle: Int,
) -> Bool {
  // Creature has summoning sickness if it entered this turn cycle
  // and doesn't have haste
  permanent.entered_battlefield_cycle >= current_cycle
  && !list.contains(permanent.granted_keywords, "Haste")
}
