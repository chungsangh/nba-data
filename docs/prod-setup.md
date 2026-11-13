# Prod setup: MotherDuck token

The prod workflow needs one secret, `MOTHERDUCK_TOKEN`. These steps keep it out of the repo, out
of logs, out of shell history, and away from any workflow that doesn't run from `main`.

## How the token is protected

| Layer | Protection |
|---|---|
| Storage | GitHub encrypted **environment secret** on `prod`, never a file in the repo. |
| Who can read it | `prod` only deploys from `main`. A job from any other branch, including one that edits `prod.yml`, is refused the secret. Pull requests from forks never receive secrets. |
| Which steps see it | Only the two steps that need it (the "is it configured?" check and "Run DAG"). Checkout, setup-uv and upload-artifact never see it. |
| Triggers | `prod.yml` runs only on the schedule and on manual dispatch (which requires write access). It never runs on `pull_request` or `pull_request_target`. |
| Logs | GitHub masks secret values in logs; no workflow step echoes it or uses `set -x`. |
| Commits | The `gitleaks` pre-commit hook blocks staged files containing tokens. GitHub push protection blocks them server-side. |
| Blast radius | Use a MotherDuck **service account** token, not your personal one, and give it an expiry. |

## Steps (about 5 minutes)

Order matters: create the environment with its branch rule **before** adding the secret.

1. **Create a token in MotherDuck.** Free plan, no card. In the MotherDuck UI, create a service
   account if your plan offers one (the free plan includes service accounts), then an access token
   for it. Choose an expiry (for example 90 days) and copy the token. Don't paste it anywhere except
   step 3.

2. **Create the `prod` environment, restricted to `main`.** In the GitHub repo: **Settings →
   Environments → New environment** → name it `prod` → under **Deployment branches and tags**,
   choose **Selected branches and tags** → **Add deployment branch or tag rule** → `main`.

3. **Add the secret to that environment.** On the same `prod` environment page: **Environment
   secrets → Add environment secret** → name `MOTHERDUCK_TOKEN` → paste the token → **Add secret**.
   Add it here, not under repository secrets.

   From a terminal instead, `gh` asks for the value without echoing it or saving it to shell
   history:

   ```bash
   gh secret set MOTHERDUCK_TOKEN --env prod
   ```

4. **Turn on push protection.** **Settings → Advanced Security** (named **Code security** on
   some accounts) → enable **Secret Protection** and **Push protection**. Both are free for public
   repos.

5. **Run it once.** **Actions → Prod → Run workflow** (branch `main`, DAG `nba_daily`). The first
   run creates the `nba` database in MotherDuck and builds everything. Later runs happen daily at
   14:00 UTC.

## Rotating or revoking

- **Rotate** before expiry: create a new token, rerun step 3 with the same name (it overwrites),
  then delete the old token in MotherDuck.
- **If a token leaks:** revoke it in MotherDuck first (that's what actually stops access), then set
  a new one. Removing a token from git history does not un-leak it.

## Using MotherDuck from your laptop

Keep the token in the macOS Keychain rather than a file or your shell profile:

```bash
security add-generic-password -a "$USER" -s motherduck -w
```

`-w` with no value makes it prompt, so the token never lands in shell history. Then load it only for
the commands that need it:

```bash
MOTHERDUCK_TOKEN="$(security find-generic-password -a "$USER" -s motherduck -w)" DBT_TARGET=prod NBA_DUCKDB_PATH=md:nba make build
```
