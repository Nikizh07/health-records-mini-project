# Dev Log (temporary): clinic side made accessible + PC/web layout

Session: 2026-09-11. Nothing is committed yet.

## Problem
- The doctor and admin screens existed but no one could reach them.
- Doctors added by an admin (`POST /api/doctors`) had no `users` row. On login, `/patients/me` returned 404, so the app sent them to patient registration.
- There was no desktop layout, but the clinic side is mostly used on a PC.

## Changes
### Backend
- `controllers/patient.controller.js` `getMyProfile`: on first sign-in, it links an unlinked Doctor by phone (exact match or last 10 digits) and creates the user as DOCTOR.

### App (Flutter, targeting web for PC)
- `presentation/screens/clinic/clinic_shell.dart` (new) is a `ShellRoute` wrapper around all signed-in routes:
  - it waits for session restore;
  - it sends signed-out users to `/login`;
  - it gates `/doctor/*` to DOCTOR/ADMIN and `/admin/*` to ADMIN (`canAccess`);
  - it shows a NavigationRail for staff at ≥800 px (extended at ≥1200 px). Patients and phones are unchanged.
- `routes/app_router.dart`: signed-in routes now sit under the ShellRoute. New route `/doctor/patients`.
- `doctor_screens.dart`:
  - new `DoctorPatientLookupScreen` (search on the left, cross-clinic history on the right, "New visit" button);
  - the queue uses a grid;
  - the visit form is capped at 880 px wide, has one-line prescription rows, and Ctrl+Enter saves;
  - "Done" after saving pops back, or goes to the queue if there is nothing to pop;
  - the selected-patient header no longer overflows;
  - the per-screen role guard was removed.
- `admin_screens.dart`: doctor and clinic lists use a grid, forms open as a dialog on PC (bottom sheet on phones), and the role guards were removed.
- `dashboard_screen.dart`:
  - uses `authState.role`;
  - width capped at 960 px;
  - no drawer for staff on wide screens;
  - "Patient Lookup" quick action.
- `providers/auth_provider.dart`: new `AuthState.role` getter.
- `widgets/responsive_card_list.dart` (new): a list on phones, a wrapping grid on wide screens.
- `data/services/local_cache_service.dart`: `init(inMemory: true)` for tests.
- `web/index.html`, `web/manifest.json`: real app name, zoom allowed, `orientation: any`.

### Tests
- `test/clinic_shell_test.dart`: the role gate.
- `test/clinic_flow_test.dart`: real router and screens with fake services. It covers:
  - the doctor flow (lookup → history → new visit → Ctrl+Enter save → history refresh);
  - the admin grid and dialog;
  - a patient being blocked from admin pages;
  - no side nav on a phone.
- The backend linking was checked with a scratch script against the local DB (6/6 passed, rows cleaned up).
- `flutter analyze` is clean and `flutter test` passes 6/6. The web build compiles.

## Local state
- Test DOCTOR account: guest `guest-tjEBbgzUuleqMiAFIuzj0i73rGX2` ("Dr. Test Doctor"). It is signed in only in the in-app browser.
- There is a guest patient "kkh" (created 14:17) that is not from this session.

## Run the doctor page
1. Start the backend: `cd backend && npm run dev`
2. Start the app: `cd mobile_app && flutter run -d chrome`
3. Continue as guest and register.
4. Promote the newest guest (fish shell; in bash use `$(...)`):
   `cd backend && node scripts/set-user-role.js (node -e 'require("dotenv").config();const p=require("./config/prisma");p.user.findFirst({where:{phone:{startsWith:"guest-"}},orderBy:{created_at:"desc"}}).then(u=>console.log(u.phone)).finally(()=>p.$disconnect())' | tail -1) DOCTOR "Dr. Test" "General Medicine"`
5. Refresh with F5 and keep the window at least 800 px wide.

## Known / not done
- Release builds require an `https://` `API_BASE_URL`. Use `flutter run` or `--profile` locally.
- Linux/Windows desktop builds can't do Firebase phone auth, so use the web build.
- The first ADMIN must be created with `set-user-role.js`.
- An existing patient added as a doctor is not auto-linked.
- Pre-existing issues:
  - Enter in patient search doesn't search;
  - the save button spins behind the success dialog;
  - an empty prescription row shows errors early;
  - long guest phone numbers overflow the search result card.
