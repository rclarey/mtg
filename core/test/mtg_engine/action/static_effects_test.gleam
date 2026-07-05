import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/card_type
import mtg_engine/combat
import mtg_engine/effect_resolver
import mtg_engine/effects
import mtg_engine/extensions
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import test_helpers.{
  add_creature_to_battlefield, add_land_to_battlefield, create_creature,
  create_test_land, get_permanent, get_player, pass, pass_until,
}

fn noop_mana() -> mana.Produced {
  mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
}

// ===== PumpAll Tests =====

pub fn pump_all_grants_power_toughness_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 3)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  // Dispatch a no-op action through dispatch_with_ext to trigger static effects
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Base 2/3 +1/+1 = 3/4
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(4)
}

pub fn pump_all_filter_non_matching_unaffected_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 3)
  // This land should not be affected by the pump
  let land = create_test_land("land1", "Forest")

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)
    |> add_land_to_battlefield(1, land)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Creature should be buffed
  let perm = get_permanent(state, 1, creature.id)
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(4)

  // Land should be unaffected (no power/toughness to begin with)
  let land_perm = get_permanent(state, 1, land.id)
  assert land_perm.card.power == None
  assert land_perm.card.toughness == None
}

pub fn pump_all_multiple_creatures_test() {
  let creature1 = create_creature("c1", "Bear", 2, 2)
  let creature2 = create_creature("c2", "Wolf", 3, 3)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature1, 0)
    |> add_creature_to_battlefield(1, creature2, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 2,
        toughness: 0,
        keywords: [],
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Both creatures should get +2/+0
  let perm1 = get_permanent(state, 1, creature1.id)
  assert perm1.card.power == Some(4)
  assert perm1.card.toughness == Some(2)

  let perm2 = get_permanent(state, 1, creature2.id)
  assert perm2.card.power == Some(5)
  assert perm2.card.toughness == Some(3)
}

pub fn pump_all_different_players_test() {
  let creature_p1 = create_creature("c1", "P1 Creature", 2, 2)
  let creature_p2 = create_creature("c2", "P2 Creature", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature_p1, 0)
    |> add_creature_to_battlefield(2, creature_p2, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Both players' creatures should be buffed
  let perm1 = get_permanent(state, 1, creature_p1.id)
  assert perm1.card.power == Some(3)
  assert perm1.card.toughness == Some(3)

  let perm2 = get_permanent(state, 2, creature_p2.id)
  assert perm2.card.power == Some(3)
  assert perm2.card.toughness == Some(3)
}

// ===== GrantKeyword Tests =====

pub fn grant_keyword_adds_keyword_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Haste,
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  assert list.contains(perm.granted_keywords, "Haste")
}

pub fn grant_keyword_filter_non_matching_unaffected_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 2)
  let land = create_test_land("land1", "Forest")

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)
    |> add_land_to_battlefield(1, land)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Trample,
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Creature should have Trample
  let perm = get_permanent(state, 1, creature.id)
  assert list.contains(perm.granted_keywords, "Trample")

  // Land should not have Trample
  let land_perm = get_permanent(state, 1, land.id)
  assert !list.contains(land_perm.granted_keywords, "Trample")
}

// ===== Combined Static Effects Tests =====

pub fn multiple_static_effects_combined_test() {
  let creature = create_creature("creature1", "Test Subject", 1, 1)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 2,
        toughness: 2,
        keywords: [effects.Vigilance],
      ),
      "test",
    )
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Flying,
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Should have +2/+2
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(3)
  // Should have Vigilance (from PumpAll) and Flying (from GrantKeyword)
  assert list.contains(perm.granted_keywords, "Vigilance")
  assert list.contains(perm.granted_keywords, "Flying")
}

// ===== Idempotency Tests =====

pub fn static_effects_do_not_compound_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  // Dispatch multiple times - effect should not compound
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Should still be 3/3, not 5/5
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(3)
}

pub fn grant_keyword_does_not_compound_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Haste,
      ),
      "test",
    )

  // Dispatch multiple times - Haste should appear only once in granted_keywords
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Should have Haste
  assert list.contains(perm.granted_keywords, "Haste")
  // Should NOT have Haste duplicated
  let haste_count =
    list.fold(perm.granted_keywords, 0, fn(count, kw) {
      case kw == "Haste" {
        True -> count + 1
        False -> count
      }
    })
  assert haste_count == 1
}

