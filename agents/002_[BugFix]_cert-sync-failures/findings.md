# Findings

- Tokyo's existing hourly root cron entry invokes `/srv/server-toolkit/storage/cert/worker.sh`; no new schedule is needed.
- The deployed worker template reads `/etc/environment`; the newer helper prefers `/etc/server-toolkit/device.env`. Current URL and token values match, so the failure was not caused by source precedence.
- Vault reads without an explicit product User-Agent were blocked at Cloudflare with HTTP 403. The authorized `server-toolkit` User-Agent reaches the Vault API, where individual certificate reads can still be denied. Transport success therefore cannot stand in for per-operation authorization or certificate-content validation.
- The existing worker used curl's nonempty response as success, didn't inspect HTTP status or per-operation status/content, and always logged completion. It could report success on an HTML/edge denial and proceed to reload without refreshed certificates.
- Keep permission grants and production state out of this change. A rejected per-operation read must fail the run and prevent reload; do not expose response bodies, tokens, or endpoint URLs in logs.
