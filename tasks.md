# MTG Engine Implementation Plan

## Phase 1: Minimal Working Skeleton

- [x] **Define basic type structures** - Create minimal types for Card, Player, GameState, Zone enums, Phase/Step enums

- [x] **Define Action and Error types** - Create Action type with one simple action (e.g., PassPriority) and Error type with one error case

- [x] **Implement basic dispatch function** - Create dispatch function that handles the one simple action and returns Result(GameState, Error)

- [x] **Implement game initialization** - Create function to set up a minimal game state (two players, initial phase)

- [x] **Write initial tests** - Test that game initializes and dispatch can handle the basic action

## Phase 2: Turn Structure

- [x] **Add phase/step advancement** - Implement action to advance to next phase/step and update dispatch to handle it

- [x] **Test phase advancement** - Verify phases advance in correct order through a full turn cycle

- [x] **Add basic priority passing** - Implement priority system and automatic phase advancement when both players pass

- [x] **Test priority system** - Verify priority passes correctly between players

## Phase 3: Mana System

- [x] **Add mana pool to player state** - Extend Player type with mana pool tracking each color

- [x] **Add mana production action** - Implement action to add mana to pool (e.g., tap land for mana)

- [x] **Test mana system** - Verify mana can be added

- [x] **Add mana pool emptying** - Implement automatic mana pool clearing at step transitions

- [x] **Test mana pool emptying** - Verify mana empties at correct times

## Phase 4: Playing Lands

- [x] **Add play land action** - Implement action to play land from hand to battlefield with basic validation

- [x] **Test land playing** - Verify lands move from hand to battlefield, land-per-turn limit works

- [x] **Add land tap/untap** - Implement tapping lands for mana as an action

- [x] **Test land tapping** - Verify lands tap, produce mana, and untap during untap step

## Phase 5: Casting and Resolving Creatures

- [x] **Add stack to game state** - Extend GameState with stack zone

- [x] **Add cast creature action** - Implement casting creatures (pay cost, put on stack)

- [x] **Test creature casting** - Verify mana is paid and spell goes on stack

- [x] **Add spell resolution** - Implement resolving top spell from stack to battlefield

- [x] **Test creature resolution** - Verify creatures enter battlefield with correct stats

- [ ] **Add summoning sickness** - Track when creatures can attack/tap

- [ ] **Test summoning sickness** - Verify creatures have summoning sickness correctly

## Phase 6: Basic Combat

- [ ] **Add declare attackers action** - Implement declaring attackers with basic validation

- [ ] **Test declare attackers** - Verify only legal creatures can attack

- [ ] **Add declare blockers action** - Implement declaring blockers with basic validation

- [ ] **Test declare blockers** - Verify only legal blocks are accepted

- [ ] **Add combat damage** - Implement dealing combat damage to creatures and players

- [ ] **Test combat damage** - Verify damage is calculated and dealt correctly

- [ ] **Add state-based actions** - Implement checking for creature death and player loss

- [ ] **Test state-based actions** - Verify dead creatures go to graveyard, players at 0 life lose

## Phase 7: Instants and Sorceries

- [ ] **Add cast instant action** - Implement instant casting (any time with priority)

- [ ] **Add cast sorcery action** - Implement sorcery casting (main phase, stack empty)

- [ ] **Test instant/sorcery timing** - Verify timing restrictions work correctly

- [ ] **Add basic spell effects** - Implement simple effects (deal damage, draw card)

- [ ] **Test spell effects** - Verify effects resolve correctly

## Phase 8: Artifacts and Enchantments

- [ ] **Add cast artifact action** - Implement artifact casting

- [ ] **Add cast enchantment action** - Implement enchantment casting

- [ ] **Test artifact/enchantment casting** - Verify they enter battlefield correctly

## Phase 9: Creature Keywords

- [ ] **Add keyword support to creatures** - Extend creature type to include keyword list

- [ ] **Add flying combat rules** - Implement flying/reach in blocking validation

- [ ] **Test flying** - Verify flying creatures can only be blocked by flying/reach

- [ ] **Add first strike** - Implement first strike combat damage step

- [ ] **Test first strike** - Verify first strike damage happens before normal damage

- [ ] **Add remaining keywords** - Implement trample, vigilance, haste, lifelink, deathtouch, double strike

- [ ] **Test all keywords** - Verify each keyword works correctly in combat and other contexts

## Phase 10: Polish and Edge Cases

- [ ] **Add comprehensive error types** - Expand error types to cover all validation failures

- [ ] **Add validation edge cases** - Handle corner cases in all actions

- [ ] **Write integration tests** - Test complete multi-turn game scenarios

- [ ] **Test invalid action sequences** - Verify all invalid actions return appropriate errors
