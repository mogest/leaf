# Leaf — Project Scope (Draft 2)

Functional scope only. No technical decisions, data formats, or architecture here.

## 1. What this is

An open source leave management platform for organisations with staff and contractors across
multiple countries. It is the single place where people request leave, managers approve it,
and balances accrue — producing a reliable log and reports that administrators feed into
whatever payroll system they use.

Built for a single organisation to start with. Multi-tenancy is an eventual, not a v1 goal:
model things so that hosting many organisations later is not a rewrite, but don't build tenant
management, billing, or per-tenant isolation now.

The first organisation it is built for has people in New Zealand, the UK, Canada and Spain,
a mix of employees and employee/contractor hybrids, and a country-specific payroll system that
only covers part of the workforce. Nothing about that organisation is hardcoded — those
circumstances are what make the requirements broad, not what the system is built around.

## 2. Problems it solves

- Leave gets tracked in spreadsheets and ad-hoc chat messages. There is no record of who
  requested what, when, or whether anyone approved it.
- Where entitlement is granted as a lump at the start of a financial year, admins end up
  maintaining a separate spreadsheet to work out what someone has *actually* accrued at a
  point in time.
- Payroll runs before month end, so leave entered late has to be manually reconciled against
  the previous run.
- Payroll systems are usually country-specific, so staff outside that country have nowhere to
  file leave and there is no one system everybody feeds into.
- Cross-referencing leave, public holidays, FTE and work patterns at payroll time is manual.

## 3. Explicitly out of scope

- Money. No pay rates, no leave valuation, no average-daily-pay or last-52-weeks
  calculations, no payouts. Payroll does that; this system answers *when* and *how much time*.
- Automated payroll integration in v1. Output is reports/exports that a human enters.
- Enforcing statutory minimums by jurisdiction. Policies are configured by the organisation;
  the system does not assert legal compliance.
- Multi-tenant hosting, billing, tenant administration.
- Timesheets, rostering, attendance, expenses, performance.

## 4. Core concepts

### 4.1 Organisation
Owns the people, policies, leave types, public holiday calendars and roles. One organisation
in v1.

### 4.2 Person
An employee or contractor. Has an employment start date, a birth date, a country/holiday
calendar, a manager, and a status (active / ended, with an end date).

Employee vs contractor is **not** a distinction the system makes. It is expressed purely by
which leave policy the person is on.

### 4.3 Work pattern
Hours worked on each day of the week — e.g. Mon 9, Tue 9, Wed 4, Thu 0, Fri 0, Sat 0, Sun 0.
The system derives contracted weekly hours and FTE fraction from this against an
organisation-level full-time week.

Work patterns are **effective-dated**: a person has a pattern from a given date, and history
is preserved.

### 4.4 Everything is editable historically
Work patterns, policy assignments, leave types, entitlements, leave records and public holiday
calendars can all be created, amended or removed **retrospectively**. Admins can insert a work
pattern change that started six months ago, correct an FTE that was wrong all year, or fix a
back-dated start date.

When that happens the system recalculates accruals, grants, expiries and balances from the
effective date forward, shows what changed, and records it in the audit log. Already-recorded
leave is not corrupted by the change — but where a correction genuinely alters a past balance,
the new balance is the truth and the delta is visible.

### 4.5 Leave policy (entitlement set)
A named, reusable group of entitlements — e.g. "NZ Employee", "UK Employee",
"Contractor-employee hybrid". Assigned to a person **with effective dates**, so a person can
move between policies over time.

For each leave type it includes, a policy defines:

- the **entitlement per grant period at 1.0 FTE** — 8 hours each quarter, 10 days each year
- whether the entitlement is **pro-rated by FTE**
- how it is **granted** — the grant period, what that period is anchored to, and whether the
  entitlement accrues across it or lands at its start (§4.7)
- the **rollover/expiry rule** (§4.8)
- when the entitlement **starts and stops being offered** (§4.8)
- whether a **negative balance** is permitted
- how **public holidays** are treated (§4.9)

The **unit** — hours or days — belongs to the leave type (§4.6) rather than to the policy.
A sick day is a day under every policy.

### 4.6 Leave type
Configurable per organisation. Each has a unit; how it is granted comes from the policy that
includes it (§4.5), so the same type can behave differently under two policies. A representative
set:

