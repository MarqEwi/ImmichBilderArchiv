# ImmichBilderArchiv

Einrichtung von [Immich](https://immich.app) auf dem UGREEN NASync DH2300 (`STEVENAS`).

- `prompts/immich-setup-claude-code.md` – Prompt für Claude Code (PowerShell auf dem
  Master-PC, SSH zum NAS). Enthält Auftrag, Arbeitsregeln, Ermittlungs- und
  Einrichtungsphasen.
- Die eigentlichen Konfigurationsdateien (`immich/docker-compose.yml`, `.env.example`,
  `scripts/`, `docs/RUNBOOK.md`) entstehen beim Abarbeiten des Prompts in diesem Repo.
- `immich/.env` mit dem Datenbank-Passwort wird nie committet.
