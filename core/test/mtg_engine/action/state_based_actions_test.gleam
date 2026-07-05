import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effect_resolver
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/supertype
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, create_test_creature, pass,
  pass_until,
}

fn create_legendary_creature(id: String, name: String) -> card.Card {
  card.Card(..create_test_creature(id, name), supertypes: [
    supertype.Legendary,
  ])
}

fn add_legendary_to_battlefield(
  state: state.State,
  player_id: Int,
  creature: card.Card,
  entered_cycle: Int,
) -> state.State {
  let creature_permanent =
    permanent.Permanent(
      card: creature,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: entered_cycle,
      damage: 0,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, creature.id, creature_permanent),
      )
    }),
  )
}

// Test: Two legendary permanents with same name → one is sacrificed
pub fn legend_rule_same_name_test() {
  let state = state.new()
  let legendary1 = create_legendary_creature("legend1", "Kibo")
  let legendary2 = create_legendary_creature("legend2", "Kibo")

  let state = add_legendary_to_battlefield(state, 1, legendary1, 0)
  let state = add_legendary_to_battlefield(state, 1, legendary2, 0)

  // Before SBA, both should be on battlefield
  let assert Ok(p1_before) = player.find(state.players, 1)
  assert dict.size(p1_before.battlefield) == 2

  let state = effect_resolver.check_state_based_actions(state)

  // After SBA, only one should remain, one should be in graveyard
  let assert Ok(p1_after) = player.find(state.players, 1)
  assert dict.size(p1_after.battlefield) == 1
  assert list.length(p1_after.graveyard) == 1
  let assert Ok(gy_card) = list.first(p1_after.graveyard)
  assert gy_card.name == "Kibo"
}

// Test: Two legendary permanents with different names → both stay
pub fn legend_rule_different_names_test() {
  let state = state.new()
  let legendary1 = create_legendary_creature("legend1", "Kibo")
  let legendary2 = create_legendary_creature("legend2", "Muxus")

  let state = add_legendary_to_battlefield(state, 1, legendary1, 0)
  let state = add_legendary_to_battlefield(state, 1, legendary2, 0)

  let state = effect_resolver.check_state_based_actions(state)

  // Both should remain since names are different
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert p1.graveyard == []
}

// Test: Non-legendary permanents with same name → both stay
pub fn legend_rule_non_legendary_same_name_test() {
  let state = state.new()
  let creature1 = create_test_creature("creature1", "Squirrel")
  let creature2 = create_test_creature("creature2", "Squirrel")

  let state = add_creature_to_battlefield(state, 1, creature1, 0)
  let state = add_creature_to_battlefield(state, 1, creature2, 0)

  let state = effect_resolver.check_state_based_actions(state)

  // Both should remain since they're not legendary
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  assert p1.graveyard == []
}

// Test: Legend rule only affects the controlling player, not other players
pub fn legend_rule_per_player_test() {
  let state = state.new()
  let legendary1 = create_legendary_creature("legend1", "Kibo")
  let legendary2 = create_legendary_creature("legend2", "Kibo")

  let state = add_legendary_to_battlefield(state, 1, legendary1, 0)
  let state = add_legendary_to_battlefield(state, 2, legendary2, 0)

  let state = effect_resolver.check_state_based_actions(state)

  // Both should remain since each player only controls one
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  assert dict.size(p1.battlefield) == 1
  assert dict.size(p2.battlefield) == 1
  assert p1.graveyard == []
  assert p2.graveyard == []
}

// Test: Three legendary permanents with same name → two are sacrificed
pub fn legend_rule_three_same_name_test() {
  let state = state.new()
  let legendary1 = create_legendary_creature("legend1", "Kibo")
  let legendary2 = create_legendary_creature("legend2", "Kibo")
  let legendary3 = create_legendary_creature("legend3", "Kibo")

  let state = add_legendary_to_battlefield(state, 1, legendary1, 0)
  let state = add_legendary_to_battlefield(state, 1, legendary2, 0)
  let state = add_legendary_to_battlefield(state, 1, legendary3, 0)

  let state = effect_resolver.check_state_based_actions(state)

  // After SBA, only one should remain, two should be in graveyard
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 1
  assert list.length(p1.graveyard) == 2
}

