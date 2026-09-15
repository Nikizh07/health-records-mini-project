import 'package:go_router/go_router.dart';
import '../presentation/screens/auth/claim_profile_screen.dart';
import '../presentation/screens/auth/email_verification_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/otp_verification_screen.dart';
import '../presentation/screens/auth/patient_registration_screen.dart';
import '../presentation/screens/auth/staff_application_screen.dart';
import '../presentation/screens/clinic/clinic_shell.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/records/records_screen.dart';
import '../presentation/screens/records/record_detail_screen.dart';
import '../presentation/screens/appointments/appointments_screen.dart';
import '../presentation/screens/appointments/book_appointment_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/doctor/doctor_screens.dart';
import '../presentation/screens/admin/admin_screens.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/verify-otp',
      name: 'verify-otp',
      builder: (context, state) => const OtpVerificationScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const PatientRegistrationScreen(),
    ),
    // Sign-in steps before a profile exists (outside the shell).
    GoRoute(
      path: '/link-phone',
      name: 'link-phone',
      builder: (context, state) => const LoginScreen(linkPhone: true),
    ),
    GoRoute(
      path: '/claim',
      name: 'claim',
      builder: (context, state) => const ClaimProfileScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      name: 'verify-email',
      builder: (context, state) => const EmailVerificationScreen(),
    ),
    GoRoute(
      path: '/staff-apply',
      name: 'staff-apply',
      builder: (context, state) => const StaffApplicationScreen(),
    ),
    // Every signed-in page. ClinicShell handles the auth wait, role gating
    // and the staff side navigation on wide screens.
    ShellRoute(
      builder: (context, state, child) =>
          ClinicShell(path: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/records',
          name: 'records',
          builder: (context, state) => const RecordsScreen(),
        ),
        GoRoute(
          path: '/records/:id',
          name: 'record-detail',
          builder: (context, state) {
            final recordId = state.pathParameters['id'] ?? '';
            final recordData = state.extra as Map<String, dynamic>?;
            return RecordDetailScreen(
              recordId: recordId,
              initialRecordData: recordData,
            );
          },
        ),
        GoRoute(
          path: '/appointments',
          name: 'appointments',
          builder: (context, state) => const AppointmentsScreen(),
        ),
        GoRoute(
          path: '/book-appointment',
          name: 'book-appointment',
          builder: (context, state) => const BookAppointmentScreen(),
        ),
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        // Clinic routes: gated by permission in ClinicShell
        GoRoute(
          path: '/doctor/today-appointments',
          name: 'doctor-today-appointments',
          builder: (context, state) => const DoctorTodayAppointmentsScreen(),
        ),
        GoRoute(
          path: '/doctor/add-record',
          name: 'doctor-add-record',
          builder: (context, state) {
            final appointmentData = state.extra as Map<String, dynamic>?;
            return DoctorAddRecordScreen(initialAppointmentData: appointmentData);
          },
        ),
        GoRoute(
          path: '/doctor/patients',
          name: 'doctor-patients',
          builder: (context, state) => const DoctorPatientLookupScreen(),
        ),
        GoRoute(
          path: '/admin/staff',
          name: 'admin-staff',
          builder: (context, state) => const AdminStaffScreen(),
        ),
        GoRoute(
          path: '/admin/clinics',
          name: 'admin-clinics',
          builder: (context, state) => const AdminManageClinicsScreen(),
        ),
      ],
    ),
  ],
);
