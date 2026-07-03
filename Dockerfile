# Caddy 2.10 with the Cloudflare DNS plugin, so it can obtain a real Let's
# Encrypt certificate for kavinb.com via a DNS-01 challenge. The box isn't
# publicly reachable, so the usual HTTP-01 challenge can't work — DNS-01 proves
# domain ownership through the Cloudflare API instead. Used only by the tailnet
# HTTPS door; the public path (via the Cloudflare tunnel) stays HTTP-internal.
FROM caddy:2.10-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2.10
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
