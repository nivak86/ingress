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

**Caddyfile changes need a recreate.** The Caddyfile is a single-file bind mount, and `git pull`
replaces the file, so the running container keeps reading the old copy: `caddy reload` and a plain
`docker compose up -d` both leave the old routes in place. After pulling a Caddyfile change run
`docker compose up -d --force-recreate caddy` (a few seconds of downtime for every route), then
check `docker compose exec caddy grep <something new> /etc/caddy/Caddyfile`.

**CI:** pushing to `main` runs `.github/workflows/deploy.yml`, which joins the
tailnet, rsyncs the config to the box (never touching `.env`), validates, and
recreates the stack. The workflow is **gated on secrets** — it skips cleanly
until `TS_OAUTH_CLIENT_ID`, `HETZNER_HOST`, `HETZNER_USER`, `HETZNER_SSH_KEY`
are set on the repo.

## Static pages

**oceanfrontsurvey.com** (and www, redirected to the apex) is served by this stack too: a tunnel
public hostname points it at `caddy:80`, and the `http://oceanfrontsurvey.com` site maps every path
into the survey app's `/public/*` tree. No Access app covers that hostname, so the survey is open to
anyone. `kavinb.com/survey` and `/survey/` redirect there.

`/survey/` and `/survey-admin/` go to `survey_api:8000`, the Oceanfront resident survey app
(`nivak86/oceanfront-survey`, deployed at `/opt/survey`). Caddy rewrites `/survey/*` to the
app's `/public/*` tree and strips `Cf-Access-Authenticated-User-Email` there; `/survey-admin/*`
goes to `/admin/*`, which requires that header. `/survey` must keep its Cloudflare Access
bypass policy (it is public by design); `/survey-admin` stays behind Access.

The old static copy is gone; `survey/` only holds a pointer. Its read-only mount in
`compose.yml` is unused and can be dropped the next time the caddy container is recreated.

## Add / change a route

1. Edit `Caddyfile` (add a `handle_path /thing/* { reverse_proxy thing_api:8000 }`
   block; the backend must be on the `kavinb-public` network with that alias).
2. To expose a brand-new public hostname, also add it in the Cloudflare Zero Trust
   dashboard (Tunnel → public hostname) and put a Cloudflare Access policy over it.
3. Deploy (above). Verify: `curl -I https://kavinb.com/thing/` returns the Access
   `302` for an anonymous request (perimeter alive).
