import gleam/list
import gleam/option.{None, Some}
import gleam/result
import mtg_engine/ability
import mtg_engine/action
import mtg_engine/card
import mtg_engine/card_type
import mtg_engine/color
import mtg_engine/effects
import mtg_engine/extensions
import mtg_engine/filter_matcher
import mtg_engine/filters
import mtg_engine/mana
import mtg_engine/permanent
import mtg_engine/player
import mtg_engine/state
import mtg_engine/step
import mtg_engine/supertype
import mtg_engine/targeting
import mtg_engine/zone
import test_helpers.{
  add_creature_to_battlefield, add_land_to_battlefield, create_creature,
  create_test_land, get_permanent, get_player, pass, pass_until,
}

fn noop_mana() -> mana.Produced {
  mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 0, colorless: 0)
}

fn swamp(id: String) -> card.Card {
  card.Card(
    ..create_test_land(id, "Swamp"),
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
  )
}

fn basic_land(id: String, name: String) -> card.Card {
  card.Card(..create_test_land(id, name), supertypes: [supertype.Basic])
}

fn black_creature(id: String, name: String, power: Int, toughness: Int) {
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
      black: 1,
      red: 0,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: Some(power),
    toughness: Some(toughness),
    abilities: [],
    is_token: False,
  )
}

fn nonblack_creature(id: String, name: String, power: Int, toughness: Int) {
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
      red: 1,
      green: 0,
      colorless: 0,
      x: 0,
    ),
    power: Some(power),
    toughness: Some(toughness),
    abilities: [],
    is_token: False,
  )
}

