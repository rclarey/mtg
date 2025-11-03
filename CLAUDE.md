# MTG Engine - Project Overview

This project implements a Magic: The Gathering game engine as a finite state machine using functional reactive programming in Gleam.

## Project Outline

- Implements a game of Magic the Gathering by strictly following the rules outlined at https://media.wizards.com/2025/downloads/MagicCompRules%2020250919.txt
  - Supports Lands, Instants, Sorceries, Creatures, Artifacts, and Enchantments
  - Supports combat (declaring attackers, declaring blockers, applying combat damage)
  - Supports basic keywords for Creatures
- Rejects invalid game actions
- Updates the game state as valid game actions occur

## Programming Language and Paradigm

- Uses a Functional Reactive Programming style
- Written in idiomatic Gleam
  - Refer to https://tour.gleam.run/everything/ for how to write Gleam
  - Refer to the pages linked on https://hexdocs.pm/gleam_stdlib/ for Gleam standard library documentation

## Project Structure

- Code is in the `src` directory and is split into different modules by concern
- There is a main function `dispatch` which takes an action and returns an updated game state, or if the action is invalid it returns an error

## Core Architecture

The engine follows a functional reactive pattern with a central `dispatch` function:
```
dispatch(GameState, Action) -> Result(GameState, Error)
```

All game actions flow through dispatch, which validates the action and returns either an updated game state or an error.

## Implementation Plan

### **tasks.md** - Source of Truth for Implementation Tasks
Contains the complete implementation plan organized in phases with checkable markdown tasks.
Check off tasks in tasks.md by changing `- [ ]` to `- [x]` as they're completed.

## Getting Started

1. Review this file for the project specification
2. Check tasks.md to see current progress and next tasks
3. Implement tasks sequentially following the phase order
4. Mark tasks complete as you finish them
