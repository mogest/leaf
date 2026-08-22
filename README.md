# Leaf

Open source leave management for organisations with staff and contractors across several
countries. One place where people request leave, managers approve it, and balances accrue —
producing a log and reports that administrators feed into whatever payroll system they use.

Elixir / Phoenix / LiveView / Postgres. Early: the domain is built, the web interface is not.

`SCOPE.md` is the functional specification and the place to start.

## What makes it different

- **Balances are never stored.** What a person holds is worked out from their employment dates,
  work patterns, policy and the leave they filed, every time it is asked for. Correcting any one
  of those corrects every figure that depended on it, with nothing left to invalidate.
- **History is editable.** Work patterns, policy assignments, entitlements and calendars can all
  be amended or removed retrospectively, and everything downstream follows.
- **The leave year is the person's own employment anniversary**, not a shared one — which is what
  removes the parallel spreadsheet. Where an entitlement needs a calendar or financial year
  instead, that is configuration.
- **Nothing is hardcoded per country.** Jurisdictions are calendars, policies and leave types.
  New Zealand's rules are the most awkward, so the model is shaped to them.
- **It never talks about money.** No pay rates, no valuation, no payouts. It answers *when* and
  *how much time*; payroll does the rest.

## Running it

Postgres is the only dependency to have running.

```sh
mix setup                # deps, database, assets
mix leaf.seed            # an example New Zealand organisation to develop against
mix phx.server
```

`mix leaf.seed` refuses to run where an organisation already exists; `mix ecto.reset` first.

## Working on it

```sh
mix precommit            # compile --warnings-as-errors, unused deps, format, test
mix credo
```

`CLAUDE.md` holds the conventions this codebase is written to — context boundaries, how writes are
shaped and audited, comment style, CSS, and how leave arithmetic is allowed to round. They apply
to everyone, not only to Claude.
