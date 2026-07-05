import gleam/dict
import gleam/list
import gleam/option.{Some}
import mtg_engine/action
import mtg_engine/effects
import mtg_engine/engine
import mtg_engine/error
import mtg_engine/extensions
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, create_creature,
  create_test_creature, create_test_land, get_permanent, pass_until,
}

/// Test 1: Engine new and get_state
pub fn engine_new_and_get_state_test() {
  // Create initial state
  let state = state.new()
  let engine = engine.new(state)

  // Verify get_state returns the initial state
  let retrieved = engine.get_state(engine)
  assert retrieved == state
}

/// Test 2: Engine dispatch cast creature — cast a creature through Engine,
/// pass priority until it resolves, verify it's on the battlefield.
pub fn engine_dispatch_cast_creature_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let state = add_card_to_hand(state, 1, creature)
  let state = pass_until(state, step.PreCombatMain)

  let engine = engine.new(state)

  // Produce green mana through the Engine
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(engine) = engine.dispatch(engine, action.ProduceMana(1, mana))

  // Cast the creature through the Engine
  let assert Ok(engine) =
    engine.dispatch(engine, action.CastCreature(1, "creature1", 0))

  // Both players pass priority — spell resolves automatically
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(2))

  // Verify creature is on battlefield
  let state = engine.get_state(engine)
  assert state.stack == []
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1
  let assert Ok(perm) = permanent.find(player1.battlefield, "creature1")
  assert perm.card.name == "Grizzly Bears"
  assert perm.card.power == Some(2)
  assert perm.card.toughness == Some(2)
  assert perm.tapped == False
}

/// Test 3: Engine dispatch with static effects — create an engine with a
/// PumpAll static effect, verify a creature on the battlefield gets the bonus.
pub fn engine_dispatch_with_static_effects_test() {
  let state = state.new()
  let creature = create_creature("creature1", "Test Subject", 2, 3)
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  let effect =
    effects.PumpAll(
      filter: filters.creature(),
      power: 1,
      toughness: 1,
      keywords: [],
    )
  let ext = extensions.new() |> extensions.add_static_effect(effect, "source_1")
  let engine = engine.new_with_extensions(state, ext)

  // Dispatch a no-op action through the Engine to trigger static effects
  let noop_mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
  let assert Ok(engine) =
    engine.dispatch(engine, action.ProduceMana(1, noop_mana))

  // Verify creature has +1/+1 from the static effect
  let state = engine.get_state(engine)
  let perm = get_permanent(state, 1, creature.id)
  // Base 2/3 +1/+1 = 3/4
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(4)
}

/// Test 4: Engine dispatch error propagation — dispatch an invalid action
/// (player without priority trying to cast), verify it returns an Error.
pub fn engine_dispatch_error_propagation_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let state = add_card_to_hand(state, 1, creature)
  let state = pass_until(state, step.PreCombatMain)

  let engine = engine.new(state)

  // Pass priority away from player 1
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))

  // Try to cast as player 1 without priority — should fail
  let result = engine.dispatch(engine, action.CastCreature(1, "creature1", 0))
  assert result == Error(error.DoNotHavePriority)
}

/// Test 5: Engine multiple dispatches — play a land, tap it for mana, cast a
/// creature, verify state updates correctly throughout.
pub fn engine_multiple_dispatches_test() {
  let state = state.new()
  let land = create_test_land("land1", "Forest")
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let state = add_card_to_hand(state, 1, land)
  let state = add_card_to_hand(state, 1, creature)
  let state = pass_until(state, step.PreCombatMain)

  let engine = engine.new(state)

  // 1. Play a land
  let assert Ok(engine) = engine.dispatch(engine, action.PlayLand(1, "land1"))

  // Verify land is on battlefield
  let state = engine.get_state(engine)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1
  assert dict.has_key(p1.battlefield, "land1")
  assert p1.lands_played_this_turn == 1

  // 2. Tap the land for green mana
  let assert Ok(engine) =
    engine.dispatch(engine, action.TapLandForMana(1, "land1"))

  // Verify mana was produced
  let state = engine.get_state(engine)
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.green == 1

  // 3. Cast the creature
  let assert Ok(engine) =
    engine.dispatch(engine, action.CastCreature(1, "creature1", 0))

  // Verify creature is on stack and mana was paid
  let state = engine.get_state(engine)
  assert list.length(state.stack) == 1
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.mana_pool.green == 0

  // 4. Pass priority to resolve
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(2))

  // Verify both land and creature are on battlefield
  let state = engine.get_state(engine)
  assert state.stack == []
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert dict.has_key(p1.battlefield, "land1")
  assert dict.has_key(p1.battlefield, "creature1")
}

/// Test 6: Engine get_extensions — after dispatching, verify extensions are
/// accessible and carry delayed trigger state changes.
pub fn engine_get_extensions_test() {
  let state = state.new()
  let state = pass_until(state, step.PreCombatMain)

  // Create an engine with a "once per turn" delayed trigger for BeginCombat
  let trigger =
    effects.DelayedTrigger(
      event: effects.AtStep(step.BeginCombat),
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(3),
        target: targeting.Controller,
      )),
      controller: 1,
      duration: effects.Once,
    )
  let ext = extensions.new() |> extensions.add_delayed_trigger(trigger)
  let engine = engine.new_with_extensions(state, ext)

  // Verify the trigger is present before dispatching
  let ext_before = engine.get_extensions(engine)
  assert list.length(ext_before.delayed_triggers) == 1

  // Pass priority for both players to advance step to BeginCombat
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(2))

  // Engine should have advanced to BeginCombat and trigger should have fired
  let state = engine.get_state(engine)
  assert state.step == step.BeginCombat
  assert list.length(state.stack) == 1

  // Verify extensions: the Once trigger should have been consumed
  let extensions = engine.get_extensions(engine)
  assert extensions.delayed_triggers == []

  // Now resolve the triggered ability by passing priority again
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(2))

  // Player 1 should have gained 3 life
  let state = engine.get_state(engine)
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 23
}

/// Test 7: Engine full game flow — a mini-game through the Engine:
/// play a land, cast a creature, pass priority to resolve, verify state.
pub fn engine_full_game_flow_test() {
  let state = state.new()
  let land = create_test_land("land1", "Forest")
  let creature = create_test_creature("creature1", "Grizzly Bears")
  let state = add_card_to_hand(state, 1, land)
  let state = add_card_to_hand(state, 1, creature)
  let state = pass_until(state, step.PreCombatMain)

  let engine = engine.new(state)

  // 1. Play a land
  let assert Ok(engine) = engine.dispatch(engine, action.PlayLand(1, "land1"))

  let state = engine.get_state(engine)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "land1")
  assert p1.lands_played_this_turn == 1

  // 2. Tap land for green mana
  let assert Ok(engine) =
    engine.dispatch(engine, action.TapLandForMana(1, "land1"))

  // 3. Cast the creature spell
  let assert Ok(engine) =
    engine.dispatch(engine, action.CastCreature(1, "creature1", 0))

  // 4. Pass priority until it resolves (both players pass)
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(1))
  let assert Ok(engine) = engine.dispatch(engine, action.PassPriority(2))

  // Verify the creature is on the battlefield
  let state = engine.get_state(engine)
  assert state.stack == []
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert dict.has_key(p1.battlefield, "creature1")

  // Verify creature has correct stats
  let assert Ok(perm) = permanent.find(p1.battlefield, "creature1")
  assert perm.card.power == Some(2)
  assert perm.card.toughness == Some(2)
  assert perm.card.name == "Grizzly Bears"
  assert perm.tapped == False
}
