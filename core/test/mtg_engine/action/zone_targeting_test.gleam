import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import mtg_engine/trigger
import mtg_engine/zone
import test_helpers.{add_creature_to_battlefield, get_player, pass, pass_until}

fn add_card_to_graveyard(
  state: state.State,
  player_id: Int,
  c: card.Card,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, graveyard: [c, ..p.graveyard])
    }),
  )
}

fn add_card_to_hand(
  state: state.State,
  player_id: Int,
  c: card.Card,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, hand: [c, ..p.hand])
    }),
  )
}

fn black_mana() -> mana.Produced {
  mana.Produced(white: 0, blue: 0, black: 2, red: 0, green: 0, colorless: 1)
}

// Gravedigger — "When Gravedigger enters the battlefield, return target
// creature card from your graveyard to your hand."
// Targets: And(Single(Creature), Zone(Graveyard))
// Effect: Bounce(PrimaryTarget) — moves from graveyard to hand.
fn gravedigger_card() -> card.Card {
  card.Card(
    id: "gravedigger",
    name: "Gravedigger",
    supertypes: [],
    subtypes: [],
    card_type: card_type.Creature,
    mana_cost: mana.Cost(
      generic: 2,
      white: 0,
      blue: 0,
      black: 1,
      red: 0,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: Some(2),
    toughness: Some(2),
    abilities: [
      ability.Triggered(ability.TriggeredAbility(
        trigger: trigger.EntersBattlefield,
        targets: [
          targeting.target_info(targeting.And(
            targeting.Single(targeting.Creature),
            targeting.Zone(zone.Graveyard),
          )),
        ],
        effect: effects.Single(effects.MoveCard(
          target: targeting.PrimaryTarget,
          from_zone: zone.Graveyard,
          to_zone: zone.Hand,
        )),
        optional: False,
        intervening_if: None,
      )),
    ],
    is_token: False,
  )
}

fn creature_in_graveyard(id: String, name: String) -> card.Card {
  card.Card(
    id: id,
    name: name,
    supertypes: [],
    subtypes: [],
    card_type: card_type.Creature,
    mana_cost: mana.Cost(
      generic: 1,
      white: 0,
      blue: 0,
      black: 0,
      red: 0,
      green: 1,
      colorless: 0,
      x: 0,
    ),
    power: Some(1),
    toughness: Some(1),
    abilities: [],
    is_token: False,
  )
}

fn cast_creature(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  mana_to_produce: mana.Produced,
) {
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_to_produce),
  ))
  action.dispatch(state, action.CastCreature(caster_id, spell.id, 0))
}

// ══════════════════════════════════════════════════════════════════════════
// Task 4: Gravedigger — creature in controller's graveyard succeeds
// ══════════════════════════════════════════════════════════════════════════

pub fn gravedigger_own_graveyard_succeeds_test() {
  let gravedigger = gravedigger_card()
  let creature_in_gy = creature_in_graveyard("gy_creature", "Dead Creature")

  let state =
    state.new()
    |> add_card_to_graveyard(1, creature_in_gy)
    |> add_card_to_hand(1, gravedigger)
    |> pass_until(step.PreCombatMain)

  // Cast Gravedigger (3 mana: 2 generic + 1 black)
  let assert Ok(state) = cast_creature(state, 1, gravedigger, black_mana())

  // Both players pass — spell resolves, ETB trigger goes on the stack.
  let state = pass(state)

  // Choose the creature in GY as the trigger's target.
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ChooseTargets(
        1,
        "gravedigger",
        [
          targeting.ChosenTargets(targets: [
            targeting.TargetCard("gy_creature"),
          ]),
        ],
        None,
        [],
      ),
    )

  // Both players pass — trigger resolves, creature is returned to hand.
  let state = pass(state)

  // The creature should be back in player 1's hand
  let p1 = get_player(state, 1)
  assert list.length(p1.hand) == 1
  let assert Ok(_returned) = list.first(p1.hand)

  // And no longer in the graveyard
  assert p1.graveyard == []
}

// ══════════════════════════════════════════════════════════════════════════
// Task 4: Gravedigger — creature only in opponent's graveyard fails
// ══════════════════════════════════════════════════════════════════════════

