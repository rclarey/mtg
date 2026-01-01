import gleam/option.{None, Some}
import gleam/result
import mtg_engine/action
import mtg_engine/game
import mtg_engine/permanent
import mtg_engine/player
import test_helpers.{
  add_creature_to_battlefield, create_test_creature, pass, pass_until,
}

pub fn declare_single_blocker_test() {
  // Setup: Create a game with an attacker and a blocker
  let state = game.new()

  // Add creatures to battlefields
  let attacker = create_test_creature("attacker1", "Grizzly Bears")
  let blocker = create_test_creature("blocker1", "Wall")

  // Player 1 (active player) has an attacker (no summoning sickness)
  let state = add_creature_to_battlefield(state, 1, attacker, -1)

  // Player 2 (defending player) has a blocker (no summoning sickness)
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Player 1 declares attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  // Both players pass priority
  let assert Some(p1) = state.priority_player
  let assert Ok(state) = action.dispatch(state, action.PassPriority(p1))
  let assert Some(p2) = state.priority_player
  let assert Ok(state) = action.dispatch(state, action.PassPriority(p2))

  // We should be in DeclareBlockers step with player 2 declaring
  assert state.step == game.DeclareBlockers
  assert state.choice_player == Some(2)

  // Player 2 declares blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [game.BlockPair(blocker.id, attacker.id)]),
    )

  // Verify blocking was recorded
  assert state.blocking_creatures == [game.BlockPair(blocker.id, attacker.id)]

  // Verify we're still in DeclareBlockers step but all players have declared
  assert state.step == game.DeclareBlockers
  assert state.choice_player == None

  // Verify priority went to active player
  assert state.priority_player == Some(1)
}

pub fn declare_no_blockers_test() {
  // Setup: Create a game with an attacker but no blockers
  let state = game.new()

  // Add attacker to player 1's battlefield (no summoning sickness)
  let attacker = create_test_creature("attacker1", "Grizzly Bears")
  let state = add_creature_to_battlefield(state, 1, attacker, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Player 1 declares attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )

  // Both players pass
  let state = pass(state)

  // We should be in DeclareBlockers step
  assert state.step == game.DeclareBlockers

  // Player 2 declares no blockers
  let assert Ok(state) = action.dispatch(state, action.DeclareBlockers(2, []))

  // Verify no blocks were recorded
  assert state.blocking_creatures == []

  // Verify priority went to active player
  assert state.priority_player == Some(1)
}

pub fn multiple_blockers_different_attackers_test() {
  // Setup: Create a game with multiple attackers and blockers
  let state = game.new()

  // Add attackers to player 1's battlefield (no summoning sickness)
  let attacker1 = create_test_creature("attacker1", "Bears")
  let attacker2 = create_test_creature("attacker2", "Wolves")
  let state =
    add_creature_to_battlefield(state, 1, attacker1, -1)
    |> add_creature_to_battlefield(1, attacker2, -1)

  // Add blockers to player 2's battlefield (no summoning sickness)
  let blocker1 = create_test_creature("blocker1", "Wall 1")
  let blocker2 = create_test_creature("blocker2", "Wall 2")
  let state =
    add_creature_to_battlefield(state, 2, blocker1, -1)
    |> add_creature_to_battlefield(2, blocker2, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, game.DeclareAttackers)

  // Player 1 declares attackers
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker1.id, game.AttackPlayer(2)),
        game.AttackPair(attacker2.id, game.AttackPlayer(2)),
      ]),
    )

  // Both players pass
  let state = pass(state)

  // Player 2 declares blockers
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker1.id, attacker1.id),
        game.BlockPair(blocker2.id, attacker2.id),
      ]),
    )

  // Verify blocking was recorded
  assert state.blocking_creatures
    == [
      game.BlockPair(blocker1.id, attacker1.id),
      game.BlockPair(blocker2.id, attacker2.id),
    ]
}

pub fn cannot_block_with_tapped_creature_test() {
  // Setup: Create a game with an attacker and a tapped blocker
  let state = game.new()

  let attacker = create_test_creature("attacker1", "Bears")
  let blocker = create_test_creature("blocker1", "Wall")

  let state = add_creature_to_battlefield(state, 1, attacker, -1)
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Tap the blocker
  let state =
    game.State(
      ..state,
      players: player.update(state.players, 2, fn(p) {
        player.Player(
          ..p,
          battlefield: permanent.update(p.battlefield, blocker.id, fn(perm) {
            permanent.Permanent(..perm, tapped: True)
          }),
        )
      }),
    )

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, game.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )
  let state = pass(state)

  // Try to block with tapped creature - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker.id, attacker.id),
      ]),
    )

  assert result.is_error(result)
}

