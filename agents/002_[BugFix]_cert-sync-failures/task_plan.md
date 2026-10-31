# Certificate sync failure handling

## Scope
Use the existing hourly worker. Add the product User-Agent, check HTTP transport status and every expected Vault operation, and stop before symlink/reload handling when any configured batch fails. Do not change Vault authorization, schedules, configuration, or certificate key names.

## Plan
- [x] Inspect repository guidance, existing worker flow, cron integration, and failure evidence.
- [x] Record behavior and acceptance checks in findings/progress.
- [x] Update `cert/worker.sh` with a declared User-Agent and strict per-batch response validation.
- [x] Add a root `/test` regression test for successful, HTTP-denied, and malformed/incomplete batch responses.
- [x] Run Bash syntax and relevant repository checks; review diff and commit task branch.