// ===== Combat Integration Tests =====

pub fn pump_all_increases_unblocked_attacker_damage_test() {
  let attacker = create_creature("attacker1", "Buff Bear", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> pass_until(step.DeclareAttackers)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  // Declare attackers through dispatch_with_ext so static effects are applied
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.DeclareAttackers(1, [
        combat.AttackPair(attacker.id, combat.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  // Declare no blockers
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(state, extensions, action.DeclareBlockers(2, []))

  let state = pass(state)

  // Assign no damage (unblocked damage is automatic)
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(state, extensions, action.AssignDamage(1, []))

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(state, extensions, action.AssignDamage(2, []))

  // Player 2 should have taken 3 damage (base 2 + 1 from PumpAll), not 2
  let player2 = get_player(state, 2)
  assert player2.life == 17
}

pub fn pump_all_affects_blocked_combat_damage_test() {
  let attacker = create_creature("attacker1", "Buff Bear", 2, 2)
  let blocker = create_creature("blocker1", "Wall", 1, 5)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, attacker, -1)
    |> add_creature_to_battlefield(2, blocker, -1)
    |> pass_until(step.DeclareAttackers)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  // Declare attackers
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.DeclareAttackers(1, [
        combat.AttackPair(attacker.id, combat.AttackPlayer(2)),
      ]),
    )

  let state = pass(state)

  // Declare blockers
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.DeclareBlockers(2, [combat.BlockPair(blocker.id, attacker.id)]),
    )

  let state = pass(state)

  // Assign damage - attacker now has power 3, blocker has toughness 5+1=6 and power 2
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.AssignDamage(1, [
        combat.DamageAssignment(3, attacker.id, blocker.id),
      ]),
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.AssignDamage(2, [
        combat.DamageAssignment(2, blocker.id, attacker.id),
      ]),
    )

  // Attacker should have 2 damage and survive (base 2 + 1 from pump = 3 toughness)
  let attacker_perm = get_permanent(state, 1, attacker.id)
  assert attacker_perm.damage == 2
  // Should still be on battlefield
  assert dict.has_key(get_player(state, 1).battlefield, attacker.id)

  // Blocker should have 3 damage and survive (base 5 + 1 from pump = 6 toughness)
  let blocker_perm = get_permanent(state, 2, blocker.id)
  assert blocker_perm.damage == 3
  assert dict.has_key(get_player(state, 2).battlefield, blocker.id)
}

// ===== No Static Effects Test =====

pub fn no_static_effects_state_unchanged_test() {
  let creature = create_creature("creature1", "Test Subject", 2, 3)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  // Use default extensions (no static effects)
  let extensions = extensions.new()

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  assert perm.card.power == Some(2)
  assert perm.card.toughness == Some(3)
  assert perm.granted_keywords == []
}

// ===== StaticEffect with Name Filter =====

pub fn pump_all_name_filter_test() {
  let creature1 = create_creature("c1", "Grizzly Bears", 2, 2)
  let creature2 = create_creature("c2", "Wolf", 3, 3)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature1, 0)
    |> add_creature_to_battlefield(1, creature2, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Name("Grizzly Bears"),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Grizzly Bears should be buffed
  let perm1 = get_permanent(state, 1, creature1.id)
  assert perm1.card.power == Some(3)
  assert perm1.card.toughness == Some(3)

  // Wolf should be unaffected
  let perm2 = get_permanent(state, 1, creature2.id)
  assert perm2.card.power == Some(3)
  assert perm2.card.toughness == Some(3)
}

// ===== Static Effects with Newly Entered Creature =====

pub fn static_effects_apply_to_newly_summoned_creature_test() {
  let existing = create_creature("existing", "Existing Bear", 2, 2)
  let newcomer = create_creature("newcomer", "New Bear", 1, 1)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, existing, 0)
    |> add_creature_to_battlefield(1, newcomer, 0)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "test",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Both creatures should be buffed
  let perm1 = get_permanent(state, 1, existing.id)
  assert perm1.card.power == Some(3)
  assert perm1.card.toughness == Some(3)

  let perm2 = get_permanent(state, 1, newcomer.id)
  assert perm2.card.power == Some(2)
  assert perm2.card.toughness == Some(2)
}

