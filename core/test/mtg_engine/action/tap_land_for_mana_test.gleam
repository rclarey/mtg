import mtg_engine/action
import mtg_engine/error
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import test_helpers.{
  add_card_to_hand, add_land_to_battlefield, create_test_creature,
  create_test_land, pass_until,
}

// Test tapping a Forest for green mana
pub fn tap_forest_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let state = add_land_to_battlefield(state, 1, forest)

  // Tap the forest for mana
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(tapped_forest) = permanent.find(player1.battlefield, "land1")
  assert tapped_forest.tapped == True

  // Verify green mana was added to pool
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
    )
}

// Test tapping a Mountain for red mana
pub fn tap_mountain_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let mountain = create_test_land("land1", "Mountain")

  // Add mountain to battlefield
  let state = add_land_to_battlefield(state, 1, mountain)

  // Tap the mountain for mana
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  // Verify red mana was added to pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 0,
      red: 1,
      green: 0,
      colorless: 0,
    )
}

// Test tapping an Island for blue mana
pub fn tap_island_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let island = create_test_land("land1", "Island")

  // Add island to battlefield
  let state = add_land_to_battlefield(state, 1, island)

  // Tap the island for mana
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  // Verify blue mana was added to pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 1,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test tapping a Plains for white mana
pub fn tap_plains_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let plains = create_test_land("land1", "Plains")

  // Add plains to battlefield
  let state = add_land_to_battlefield(state, 1, plains)

  // Tap the plains for mana
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  // Verify white mana was added to pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 1,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test tapping a Swamp for black mana
pub fn tap_swamp_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let swamp = create_test_land("land1", "Swamp")

  // Add swamp to battlefield
  let state = add_land_to_battlefield(state, 1, swamp)

  // Tap the swamp for mana
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  // Verify black mana was added to pool
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool
    == mana.Produced(
      white: 0,
      blue: 0,
      black: 1,
      red: 0,
      green: 0,
      colorless: 0,
    )
}

// Test cannot tap already tapped land
pub fn tap_already_tapped_land_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let forest = create_test_land("land1", "Forest")

  // Add forest to battlefield
  let state = add_land_to_battlefield(state, 1, forest)

  // Tap the forest once
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))

  // Try to tap it again - should fail
  let result = action.dispatch(state, action.TapLandForMana(1, "land1"))
  assert result == Error(error.InvalidAction("Land is already tapped"))
}

// Test cannot tap land not on battlefield
pub fn tap_land_not_on_battlefield_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let forest = create_test_land("land1", "Forest")

  // Add forest to hand instead of battlefield
  let state = add_card_to_hand(state, 1, forest)

  // Try to tap it - should fail
  let result = action.dispatch(state, action.TapLandForMana(1, "land1"))
  assert result == Error(error.InvalidAction("Permanent not found"))
}

// Test cannot tap non-land permanent
pub fn tap_non_land_for_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield
  let state = add_land_to_battlefield(state, 1, creature)

  // Try to tap it for mana - should fail
  let result = action.dispatch(state, action.TapLandForMana(1, "creature1"))
  assert result == Error(error.InvalidAction("Card is not a land"))
}

// Test tapping multiple lands accumulates mana
pub fn tap_multiple_lands_accumulates_mana_test() {
  let state = state.new() |> pass_until(step.PreCombatMain)
  let forest1 = create_test_land("land1", "Forest")
  let forest2 = create_test_land("land2", "Forest")
  let mountain = create_test_land("land3", "Mountain")

  // Add lands to battlefield
  let state = add_land_to_battlefield(state, 1, forest1)
  let state = add_land_to_battlefield(state, 1, forest2)
  let state = add_land_to_battlefield(state, 1, mountain)

  // Tap all three lands
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land1"))
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land2"))
  let assert Ok(state) =
    action.dispatch(state, action.TapLandForMana(1, "land3"))

  // Verify mana accumulated correctly
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.mana_pool.green == 2
  assert player1.mana_pool.red == 1
}
