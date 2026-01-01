import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mtg_engine/action
import mtg_engine/game
import mtg_engine/permanent
import test_helpers.{
  add_creature_to_battlefield, create_creature, get_permanent, get_player, pass,
  pass_until,
}

// ===== Basic Blocked Combat Damage Tests =====

pub fn basic_combat_damage_both_survive_test() {
  let attacker = create_creature("attacker1", "Grizzly Bears", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 1, 3)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Should be in CombatDamage step with active player assigning first
  assert state.step == game.CombatDamage
  assert state.choice_player == Some(1)

  // Active player assigns damage from attacker to blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(2, attacker.id, blocker.id)]),
    )

  // Defending player assigns damage from blocker to attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(2, [game.DamageAssignment(1, blocker.id, attacker.id)]),
    )

  // Both creatures should survive
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 1

  let blocker = get_permanent(state, 2, blocker.id)
  assert blocker.damage == 2

  // No damage to players
  list.each(state.players, fn(p) {
    assert p.life == 20
  })

  // Priority should go to active player, choice_player cleared
  assert state.priority_player == Some(1)
  assert state.choice_player == None
}

pub fn attacker_dies_blocker_survives_test() {
  let attacker = create_creature("attacker1", "Weakling", 1, 1)
  let blocker = create_creature("blocker1", "Strong Wall", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(1, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(2, blocker.id, attacker.id),
        ]),
      )
    })

  // Attacker should be dead (in graveyard)
  let player1 = get_player(state, 1)
  assert result.is_error(permanent.find(player1.battlefield, attacker.id))
  assert player1.graveyard == [attacker]

  // Blocker should survive with 1 damage
  let blocker = get_permanent(state, 2, blocker.id)
  assert blocker.damage == 1
}

pub fn blocker_dies_attacker_survives_test() {
  let attacker = create_creature("attacker1", "Big Guy", 3, 3)
  let blocker = create_creature("blocker1", "Small Wall", 1, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(3, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker.id, attacker.id),
        ]),
      )
    })

  // Blocker should be dead
  let player2 = get_player(state, 2)
  assert result.is_error(permanent.find(player2.battlefield, blocker.id))
  assert player2.graveyard == [blocker]

  // Attacker should survive with 1 damage
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 1
}

pub fn both_creatures_die_test() {
  let attacker = create_creature("attacker1", "Mutual Destruction", 3, 3)
  let blocker = create_creature("blocker1", "Also Dies", 3, 3)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(3, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(3, blocker.id, attacker.id),
        ]),
      )
    })

  // Both should be dead
  let player1 = get_player(state, 1)
  assert result.is_error(permanent.find(player1.battlefield, attacker.id))
  assert player1.graveyard == [attacker]
  let player2 = get_player(state, 2)
  assert result.is_error(permanent.find(player2.battlefield, blocker.id))
  assert player2.graveyard == [blocker]
}

pub fn exact_lethal_damage_test() {
  let attacker = create_creature("attacker1", "Exact", 5, 10)
  let blocker = create_creature("blocker1", "Five Toughness", 1, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(5, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker.id, attacker.id),
        ]),
      )
    })

  // Blocker should be dead with exactly 5 damage
  assert permanent.find(get_player(state, 2).battlefield, blocker.id)
    |> result.is_error()

  // Attacker should survive
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 1
}

pub fn overkill_damage_test() {
  let attacker = create_creature("attacker1", "Overkill", 10, 10)
  let blocker = create_creature("blocker1", "Weak", 1, 1)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(10, attacker.id, blocker.id),
      ]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker.id, attacker.id),
        ]),
      )
    })

  // Blocker should be dead
  assert permanent.find(get_player(state, 2).battlefield, blocker.id)
    |> result.is_error()
}

pub fn zero_power_creature_deals_no_damage_test() {
  let attacker = create_creature("attacker1", "Attacker", 3, 3)
  let blocker = create_creature("blocker1", "Wall", 0, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Assign damage - attacker assigns to blocker, blocker with 0 power assigns nothing
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(3, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      // 0-power blocker does not assign any damage (empty assignment list)
      action.dispatch(state, action.AssignDamage(2, []))
    })

  // Attacker should have no damage
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 0

  // Blocker should have 3 damage but survive
  let blocker = get_permanent(state, 2, blocker.id)
  assert blocker.damage == 3
}

// ===== Unblocked Attacker Tests =====

pub fn single_unblocked_attacker_deals_damage_to_player_test() {
  let attacker = create_creature("attacker1", "Bear", 3, 3)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) = action.dispatch(state, action.DeclareBlockers(2, []))

  let state = pass(state)

  // No damage to assign (unblocked attacker damage is automatic)
  let assert Ok(state) =
    action.dispatch(state, action.AssignDamage(1, []))
    |> result.try(fn(state) {
      action.dispatch(state, action.AssignDamage(2, []))
    })

  // Player 2 should have taken 3 damage
  let player2 = get_player(state, 2)
  assert player2.life == 17

  // Attacker should still be alive with no damage
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 0
}

