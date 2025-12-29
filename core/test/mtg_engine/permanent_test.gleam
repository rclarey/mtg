import gleam/dict
import gleeunit
import mtg_engine/action
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{add_card_to_hand, create_test_creature, pass, pass_until}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn creature_has_summoning_sickness_same_turn_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to hand and advance to main phase
  let game = add_card_to_hand(game, 1, creature)
  let game = pass_until(game.PreCombatMain, game)

  // Give player mana to cast
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast and resolve the creature
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))
  let game_after_resolve = pass(game_after_cast)

  // Get the creature from the battlefield
  let assert Ok(player) = player.find(game_after_resolve.players, 1)
  let assert Ok(creature_on_battlefield) =
    dict.get(player.battlefield, "creature1")

  // Verify the creature has summoning sickness (entered this turn cycle)
  let current_cycle = game.turn_cycle(game_after_resolve)
  assert permanent.has_summoning_sickness(
      creature_on_battlefield,
      current_cycle,
    )
    == True
}

// Test that a creature does NOT have summoning sickness on the next turn
pub fn creature_no_summoning_sickness_next_turn_test() {
  let game = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to hand and advance to main phase
  let game = add_card_to_hand(game, 1, creature)
  let game = pass_until(game.PreCombatMain, game)

  // Give player mana to cast
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(game_with_mana) =
    action.dispatch(game, action.ProduceMana(1, mana))

  // Cast and resolve the creature (turn_index 0, player 1, cycle 0)
  let assert Ok(game_after_cast) =
    action.dispatch(game_with_mana, action.CastCreature(1, "creature1"))
  let game_after_resolve = pass(game_after_cast)

  // Verify creature entered on cycle 0
  let cycle_entered = game.turn_cycle(game_after_resolve)
  assert cycle_entered == 0

  // Get the creature from the battlefield
  let assert Ok(player) = player.find(game_after_resolve.players, 1)
  let assert Ok(creature_on_battlefield) =
    dict.get(player.battlefield, "creature1")

  // Verify the creature HAS summoning sickness on the same cycle it entered
  assert permanent.has_summoning_sickness(
      creature_on_battlefield,
      cycle_entered,
    )
    == True

  // Now test on a later cycle - the key is just checking cycle_entered < current_cycle
  // If creature entered on cycle 0, checking it on cycle 1 should return False
  assert permanent.has_summoning_sickness(
      creature_on_battlefield,
      cycle_entered + 1,
    )
    == False
}

// Test that summoning sickness only applies to permanents on the battlefield
// This test verifies the type system enforces that only permanents can be checked
pub fn summoning_sickness_only_for_permanents_test() {
  // Create a permanent that entered on cycle 0
  let permanent_value =
    permanent.Permanent(
      card: create_test_creature("creature1", "Grizzly Bears"),
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
    )

  // Creature should have summoning sickness on the same cycle it entered
  assert permanent.has_summoning_sickness(permanent_value, 0) == True

  // Creature should not have summoning sickness on a later cycle
  assert permanent.has_summoning_sickness(permanent_value, 1) == False
}