| Type | Unit | Granted | Expiry | Notes |
|---|---|---|---|---|
| Annual leave | hours | Daily accrual | Rolls over indefinitely | Pro-rated by FTE |
| Sick leave | days | Block grant on employment anniversary | Rolls over up to a cap | Not pro-rated by hours worked — a sick day is a sick day |
| Quarterly leave | hours | Block grant on the first day of each quarter | Lapses at quarter end | 8h at 1.0 FTE, pro-rated (0.6 FTE = 4.8h) |
| Birthday leave | days | Block grant on the person's birthday | Lapses a configurable window (default 2 weeks) after the birthday | Always 1 day, not pro-rated. May go negative |
| Longevity leave | days | Block grant on employment anniversary | Lapses at the next anniversary | Always 1 day, not pro-rated |
| Public holiday allowance | hours | Calculated from the country calendar × FTE (§4.9) | Follows annual leave | Only where holidays are included in entitlement |
| Unpaid leave | hours | Not granted | n/a | No balance, recorded only |
| Bereavement / other | days | Org-configurable | Org-configurable | |

### 4.7 Granting: accrual and block grants
Two mechanisms, chosen per leave type in the policy.

**Daily accrual.** The entitlement accrues evenly across its grant period, day by day. Rate
derives from the policy entitlement, the person's FTE and the length of the period. This is
annual leave's model, and it is the thing that removes the parallel spreadsheet.

**Block grant.** The whole entitlement lands at once, on the first day of its grant period.
Block grants exist because NZ and UK law grant some leave — sick leave in particular — as a
block rather than accruing it, and the system has to match the law rather than the other way
round.

Where a block grant is pro-rated by FTE, it is the hours the person works on the day it lands that
it is pro-rated by. Changing their hours later in the period does not resize a grant that has
already landed. Correcting the hours they were *on* when it landed does (§4.4).

Either way the **grant period is configuration**, not a fixed list of trigger dates. It is a
month, a quarter or a year, anchored to the person's employment start date, their birthday, the
calendar year, or the organisation's financial year — and the organisation configures which
month its financial year starts. Calendar-anchored and financial-year-anchored entitlements stay
distinct even where they currently coincide: moving the organisation's financial year must not
move a calendar-anchored grant.

So annual leave is a year anchored to the employment date, accruing daily; sick and longevity
leave the same year, granted as a block; quarterly leave a calendar quarter, granted as a block;
birthday leave a year anchored to the birthday. Monthly accrual against a financial year, common
in the UK, needs no new mechanism.

A person who joins part-way through a grant period receives no **block grant** for that period —
their first one lands at the start of the next period (§8). Accrual is not affected: it is
proportional by nature, so it starts on their first day and their first period is simply a part
period.

Balances may go **negative** where the policy allows it (advance leave). The person then
accrues back to positive; the system doesn't block this, it just shows a negative balance.

### 4.8 Rollover and expiry
Configured per leave type:

- **Rolls over indefinitely** — annual leave.
- **Rolls over up to a cap** — e.g. sick leave.
- **Lapses at the end of its grant period** — quarterly leave does not survive the quarter;
  longevity leave does not survive the year.
- **Lapses a fixed window after its grant** — birthday leave expires a configurable period
  (default two weeks) after the birthday.

Expiry is applied automatically and shows in the person's leave history, so a balance never
silently disappears.

**Which lot gets used first.** A person can hold more than one lot of the same leave type at once,
lapsing at different times — a one-off top-up that must be used by June sitting alongside annual
leave that never lapses. Leave always draws on the lot that lapses soonest, so a lot with a
deadline is spent before one without it, and nothing lapses that could have been used.

**Discontinuing an entitlement.** A policy can stop offering a leave type from a date without
disturbing anything it granted before then. Two dates matter and they may differ: the date
granting stops, and the date the leave type stops being usable. Setting the second later than the
first gives a wind-down — "we are dropping quarterly leave from 1 January, use what you have
left by 31 March". Whatever balance remains on the final day expires like any other lapse, visibly and
in the audit log. Leave already taken is untouched, and leave dated while the entitlement was
still offered can still be filed afterwards (§5.2). An entitlement may also be re-offered later;
the gap is part of the record.

**"The year" is by default the person's employment anniversary year**, not a shared financial or
calendar year, and that is the anchor for anything that accrues. Anything anchored that way —
accrual, anniversary block grants, longevity leave lapsing, sick leave rollover caps,
excess-balance thresholds — therefore starts on a different date for each person, which is the
price of having entitlement tie back to when they actually started. Where an entitlement needs a
shared year instead, that is configuration (§4.7), not an exception in code.

Reporting is unaffected — reports run over whatever date range is asked for (a payroll month,
a quarter, a financial year). The anniversary year governs *entitlement*, not *reporting
periods*.

