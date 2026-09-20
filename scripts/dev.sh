#!/usr/bin/env bash
# Starts the whole stack locally: Postgres (Docker) → backend :3000 → Flutter web :5000.
# Ctrl+C stops the backend and the web server; the DB container keeps running
# (stop it with: cd backend && docker compose down).
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f backend/.env ] || { echo "backend/.env missing — copy backend/.env.example and fill it in"; exit 1; }

echo "==> Postgres"
# a leftover non-compose container of the same name blocks the name; data lives in the volume
docker rm migrant-clinic-db >/dev/null 2>&1 || true
(cd backend && docker compose up -d --wait)

echo "==> migrations"
(cd backend && npx prisma migrate deploy)

echo "==> backend :3000"
(cd backend && npm run dev) &
trap 'kill 0' EXIT INT TERM

echo "==> flutter web :5000"
(cd mobile_app && flutter run -d web-server --web-port 5000 --web-hostname localhost \
  --dart-define=API_BASE_URL=http://localhost:3000/api)
