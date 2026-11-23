# Google Tasks widget: one-time setup

quickdock talks to the Google Tasks API with your own OAuth client (nothing goes through a third party).

1. Google Cloud Console → create a project (any name).
2. APIs & Services → Library → enable **Google Tasks API**.
3. APIs & Services → OAuth consent screen → External, add yourself as a test user.
4. Credentials → Create credentials → OAuth client ID → **Desktop app** → download the JSON.
5. Save it as `~/.config/quickdock/google-client.json`.
6. Click the tasks tile → **Connect Google account** and approve in the browser.

The refresh token is stored in `~/.config/quickdock/google-token.json` (mode 0600). The widget uses your *default* task list (`@default`).
