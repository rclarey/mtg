import gleam/list
import gleam/option.{None}
import mtg_engine/action
import mtg_engine/card
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/player
import test_helpers.{add_card_to_hand, pass_until}

// Test casting an instant when the stack is non-empty (should succeed)
pub fn test_cast_instant_non_empty_stack() {
  let state = game.new()
  let instant =
    card.Card(
      id: "instant1",
      name: "Test Instant",
      card_type: card.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: None,
      toughness: None,
    )
  let state = add_card_to_hand(state, 1, instant)
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana for casting
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Put something on the stack first by casting the instant
  let assert Ok(state) =
    action.dispatch(state, action.CastInstant(1, "instant1"))

  // Try to cast another instant while the stack is non-empty
  // This should succeed because instants can be cast anytime during main phases
  let assert Ok(state) =
    action.dispatch(state, action.CastInstant(1, "instant1"))

  // Verify both instants are on the stack
  assert list.length(state.stack) == 2
}

// Test attempting to cast a sorcery as a non-active player (should fail)
pub fn test_cast_sorcery_non_active_player() {
  let state = game.new()
  let sorcery =
    card.Card(
      id: "sorcery1",
      name: "Test Sorcery",
      card_type: card.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 2,
        colorless: 0,
      ),
      power: None,
      toughness: None,
    )
  let state = add_card_to_hand(state, 1, sorcery)
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana for casting
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast as player 2 (non-active player) - should fail
  let assert Error(error.InvalidAction(_)) =
    action.dispatch(state, action.CastSorcery(2, "sorcery1"))
}

// Test successful casting of a sorcery by active player during main phase with empty stack
pub fn test_cast_sorcery_success() {
  let state = game.new()
  let sorcery =
    card.Card(
      id: "sorcery1",
      name: "Test Sorcery",
      card_type: card.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 2,
        colorless: 0,
      ),
      power: None,
      toughness: None,
    )
  let state = add_card_to_hand(state, 1, sorcery)
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana for casting
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast sorcery as active player - should succeed
  let assert Ok(state) =
    action.dispatch(state, action.CastSorcery(1, "sorcery1"))

  // Verify sorcery is removed from hand
  let assert Ok(player) = player.find(state.players, 1)
  assert player.hand == []

  // Verify sorcery is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "sorcery1"
  assert stack_item.controller_id == 1
}

// Test that casting an instant with empty stack succeeds
pub fn test_cast_instant_empty_stack() {
  let state = game.new()
  let instant =
    card.Card(
      id: "instant1",
      name: "Test Instant",
      card_type: card.Instant,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 1,
        colorless: 0,
      ),
      power: None,
      toughness: None,
    )
  let state = add_card_to_hand(state, 1, instant)
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana for casting
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Cast instant with empty stack - should succeed
  let assert Ok(state) =
    action.dispatch(state, action.CastInstant(1, "instant1"))

  // Verify instant is removed from hand
  let assert Ok(player) = player.find(state.players, 1)
  assert player.hand == []

  // Verify instant is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(stack_item) = list.first(state.stack)
  assert stack_item.card.id == "instant1"
  assert stack_item.controller_id == 1
}

// Test that the active player guard works for sorcery casting
pub fn test_sorcery_active_player_guard() {
  let state = game.new()
  let sorcery =
    card.Card(
      id: "sorcery1",
      name: "Test Sorcery",
      card_type: card.Sorcery,
      mana_cost: mana.Cost(
        generic: 0,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 2,
        colorless: 0,
      ),
      power: None,
      toughness: None,
    )
  let state = add_card_to_hand(state, 1, sorcery)
  let state = pass_until(state, game.PreCombatMain)

  // Add green mana for casting
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 2, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  // Try to cast sorcery as non-active player (player 2) - should fail
  let assert Error(error.InvalidAction(_)) =
    action.dispatch(state, action.CastSorcery(2, "sorcery1"))

  // Cast sorcery as active player (player 1) - should succeed
  let assert Ok(_) = action.dispatch(state, action.CastSorcery(1, "sorcery1"))
}
