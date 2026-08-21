# Leaf

Leave management for employees and contractors. Elixir / Phoenix / LiveView / Postgres.
Functional scope lives in `SCOPE.md` — read it before designing anything.

After changing code: `mix format`, `mix test`, `mix credo`.

## Working in this repo

- Use the built-in file tools — Read, Edit, Write — for reading and editing files, **including in auto
  mode**. Prefer them over `cat`/heredocs/`sed`: Edit fails loudly on a bad match, and Write won't
  clobber a file that hasn't been read. Shell tools are for running things, not for editing files.
- Never commit unless asked. Never push unless asked, every time.

## Simplicity comes first

- Before finishing anything, ask whether this is the *simplest* solution. If not, redo it.
- Wanting to tack more logic into an already crowded function or module means **the abstraction is
  wrong**. Don't add the branch — step back and simplify the design.
- Prefer deleting code and collapsing concepts over adding options, flags and special cases.
- Solve the problem in front of you. No speculative generality.

## Separation of concerns

- **`Leaf.X`** — context module. The only public interface to its area. Callers (web, mix tasks,
  other contexts) go through it and nothing else.
- **`Leaf.X.Y`** — the modules that do the work: schemas, queries, calculations. Not called from
  outside `Leaf.X`.
- Logic lives in the logic layer. LiveViews assign and render; they don't calculate, query, or
  hold business rules.
- A context calling into another context's internals is a bug. Cross-context work goes through
  the other context's public functions.

## Comments

- Comment only when the *why* can't be carried by the code, and only where it's critical.
  Most code needs none. Reader = experienced Elixir dev.
- Feeling the need to explain *what* the code does means the code isn't simple enough — see above.
- `@moduledoc` on every module: one line where one line does.
- Never comment CSS unless asked.

## Elixir style

Match the style of `~/src/cogo/drome/spark` (before 2026-02-24 it lived at `spark/app/`; end-of-2025
revision `af87da500` is the reference). In short:

- `@spec` on public context functions. `@type t` on structs, `@enforce_keys` where a key is required.
- Lookups return `{:ok, thing} | :error`; `fetch_*` names for those. `!` variants raise.
- Always handle `{:error, _}` — propagate, use the `!` variant, or pattern-match to crash. Never
  silently ignore.
- Pattern matching and multiple function heads over `cond`/nested `if`. `with` for happy paths.
- Aliases one per line, alphabetical, after `require`. Alias anything nested deeper than 2 or used
  more than once.
- Module attributes for static data tables.
- Max line length 120.
- No `dbg`, `IO.inspect`, or `TODO` left in code.

## LiveView

- Never call `assign/2,3` inside `render/1` or a function component.
- Real `Form` struct via `to_form/2`; bind `phx-change` so params write back to the changeset in
  assigns. A lone-button form can skip it.
- One changeset per schema. Per-form changesets leak the front end into the backend; split only for
  genuinely distinct states (create vs update) and share the validation.
- Lean on `Ecto.Changeset` built-ins instead of hand-rolling equivalents.

## CSS

- **No Tailwind. No utility classes. No BEM.** Not negotiable.
- A design system of pure semantic classes. CSS is code: a class is named for *what it does*, not
  for the thing it happens to be marking up right now — the same way a function is named.
- Nested CSS. Scope page-specific rules under the page's top-level selector (`main.request-leave { … }`).
  Leave a rule unscoped only when it's genuinely site-wide.
- Reuse existing classes before adding new ones.
- Logical properties (`inline-size`, `margin-inline-start`) over physical ones.
- Baseline widely available.

## Testing

- Concise. Test public functions only. Minimise test count while covering all reasonable paths.
- Mock with Mimic, and **only** external services (APIs). Never mock internal application code.
- No conditionals over static test data — tests know their expected values up front. Conditionals
  only when asserting on system output.
- No real people or real companies in test data.

## Dates, times and numbers

- Leave arithmetic is exact: no floats for balances. Fractional hours are required (a 7.2h grant
  plus 1.8h annual covers a 9h day).
- Everything year-shaped hangs off the person's own employment anniversary, not a shared year.
