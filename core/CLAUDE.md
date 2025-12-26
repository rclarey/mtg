# MTG Engine - Project Overview

## Project Outline

- Implements a game of Magic the Gathering by strictly following the rules in the `../rules/` directory (relative to this module)
  - `../rules/000-contents.md` is the entrypoint which contains a table of contents and links to other rules files
- Rejects invalid game actions
- Updates the game state as valid game actions occur

## Programming Language and Paradigm

- Uses a Functional Reactive Programming style
- Written in idiomatic Gleam
  - Refer to https://tour.gleam.run/everything/ for how to write Gleam
  - Refer to the pages linked on https://hexdocs.pm/gleam_stdlib/ for Gleam standard library documentation
  - Follow existing patterns in the code
  - Use `result.try` and `bool.guard` instead of nested pattern matching wherever possible

## Project Structure

- code is in the `src` directory
- tests are in the `test` directory

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
