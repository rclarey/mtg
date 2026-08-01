import gleam/list
import gleam/option.{None}
import mtg_engine/action
import mtg_engine/ability
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/effects
import mtg_engine/extensions
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/targeting
import mtg_engine/zone
import test_helpers.{add_card_to_hand, create_creature, get_player, pass_until}

// ── Layer / Priority Tests (Rule 613) ─────────────────────────────

pub fn effect_layer_pump_all_is_layer_pt_test() {
  assert effects.effect_layer(effects.PumpAll(
    filter: filters.creature(),
    power: 1,
    toughness: 1,
    keywords: [],
  )) == effects.LayerPT
}

pub fn effect_layer_grant_keyword_is_layer_ability_test() {
  assert effects.effect_layer(effects.GrantKeyword(
    filter: filters.creature(),
    keyword: effects.Flying,
  )) == effects.LayerAbility
}

pub fn layer_priority_copy_is_1_test() {
  assert effects.layer_priority(effects.LayerCopy) == 1
}

pub fn layer_priority_control_is_2_test() {
  assert effects.layer_priority(effects.LayerControl) == 2
}

pub fn layer_priority_text_is_3_test() {
  assert effects.layer_priority(effects.LayerText) == 3
}

pub fn layer_priority_type_is_4_test() {
  assert effects.layer_priority(effects.LayerType) == 4
}

pub fn layer_priority_color_is_5_test() {
  assert effects.layer_priority(effects.LayerColor) == 5
}

pub fn layer_priority_ability_is_6_test() {
  assert effects.layer_priority(effects.LayerAbility) == 6
}

pub fn layer_priority_pt_is_7_test() {
  assert effects.layer_priority(effects.LayerPT) == 7
}

pub fn layer_priority_copy_before_control_test() {
  assert effects.layer_priority(effects.LayerCopy) < effects.layer_priority(effects.LayerControl)
}

pub fn layer_priority_type_before_pt_test() {
  assert effects.layer_priority(effects.LayerType) < effects.layer_priority(effects.LayerPT)
}

// ── Remove Static Effects by Source Tests ─────────────────────────

pub fn remove_static_effects_by_source_removes_matching_source_test() {
  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.creature(),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "source_a",
    )
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.creature(),
        power: 2,
        toughness: 2,
        keywords: [],
      ),
      "source_b",
    )

  let result =
    extensions.remove_static_effects_by_source(extensions, "source_a")

  assert list.length(result.static_effects) == 1
  let assert Ok(remaining) = list.first(result.static_effects)
  assert remaining.source == "source_b"
}

pub fn remove_static_effects_by_source_non_existent_source_noop_test() {
  let extensions =
    extensions.new()
    |> extensions.add_static_effect(
      effects.PumpAll(
        filter: filters.creature(),
        power: 1,
        toughness: 1,
        keywords: [],
      ),
      "source_x",
    )

  let result =
    extensions.remove_static_effects_by_source(
      extensions,
      "non_existent_source",
    )

  assert list.length(result.static_effects) == 1
}

pub fn remove_static_effects_by_source_empty_extensions_noop_test() {
  let extensions = extensions.new()

  let result =
    extensions.remove_static_effects_by_source(extensions, "anything")

  assert result.static_effects == []
}

// ── Sequence Integration Test ─────────────────────────────────────

fn two_mana() -> mana.Produced {
  mana.Produced(white: 0, blue: 0, black: 0, red: 1, green: 0, colorless: 1)
}

