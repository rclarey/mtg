import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/combat
import mtg_engine/effect_resolver
import mtg_engine/effects
import mtg_engine/error
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/stack
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import mtg_engine/trigger
import test_helpers.{
  add_card_to_hand, add_creature_to_battlefield, create_test_creature,
  get_permanent, pass, pass_until,
}

// Test creature with EntersBattlefield trigger puts trigger on the stack when it resolves
pub fn enters_battlefield_trigger_fires_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "Lifebear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - creature resolves, trigger should go on stack
  let state = pass(state)

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
  assert trigger_item.effect_override
    == Some(
      effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
    )

  // Verify life hasn't changed yet (trigger on stack, not resolved)
  assert player1.life == 20
}

// Test EntersBattlefield trigger resolves and has effect
pub fn enters_battlefield_trigger_resolves_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(3),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "Gainbear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Pass to resolve creature and put trigger on stack
  let state = pass(state)

  // Verify trigger is on stack
  assert list.length(state.stack) == 1

  // Pass again to resolve the trigger
  let state = pass(state)

  // Verify trigger resolved and controller gained life
  let assert Ok(player1) = player.find(state.players, 1)
  assert player1.life == 23
  assert state.stack == []
}

// Test creature without EntersBattlefield trigger doesn't put anything on stack
pub fn creature_without_trigger_does_not_add_to_stack_test() {
  let creature = create_test_creature("creature1", "Plain Bear")

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Both players pass priority - creature resolves
  let state = pass(state)

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify stack is empty (no trigger added)
  assert state.stack == []
}

// Test intervening_if prevents trigger from firing
pub fn intervening_if_blocks_trigger_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(5),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: Some(filters.Name("NonExistent")),
    )

  let creature =
    card.Card(
      ..create_test_creature("creature1", "Conditional Bear"),
      abilities: [ability.Triggered(trigger_ability)],
    )

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass priority - creature resolves
  let state = pass(state)

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify stack is empty (intervening_if blocked the trigger)
  assert state.stack == []

  // Verify life unchanged
  assert player1.life == 20
}

// Test intervening_if allows trigger to fire when it matches
pub fn intervening_if_allows_trigger_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(7),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: Some(filters.Name("Lifebear")),
    )

  let creature =
    card.Card(..create_test_creature("creature1", "Lifebear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass priority - creature resolves
  let state = pass(state)

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify trigger is on the stack (intervening_if matched)
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
}

// ── LeavesBattlefield ────────────────────────────────────

// Helper: create a trigger that gains life
fn make_gain_life_trigger(
  trigger_event: trigger.Trigger,
) -> ability.TriggeredAbility {
  ability.TriggeredAbility(
    trigger: trigger_event,
    targets: [],
    effect: effects.Single(effects.GainLife(
      amount: effects.Fixed(3),
      target: targeting.Controller,
    )),
    optional: False,
    intervening_if: None,
  )
}

pub fn leaves_battlefield_trigger_fires_on_lethal_damage_test() {
  let trigger_ability = make_gain_life_trigger(trigger.LeavesBattlefield)
  let creature =
    card.Card(..create_test_creature("creature1", "Leavesbear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  // Give creature lethal damage (toughness is 2)
  let perm = get_permanent(state, 1, "creature1")
  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: dict.insert(
            p.battlefield,
            "creature1",
            permanent.Permanent(..perm, damage: 2),
          ),
        )
      }),
    )

  // Check state-based actions - should trigger LeavesBattlefield
  let state = effect_resolver.check_state_based_actions(state)

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
  assert trigger_item.effect_override
    == Some(
      effects.Single(effects.GainLife(
        amount: effects.Fixed(3),
        target: targeting.Controller,
      )),
    )
}

