Mimic.copy(Leaf.Messaging.Slack.API)
Mimic.copy(Sentry)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Leaf.Repo, :manual)