fn add_card_to_library(
  state: state.State,
  player_id: Int,
  c: card.Card,
) -> state.State {
  state.State(
    ..state,
    players: player.update(state.players, player_id, fn(p) {
      player.Player(..p, library: [c, ..p.library])
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

fn cast_spell_with_targets(
  state: state.State,
  caster_id: Int,
  spell: card.Card,
  mana_to_produce: mana.Produced,
  chosen_targets: List(targeting.ChosenTargets),
) {
  use state <- result.try(action.dispatch(
    state,
    action.ProduceMana(caster_id, mana_to_produce),
  ))
  let cast_action = case spell.card_type {
    card_type.Instant -> action.CastInstant(caster_id, spell.id, 0)
    card_type.Sorcery -> action.CastSorcery(caster_id, spell.id, 0)
    _ -> action.CastCreature(caster_id, spell.id, 0)
  }
  use state <- result.try(action.dispatch(state, cast_action))
  action.dispatch(
    state,
    action.ChooseTargets(caster_id, spell.id, chosen_targets, None, []),
  )
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: WithController(You) — Glorious Anthem
// ══════════════════════════════════════════════════════════════════════════

pub fn glorious_anthem_only_controller_creatures_test() {
  let anthem = create_creature("anthem", "Glorious Anthem", 1, 1)
  let creature_p1 = create_creature("c1", "P1 Creature", 2, 2)
  let creature_p2 = create_creature("c2", "P2 Creature", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, anthem, 0)
    |> add_creature_to_battlefield(1, creature_p1, 0)
    |> add_creature_to_battlefield(2, creature_p2, 0)

  // Glorious Anthem — "Creatures you control get +1/+1"
  // Source is the Anthem permanent, controlled by player 1.
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions.new()
        |> extensions.add_static_effect(
          effects.PumpAll(
            filter: filters.And(
              filters.creature(),
              filters.WithController(filters.You),
            ),
            power: 1,
            toughness: 1,
            keywords: [],
          ),
          "anthem",
        ),
      action.ProduceMana(1, noop_mana()),
    )

  // Player 1's creature should be buffed (2/2 + 1/1 = 3/3)
  let perm1 = get_permanent(state, 1, creature_p1.id)
  assert perm1.card.power == Some(3)
  assert perm1.card.toughness == Some(3)

  // Player 2's creature should NOT be buffed (still 2/2)
  let perm2 = get_permanent(state, 2, creature_p2.id)
  assert perm2.card.power == Some(2)
  assert perm2.card.toughness == Some(2)
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: Subtype — Goblin King
// ══════════════════════════════════════════════════════════════════════════

pub fn goblin_king_only_goblins_get_mountainwalk_test() {
  let king = create_creature("king", "Goblin King", 2, 2)
  let goblin_card =
    card.Card(..create_creature("goblin1", "Goblin Lackey", 1, 1), subtypes: [
      "Goblin",
    ])
  let non_goblin = create_creature("nongob", "Bear", 2, 2)

  let state =
    state.new()
    |> add_creature_to_battlefield(1, king, 0)
    |> add_creature_to_battlefield(1, goblin_card, 0)
    |> add_creature_to_battlefield(1, non_goblin, 0)

  // Goblin King — "Other Goblins get +1/+1 and have mountainwalk"
  let assert Ok(#(state, _)) =
    action.dispatch_with_ext(
      state,
      extensions.new()
        |> extensions.add_static_effect(
          effects.PumpAll(
            filter: filters.And(
              filters.Subtype("Goblin"),
              filters.Not(filters.Name("Goblin King")),
            ),
            power: 1,
            toughness: 1,
            keywords: [effects.Mountainwalk],
          ),
          "king",
        ),
      action.ProduceMana(1, noop_mana()),
    )

  // Goblin should get +1/+1 and mountainwalk
  let goblin_perm = get_permanent(state, 1, goblin_card.id)
  assert goblin_perm.card.power == Some(2)
  assert goblin_perm.card.toughness == Some(2)
  assert list.contains(goblin_perm.granted_keywords, "Mountainwalk")

  // Non-goblin should be unaffected
  let non_goblin_perm = get_permanent(state, 1, non_goblin.id)
  assert non_goblin_perm.card.power == Some(2)
  assert non_goblin_perm.card.toughness == Some(2)
  assert !list.contains(non_goblin_perm.granted_keywords, "Mountainwalk")
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1+2: Supertype — Rampant Growth
// ══════════════════════════════════════════════════════════════════════════

pub fn rampant_growth_finds_basic_land_test() {
  let basic = basic_land("basic1", "Forest")
  let non_basic = create_test_land("nonbasic1", "Urza's Tower")
  let creature = create_creature("lib_creature", "Library Creature", 1, 1)

  // Rampant Growth — Sorcery, "Search your library for a basic land card,
  // put it onto the battlefield tapped."
  let rampant =
    card.Card(
      id: "rampant",
      name: "Rampant Growth",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Sorcery,
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
      power: None,
      toughness: None,
      abilities: [
        ability.Spell(ability.SpellAbility(
          targets: [],
          additional_costs: [],
          effect: effects.Single(effects.SearchLibrary(
            target: targeting.Controller,
            filter: filters.And(
              filters.Types([card_type.Land]),
              filters.Supertype(supertype.Basic),
            ),
            destination: effects.Battlefield,
            reveal: False,
            tapped: True,
          )),
        )),
      ],
      is_token: False,
    )

  let state =
    state.new()
    |> add_card_to_library(1, creature)
    |> add_card_to_library(1, non_basic)
    |> add_card_to_library(1, basic)
    |> add_card_to_hand(1, rampant)
    |> pass_until(step.PreCombatMain)

  let mana_to_produce =
    mana.Produced(white: 0, blue: 0, black: 0, red: 0, green: 1, colorless: 1)
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, rampant, mana_to_produce, [])

  // Both players pass — spell resolves
  let state = pass(state)

  // Basic land should be on the battlefield, tapped
  let basic_perm = get_permanent(state, 1, basic.id)
  assert basic_perm.tapped
  assert basic_perm.card.name == "Forest"

  // Non-basic land and creature should still be in the library
  let p1 = get_player(state, 1)
  assert list.length(p1.library) == 2
  let library_ids = list.map(p1.library, fn(c) { c.id })
  assert list.contains(library_ids, "nonbasic1")
  assert list.contains(library_ids, "lib_creature")
  assert !list.contains(library_ids, "basic1")
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: Color filter — Dark Banishing (unit test for Color filter)
// ══════════════════════════════════════════════════════════════════════════

pub fn color_filter_matches_black_creature_test() {
  let black = black_creature("black1", "Black Knight", 2, 2)
  let nonblack = nonblack_creature("red1", "Red Goblin", 2, 2)
  let ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [2],
      is_tapped: None,
      zone: zone.Battlefield,
      chosen_color: None,
    )
  // Black creature matches Color(Literal(Black))
  assert filter_matcher.matches(
    black,
    filters.Color(filters.Literal(color.Black)),
    ctx,
  )
  // Nonblack creature does not match Color(Literal(Black))
  assert !filter_matcher.matches(
    nonblack,
    filters.Color(filters.Literal(color.Black)),
    ctx,
  )
  // Dark Banishing filter: And(Types([Creature]), Not(Color(Literal(Black))))
  let dark_banishing_filter =
    filters.And(
      filters.Types([card_type.Creature]),
      filters.Not(filters.Color(filters.Literal(color.Black))),
    )
  // Black creature fails the filter (it's black, filter wants nonblack)
  assert !filter_matcher.matches(black, dark_banishing_filter, ctx)
  // Nonblack creature passes the filter
  assert filter_matcher.matches(nonblack, dark_banishing_filter, ctx)
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: WithController(You) in Count — Corrupt
// ══════════════════════════════════════════════════════════════════════════

pub fn corrupt_counts_only_controller_swamps_test() {
  let swamp_p1_a = swamp("sw1")
  let swamp_p1_b = swamp("sw2")
  let swamp_p2 = swamp("sw3")

  // Corrupt — "Deal damage equal to Swamps you control. Gain life equal
  // to damage dealt."
  let corrupt =
    card.Card(
      id: "corrupt",
      name: "Corrupt",
      supertypes: [],
      subtypes: [],
      card_type: card_type.Sorcery,
      mana_cost: mana.Cost(
        generic: 5,
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
        ability.Spell(ability.SpellAbility(
          targets: [targeting.any_target()],
          additional_costs: [],
          effect: effects.Sequence([
            effects.DealDamage(
              amount: effects.Count(filters.And(
                filters.And(
                  filters.Types([card_type.Land]),
                  filters.Name("Swamp"),
                ),
                filters.WithController(filters.You),
              )),
              target: targeting.PrimaryTarget,
              source_is_combat: False,
            ),
            effects.GainLife(
              amount: effects.PreviousStep,
              target: targeting.Controller,
            ),
          ]),
        )),
      ],
      is_token: False,
    )

  let state =
    state.new()
    |> add_land_to_battlefield(1, swamp_p1_a)
    |> add_land_to_battlefield(1, swamp_p1_b)
    |> add_land_to_battlefield(2, swamp_p2)
    |> add_card_to_hand(1, corrupt)
    |> pass_until(step.PreCombatMain)

  // Player 1 has 2 swamps, player 2 has 1 swamp. Corrupt should deal 2
  // damage (only player 1's swamps count) and gain 2 life.
  let mana_to_produce =
    mana.Produced(white: 0, blue: 0, black: 1, red: 0, green: 0, colorless: 5)
  let targets = [targeting.ChosenTargets(targets: [targeting.TargetPlayer(2)])]
  let assert Ok(state) =
    cast_spell_with_targets(state, 1, corrupt, mana_to_produce, targets)

  // Both players pass — spell resolves
  let state = pass(state)

  // Player 2 should have lost 2 life (2 swamps controlled by player 1)
  let p2 = get_player(state, 2)
  assert p2.life == 18

  // Player 1 should have gained 2 life
  let p1 = get_player(state, 1)
  assert p1.life == 22
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: WithRestriction(Tapped) — unit test
// ══════════════════════════════════════════════════════════════════════════

pub fn with_restriction_tapped_matches_only_tapped_test() {
  let creature = create_creature("c1", "Test Creature", 2, 2)

  let tapped_perm =
    permanent.Permanent(
      card: creature,
      owner_id: 1,
      tapped: True,
      entered_battlefield_cycle: 0,
      damage: 0,
      granted_keywords: [],
      attached_to: None,
      static_bonus_power: 0,
      static_bonus_toughness: 0,
      static_bonus_keywords: [],
    )

  let untapped_perm =
    permanent.Permanent(
      card: creature,
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

  let tapped_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: Some(True),
      zone: zone.Battlefield,
      chosen_color: None,
    )
  let untapped_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: Some(False),
      zone: zone.Battlefield,
      chosen_color: None,
    )
  let none_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: None,
      zone: zone.Hand,
      chosen_color: None,
    )

  let _ = tapped_perm
  let _ = untapped_perm

  // Tapped filter matches only tapped permanents
  assert filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Tapped),
    tapped_ctx,
  )
  assert !filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Tapped),
    untapped_ctx,
  )

  // Untapped filter matches only untapped permanents
  assert filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Untapped),
    untapped_ctx,
  )
  assert !filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Untapped),
    tapped_ctx,
  )

  // WithRestriction returns False when is_tapped is None (non-battlefield)
  assert !filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Tapped),
    none_ctx,
  )
  assert !filter_matcher.matches(
    creature,
    filters.WithRestriction(filters.Untapped),
    none_ctx,
  )
}