pub fn leaves_battlefield_trigger_fires_via_move_card_test() {
  let trigger_ability = make_gain_life_trigger(trigger.LeavesBattlefield)
  let creature =
    card.Card(..create_test_creature("creature1", "Leavesbear2"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  // Use a bounce spell with PrimaryTarget targeting the creature
  let bounce_spell =
    card.Card(
      id: "bounce_spell",
      name: "Bounce Spell",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Instant,
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
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [targeting.target_info(targeting.Single(targeting.Creature))],
          additional_costs: [],
          effect: effects.Single(effects.Bounce(target: targeting.PrimaryTarget)),
        )),
      ],
      is_token: False,
    )

  // Put bounce spell on stack with chosen targets pointing to creature1
  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: bounce_spell,
        controller_id: 1,
        chosen_targets: [
          targeting.ChosenTargets(targets: [
            targeting.TargetCard("creature1"),
          ]),
        ],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: None,
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  // Resolve the stack item
  let assert Ok(state) = effect_resolver.resolve_stack_item(state)

  // Verify creature left battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 0

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
}

pub fn leaves_battlefield_trigger_fires_on_destroy_test() {
  let trigger_ability = make_gain_life_trigger(trigger.LeavesBattlefield)
  let creature =
    card.Card(..create_test_creature("creature1", "Leavesbear3"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  // Destroy via MoveCard effect: Battlefield -> Graveyard
  let destroy_spell =
    card.Card(
      id: "destroy_spell",
      name: "Destroy Spell",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Instant,
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

  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: destroy_spell,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: Some(
          effects.Single(effects.Destroy(
            target: targeting.AllOf(filters.Name("Leavesbear3")),
            cant_regenerate: False,
          )),
        ),
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  let assert Ok(state) = effect_resolver.resolve_stack_item(state)

  // Verify creature left battlefield
  let assert Ok(p1) = player.find(state.players, 1)
  assert dict.size(p1.battlefield) == 0

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
}

// ── Dies ──────────────────────────────────────────────────

pub fn dies_trigger_fires_on_lethal_damage_test() {
  let trigger_ability = make_gain_life_trigger(trigger.Dies)
  let creature =
    card.Card(..create_test_creature("creature1", "Lifebear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, 0)

  // Give creature lethal damage (toughness is 2)
  let perm = get_permanent(state, 1, "creature1")
  let state =
    state.State(
      ..state,
      players: player.update(state.players, 1, fn(p) {
        player.Player(
          ..p,
          battlefield: dict.insert(
            p.battlefield,
            "creature1",
            permanent.Permanent(..perm, damage: 2),
          ),
        )
      }),
    )

  // Check state-based actions - should trigger Dies
  let state = effect_resolver.check_state_based_actions(state)

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
}

pub fn dies_trigger_does_not_fire_for_non_creature_test() {
  // An artifact with a Dies trigger should NOT fire Dies
  // (Dies specifically means a creature goes to graveyard from battlefield)
  let trigger_ability = make_gain_life_trigger(trigger.Dies)
  let artifact =
    card.Card(
      id: "artifact1",
      name: "Test Artifact",
      supertypes: [],
      subtypes: [],
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
      abilities: [ability.Triggered(trigger_ability)],
      is_token: False,
    )

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, artifact, 0)

  // Destroy the artifact via state-based actions (give it lethal damage won't work
  // since it's not a creature, so use legend rule approach)
  // Actually, for non-creatures, destroy only works through Destroy effects.
  // Let's directly check that the Dies trigger isn't checked for non-creatures
  // by calling check_dies_triggers directly (it's public):
  let state = effect_resolver.check_dies_triggers(state, artifact, 1)

  // Verify stack is empty (no Dies trigger for non-creature)
  assert state.stack == []
}

// ── Attacks ───────────────────────────────────────────────

pub fn attacks_trigger_fires_test() {
  let trigger_ability = make_gain_life_trigger(trigger.Attacks)
  let creature =
    card.Card(..create_test_creature("attacker1", "Attackbear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  // Add creature without summoning sickness
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, step.DeclareAttackers)

  // Declare the creature as an attacker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "attacker1"
}

pub fn attacks_trigger_fires_and_resolves_test() {
  let trigger_ability = make_gain_life_trigger(trigger.Attacks)
  let creature =
    card.Card(..create_test_creature("attacker1", "Attackbear2"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to DeclareAttackers step
  let state = pass_until(state, step.DeclareAttackers)

  // Declare the creature as an attacker - puts trigger on stack
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Verify trigger on stack
  assert list.length(state.stack) == 1

  // Pass priority to resolve the trigger
  let state = pass(state)

  // Verify trigger resolved
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 23
}

// ── Blocks ────────────────────────────────────────────────

pub fn blocks_trigger_fires_test() {
  let trigger_ability = make_gain_life_trigger(trigger.Blocks)
  let blocker =
    card.Card(..create_test_creature("blocker1", "Blockbear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let attacker = create_test_creature("attacker1", "Goblin")
  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, attacker, -1)
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, step.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Advance to DeclareBlockers
  let state = pass(state)

  // Verify we're in DeclareBlockers
  assert state.step == step.DeclareBlockers

  // Declare blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        combat.BlockPair(blocker: "blocker1", attacker: "attacker1"),
      ]),
    )

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "blocker1"
}

pub fn blocks_trigger_fires_and_resolves_test() {
  let trigger_ability = make_gain_life_trigger(trigger.Blocks)
  let blocker =
    card.Card(..create_test_creature("blocker1", "Blockbear2"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let attacker = create_test_creature("attacker1", "Goblin2")
  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, attacker, -1)
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, step.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Advance to DeclareBlockers
  let state = pass(state)

  // Declare blocker - puts trigger on stack
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        combat.BlockPair(blocker: "blocker1", attacker: "attacker1"),
      ]),
    )

  // Verify trigger on stack
  assert list.length(state.stack) == 1

  // Pass priority to resolve the trigger
  let state = pass(state)

  // Verify trigger resolved
  let assert Ok(p2) = player.find(state.players, 2)
  assert p2.life == 23
}

// ── DealsDamage ──────────────────────────────────────────

pub fn deals_damage_trigger_fires_via_activated_ability_test() {
  // Create a creature with:
  // 1) A DealsDamage triggered ability
  // 2) An activated ability that deals damage (tap: deal 1 damage to target player)
  let deals_damage_ta =
    ability.TriggeredAbility(
      trigger: trigger.DealsDamage(None),
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: None,
    )

  let ping_ability =
    ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [targeting.player_target()],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Fixed(1),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    )

  let creature =
    card.Card(
      id: "pinger1",
      name: "Pinger",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [
        ability.Activated(ping_ability),
        ability.Triggered(deals_damage_ta),
      ],
      is_token: False,
    )

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Activate the ping ability targeting player 2
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(1, "pinger1", 0, 0, [
        targeting.ChosenTargets(targets: [
          targeting.TargetPlayer(2),
        ]),
      ]),
    )

  // Verify the activated ability went on the stack (but not the trigger yet)
  assert list.length(state.stack) == 1

  // We need to choose targets for the triggered ability? No, it has no targets.
  // Actually, the triggered ability is on the creature and hasn't fired yet.
  // The activated ability needs to resolve first, then the DealDamage step
  // will check for DealsDamage triggers.

  // But wait - the activated ability ping goes on the stack.
  // We need to pass priority to resolve it.
  let state = pass(state)

  // Now the ping should resolve, deal 1 damage to player 2,
  // and the DealsDamage trigger should go on the stack.
  // Verify the trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "pinger1"

  // Pass again to resolve the trigger
  let state = pass(state)

  // Verify trigger resolved (player 1 gained 2 life from the trigger)
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 22

  // Verify player 2 lost 1 life from the ping
  let assert Ok(p2) = player.find(state.players, 2)
  assert p2.life == 19
}

pub fn deals_damage_trigger_with_player_filter_test() {
  // Create a creature that only triggers when dealing damage to a player
  let deals_damage_ta =
    ability.TriggeredAbility(
      trigger: trigger.DealsDamage(Some(targeting.Single(targeting.Player))),
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(5),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: None,
    )

  let ping_player =
    ability.ActivatedAbility(
      cost: ability.tap_cost(),
      targets: [targeting.player_target()],
      effect: effects.Single(effects.DealDamage(
        amount: effects.Fixed(1),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      )),
    )

  let creature =
    card.Card(
      id: "pinger2",
      name: "Pinger",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [
        ability.Activated(ping_player),
        ability.Triggered(deals_damage_ta),
      ],
      is_token: False,
    )

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, creature, -1)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Activate the ping ability targeting player 2
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ActivateAbility(1, "pinger2", 0, 0, [
        targeting.ChosenTargets(targets: [
          targeting.TargetPlayer(2),
        ]),
      ]),
    )

  // Pass to resolve the ping
  let state = pass(state)

  // The trigger should have fired (damage to player matches filter)
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "pinger2"
}

