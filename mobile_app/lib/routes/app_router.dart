import 'package:go_router/go_router.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/otp_verification_screen.dart';
import '../presentation/screens/auth/patient_registration_screen.dart';
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
    // Doctor Routes
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
    // Admin Routes
    GoRoute(
      path: '/admin/doctors',
      name: 'admin-doctors',
      builder: (context, state) => const AdminManageDoctorsScreen(),
    ),
    GoRoute(
      path: '/admin/clinics',
      name: 'admin-clinics',
      builder: (context, state) => const AdminManageClinicsScreen(),
    ),
  ],
);
