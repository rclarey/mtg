import gleam/list
import gleam/option.{type Option}
import gleam/result
import mtg_engine/error
import mtg_engine/mana

pub type Color {
  White
  Blue
  Black
  Red
  Green
  Colorless
}

pub type CardType {
  Land
  Creature
  Instant
  Sorcery
  Artifact
  Enchantment
}

// Card representation
pub type Card {
  Card(
    id: String,
    name: String,
    card_type: CardType,
    mana_cost: mana.Cost,
    // Optional fields for creatures
    power: Option(Int),
    toughness: Option(Int),
  )
}

pub fn find(cards: List(Card), card_id: String) -> Result(Card, error.Error) {
  list.find(cards, fn(card) { card.id == card_id })
  |> result.replace_error(error.InvalidAction("Card not found"))
}

pub fn remove(cards: List(Card), card_id: String) -> List(Card) {
  list.filter(cards, fn(card) { card.id != card_id })
}