// ── DealsCombatDamage ────────────────────────────────────

pub fn deals_combat_damage_trigger_fires_test() {
  let trigger_ability = make_gain_life_trigger(trigger.DealsCombatDamage(None))
  let attacker =
    card.Card(..create_test_creature("attacker1", "Combatbear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, attacker, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, step.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Advance through DeclareBlockers and CombatDamage to EndCombat.
  // pass_until handles CombatDamage by auto-assigning no damage,
  // which triggers apply_combat_damage → unblocked attacker deals damage → trigger fires.
  // The trigger fires and resolves within pass_until (since both players pass priority),
  // so by the time we reach EndCombat the stack is empty but the life gain happened.
  let state = pass_until(state, step.EndCombat)

  // Verify trigger resolved (controller gained 3 life from the trigger)
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 23
}

pub fn deals_combat_damage_trigger_fires_on_blocked_creature_test() {
  let trigger_ability = make_gain_life_trigger(trigger.DealsCombatDamage(None))
  let attacker =
    card.Card(..create_test_creature("attacker1", "Combatbear2"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let blocker = create_test_creature("blocker1", "Wall")
  let state = state.new()
  let state = add_creature_to_battlefield(state, 1, attacker, -1)
  let state = add_creature_to_battlefield(state, 2, blocker, -1)

  // Advance to DeclareAttackers and declare attacker
  let state = pass_until(state, step.DeclareAttackers)
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareAttackers(1, [
        combat.AttackPair("attacker1", combat.AttackPlayer(2)),
      ]),
    )

  // Advance to DeclareBlockers
  let state = pass(state)

  // Declare blocker
  let assert Ok(state) =
    action.dispatch(
      state,
      action.DeclareBlockers(2, [
        combat.BlockPair(blocker: "blocker1", attacker: "attacker1"),
      ]),
    )

  // Manually advance to CombatDamage by passing priority for all players
  // (can't use pass() because it auto-assigns no damage which fails for blocked creatures)
  let state =
    list.fold(state.players, state, fn(s, player) {
      let assert Ok(s) = action.dispatch(s, action.PassPriority(player.id))
      s
    })

  // We should be in CombatDamage step now
  assert state.step == step.CombatDamage

  // Assign damage: player 1's attacker deals 2 to blocker creature
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(1, [
        combat.DamageAssignment(amount: 2, from: "attacker1", to: "blocker1"),
      ]),
    )

  // Assign damage: player 2's blocker deals 2 to attacker creature
  let assert Ok(state) =
    action.dispatch(
      state,
      action.AssignDamage(2, [
        combat.DamageAssignment(amount: 2, from: "blocker1", to: "attacker1"),
      ]),
    )

  // Now combat damage has been applied and the trigger should be on the stack
  assert list.length(state.stack) >= 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "attacker1"
}

// ── Discarded ────────────────────────────────────────────

pub fn discarded_trigger_fires_on_discard_effect_test() {
  let trigger_ability =
    make_gain_life_trigger(trigger.Discarded(filters.AnyCard))
  let discard_card =
    card.Card(
      id: "discard1",
      name: "Discardbear",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [ability.Triggered(trigger_ability)],
      is_token: False,
    )

  let state = state.new()
  let state = add_card_to_hand(state, 1, discard_card)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Create a spell that discards cards, put it on the stack directly
  let discard_spell =
    card.Card(
      id: "discard_spell",
      name: "Discard Spell",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Sorcery,
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
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.Discard(
            who: targeting.Controller,
            filter: filters.AnyCard,
          )),
        )),
      ],
      is_token: False,
    )

  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: discard_spell,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: None,
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  // Pass to resolve the discard spell
  let state = pass(state)

  // The discard should trigger the discarded card's ability
  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "discard1"
}