// Integration test: Legend rule fires during spell resolution
pub fn legend_rule_during_spell_resolution_test() {
  let state = state.new()
  let legendary1 = create_legendary_creature("legend1", "Kibo")
  let legendary2 = create_legendary_creature("legend2", "Kibo")

  let state = add_legendary_to_battlefield(state, 1, legendary1, 0)
  let state = add_legendary_to_battlefield(state, 1, legendary2, 0)

  // Before SBA, both should be on battlefield
  let assert Ok(p1_before) = player.find(state.players, 1)
  assert dict.size(p1_before.battlefield) == 2

  // Add a creature to hand and cast it to trigger SBA check on resolution
  let creature = create_test_creature("creature3", "Random Bear")
  let state = add_card_to_hand(state, 1, creature)
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature3", 0))

  // Pass priority - creature resolves, triggering SBA
  let state = pass(state)

  // After resolution, legend rule should have been applied
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 2
  // The new creature + 1 legendary
  assert list.length(p1.graveyard) == 1
  // 1 legendary sacrificed
}

// ── Aura illegal attachment (704.5m) ──────────────────────

fn create_aura_card(id: String, name: String) -> card.Card {
  card.Card(..create_test_creature(id, name), subtypes: ["Aura"])
}

fn add_aura_to_battlefield(
  state: state.State,
  player_id: Int,
  aura: card.Card,
  attached_to: String,
) -> state.State {
  let aura_permanent =
    permanent.Permanent(
      card: aura,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: Some(attached_to),
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, aura.id, aura_permanent),
      )
    }),
  )
}

// Test: Aura with no attached target -> Aura goes to graveyard
pub fn aura_with_no_attachment_goes_to_graveyard_test() {
  let state = state.new()
  let aura_card = create_aura_card("aura1", "Test Aura")
  let aura_permanent =
    permanent.Permanent(
      card: aura_card,
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

  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: dict.insert(p.battlefield, "aura1", aura_permanent),
        )
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Aura should be in graveyard (not attached to anything)
  let assert Ok(p1) = player.find(state.players, 1)
  assert !dict.has_key(p1.battlefield, "aura1")
  assert list.length(p1.graveyard) == 1
  let assert Ok(gy_card) = list.first(p1.graveyard)
  assert gy_card.id == "aura1"
}

// Test: Aura attached to a creature that is destroyed -> Aura goes to graveyard
pub fn aura_attached_to_destroyed_creature_goes_to_graveyard_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let aura = create_aura_card("aura1", "Test Aura")

  let state = add_creature_to_battlefield(state, 1, creature, 0)
  let state = add_aura_to_battlefield(state, 1, aura, "creature1")

  // First, destroy the creature so it's no longer on the battlefield
  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(..p, battlefield: dict.delete(p.battlefield, "creature1"))
      }),
    )

  // Check state-based actions - aura should now be illegal
  let state = effect_resolver.check_state_based_actions(state)

  // Aura should be in graveyard
  let assert Ok(p1) = player.find(state.players, 1)
  assert !dict.has_key(p1.battlefield, "aura1")
  assert list.length(p1.graveyard) >= 1
}

// Test: Aura attached to a creature that is still on battlefield -> Aura stays
pub fn aura_attached_to_valid_creature_stays_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let aura = create_aura_card("aura1", "Test Aura")

  let state = add_creature_to_battlefield(state, 1, creature, 0)
  let state = add_aura_to_battlefield(state, 1, aura, "creature1")

  let state = effect_resolver.check_state_based_actions(state)

  // Both should still be on battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "creature1")
  assert dict.has_key(p1.battlefield, "aura1")
  assert p1.graveyard == []
}

// ── Equipment illegal attachment (704.5n) ──────────────────

fn create_equipment_card(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    supertypes: [],
    subtypes: ["Equipment"],
    card_type: card_type.Artifact,
    mana_cost: mana.Cost(
      generic: 1,
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: None,
    toughness: None,
    abilities: [],
    is_token: False,
  )
}

fn add_equipment_to_battlefield(
  state: state.State,
  player_id: Int,
  equipment: card.Card,
  attached_to: String,
) -> state.State {
  let equipment_permanent =
    permanent.Permanent(
      card: equipment,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: Some(attached_to),
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(
          p.battlefield,
          equipment.id,
          equipment_permanent,
        ),
      )
    }),
  )
}

// Test: Equipment with no attached target -> stays on battlefield
pub fn equipment_with_no_attachment_stays_test() {
  let state = state.new()
  let equipment = create_equipment_card("equip1", "Test Equipment")
  let eq_permanent =
    permanent.Permanent(
      card: equipment,
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

  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: dict.insert(p.battlefield, "equip1", eq_permanent),
        )
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Equipment should stay on battlefield (unattached is fine)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "equip1")
  assert p1.graveyard == []
}

