# CLAUDE.md

## Read these first
- **`SNAPSHOT.md`**: use it for all folder and file references. Check it to find where things live before searching the repo.
- **`MEMORY.md`**: use it for project context: what the project is, decisions made, current status, gotchas and user preferences.

## Keep them current
- Added, moved or deleted files or folders → update the tree in `SNAPSHOT.md`.
- A decision was made, status changed, or you found a gotcha → add a dated note to `MEMORY.md`.

## Working rules
- When asked for a plan, write it to a `.md` file in the repo and stop. Implement only when explicitly asked.
- Never commit, print or publish secrets: `backend/.env`, `backend/config/firebase-adminsdk.json`.
- Firebase (Auth + Admin) stays as is. The AWS migration covers only the DB, storage and backend hosting (see `AWS_MIGRATION_PLAN.md`).

## Commands
- Backend dev: `cd backend && npm run dev`
- Backend start: `cd backend && npm start`
- Prisma migrations: `cd backend && npx prisma migrate deploy`
- Mobile run: `cd mobile_app && flutter run --dart-define=API_BASE_URL=http://<host>:3000/api`