pub fn discarded_trigger_with_filter_matching_test() {
  // Only trigger when a card named "SpecificCard" is discarded
  let trigger_ability =
    make_gain_life_trigger(trigger.Discarded(filters.Name("SpecificCard")))
  let matching_card =
    card.Card(
      id: "discard2",
      name: "SpecificCard",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [ability.Triggered(trigger_ability)],
      is_token: False,
    )
  let non_matching_card =
    card.Card(
      id: "discard3",
      name: "OtherCard",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [ability.Triggered(trigger_ability)],
      is_token: False,
    )

  let state = state.new()
  let state = add_card_to_hand(state, 1, matching_card)

  // Discard the matching card directly via public API
  let state = effect_resolver.check_discarded_triggers(state, matching_card, 1)

  // Verify trigger is on the stack (filter matched)
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "discard2"

  // Now test non-matching card
  let state = add_card_to_hand(state, 1, non_matching_card)
  let state =
    effect_resolver.check_discarded_triggers(state, non_matching_card, 1)

  // The non-matching card should NOT trigger (name filter doesn't match)
  assert list.length(state.stack) == 1
  // The existing trigger from matching_card is still there
}

// ── Optional Triggers ────────────────────────────────────

pub fn optional_enters_battlefield_trigger_does_not_go_on_stack_automatically_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: True,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "OptionalBear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Verify creature is on stack
  assert list.length(state.stack) == 1

  // Manually pass priority for both players to resolve the creature
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify stack is empty (optional trigger NOT put on stack automatically)
  assert state.stack == []

  // Verify pending_optional_trigger is set
  let assert Some(pending) = state.pending_optional_trigger
  assert pending.source_card.id == "creature1"
  assert pending.controller == 1
  assert pending.ability.optional == True
}