// ══════════════════════════════════════════════════════════════════════════
// Task 2: Supertype filter — unit test
// ══════════════════════════════════════════════════════════════════════════

pub fn supertype_filter_matches_basic_test() {
  let basic_land_card = basic_land("bl1", "Forest")
  let ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: None,
      zone: zone.Library,
      chosen_color: None,
    )

  // Card with supertypes: [Basic] matches Supertype(Basic)
  assert filter_matcher.matches(
    basic_land_card,
    filters.Supertype(supertype.Basic),
    ctx,
  )

  // Card with supertypes: [Basic] does NOT match Supertype(Legendary)
  assert !filter_matcher.matches(
    basic_land_card,
    filters.Supertype(supertype.Legendary),
    ctx,
  )
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: Zone filter — unit test
// ══════════════════════════════════════════════════════════════════════════

pub fn zone_filter_matches_correct_zone_test() {
  let creature = create_creature("c1", "Test Creature", 2, 2)
  let graveyard_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: None,
      zone: zone.Graveyard,
      chosen_color: None,
    )
  let hand_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [],
      is_tapped: None,
      zone: zone.Hand,
      chosen_color: None,
    )

  // Zone(Graveyard) matches when zone is Graveyard
  assert filter_matcher.matches(
    creature,
    filters.Zone(zone.Graveyard),
    graveyard_ctx,
  )
  // Zone(Graveyard) does NOT match when zone is Hand
  assert !filter_matcher.matches(
    creature,
    filters.Zone(zone.Graveyard),
    hand_ctx,
  )
}

