# ingress — kavinb.com front door

The public entry point for **kavinb.com**. Two containers, one job: terminate the
Cloudflare Tunnel and route paths to the app backends. The box itself is
**zero-inbound** (no public 22/80/443) — this stack never publishes a host port;
`cloudflared` dials *out* to Cloudflare.

```
Internet ──HTTPS──▶ Cloudflare edge ──▶ Cloudflare Access (Google / email OTP)
                                          │  (only authenticated requests pass)
                                          ▼
                              Cloudflare Tunnel (outbound from the box)
                                          ▼
                          cloudflared ──▶ caddy:80 (HTTP-only, internal)
                                          ▼
        /money  ─▶ money_api:8000   /workout ─▶ workout_api:8000   /health ─▶ health_api:8000
```

All three apps trust the `Cf-Access-Authenticated-User-Email` header that Access
injects, so Cloudflare login is the single sign-on — no second password.

## Layout

| File | Purpose |
|------|---------|
| `compose.yml` | `cloudflared` (tunnel) + `caddy` (router). No host ports. Joins the external `kavinb-public` docker network. |
| `Caddyfile`   | HTTP-only path routing for `/money`, `/workout`, `/health`. Cloudflare terminates TLS at the edge. |
| `.env`        | **Box-only, never committed.** Holds `TUNNEL_TOKEN` (the cloudflared connector token). See `.env.example`. |

Caddy mounts the **external** volumes `money_caddy_data` / `money_caddy_config`
(historical names, kept so nothing has to be re-created).

## Deploy

Lives at `/opt/ingress` on the kavinb box. The box is reachable for admin only
over Tailscale (`ssh kavinb`).

**Manual (preferred for this stack — the front door changes rarely):**

```bash
ssh kavinb
cd /opt/ingress
git pull                        # this repo is checked out here
docker compose config -q        # validate before applying
docker compose up -d            # recreate changed containers
docker compose logs -f cloudflared   # watch the tunnel reconnect
```

**CI:** pushing to `main` runs `.github/workflows/deploy.yml`, which joins the
tailnet, rsyncs the config to the box (never touching `.env`), validates, and
recreates the stack. The workflow is **gated on secrets** — it skips cleanly
until `TS_OAUTH_CLIENT_ID`, `HETZNER_HOST`, `HETZNER_USER`, `HETZNER_SSH_KEY`
are set on the repo.

## Add / change a route

1. Edit `Caddyfile` (add a `handle_path /thing/* { reverse_proxy thing_api:8000 }`
   block; the backend must be on the `kavinb-public` network with that alias).
2. To expose a brand-new public hostname, also add it in the Cloudflare Zero Trust
   dashboard (Tunnel → public hostname) and put a Cloudflare Access policy over it.
3. Deploy (above). Verify: `curl -I https://kavinb.com/thing/` returns the Access
   `302` for an anonymous request (perimeter alive).
