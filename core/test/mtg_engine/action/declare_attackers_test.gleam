import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/error
import mtg_engine/game
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, add_land_to_battlefield,
  create_test_creature, create_test_land, pass_until,
}

// Test declaring attackers successfully
pub fn declare_attackers_success_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness (entered in cycle -1)
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare attackers
  let attack_pairs = [game.AttackPair("creature1", game.AttackPlayer(2))]
  let assert Ok(state) =
    action.dispatch(state, action.DeclareAttackers(1, attack_pairs))

  // Verify creature is tapped
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(attacker) = permanent.find(player1.battlefield, "creature1")
  assert attacker.tapped == True

  // Verify attacking_creatures is set
  assert state.attacking_creatures == Some(attack_pairs)

  // Verify active player retains priority
  assert state.priority_player == Some(1)

  // Verify consecutive passes was reset
  assert state.consecutive_passes == 0
}

// Test declaring multiple attackers
pub fn declare_multiple_attackers_test() {
  let state = game.new()
  let creature1 = create_test_creature("creature1", "Bear 1")
  let creature2 = create_test_creature("creature2", "Bear 2")

  // Add creatures to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature1, -1)
  let state = add_creature_to_battlefield(state, 1, creature2, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare both attackers
  let attack_pairs = [
    game.AttackPair("creature1", game.AttackPlayer(2)),
    game.AttackPair("creature2", game.AttackPlayer(2)),
  ]
  let assert Ok(state) =
    action.dispatch(state, action.DeclareAttackers(1, attack_pairs))

  // Verify both creatures are tapped
  let assert Ok(player1) = player.find(state.players, 1)
  let assert Ok(attacker1) = permanent.find(player1.battlefield, "creature1")
  let assert Ok(attacker2) = permanent.find(player1.battlefield, "creature2")
  assert attacker1.tapped == True
  assert attacker2.tapped == True

  // Verify both are listed as attackers
  assert state.attacking_creatures == Some(attack_pairs)
}

// Test cannot declare attackers with tapped creature
pub fn declare_attackers_tapped_creature_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Tap the creature manually
  let state =
    game.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: permanent.update(p.battlefield, "creature1", fn(perm) {
            permanent.Permanent(..perm, tapped: True)
          }),
        )
      }),
    )

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Try to declare tapped creature as attacker - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )
  assert result
    == Error(error.InvalidAction("Cannot attack with tapped creature"))
}

// Test cannot declare attackers with summoning sickness
pub fn declare_attackers_summoning_sickness_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield with summoning sickness (current cycle)
  let current_cycle = game.turn_cycle(state)
  let state = add_creature_to_battlefield(state, 1, creature, current_cycle)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Try to attack with creature that has summoning sickness - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )
  assert result
    == Error(error.InvalidAction(
      "Cannot attack with creature that has summoning sickness",
    ))
}

// Test non-active player cannot declare attackers
pub fn declare_attackers_not_active_player_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 2's battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 2, creature, -1)

  // Advance to DeclareAttackers step (player 1 is active)
  let state = pass_until(state, game.DeclareAttackers)

  // Player 2 tries to declare attackers - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(2, [
        game.AttackPair("creature1", game.AttackPlayer(1)),
      ]),
    )
  assert result
    == Error(error.InvalidAction("Only the active player can declare attackers"))
}

// Test cannot declare attackers in wrong step
pub fn declare_attackers_wrong_step_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Stay in PreCombatMain (wrong step)
  let state = pass_until(state, game.PreCombatMain)

  // Try to declare attackers in wrong step - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )
  assert result
    == Error(error.InvalidAction(
      "Can only declare attackers during DeclareAttackers step",
    ))
}

// Test priority is given to active player after declaring attackers
pub fn declare_attackers_retains_priority_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Verify no one has priority yet (attackers not declared)
  assert state.priority_player == None

  // Declare attackers
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )

  // Verify player 1 now has priority after declaring
  assert state.priority_player == Some(1)
}

// Test cannot declare attackers more than once
pub fn declare_attackers_already_declared_test() {
  let state = game.new()
  let creature1 = create_test_creature("creature1", "Bear 1")
  let creature2 = create_test_creature("creature2", "Bear 2")

  // Add creatures to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature1, -1)
  let state = add_creature_to_battlefield(state, 1, creature2, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare first attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )

  // Try to declare attackers again - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature2", game.AttackPlayer(2)),
      ]),
    )
  assert result
    == Error(error.InvalidAction(
      "Attackers have already been declared this step",
    ))
}

// Test cannot declare non-creature as attacker
pub fn declare_attackers_not_creature_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to battlefield
  let state = add_land_to_battlefield(state, 1, land)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Try to declare land as attacker - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("land1", game.AttackPlayer(2)),
      ]),
    )
  assert result == Error(error.InvalidAction("Only creatures can attack"))
}

// Test non-active player cannot declare attackers (already tested above but keeping for completeness)
pub fn declare_attackers_without_priority_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 2, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Player 2 (non-active) tries to declare attackers - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(2, [
        game.AttackPair("creature1", game.AttackPlayer(1)),
      ]),
    )
  assert result
    == Error(error.InvalidAction("Only the active player can declare attackers"))
}

