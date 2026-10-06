# Slack

Leaf sends direct messages in Slack about leave requests. It DMs whoever has to decide a request,
and rewrites that message once the request is decided so nobody acts on it twice. It also DMs the
requester when somebody else decides, amends or cancels their request. Messages only go out; Leaf
reads nothing back from Slack.

Slack is optional. Without a token, Leaf logs each message it would have sent and does nothing
else.

## Create the app

1. At <https://api.slack.com/apps>, choose **Create New App → From a manifest**, pick the
   workspace and paste:

   ```yaml
   display_information:
     name: Leaf
     description: Leave requests and approvals
   features:
     app_home:
       home_tab_enabled: false
       messages_tab_enabled: true
       messages_tab_read_only_enabled: true
     bot_user:
       display_name: Leaf
       always_online: false
   oauth_config:
     scopes:
       bot:
         - chat:write
         - users:read
         - users:read.email
   settings:
     socket_mode_enabled: false
     token_rotation_enabled: false
   ```

   The Messages tab is read-only because nothing reads replies.

2. Under **Basic Information → Display Information**, upload [`slack-icon.png`](slack-icon.png)
   as the app icon. The manifest has no field for it.

3. Under **Install App**, install it to the workspace. A workspace that restricts app installs
   sends this to a Slack admin to approve. Copy the **Bot User OAuth Token** (`xoxb-…`).

## Give Leaf the token

Set `SLACK_BOT_TOKEN` in production's environment and restart. Keep it with the other secrets,
not in plain config. The token is read in production only, so nothing done in development or
test messages real people.

To check the token before deploying:

```sh
curl -s -H "Authorization: Bearer xoxb-…" \
  "https://slack.com/api/users.lookupByEmail?email=someone@example.com"
```

`"ok": true` means the token and scopes work.

## Things to know

- People are found by email, so a person's email in Leaf must be their Slack email. Anyone whose
  email Slack doesn't recognise is skipped, with a warning in the log.
- Links in messages use `PHX_HOST`.
- Any other Slack failure, such as a revoked token or a missing scope, is logged as an error, and
  reported to Sentry when `SENTRY_DSN` is set.
- Messages carry names, leave types, dates and approval comments into Slack.