### 4.9 Public holidays
Two treatments, set by the policy:

1. **Automatically granted off** — the public holiday is a non-working day. No leave is
   deducted; the person simply doesn't work. Standard employee case.
2. **Included in entitlement** — the person's pro-rata share of the country's public holidays
   is added to their allowance (e.g. 11 NZ/Canadian public holidays at 0.6 FTE = 6.6 days).
   Public holidays are then ordinary working days for them: if they want one off, they submit
   a normal leave request for it, or shift their hours to another day. This is how the
   contractor/employee hybrid arrangement works.

**The system calculates the top-up itself.** It counts the public holidays in the person's
calendar for their leave year, applies their FTE and standard day length, and credits the
result as its own public holiday allowance line — visible and reportable separately from
annual leave, rather than silently folded into one number. When the holiday calendar changes,
or someone's FTE changes mid-year, the allowance recalculates like any other entitlement
(§4.4) and the change is audited.

The system holds public holiday calendars per country (and region where relevant), and shows
them on calendars and in reports.

### 4.10 Opening balances
The organisation records the date it started tracking leave here. Nothing is accrued, granted or
expired before that date, so every person employed on it needs an opening balance per leave type,
imported from existing spreadsheets/payroll — those balances are the whole story up to that point.
Leave dated earlier can still be recorded and draws down what was brought in, which is what makes
a sick day discovered after go-live land correctly.

Moving that date re-works every balance in the organisation at once. It is the one setting that
does, so it is worth being deliberate about.

Admins can also make manual balance adjustments at any time, with a mandatory reason, fully
audited.

## 5. Functionality

### 5.1 Roles
- **Person** — requests leave, sees own balances and history, sees team calendar.
- **Manager** — everything a person can do, plus approve/decline/cancel for their reports.
- **Administrator (HR/payroll)** — full access: people, policies, work patterns, balances,
  adjustments, reports, everything a manager can do for anyone.

Reporting lines are recorded (this person reports to that person). Where a person has no
manager, or their manager is unavailable, approval **falls back to an administrator**. No
configurable delegate in v1.

### 5.2 Requesting leave
- Choose leave type, dates, and amount.
- Amount can be entered in **hours or days**, whichever suits — the system converts using the
  person's work pattern for those dates and shows both. A person on 5×8h picks "1 day"; a
  person on a 9-hour day picks "9 hours".
- **Arbitrary fractional amounts are allowed.** No half-day-only constraint: quarterly leave
  might grant 7.2 hours, and the person needs 1.8 hours of annual leave on top to take a
  9-hour day off.
- **A single day off can draw on more than one leave type** — 7.2h quarterly + 1.8h annual for
  the same day. The system must support splitting a day across leave types and show the day
  as fully covered.
- Multi-day requests span only working days per the person's pattern.
- Optional note/reason.
- Shows the projected balance if approved, including if it goes negative — warns but does not
  block where the policy allows.
- **Retrospective entry** is supported: sick leave in particular is often recorded after the
  fact.

### 5.3 Approval
- Request goes to the person's manager, or to an administrator where there isn't one
  available.
- Manager approves or declines, with an optional comment.
- Pending requests are visible to the approver as a queue and appear on calendars as
  tentative.
- The system surfaces what needs attention; how people are told about it (email, Slack, in-app)
  is a delivery decision outside this scope.

### 5.4 Cancellation and amendment
- The requester may cancel or amend a request **while it is still pending**.
- Once approved, **only a manager or administrator can cancel or amend it**. This is
  deliberate — people should not be able to quietly remove leave they've already taken.
- Cancellation returns the balance and is recorded in the log.

### 5.5 Calendars
- Team/organisation calendar showing who is away, when, what type, and status
  (pending/approved).
- Public holidays shown per person's country.
- Individual view of own leave and balances, and of how each balance was arrived at — what was
  granted or accrued, what was taken, and what lapsed.
- A shared "who's around" spreadsheet should become unnecessary.

### 5.6 Reporting
Reports are the payroll handover, so they matter as much as the request flow.

- **Leave taken in a period** — by person, by type, by country, in both hours and days.
- **Payroll reconciliation** — leave for a given payroll period, flagging records that were
  created, approved, or amended *after* a nominated cut-off date (i.e. after the last payroll
  run) so admins can see what needs to be picked up this cycle rather than eyeballing colours
  in a spreadsheet.
- **Current balances** — per person, per leave type, as at a date.
- **Excess balance / upper threshold** — people whose accrued balance exceeds a configured
  threshold, so it can be actioned before it becomes a liability.