pub fn optional_trigger_accepted_puts_trigger_on_stack_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: True,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "OptionalBear2"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass to resolve creature, setting pending trigger
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))

  // Verify pending trigger is set
  let assert Some(_) = state.pending_optional_trigger

  // Accept the trigger
  let assert Ok(state) =
    action.dispatch(state, action.ChooseTrigger(1, "creature1", True))

  // Verify pending_optional_trigger is cleared
  assert state.pending_optional_trigger == None
  assert state.choice_player == None

  // Verify trigger is on the stack
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
}

pub fn optional_trigger_rejected_does_not_put_trigger_on_stack_test() {
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: True,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "OptionalBear3"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass to resolve creature, setting pending trigger
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))

  // Verify pending trigger is set
  let assert Some(_) = state.pending_optional_trigger

  // Reject the trigger
  let assert Ok(state) =
    action.dispatch(state, action.ChooseTrigger(1, "creature1", False))

  // Verify pending_optional_trigger is cleared
  assert state.pending_optional_trigger == None
  assert state.choice_player == None

  // Verify stack is still empty (trigger was not put on stack)
  assert state.stack == []
}

pub fn non_optional_triggers_still_work_with_new_field_test() {
  // Backward compatibility: non-optional triggers still go on stack automatically
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
      optional: False,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "Lifebear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass - creature resolves, non-optional trigger goes on stack
  let state = pass(state)

  // Verify creature is on battlefield
  let assert Ok(player1) = player.find(state.players, 1)
  assert dict.size(player1.battlefield) == 1

  // Verify trigger is on the stack automatically
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
  assert trigger_item.effect_override
    == Some(
      effects.Single(effects.GainLife(
        amount: effects.Fixed(2),
        target: targeting.Controller,
      )),
    )

  // No pending trigger
  assert state.pending_optional_trigger == None
}