// Test: Equipment attached to a creature that is destroyed -> becomes unattached
pub fn equipment_attached_to_destroyed_creature_becomes_unattached_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let equipment = create_equipment_card("equip1", "Test Equipment")

  let state = add_creature_to_battlefield(state, 1, creature, 0)
  let state = add_equipment_to_battlefield(state, 1, equipment, "creature1")

  // Destroy the creature
  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(..p, battlefield: dict.delete(p.battlefield, "creature1"))
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Equipment should stay on battlefield but become unattached
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "equip1")
  assert p1.graveyard == []

  let assert Ok(eq_perm) = permanent.find(p1.battlefield, "equip1")
  assert eq_perm.attached_to == None
}

// Test: Equipment attached to valid creature -> stays attached
pub fn equipment_attached_to_valid_creature_stays_attached_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let equipment = create_equipment_card("equip1", "Test Equipment")

  let state = add_creature_to_battlefield(state, 1, creature, 0)
  let state = add_equipment_to_battlefield(state, 1, equipment, "creature1")

  let state = effect_resolver.check_state_based_actions(state)

  // Both should stay on battlefield and equipment should stay attached
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "creature1")
  assert dict.has_key(p1.battlefield, "equip1")
  assert p1.graveyard == []

  let assert Ok(eq_perm) = permanent.find(p1.battlefield, "equip1")
  assert eq_perm.attached_to == Some("creature1")
}

// Test: Regular enchantment (no Aura subtype) that is unattached -> stays
pub fn regular_enchantment_unattached_stays_test() {
  let state = state.new()
  let enchantment =
    card.Card(
      id: "ench1",
      name: "Test Enchantment",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Enchantment,
      mana_cost: mana.Cost(
        generic: 1,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      abilities: [],
      is_token: False,
    )

  let ench_permanent =
    permanent.Permanent(
      card: enchantment,
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

  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: dict.insert(p.battlefield, "ench1", ench_permanent),
        )
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Enchantment should stay (it's not an Aura, so the SBA doesn't affect it)
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "ench1")
  assert p1.graveyard == []
}

// Test: Aura attached to another player's creature across players -> stays
pub fn aura_attached_across_players_stays_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let aura = create_aura_card("aura1", "Test Aura")

  // Player 2 controls the creature, player 1 controls the aura
  let state = add_creature_to_battlefield(state, 2, creature, 0)
  let state = add_aura_to_battlefield(state, 1, aura, "creature1")

  let state = effect_resolver.check_state_based_actions(state)

  // Both should still be on their respective battlefields
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  assert dict.has_key(p1.battlefield, "aura1")
  assert dict.has_key(p2.battlefield, "creature1")
  assert p1.graveyard == []
  assert p2.graveyard == []
}

// Test: Equipment attached across players is fine as long as target exists
pub fn equipment_attached_across_players_stays_test() {
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Creature")
  let equipment = create_equipment_card("equip1", "Test Equipment")

  // Player 2 controls the creature, player 1 controls the equipment
  let state = add_creature_to_battlefield(state, 2, creature, 0)
  let state = add_equipment_to_battlefield(state, 1, equipment, "creature1")

  let state = effect_resolver.check_state_based_actions(state)

  // Both should stay
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(p2) = player.find(state.players, 2)
  assert dict.has_key(p1.battlefield, "equip1")
  assert dict.has_key(p2.battlefield, "creature1")
  let assert Ok(eq_perm) = permanent.find(p1.battlefield, "equip1")
  assert eq_perm.attached_to == Some("creature1")
}

// ── Token in non-battlefield zone ceases to exist (704.5d) ──

fn create_token_card(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    supertypes: [],
    subtypes: [],
    card_type: card_type.Creature,
    mana_cost: mana.Cost(
      generic: 0,
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: Some(1),
    toughness: Some(1),
    abilities: [],
    is_token: True,
  )
}

fn add_card_to_exile(
  state: state.State,
  player_id: Int,
  card: card.Card,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, exile: [card, ..p.exile])
    }),
  )
}

// Test: Token on battlefield should stay after SBA check
pub fn token_on_battlefield_stays_test() {
  let state = state.new()
  let token = create_token_card("token1", "Token Creature")
  let state = add_creature_to_battlefield(state, 1, token, 0)

  let state = effect_resolver.check_state_based_actions(state)

  // Token should still be on battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.has_key(p1.battlefield, "token1")
  assert p1.graveyard == []
  assert p1.exile == []
}