pub fn gravedigger_opponent_graveyard_fails_test() {
  let gravedigger = gravedigger_card()
  let creature_in_gy = creature_in_graveyard("opp_creature", "Opp Creature")

  // Creature is in player 2's graveyard, not player 1's
  let state =
    state.new()
    |> add_card_to_graveyard(2, creature_in_gy)
    |> add_card_to_hand(1, gravedigger)
    |> pass_until(step.PreCombatMain)

  let assert Ok(state) = cast_creature(state, 1, gravedigger, black_mana())

  // Both players pass — spell resolves, ETB trigger goes on the stack.
  let state = pass(state)

  // Attempt to target the creature in opponent's graveyard — should fail
  let result =
    action.dispatch(
      state,
      action.ChooseTargets(
        1,
        "gravedigger",
        [
          targeting.ChosenTargets(targets: [
            targeting.TargetCard("opp_creature"),
          ]),
        ],
        None,
        [],
      ),
    )

  // The target validation should reject this
  assert result |> result.is_error()
}

// ══════════════════════════════════════════════════════════════════════════
// Task 4: Gravedigger — non-creature card in graveyard fails
// ══════════════════════════════════════════════════════════════════════════

pub fn gravedigger_non_creature_in_graveyard_fails_test() {
  let gravedigger = gravedigger_card()
  let land_in_gy =
    card.Card(
      id: "gy_land",
      name: "Swamp",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Land,
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
    state.new()
    |> add_card_to_graveyard(1, land_in_gy)
    |> add_card_to_hand(1, gravedigger)
    |> pass_until(step.PreCombatMain)

  let assert Ok(state) = cast_creature(state, 1, gravedigger, black_mana())

  // Both players pass — spell resolves, ETB trigger goes on the stack.
  let state = pass(state)

  // Attempt to target the land in graveyard — should fail (not a creature)
  let result =
    action.dispatch(
      state,
      action.ChooseTargets(
        1,
        "gravedigger",
        [
          targeting.ChosenTargets(targets: [targeting.TargetCard("gy_land")]),
        ],
        None,
        [],
      ),
    )

  assert result |> result.is_error()
}

// ══════════════════════════════════════════════════════════════════════════
// Task 4: Strands of Night — no creature in controller's graveyard fails
// ══════════════════════════════════════════════════════════════════════════

pub fn strands_of_night_no_creature_in_graveyard_fails_test() {
  // Strands of Night — activated ability: "{1}{B}, Pay 2 life, Sacrifice a
  // Swamp: Return target creature card from your graveyard to the battlefield."
  let strands =
    card.Card(
      id: "strands",
      name: "Strands of Night",
      supertypes: [],
      subtypes: ["Enchantment"],
      card_type: card_type.Enchantment,
      mana_cost: mana.Cost(
        generic: 1,
        white: 0,
        blue: 0,
        black: 1,
        red: 0,
        green: 0,
        colorless: 0,
        x: 0,
      ),
      power: None,
      toughness: None,
      abilities: [
        ability.Activated(ability.ActivatedAbility(
          cost: ability.Costs([
            ability.Mana(mana.Cost(
              generic: 1,
              white: 0,
              blue: 0,
              black: 1,
              red: 0,
              green: 0,
              colorless: 0,
              x: 0,
            )),
            ability.PayLife(effects.Fixed(2)),
            ability.Sacrifice(filters.And(
              filters.Types([card_type.Land]),
              filters.Name("Swamp"),
            )),
          ]),
          targets: [
            targeting.target_info(targeting.And(
              targeting.Single(targeting.Creature),
              targeting.Zone(zone.Graveyard),
            )),
          ],
          effect: effects.Single(effects.MoveCard(
            target: targeting.PrimaryTarget,
            from_zone: zone.Graveyard,
            to_zone: zone.Hand,
          )),
        )),
      ],
      is_token: False,
    )
  let _ = strands

  // Set up: player 1 has Strands of Night and a Swamp on the battlefield,
  // but no creatures in graveyard.
  let swamp =
    card.Card(
      id: "swamp1",
      name: "Swamp",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Land,
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
    state.new()
    |> add_creature_to_battlefield(1, strands, 0)
    |> test_helpers.add_land_to_battlefield(1, swamp)
    |> pass_until(step.PreCombatMain)

  // Produce mana for the activation cost
  let assert Ok(state) =
    action.dispatch(
      state,
      action.ProduceMana(
        1,
        mana.Produced(
          white: 0,
          blue: 0,
          black: 1,
          red: 0,
          green: 0,
          colorless: 1,
        ),
      ),
    )

  // Attempt to activate Strands of Night targeting a non-existent creature
  let result =
    action.dispatch(
      state,
      action.ActivateAbility(
        player_id: 1,
        permanent_id: "strands",
        ability_index: 0,
        x_value: 0,
        chosen_targets: [
          targeting.ChosenTargets(targets: [
            targeting.TargetCard("nonexistent"),
          ]),
        ],
      ),
    )

  // Should fail — target not found
  assert result |> result.is_error()
}