// ══════════════════════════════════════════════════════════════════════════
// Task 1: WithController(Opponent) — unit test
// ══════════════════════════════════════════════════════════════════════════

pub fn with_controller_opponent_matches_only_opponents_test() {
  let creature = create_creature("c1", "Test Creature", 2, 2)
  // active_player = 1, so opponents = [2]
  let p1_ctx =
    filter_matcher.FilterContext(
      controller_id: 1,
      active_player: 1,
      target_player: None,
      opponent_ids: [2],
      is_tapped: None,
      zone: zone.Battlefield,
      chosen_color: None,
    )
  let p2_ctx =
    filter_matcher.FilterContext(
      controller_id: 2,
      active_player: 1,
      target_player: None,
      opponent_ids: [2],
      is_tapped: None,
      zone: zone.Battlefield,
      chosen_color: None,
    )

  // WithController(You) matches when controller_id == active_player
  assert filter_matcher.matches(
    creature,
    filters.WithController(filters.You),
    p1_ctx,
  )
  assert !filter_matcher.matches(
    creature,
    filters.WithController(filters.You),
    p2_ctx,
  )

  // WithController(Opponent) matches when controller_id is in opponent_ids
  assert filter_matcher.matches(
    creature,
    filters.WithController(filters.Opponent),
    p2_ctx,
  )
  assert !filter_matcher.matches(
    creature,
    filters.WithController(filters.Opponent),
    p1_ctx,
  )

  // WithController(Any) always matches
  assert filter_matcher.matches(
    creature,
    filters.WithController(filters.Any),
    p1_ctx,
  )
  assert filter_matcher.matches(
    creature,
    filters.WithController(filters.Any),
    p2_ctx,
  )
}
