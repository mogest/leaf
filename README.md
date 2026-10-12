# Leaf

Open source leave management for organisations with staff and contractors across several
countries. One place where people request leave, managers approve it, and balances accrue —
producing a log and reports that administrators feed into whatever payroll system they use.

Elixir / Phoenix / LiveView / Postgres. The web interface covers requesting, amending and approving
leave, balances, who is away, and administering people, policies, leave types, calendars and the
audit log. People sign in with Google.

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

## Signing in

Somebody may sign in with Google only where a person in Leaf has their address. The Google
credentials come from an Internal OAuth client in the organisation's Google Cloud, whose
authorised redirect URI is `https://<host>/sign-in/callback`:

- `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` — required in production, and used in development
  wherever they are set.
- `SIGN_IN_PICKER=true` lets anybody sign in as anybody from a list at `/sign-in/pick`, for testing.
  It is always on in development, since seeded people have made-up addresses, and off in
  production unless set.

To send notifications in Slack, see `docs/slack.md`.

The development database is `leaf_dev`. Set `DEV_DATABASE` to use another, so a second checkout can
run beside the first: `DEV_DATABASE=leaf_dev_other PORT=4001 mix phx.server`.

## Working on it

```sh
mix precommit            # compile --warnings-as-errors, unused deps, format, test
mix credo
```

`CLAUDE.md` holds the conventions this codebase is written to — context boundaries, how writes are
shaped and audited, comment style, CSS, and how leave arithmetic is allowed to round. They apply
to everyone, not only to Claude.
