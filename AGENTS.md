# AGENTS.md — ingress

Instructions for any AI agent (Claude, Codex, …) working on this repo. Read this
before changing anything. (`CLAUDE.md` just points here.) This is the **front door**
for kavinb.com — be careful; a bad change here can take all three apps offline.

## Source of truth & how to make changes durably

GitHub `main` (`nivak86/ingress`) is the **source of truth**.

**Deploy model: PULL.** The box (`/opt/ingress` on the kavinb box) is a real **git
checkout**. It is deployed **manually** (the CI workflow is intentionally gated off — the
front door changes rarely and is safer deployed by hand):

```
ssh kavinb
cd /opt/ingress
git pull
docker compose config -q     # validate before applying
docker compose up -d
docker compose logs -f cloudflared
```

GitHub is still the source of truth, so make changes in git first:
1. Edit → `git commit` → `git push origin main`.
2. Then `git pull` on the box and bring the stack up (above).

Never leave the box checkout with uncommitted edits — commit + push them so they aren't
lost and so the box can `git pull` cleanly.

## Important paths

- Box path: `/opt/ingress` (kavinb box; admin only over Tailscale, `ssh kavinb`).
- `.env` on the box holds `TUNNEL_TOKEN` (cloudflared connector token) — **box-only, gitignored, never commit it.**
- Caddy reuses external volumes `money_caddy_data` / `money_caddy_config`.

## Project shape

`cloudflared` (zero-inbound Cloudflare Tunnel) + `caddy` (HTTP-only path router for
`/money` `/workout` `/health`). No host ports are published — cloudflared dials out and
reaches caddy over the `kavinb-public` docker network.

See `README.md` for the full architecture, how to add a route, and the deploy details.