pub fn multiple_unblocked_attackers_test() {
  let attacker1 = create_creature("attacker1", "Bear", 2, 2)
  let attacker2 = create_creature("attacker2", "Wolf", 3, 3)
  let attacker3 = create_creature("attacker3", "Dragon", 5, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker1, -1)
    |> add_creature_to_battlefield(1, attacker2, -1)
    |> add_creature_to_battlefield(1, attacker3, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker1.id, game.AttackPlayer(2)),
        game.AttackPair(attacker2.id, game.AttackPlayer(2)),
        game.AttackPair(attacker3.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) = action.dispatch(state, action.DeclareBlockers(2, []))

  let state = pass(state)

  // No damage assignments
  let assert Ok(state) =
    action.dispatch(state, action.AssignDamage(1, []))
    |> result.try(fn(state) {
      action.dispatch(state, action.AssignDamage(2, []))
    })

  // Player 2 should take 2+3+5 = 10 damage
  let player2 = get_player(state, 2)
  assert player2.life == 10
}

pub fn mixed_blocked_and_unblocked_attackers_test() {
  let attacker1 = create_creature("attacker1", "Blocked Bear", 2, 2)
  let attacker2 = create_creature("attacker2", "Free Wolf", 3, 3)
  let blocker = create_creature("blocker1", "Wall", 1, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker1, -1)
    |> add_creature_to_battlefield(1, attacker2, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker1.id, game.AttackPlayer(2)),
        game.AttackPair(attacker2.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker1.id)]),
    )

  let state = pass(state)

  // Assign damage for blocked combat
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(2, attacker1.id, blocker.id),
      ]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker.id, attacker1.id),
        ]),
      )
    })

  // Player 2 should take 3 damage from unblocked attacker2
  let player2 = get_player(state, 2)
  assert player2.life == 17

  // Blocker should have 2 damage
  let blocker = get_permanent(state, 2, blocker.id)
  assert blocker.damage == 2

  // Attacker1 should have 1 damage
  let attacker1 = get_permanent(state, 1, attacker1.id)
  assert attacker1.damage == 1

  // Attacker2 should have no damage
  let attacker2 = get_permanent(state, 1, attacker2.id)
  assert attacker2.damage == 0
}

pub fn all_attackers_blocked_no_player_damage_test() {
  let attacker = create_creature("attacker1", "Bear", 5, 5)
  let blocker = create_creature("blocker1", "Wall", 1, 10)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(5, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker.id, attacker.id),
        ]),
      )
    })

  // No damage to player
  let player2 = get_player(state, 2)
  assert player2.life == 20
}

// ===== Multiple Blockers Tests =====

pub fn multiple_blockers_on_one_attacker_test() {
  let attacker = create_creature("attacker1", "Big Guy", 5, 5)
  let blocker1 = create_creature("blocker1", "Wall1", 1, 3)
  let blocker2 = create_creature("blocker2", "Wall2", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker1, -1)
    |> add_creature_to_battlefield(2, blocker2, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker1.id, attacker.id),
        game.BlockPair(blocker2.id, attacker.id),
      ]),
    )

  let state = pass(state)

  // Attacker assigns 3 to blocker1 and 2 to blocker2 (total = 5)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(3, attacker.id, blocker1.id),
        game.DamageAssignment(2, attacker.id, blocker2.id),
      ]),
    )
    |> result.try(fn(state) {
      // Both blockers assign damage back
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(1, blocker1.id, attacker.id),
          game.DamageAssignment(2, blocker2.id, attacker.id),
        ]),
      )
    })

  // Both blockers should be dead
  let player2 = get_player(state, 2)
  assert result.is_error(permanent.find(player2.battlefield, blocker1.id))
  assert result.is_error(permanent.find(player2.battlefield, blocker2.id))

  // Attacker should have 3 damage (1+2)
  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 3
}