// ===== Layer Ordering Tests (Rule 613) =====

pub fn grant_keyword_layer_before_pump_all_test() {
  // GrantKeyword (Layer 6 - Ability) should be applied before PumpAll (Layer 7 - PT).
  // This test verifies that a creature gets a keyword granted by a Layer 6 effect
  // before a PumpAll Layer 7 effect checks what keywords exist.
  // Since both effects append to granted_keywords, the order manifests as
  // PumpAll's keywords appearing after GrantKeyword's in the list.

  let creature = create_creature("creature1", "Test Subject", 1, 1)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    // Add PumpAll (Layer 7) effect first
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [effects.Trample],
      ),
      "pump_source",
    )
    // Add GrantKeyword (Layer 6) effect second (should be applied first due to layer order)
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Flying,
      ),
      "grant_source",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Creature should have both Flying (from GrantKeyword, Layer 6) and Trample (from PumpAll, Layer 7)
  assert list.contains(perm.granted_keywords, "Flying")
  assert list.contains(perm.granted_keywords, "Trample")
  // Power/Toughness should reflect the PumpAll bonus
  assert perm.card.power == Some(2)
  assert perm.card.toughness == Some(2)
}

pub fn older_timestamp_within_same_layer_applied_first_test() {
  // Within the same layer, older timestamp effects should be applied before newer ones.
  // Both PumpAll effects are Layer 7, so they should be sorted by timestamp.
  // The effect added first (older timestamp) applies first, then the newer one.
  // Since both modify power/toughness, the final result is cumulative regardless of order,
  // but the ordering affects intermediate states.

  let creature = create_creature("creature1", "Test Subject", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  let extensions =
    extensions.new()
    // Add first PumpAll (timestamp 0) - older
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 0,
        keywords: [],
      ),
      "source_a",
    )
    // Add second PumpAll (timestamp 1) - newer
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 0,
        toughness: 2,
        keywords: [],
      ),
      "source_b",
    )

  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  let perm = get_permanent(state, 1, creature.id)
  // Both effects should be applied: +1/+0 and +0/+2 = +1/+2 total
  assert perm.card.power == Some(3)
  assert perm.card.toughness == Some(4)
}

// ===== Static Effect Removal Tests =====

pub fn remove_static_effects_by_source_filters_correctly_test() {
  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "source_a",
    )
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 2,
        toughness: 2,
        keywords: [],
      ),
      "source_b",
    )

  // Remove source_a
  let extensions =
    extensions.remove_static_effects_by_source(extensions, "source_a")

  // Should have 1 effect remaining
  assert list.length(extensions.static_effects) == 1

  // The remaining effect should be from source_b
  let assert Ok(remaining) = list.first(extensions.static_effects)
  assert remaining.source == "source_b"
}

pub fn remove_static_effects_by_source_removes_all_from_same_source_test() {
  // Two effects from the same source should both be removed
  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "the_source",
    )
    |> extensions.add_static_effect(
      effects.GrantKeyword(
        filter: filters.Types([card_type.Creature]),
        keyword: effects.Haste,
      ),
      "the_source",
    )
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 3,
        toughness: 3,
        keywords: [],
      ),
      "other_source",
    )

  let extensions =
    extensions.remove_static_effects_by_source(extensions, "the_source")

  // Should have 1 effect remaining (from other_source)
  assert list.length(extensions.static_effects) == 1
  let assert Ok(remaining) = list.first(extensions.static_effects)
  assert remaining.source == "other_source"
}

pub fn check_state_based_actions_tracks_dead_creature_test() {
  // Creature with 0 toughness - dies as a state-based action
  let creature = create_creature("dead_creature", "Dead Creature", 1, 0)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  // Call check_state_based_actions - the 0-toughness creature should die
  let state = effect_resolver.check_state_based_actions(state)

  // The creature should be in pending_removed_sources
  assert list.contains(state.pending_removed_sources, "dead_creature")

  // Creature should no longer be on the battlefield
  let p = get_player(state, 1)
  assert !dict.has_key(p.battlefield, "dead_creature")
}