- **Public holidays in a period** — who observes them, who has them in their entitlement,
  what FTE and work pattern applied.
- **Expiring soon** — balances about to lapse (quarterly, birthday, longevity).
- **Audit** — see below.
- All reports exportable.

### 5.7 Audit log
Every meaningful action recorded with who, what, when, and before/after values: requests,
approvals, declines, cancellations, amendments, policy and work-pattern changes (including
retrospective ones), manual balance adjustments, opening-balance imports.

Grants, accruals and expiries are not actions anyone takes — they follow from someone's dates,
hours and policy — so they belong to the leave history (§4.8, §5.5) rather than here. What the
audit log holds is the change that caused them, and who made it.

### 5.8 Query interface (MCP / API)
An interface that lets admins ask the system questions in natural language via an AI assistant
— "who took leave last month", "build me a sheet of hours for August", "who is over their
threshold". This replaces a lot of manual spreadsheet assembly and is a first-class goal,
not an afterthought.

### 5.9 Accounts and access
- **Google OAuth** is the only login mechanism in v1.
- Person-level account provisioning by administrators.
- Sensible privacy: people see their own detail; managers see their reports; leave *reasons*
  and sick-leave detail should not be broadly visible.

## 6. Deliberate design positions

1. **Accrual from the person's own start date**, not a shared annual grant — for leave types
   that accrue. Removes the parallel spreadsheet.
2. **Block grants are first-class**, not a workaround, because sick leave and similar
   entitlements are granted that way by law.
3. **Hours are the underlying unit where the leave type is time-based**; days where the leave
   type is day-based (sick, birthday, longevity). Display in both; let people enter in either.
4. **Arbitrary fractions of an hour are valid**, and one day can be covered by several leave
   types.
5. **Negative balances are allowed, not blocked.** Advance leave is a real thing.
6. **The system never talks about money.**
7. **History is editable.** Corrections are expected and the system recalculates rather than
   forcing admins into a spreadsheet. A balance is always worked out from the record rather than
   kept as a running total, so a correction takes effect everywhere at once.
8. **Nothing country-specific is hardcoded.** New Zealand's rules are the most complex, so if
   the model handles NZ it handles the rest; but jurisdictions are expressed as configuration
   (calendars, policies, leave types), not code.
9. **Approved leave is not self-serve-deletable.**
10. **Employee vs contractor is a policy, not a type.**
11. **The leave year is by default the person's employment anniversary year**, not a shared one.
    Where an entitlement genuinely needs a calendar or financial year, that is configuration.

## 7. Suggested phasing

**Phase 1 — the log.** People, work patterns, leave types, policies, opening balances,
requests, approvals, cancellation rules, audit log, basic balances, calendar, Google OAuth.

**Phase 2 — the maths.** Daily accrual, block grants and trigger dates, FTE pro-rating,
rollover and expiry, public holiday treatments, retrospective editing and recalculation,
manual adjustments.

**Phase 3 — the handover.** Reporting suite, payroll reconciliation report, exports,
threshold and expiry alerts.

**Phase 4 — the assistant.** MCP/API query interface.

**Later, not now.** Payroll system integration, multi-tenancy, statutory compliance
assertions, mobile app.

## 8. Known gaps and accepted limitations

- **Alternative holidays / time off in lieu.** NZ generates an alternative holiday when someone
  works a public holiday. The system does not model this. For now an administrator manually
  allocates the extra leave. **This is a known gap and should be designed properly later.**
- **Mid-period joiners and block grants.** Someone joining part-way through a grant period gets no
  block grant for that period; their first one lands at the start of the next. Pro-rating a block
  grant across a first partial period is not modelled, and should be designed later if it turns out
  to be wanted. Accrual has no such gap.
- **A booked day whose hours later fall to zero.** What a whole day off is worth follows from the
  work pattern on that date, so a day booked in advance moves with a pattern change before it —
  which is the point. Where the change takes the day to no hours at all, the leave silently stops
  counting, and nobody is told. The system should surface this rather than let it vanish, and has
  nowhere to surface it yet.
- **Public holidays worked but not credited.** §4.9's two treatments are the only arrangements
  available. An arrangement where public holidays are ordinary working days and *no* allowance is
  credited — a pure contractor who simply does not bill them — cannot be configured.
- **No payroll integration.** Admins re-key from exports.
- **No statutory validation.** The system will happily be configured below a legal minimum.
- **Notification delivery** (email, Slack, in-app) is deliberately unspecified here.