pub fn attacker_dies_from_multiple_blockers_test() {
  let attacker = create_creature("attacker1", "Weak", 2, 3)
  let blocker1 = create_creature("blocker1", "Strong1", 2, 5)
  let blocker2 = create_creature("blocker2", "Strong2", 2, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker1, -1)
    |> add_creature_to_battlefield(2, blocker2, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker1.id, attacker.id),
        game.BlockPair(blocker2.id, attacker.id),
      ]),
    )

  let state = pass(state)

  // Attacker assigns 1 to each blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(1, attacker.id, blocker1.id),
        game.DamageAssignment(1, attacker.id, blocker2.id),
      ]),
    )
    |> result.try(fn(state) {
      // Both blockers assign 2 damage back (total 4, lethal for attacker)
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(2, blocker1.id, attacker.id),
          game.DamageAssignment(2, blocker2.id, attacker.id),
        ]),
      )
    })

  // Attacker should be dead (took 4 damage, has 3 toughness)
  assert permanent.find(get_player(state, 1).battlefield, blocker1.id)
    |> result.is_error()

  // Both blockers should survive
  let blocker1 = get_permanent(state, 2, blocker1.id)
  assert blocker1.damage == 1

  let blocker2 = get_permanent(state, 2, blocker2.id)
  assert blocker2.damage == 1
}

// ===== Validation Tests =====

pub fn cannot_assign_damage_in_wrong_step_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> pass_until(game.PreCombatMain)

  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(2, attacker.id, "target")]),
    )

  assert result.is_error(result)
}

pub fn cannot_assign_damage_when_not_choice_player_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // choice_player is 1 (active player), so player 2 cannot assign yet
  assert state.choice_player == Some(1)

  let result =
    action.dispatch(
      state,
      action.AssignDamage(2, [game.DamageAssignment(2, blocker.id, attacker.id)]),
    )

  assert result.is_error(result)
}

pub fn must_assign_all_damage_test() {
  let attacker = create_creature("attacker1", "Bear", 5, 5)
  let blocker = create_creature("blocker1", "Wall", 2, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Try to assign only 3 damage when creature has power 5
  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(3, attacker.id, blocker.id)]),
    )

  assert result.is_error(result)
}

pub fn cannot_assign_more_than_power_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Try to assign 5 damage when creature has power 2
  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(5, attacker.id, blocker.id)]),
    )

  assert result.is_error(result)
}

pub fn cannot_assign_from_zero_power_creature_test() {
  let attacker = create_creature("attacker1", "Weak", 0, 3)
  let blocker = create_creature("blocker1", "Wall", 2, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Try to assign 0 damage from 0-power attacker - should be rejected
  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(0, attacker.id, blocker.id)]),
    )

  assert result.is_error(result)
}

pub fn cannot_assign_negative_damage_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 5)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Try to assign negative damage
  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(-1, attacker.id, blocker.id),
      ]),
    )

  assert result.is_error(result)
}

pub fn must_have_corresponding_block_pair_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 5)
  let unrelated = create_creature("unrelated", "Random", 3, 3)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> add_creature_to_battlefield(2, unrelated, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Try to assign damage to unrelated creature that isn't blocking
  let result =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        game.DamageAssignment(2, attacker.id, unrelated.id),
      ]),
    )

  assert result.is_error(result)
}

// ===== State Transition Tests =====

pub fn priority_and_choice_cleared_after_damage_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(2, attacker.id, blocker.id)]),
    )
    |> result.try(fn(state) {
      action.dispatch(
        state,
        action.AssignDamage(2, [
          game.DamageAssignment(2, blocker.id, attacker.id),
        ]),
      )
    })

  // After all damage assigned, priority goes to active player
  assert state.priority_player == Some(1)
  // choice_player is cleared
  assert state.choice_player == None
  // Still in CombatDamage step
  assert state.step == game.CombatDamage
}

pub fn assigned_damage_cleared_after_application_test() {
  let attacker = create_creature("attacker1", "Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 2, 2)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Verify assigned_damage gets populated then cleared
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(2, attacker.id, blocker.id)]),
    )

  // After first assignment, should have 1 damage assignment
  assert state.assigned_damage != []

  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(2, [game.DamageAssignment(2, blocker.id, attacker.id)]),
    )

  // After all assignments applied, should be cleared
  assert state.assigned_damage == []
}

pub fn applied_damage_cleared_when_turn_ends_test() {
  let attacker = create_creature("attacker1", "Grizzly Bears", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 1, 3)

  let state =
    game.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(game.DeclareAttackers)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Should be in CombatDamage step with active player assigning first
  assert state.step == game.CombatDamage
  assert state.choice_player == Some(1)

  // Active player assigns damage from attacker to blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [game.DamageAssignment(2, attacker.id, blocker.id)]),
    )

  // Defending player assigns damage from blocker to attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(2, [game.DamageAssignment(1, blocker.id, attacker.id)]),
    )

  let attacker = get_permanent(state, 1, attacker.id)
  assert attacker.damage == 1

  let blocker = get_permanent(state, 2, blocker.id)
  assert blocker.damage == 2

  let state = pass_until(state, game.Untap)
  let attacker = get_permanent(state, 1, attacker.card.id)
  assert attacker.damage == 0

  let blocker = get_permanent(state, 2, blocker.card.id)
  assert blocker.damage == 0
}