pub fn cannot_block_creature_attacking_different_player_test() {
  // Setup: In a multiplayer game, this test ensures blockers can't block attackers
  // that aren't attacking them
  let state = game.new_multiplayer(4)

  let attacker_p2 = create_test_creature("attacker1", "Bears")
  let attacker_p3 = create_test_creature("attacker2", "Bears")
  let blocker_p2 = create_test_creature("blocker1", "Wall")
  let blocker_p3 = create_test_creature("blocker2", "Goblin")

  let state =
    add_creature_to_battlefield(state, 1, attacker_p2, -1)
    |> add_creature_to_battlefield(1, attacker_p3, -1)
    |> add_creature_to_battlefield(2, blocker_p2, -1)
    |> add_creature_to_battlefield(3, blocker_p3, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, game.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker_p2.id, game.AttackPlayer(2)),
        game.AttackPair(attacker_p3.id, game.AttackPlayer(3)),
      ]),
    )
  let state = pass(state)

  // Player 2 tries to block the creature attacking player 3
  let result =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker_p2.id, attacker_p3.id),
      ]),
    )

  assert result.is_error(result)
}

pub fn cannot_block_in_wrong_step_test() {
  let state = game.new()

  let result = action.dispatch(state, action.DeclareBlockers(2, []))

  assert result.is_error(result)
}

pub fn wrong_player_cannot_declare_blockers_test() {
  // Setup: Create a game with an attacker
  let state = game.new()

  let attacker = create_test_creature("attacker1", "Bears")
  let state = add_creature_to_battlefield(state, 1, attacker, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, game.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker.id, game.AttackPlayer(2)),
      ]),
    )
  let state = pass(state)

  // We should be in DeclareBlockers step with player 2 declaring
  assert state.step == game.DeclareBlockers
  assert state.choice_player == Some(2)

  // Try to have player 1 (not the declaring player) declare blocks - should fail
  let result = action.dispatch(state, action.DeclareBlockers(1, []))

  assert result.is_error(result)
}

pub fn cannot_block_with_same_creature_twice_test() {
  // Test that a creature cannot block multiple attackers without special ability
  let state = game.new()

  // Add attackers (no summoning sickness)
  let attacker1 = create_test_creature("attacker1", "Bears")
  let attacker2 = create_test_creature("attacker2", "Wolves")
  let state = add_creature_to_battlefield(state, 1, attacker1, -1)
  let state = add_creature_to_battlefield(state, 1, attacker2, -1)

  // Add blocker (no summoning sickness)
  let blocker = create_test_creature("blocker1", "Wall")
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers and declare attackers
  let state = pass_until(state, game.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker1.id, game.AttackPlayer(2)),
        game.AttackPair(attacker2.id, game.AttackPlayer(2)),
      ]),
    )
  let state = pass(state)

  // Try to block both attackers with the same creature - should fail
  let result =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker.id, attacker1.id),
        game.BlockPair(blocker.id, attacker2.id),
      ]),
    )

  assert result.is_error(result)
}

pub fn some_attackers_blocked_some_unblocked_test() {
  // Test that some attackers can be blocked while others remain unblocked
  let state = game.new()

  // Add attackers (no summoning sickness)
  let attacker1 = create_test_creature("attacker1", "Bears")
  let attacker2 = create_test_creature("attacker2", "Wolves")
  let state =
    add_creature_to_battlefield(state, 1, attacker1, -1)
    |> add_creature_to_battlefield(1, attacker2, -1)

  // Add one blocker (no summoning sickness)
  let blocker = create_test_creature("blocker1", "Wall")
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers and declare attackers
  let state = pass_until(state, game.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        game.AttackPair(attacker1.id, game.AttackPlayer(2)),
        game.AttackPair(attacker2.id, game.AttackPlayer(2)),
      ]),
    )
  let state = pass(state)

  // Block only one attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        game.BlockPair(blocker.id, attacker1.id),
      ]),
    )

  // Verify only one block was recorded
  assert state.blocking_creatures == [game.BlockPair(blocker.id, attacker1.id)]
}
