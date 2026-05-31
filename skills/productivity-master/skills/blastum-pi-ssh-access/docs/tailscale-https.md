# Tailscale HTTPS for services on the Pi

For apps bound to **localhost** (e.g. Docker `127.0.0.1:8780:80`), use **Tailscale Serve** so clients get **`https://<node>.ts.net/...`** with a real cert — no port in the URL (HTTPS is on **443**; the local port is only for the proxy target).

```bash
tailscale serve --bg http://127.0.0.1:8780
tailscale serve status
```

Set the app’s public base URL to `https://<node>.ts.net` (no `:8780`). See project `docker/README.md` for TIPSy3 compose defaults.

**Alternative:** bind the service on the Tailscale IP and use `http://100.x.x.x:port` — no TLS unless you add it separately.

---

## Same hostname, multiple backends (paths)

You are **not** back to per-port TLS on the Pi. Tailscale still terminates HTTPS once on **`https://<node>.ts.net`** (443). To expose **several** local HTTP servers on that **same** name, add **path mounts** with `--set-path` — each prefix routes to a different `localhost` port.

Example:

```bash
tailscale serve --bg --set-path /tipsy http://127.0.0.1:8780
tailscale serve --bg --set-path /other http://127.0.0.1:3000
```

Clients would use e.g. `https://<node>.ts.net/tipsy/calendar.ics` and `https://<node>.ts.net/other/...`. Use `tailscale serve status` to see active mounts.

### Caveat: path prefix vs app expectations

The process listening on localhost usually serves from **`/`**. If you mount it at **`/tipsy`** on Serve, the backend may still expect requests at `/` or may receive a `/tipsy` prefix — behavior depends on how Serve forwards paths. Align each app’s configured public base URL (or nginx rewrite rules) with the URL clients actually use.

**Practical split:**

- **One main app at `/`** — e.g. `tailscale serve --bg http://127.0.0.1:8780` with **no** `--set-path`.
- **Additional apps** — add **`--set-path /foo`** only for those, or use another node / hostname if path rules get awkward.

---

## Reference

- [Tailscale Serve command](https://tailscale.com/kb/1242/tailscale-serve/)
- [Serve examples](https://tailscale.com/kb/1313/serve-examples)