fn instant_card_seq(
  id: String,
  name: String,
  targets: List(targeting.TargetInfo),
  effect: effects.Effect,
) -> card.Card {
  card.Card(
    id: id,
    name: name,
    supertypes: [],
    subtypes: [],
    card_type: card_type.Instant,
    mana_cost: mana.Cost(
      generic: 1,
      white: 0,
      blue: 0,
      black: 0,
      red: 1,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: None,
    toughness: None,
    abilities: [
      ability.Spell(ability.SpellAbility(
        targets: targets,
        additional_costs: [],
        effect: effect,
      )),
    ],
    is_token: False,
  )
}

pub fn sequence_damage_then_life_test() {
  // Sequence([
  //   DealDamage(2, PrimaryTarget),
  //   GainLife(PreviousStep, Controller)
  // ])
  let seq_effect =
    effects.Sequence([
      effects.DealDamage(
        amount: effects.Fixed(2),
        target: targeting.PrimaryTarget,
        source_is_combat: False,
      ),
      effects.GainLife(
        amount: effects.PreviousStep,
        target: targeting.Controller,
      ),
    ])

  let spell =
    instant_card_seq(
      "seq1",
      "Drain Life",
      [targeting.any_target()],
      seq_effect,
    )

  let state =
    state.new()
    |> add_card_to_hand(1, spell)
    |> pass_until(step.PreCombatMain)

  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]

  let assert Ok(state) = action.dispatch(state, action.ProduceMana(1, two_mana()))
  let assert Ok(state) = action.dispatch(
    state,
    action.CastInstant(1, "seq1", 0),
  )
  let assert Ok(state) = action.dispatch(
    state,
    action.ChooseTargets(1, "seq1", targets, None, []),
  )

  // Resolve: both players pass
  let assert Ok(state) = action.dispatch(state, action.PassPriority(1))
  let assert Ok(state) = action.dispatch(state, action.PassPriority(2))

  let p1 = get_player(state, 1)
  let p2 = get_player(state, 2)
  // Player 2 took 2 damage from step 1
  assert p2.life == 18
  // Player 1 gained 2 life from step 2 (PreviousStep = 2 from damage)
  assert p1.life == 22
}

pub fn sequence_draw_then_discard_test() {
  // Sequence([
  //   DrawCards(2, Controller),
  //   Discard(Controller, AnyCard) — PreviousStep = cards drawn
  // ])
  let seq_effect =
    effects.Sequence([
      effects.DrawCards(num: effects.Fixed(2), target: targeting.Controller),
      effects.Discard(
        who: targeting.Controller,
        filter: filters.Zone(zone.Hand),
      ),
    ])

  let spell =
    instant_card_seq(
      "seq2",
      "Tolarian Winds Lite",
      [],
      seq_effect,
    )

  let a = create_creature("a", "A", 1, 1)
  let b = create_creature("b", "B", 1, 1)
  let c = create_creature("c", "C", 1, 1)
  let d = create_creature("d", "D", 1, 1)

  let s = state.new()
  let s =
    state.State(
      ..s,
      players: player.update(s.players, 1, fn(p) {
        player.Player(..p, library: [a, b, c, d])
      }),
    )
  let s = add_card_to_hand(s, 1, spell)
  let s = pass_until(s, step.PreCombatMain)

  let assert Ok(s) = action.dispatch(s, action.ProduceMana(1, two_mana()))
  let assert Ok(s) = action.dispatch(s, action.CastInstant(1, "seq2", 0))
  let assert Ok(s) = action.dispatch(
    s,
    action.ChooseTargets(1, "seq2", [], None, []),
  )

  // Resolve
  let assert Ok(s) = action.dispatch(s, action.PassPriority(1))
  let assert Ok(s) = action.dispatch(s, action.PassPriority(2))

  // Should have drawn 2 cards (a, b) then discarded them (PreviousStep = 2)
  let p1 = get_player(s, 1)
  // Library: [c, d] (drew a, b, then discarded a, b to graveyard)
  assert list.length(p1.library) == 2
  // Hand should be empty (had spell, drew 2, discarded the 2 drawn to graveyard)
  // Actually discard_cards runs filter on hand, discarding "a" and "b"
  // Wait... Discard with filter Zone(Hand) will match ALL cards in hand
  // After drawing: hand = [spell removed by cast, a, b]. Discard matches all.
  // But the spell was cast from hand already, so hand = [a, b].
  assert p1.hand == []
  assert list.length(p1.graveyard) >= 2
}