// Test: Token in exile is removed after SBA check
pub fn token_in_exile_is_removed_test() {
  let state = state.new()
  let token = create_token_card("token1", "Token Creature")
  let state = add_card_to_exile(state, 1, token)

  let state = effect_resolver.check_state_based_actions(state)

  // Token should be removed from exile
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.exile == []
}

// Test: Token in graveyard is removed after SBA check
pub fn token_in_graveyard_is_removed_test() {
  let state = state.new()
  let token = create_token_card("token1", "Token Creature")

  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(..p, graveyard: [token, ..p.graveyard])
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Token should be removed from graveyard
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.graveyard == []
}

// Test: Token in hand is removed after SBA check
pub fn token_in_hand_is_removed_test() {
  let state = state.new()
  let token = create_token_card("token1", "Token Creature")

  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(..p, hand: [token, ..p.hand])
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Token should be removed from hand
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.hand == []
}

// Test: Non-token cards in non-battlefield zones are NOT removed
pub fn non_token_cards_in_non_battlefield_zones_stay_test() {
  let state = state.new()
  let non_token = create_test_creature("card1", "Real Creature")

  // Place non-token card in hand, graveyard, and exile
  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          hand: [non_token, ..p.hand],
          graveyard: [non_token, ..p.graveyard],
          exile: [non_token, ..p.exile],
        )
      }),
    )

  let state = effect_resolver.check_state_based_actions(state)

  // Non-token cards should remain
  let assert Ok(p1) = player.find(state.players, 1)
  assert list.length(p1.hand) == 1
  assert list.length(p1.graveyard) == 1
  assert list.length(p1.exile) == 1
}

// ── Chained SBA test ────────────────────────────────────────────
// Test that SBA loop catches chains: creature dies -> equipment becomes unattached

fn add_equipment_card_to_battlefield(
  state: state.State,
  player_id: Int,
  equipment: card.Card,
  attached_to: String,
) -> state.State {
  let eq_permanent =
    permanent.Permanent(
      card: equipment,
      owner_id: player_id,
      tapped: False,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: Some(attached_to),
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: dict.insert(p.battlefield, equipment.id, eq_permanent),
      )
    }),
  )
}

fn add_damage_to_permanent(
  state: state.State,
  player_id: Int,
  card_id: String,
  amount: Int,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(
        ..p,
        battlefield: permanent.update(p.battlefield, card_id, fn(perm) {
          permanent.Permanent(..perm, damage: perm.damage + amount)
        }),
      )
    }),
  )
}

pub fn chained_creature_death_equipment_unattach_test() {
  // Scenario: A creature with lethal damage causes it to die.
  // An equipment attached to that creature should become unattached.
  // The SBA loop should handle this in a single check_state_based_actions call.
  let state = state.new()
  let creature = create_test_creature("creature1", "Test Bear")
  let equipment =
    card.Card(
      id: "equip1",
      name: "Test Equipment",
      supertypes: [],
      subtypes: ["Equipment"],
      card_type: card_type.Artifact,
      mana_cost: mana.Cost(
        generic: 1,
        white: 0,
        blue: 0,
        black: 0,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      abilities: [],
      is_token: False,
    )

  let state = add_creature_to_battlefield(state, 1, creature, 0)
  let state =
    add_equipment_card_to_battlefield(state, 1, equipment, "creature1")

  // Creature has 2 toughness, deal 3 damage
  let state = add_damage_to_permanent(state, 1, "creature1", 3)

  // Before SBA, creature is on battlefield with damage, equipment is attached
  let assert Ok(p_before) = player.find(state.players, 1)
  assert dict.has_key(p_before.battlefield, "creature1")
  assert dict.has_key(p_before.battlefield, "equip1")
  let assert Ok(eq_before) = permanent.find(p_before.battlefield, "equip1")
  assert eq_before.attached_to == Some("creature1")

  // Single SBA check should handle both: creature death + equipment unattach
  let state = effect_resolver.check_state_based_actions(state)

  // After SBA: creature is dead, equipment is unattached
  let assert Ok(p_after) = player.find(state.players, 1)
  assert !dict.has_key(p_after.battlefield, "creature1")
  assert list.length(p_after.graveyard) >= 1
  let assert Ok(gy_card) = list.first(p_after.graveyard)
  assert gy_card.id == "creature1"

  // Equipment should still be on battlefield but unattached
  assert dict.has_key(p_after.battlefield, "equip1")
  let assert Ok(eq_after) = permanent.find(p_after.battlefield, "equip1")
  assert eq_after.attached_to == None
}
