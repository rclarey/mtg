# Intangible - a MTG rules engine

## Project Outline

- Implements a rules engine for Magic the Gathering by strictly following the rules in the `./rules/` directory
  - `./rules/000-contents.md` is the entrypoint which contains a table of contents and links to other rules files
- Rejects invalid game actions
- Updates the game state as valid game actions occur

## Programming Language and Paradigm

- Written in idiomatic Gleam
  - Refer to https://tour.gleam.run/everything/ for how to write Gleam
- Depends only on the standard library (`gleam_stdlib`)
  - Documentation is found at https://hexdocs.pm/gleam_stdlib/gleam/<SUBMODULE>.html, e.g. https://hexdocs.pm/gleam_stdlib/gleam/result.html for `gleam/result`
- Follow existing patterns in the code

### Best practices
- Use the `use` keyword, `result.try`, and `util.guard` instead of nested pattern matching wherever possible
- Use shorthand syntax for record constructors (e.g. `Thing(field:)` which is equivalent to `Thing(field: field)`)
- Use unqualified imports for common standard library types/constructors **only** (e.g. `import gleam/option.{Some, None}`), otherwise use qualified imports


## Common commands
- Type check code: `gleam check`
- Run tests: `gleam test`
- Format code: `gleam format`