// Test attacking with no creatures (empty list)
pub fn declare_attackers_empty_list_test() {
  let state = game.new()

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare no attackers
  let assert Ok(state) = action.dispatch(state, action.DeclareAttackers(1, []))

  // Verify attacking_creatures is empty list wrapped in Some
  assert state.attacking_creatures == Some([])

  // Verify priority is retained
  assert state.priority_player == Some(1)
}

// Test attacking_creatures is cleared when advancing to new turn
pub fn attacking_creatures_cleared_after_combat_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare attackers
  let attack_pairs = [game.AttackPair("creature1", game.AttackPlayer(2))]
  let assert Ok(state) =
    action.dispatch(state, action.DeclareAttackers(1, attack_pairs))

  // Verify attackers are set
  assert state.attacking_creatures == Some(attack_pairs)

  let state = pass_until(state, game.PostCombatMain)

  // Verify attacking_creatures was cleared
  assert state.attacking_creatures == None
}

// Test cannot declare attackers twice even if first declaration was empty
pub fn declare_attackers_twice_with_empty_first_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare no attackers
  let assert Ok(state) = action.dispatch(state, action.DeclareAttackers(1, []))

  // Verify attackers were declared (empty list)
  assert state.attacking_creatures == Some([])

  // Active player passes priority
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))

  // Player 2 passes priority back
  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))

  // We should now be in DeclareBlockers step
  assert state.step == game.DeclareBlockers

  // But let's test the scenario where we're still in DeclareAttackers
  // (for example, if player 2 had cast a spell)
  // We'll manually set the game state back to simulate this

  let state = game.State(..state, step: game.DeclareAttackers)

  // Try to declare attackers again - should fail because attackers were already declared
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(2)),
      ]),
    )
  assert result
    == Error(error.InvalidAction(
      "Attackers have already been declared this step",
    ))
}

// Test cannot pass priority in DeclareAttackers step before declaring attackers
pub fn cannot_pass_priority_before_declaring_attackers_test() {
  let state = game.new()

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Try to pass priority without declaring attackers - should fail
  let result = action.dispatch(state, action.PassPriority(1))
  assert result == Error(error.DoNotHavePriority)
}

// Test can pass priority after declaring attackers
pub fn can_pass_priority_after_declaring_attackers_test() {
  let state = game.new()

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Declare no attackers
  let assert Ok(state) = action.dispatch(state, action.DeclareAttackers(1, []))

  // Now should be able to pass priority
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  assert state.priority_player == Some(2)
}

// Test cannot play land before declaring attackers
pub fn cannot_play_land_before_declaring_attackers_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to player 1's hand
  let state = add_card_to_hand(state, 1, land)

  // Manually set to DeclareAttackers step with no priority
  // (normally you can't get here, but testing the validation)
  let state =
    game.State(
      ..state,
      step: game.DeclareAttackers,
      priority_player: None,
      attacking_creatures: None,
    )

  // Try to play land - should fail
  let result = action.dispatch(state, action.PlayLand(1, "land1"))
  assert result == Error(error.DoNotHavePriority)
}

// Test cannot tap land before declaring attackers
pub fn cannot_tap_land_before_declaring_attackers_test() {
  let state = game.new()
  let land = create_test_land("land1", "Forest")

  // Add land to battlefield
  let state = add_land_to_battlefield(state, 1, land)

  // Manually set to DeclareAttackers step with no priority
  let state =
    game.State(
      ..state,
      step: game.DeclareAttackers,
      priority_player: None,
      attacking_creatures: None,
    )

  // Try to tap land for mana - should fail
  let result = action.dispatch(state, action.TapLandForMana(1, "land1"))
  assert result == Error(error.DoNotHavePriority)
}

// Test cannot cast creature before declaring attackers
pub fn cannot_cast_creature_before_declaring_attackers_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to player 1's hand
  let state = add_card_to_hand(state, 1, creature)

  // Manually set to DeclareAttackers step with mana
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))

  let state =
    game.State(
      ..state,
      step: game.DeclareAttackers,
      priority_player: None,
      attacking_creatures: None,
    )

  // Try to cast creature - should fail
  let result = action.dispatch(state, action.CastCreature(1, "creature1"))
  assert result == Error(error.DoNotHavePriority)
}

// Test no one can pass priority before attackers declared (priority is None)
pub fn non_active_player_can_act_before_attackers_declared_test() {
  let state = game.new()

  // Advance to DeclareAttackers step (priority_player will be None)
  let state = pass_until(state, game.DeclareAttackers)

  // Verify priority is None
  assert state.priority_player == None

  // Player 2 tries to pass priority - should fail
  let result = action.dispatch(state, action.PassPriority(2))
  assert result == Error(error.DoNotHavePriority)
}

// Test cannot attack yourself
pub fn declare_attackers_cannot_attack_yourself_test() {
  let state = game.new()
  let creature = create_test_creature("creature1", "Grizzly Bears")

  // Add creature to battlefield without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Try to attack yourself - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair("creature1", game.AttackPlayer(1)),
      ]),
    )
  assert result == Error(error.InvalidAction("Cannot attack yourself"))
}
