defmodule Leaf.Repo.Migrations.ExcludeOverlappingGrantWindows do
  use Ecto.Migration

  @drop "ALTER TABLE policy_entitlements DROP CONSTRAINT policy_entitlements_no_overlap"

  @grant_windows """
  ALTER TABLE policy_entitlements
    ADD CONSTRAINT policy_entitlements_no_overlap
    EXCLUDE USING gist (
      leave_policy_id WITH =,
      leave_type_id WITH =,
      daterange(effective_from, COALESCE(granted_to, effective_to, 'infinity'::date), '[]') WITH &&
    )
  """

  @lives """
  ALTER TABLE policy_entitlements
    ADD CONSTRAINT policy_entitlements_no_overlap
    EXCLUDE USING gist (
      leave_policy_id WITH =,
      leave_type_id WITH =,
      daterange(effective_from, COALESCE(effective_to, 'infinity'::date), '[]') WITH &&
    )
  """

  # The harm the constraint names is granting the same balance twice over, and that is a property of
  # the grant windows, not of the lives. Excluding on the life also refused a succession that
  # changes an entitlement's terms — an open-ended row occupies all future time — which left
  # `effective_to` as the only way to say "from here, these terms instead", lapsing everything the
  # old row had granted.
  def up do
    execute @drop
    execute @grant_windows
  end

  def down do
    execute @drop
    execute @lives
  end
end