pub fn static_effect_stops_applying_when_source_dies_test() {
  let source_card = create_creature("source", "Source Creature", 1, 2)
  let target_card = create_creature("target", "Target Creature", 2, 2)

  // Create source permanent with lethal damage (5 damage vs 2 base toughness)
  let source_perm =
    permanent.Permanent(
      card: source_card,
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 5,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let target_perm =
    permanent.Permanent(
      card: target_card,
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let battlefield =
    dict.from_list([#("source", source_perm), #("target", target_perm)])
  let s = state.new()
  let players =
    player.update(s.players, 1, fn(p) { player.Player(..p, battlefield:) })
  let state = state.State(..s, players:)

  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "source",
    )

  // First dispatch: static effects apply (source is alive)
  let assert Ok(#(state, extensions)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Target should be 3/3 (2/2 +1/+1)
  let target_perm = get_permanent(state, 1, "target")
  assert target_perm.card.power == Some(3)
  assert target_perm.card.toughness == Some(3)

  // Call check_state_based_actions - source dies from lethal damage
  let state = effect_resolver.check_state_based_actions(state)

  // Source should be dead and removed from battlefield
  let p = get_player(state, 1)
  assert !dict.has_key(p.battlefield, "source")

  // pending_removed_sources should track the source
  assert list.contains(state.pending_removed_sources, "source")

  // Dispatch to consume pending_removed_sources (effect still applied this time)
  let assert Ok(#(state, extensions)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Next dispatch: effect should be gone since source was removed from extensions
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Target should be back to 2/2 (no longer getting +1/+1 from source)
  let target_perm = get_permanent(state, 1, "target")
  assert target_perm.card.power == Some(2)
  assert target_perm.card.toughness == Some(2)
}

pub fn static_effect_from_other_sources_still_applies_test() {
  let source_card = create_creature("source", "Source Creature", 1, 2)
  let other_card = create_creature("other", "Other Source", 1, 1)
  let target_card = create_creature("target", "Target Creature", 2, 2)

  // Create source permanent with lethal damage
  let source_perm =
    permanent.Permanent(
      card: source_card,
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 5,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let other_perm =
    permanent.Permanent(
      card: other_card,
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let target_perm =
    permanent.Permanent(
      card: target_card,
      owner_id: 1,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let battlefield =
    dict.from_list([
      #("source", source_perm),
      #("other", other_perm),
      #("target", target_perm),
    ])
  let s = state.new()
  let players =
    player.update(s.players, 1, fn(p) { player.Player(..p, battlefield:) })
  let state = state.State(..s, players:)

  let extensions =
    extensions.new()
    // Effect from source that will die
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 1,
        toughness: 0,
        keywords: [],
      ),
      "source",
    )
    // Effect from other source that stays alive
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.Types([card_type.Creature]),
        power: 0,
        toughness: 2,
        keywords: [],
      ),
      "other",
    )

  // First dispatch: both effects apply
  let assert Ok(#(state, extensions)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Target should be 3/4 (2/2 +1/+0 from source +0/+2 from other)
  let target_perm = get_permanent(state, 1, "target")
  assert target_perm.card.power == Some(3)
  assert target_perm.card.toughness == Some(4)

  // Kill source via state-based actions
  let state = effect_resolver.check_state_based_actions(state)

  // Dispatch to consume pending_removed_sources
  let assert Ok(#(state, extensions)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Next dispatch: only the "other" effect should remain
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions,
      action.ProduceMana(1, noop_mana()),
    )

  // Target should be 2/4 (only +0/+2 from "other", +1/+0 from "source" is gone)
  let target_perm = get_permanent(state, 1, "target")
  assert target_perm.card.power == Some(2)
  assert target_perm.card.toughness == Some(4)
}

pub fn lose_game_tracks_battlefield_sources_test() {
  let creature = create_creature("c1", "Test Creature", 1, 1)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, creature, 0)

  // Player 1 loses the game
  let state = effect_resolver.lose_game(state, 1)

  // The creature's ID should be in pending_removed_sources
  assert list.contains(state.pending_removed_sources, "c1")
}