// ── CreateDelayedTrigger ─────────────────────────────────

pub fn create_delayed_trigger_effect_works_test() {
  let state = state.new()
  let dt =
    effects.DelayedTrigger(
      event: effects.AtStep(step.BeginCombat),
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(5),
        target: targeting.Controller,
      )),
      controller: 1,
      duration: effects.Once,
    )

  // Create a dummy spell that uses CreateDelayedTrigger
  let dummy_card =
    card.Card(
      id: "delayer",
      name: "Delayer",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Instant,
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
      power: None,
      toughness: None,
      abilities: [],
      is_token: False,
    )

  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: dummy_card,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: Some(
          effects.Single(effects.CreateDelayedTrigger(trigger: dt)),
        ),
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  // Resolve the stack item
  let assert Ok(state) = effect_resolver.resolve_stack_item(state)

  // Verify the delayed trigger was stored in pending_delayed_triggers
  assert list.length(state.pending_delayed_triggers) == 1
  let assert Ok(created) = list.first(state.pending_delayed_triggers)
  assert created.event == effects.AtStep(step.BeginCombat)
  assert created.controller == 1
}

// ── TriggerSubject ────────────────────────────────────────

pub fn trigger_subject_as_card_resolves_test() {
  // A creature with an ETB trigger that uses TriggerSubject to pump itself
  // (TriggerSubject refers to the creature that entered the battlefield)
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.PumpCreature(
        target: targeting.TriggerSubject,
        power: effects.Fixed(3),
        toughness: effects.Fixed(3),
        add_keywords: [],
        duration: effects.EndOfTurn,
      )),
      optional: False,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "SelfPumper"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Both players pass - creature resolves, trigger goes on stack
  let state = pass(state)

  // Verify trigger is on stack with the trigger subject set to the creature
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.card.id == "creature1"
  assert trigger_item.trigger_subject == Some(targeting.TargetCard("creature1"))

  // Pass to resolve the trigger
  let state = pass(state)

  // Verify the creature got pumped (+3/+3) from the trigger
  let assert Ok(p1) = player.find(state.players, 1)
  let assert Ok(perm) = permanent.find(p1.battlefield, "creature1")
  assert perm.card.power == Some(5)
  // 2 + 3
  assert perm.card.toughness == Some(5)
  // 2 + 3
  assert state.stack == []
}

pub fn trigger_subject_as_player_resolves_test() {
  // A card that when discarded, makes the player who discarded it lose 1 life
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.Discarded(filters.AnyCard),
      targets: [],
      effect: effects.Single(effects.LoseLife(
        amount: effects.Fixed(1),
        target: targeting.TriggerSubject,
      )),
      optional: False,
      intervening_if: None,
    )

  let discard_card =
    card.Card(
      id: "discard1",
      name: "Painbear",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Creature,
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
      power: Some(1),
      toughness: Some(1),
      abilities: [ability.Triggered(trigger_ability)],
      is_token: False,
    )

  let state = state.new()
  let state = add_card_to_hand(state, 1, discard_card)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Create a discard spell and put it on the stack directly
  let discard_spell =
    card.Card(
      id: "discard_spell",
      name: "Discard Spell",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Sorcery,
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
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.Discard(
            who: targeting.Controller,
            filter: filters.AnyCard,
          )),
        )),
      ],
      is_token: False,
    )

  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: discard_spell,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: None,
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  // Pass to resolve the discard spell
  let state = pass(state)

  // The trigger should be on the stack with a player trigger subject
  assert list.length(state.stack) == 1
  let assert Ok(trigger_item) = list.first(state.stack)
  assert trigger_item.trigger_subject == Some(targeting.TargetPlayer(1))

  // Pass to resolve the trigger
  let state = pass(state)

  // Verify player 1 lost 1 life (TriggerSubject resolved to the player who discarded)
  let assert Ok(p1) = player.find(state.players, 1)
  assert p1.life == 19
  assert state.stack == []
}

pub fn trigger_subject_not_set_returns_error_test() {
  // A triggered ability using TriggerSubject when no trigger subject is set
  // (e.g., a spell on the stack that was not a trigger) should return an error
  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.GainLife(
        amount: effects.Fixed(1),
        target: targeting.TriggerSubject,
      )),
      optional: False,
      intervening_if: None,
    )

  let creature =
    card.Card(..create_test_creature("creature1", "ErrorBear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()
  let state = add_card_to_hand(state, 1, creature)

  // Advance to PreCombatMain
  let state = pass_until(state, step.PreCombatMain)

  // Add mana and cast the creature
  let mana =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 0)
  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, mana))
  let assert Ok(state) =
    action.dispatch(state, action.CastCreature(1, "creature1", 0))

  // Manually craft a stack item with None trigger_subject (simulating a spell,
  // not a trigger) to test error resolution - but actually, triggers always have
  // a subject now. Test that a non-trigger spell can't resolve TriggerSubject.

  // Instead, test that TriggerSubject on a spell (which has trigger_subject=None)
  // resolves to an error.
  // We'll put a spell on the stack with TriggerSubject target and try to resolve it.
  let test_spell =
    card.Card(
      id: "test_spell",
      name: "Test Spell",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Instant,
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
      power: None,
      toughness: None,
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.GainLife(
            amount: effects.Fixed(1),
            target: targeting.TriggerSubject,
          )),
        )),
      ],
      is_token: False,
    )

  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: test_spell,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: None,
        trigger_subject: None,
        chosen_color: None,
      ),
    ])

  // Resolving should return an error since no trigger subject is available
  let assert Error(error.InvalidAction(_)) =
    effect_resolver.resolve_stack_item(state)
}

pub fn trigger_subject_player_mismatch_is_handled_gracefully_test() {
  // Test that using TriggerSubject as a card target when it's a player
  // is handled gracefully (PumpCreature catches the error and returns state unchanged).
  // We test the resolution logic directly by setting up a trigger item manually.

  let trigger_ability =
    ability.TriggeredAbility(
      trigger: trigger.EntersBattlefield,
      targets: [],
      effect: effects.Single(effects.PumpCreature(
        target: targeting.TriggerSubject,
        power: effects.Fixed(1),
        toughness: effects.Fixed(1),
        add_keywords: [],
        duration: effects.EndOfTurn,
      )),
      optional: False,
      intervening_if: None,
    )

  let trigger_card =
    card.Card(..create_test_creature("trigger1", "TriggerBear"), abilities: [
      ability.Triggered(trigger_ability),
    ])

  let state = state.new()

  // Put a trigger stack item with a PLAYER trigger subject on the stack
  // This simulates a discarded trigger where the subject is the player
  let state =
    state.State(..state, stack: [
      stack.StackItem(
        card: trigger_card,
        controller_id: 1,
        chosen_targets: [],
        chosen_mode: None,
        damage_division: [],
        x_value: 0,
        effect_override: Some(
          effects.Single(effects.PumpCreature(
            target: targeting.TriggerSubject,
            power: effects.Fixed(1),
            toughness: effects.Fixed(1),
            add_keywords: [],
            duration: effects.EndOfTurn,
          )),
        ),
        trigger_subject: Some(targeting.TargetPlayer(1)),
        chosen_color: None,
      ),
    ])

  // Resolving should succeed (PumpCreature swallows the card resolution error)
  let assert Ok(state) = effect_resolver.resolve_stack_item(state)

  // Stack should be empty after resolution
  assert state.stack == []
}
