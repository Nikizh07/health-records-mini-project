// Drives the real clinic screens through the real router with fake services
// (no Firebase, no backend). Covers the PC/web layout and the doctor flow.
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/data/services/admin_service.dart';
import 'package:mobile_app/data/services/auth_service.dart';
import 'package:mobile_app/data/services/local_cache_service.dart';
import 'package:mobile_app/data/services/patient_service.dart';
import 'package:mobile_app/data/services/record_service.dart';
import 'package:mobile_app/data/services/secure_storage_service.dart';
import 'package:mobile_app/l10n/generated/app_localizations.dart';
import 'package:mobile_app/providers/admin_provider.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/providers/records_provider.dart';
import 'package:mobile_app/routes/app_router.dart';

class _Auth implements AuthService {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Storage implements SecureStorageService {
  @override
  Future<String?> getToken() async => 'test-token';
  @override
  Future<String?> getPhoneNumber() async => null;
  @override
  Future<void> saveToken(String token) async {}
  @override
  Future<void> savePhoneNumber(String phoneNumber) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _patient = {'id': 'p1', 'name': 'Asha Kumari', 'health_id': 'MWH-AB1234', 'gender': 'Female'};

class _Patients extends PatientService {
  _Patients(this.profile) : super(dio: Dio());
  final Map<String, dynamic> profile;

  @override
  Future<Map<String, dynamic>?> getMyProfile(String idToken) async => profile;

  @override
  Future<List<Map<String, dynamic>>> searchPatients({
    required String idToken,
    required String query,
  }) async =>
      [Map.of(_patient)];
}

class _Records extends RecordService {
  _Records() : super(dio: Dio());
  final records = <Map<String, dynamic>>[];
  Map<String, dynamic>? created;

  @override
  Future<List<Map<String, dynamic>>> getPatientRecords({
    required String idToken,
    required String patientId,
  }) async =>
      List.of(records);

  @override
  Future<Map<String, dynamic>> createMedicalRecord({
    required String idToken,
    required String patientId,
    String? doctorId,
    String? appointmentId,
    String? visitDate,
    required String diagnosis,
    String? notes,
    List<Map<String, String>>? prescriptions,
  }) async {
    created = {
      'patient_id': patientId,
      'doctor_id': doctorId,
      'diagnosis': diagnosis,
      'prescriptions': prescriptions,
    };
    final record = {
      'id': 'r1',
      'diagnosis': diagnosis,
      'visit_date': '2026-09-11T10:00:00Z',
      'doctor': {'name': 'Rao'},
      'prescriptions': prescriptions ?? [],
    };
    records.add(record);
    return record;
  }
}

class _Admin extends AdminService {
  _Admin() : super(dio: Dio());

  @override
  Future<List<Map<String, dynamic>>> getAllDoctors({required String idToken, String? clinicId}) async => [
        {'id': 'd1', 'name': 'Rao', 'specialization': 'GP', 'phone': '+911', 'clinic': {'name': 'Central'}},
        {'id': 'd2', 'name': 'Iyer', 'specialization': 'Dermatology', 'phone': '+912', 'clinic': {'name': 'North'}},
      ];

  @override
  Future<List<Map<String, dynamic>>> getAllClinics({required String idToken}) async => [
        {'id': 'c1', 'name': 'Central', 'location': 'Sector 4', 'contact_number': '+913'},
      ];
}

Map<String, dynamic> _profile(String role) => switch (role) {
      'DOCTOR' => {'id': 'd1', 'name': 'Dr. Rao', 'clinic': {'name': 'Central Clinic'}, 'user': {'role': 'DOCTOR'}},
      'ADMIN' => {'name': 'System Administrator', 'role': 'ADMIN', 'user': {'role': 'ADMIN'}},
      _ => {'id': 'p9', 'name': 'Pat', 'health_id': 'MWH-X', 'user': {'role': 'PATIENT'}},
    };

Future<void> _pumpApp(
  WidgetTester tester,
  String role,
  String location, {
  _Records? records,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  appRouter.go(location);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(_Auth()),
      secureStorageServiceProvider.overrideWithValue(_Storage()),
      patientServiceProvider.overrideWithValue(_Patients(_profile(role))),
      recordServiceProvider.overrideWithValue(records ?? _Records()),
      adminServiceProvider.overrideWithValue(_Admin()),
    ],
    child: MaterialApp.router(
      routerConfig: appRouter,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  setUpAll(() => LocalCacheService.init(inMemory: true));

  testWidgets('doctor on PC: lookup → history → new visit saved with Ctrl+Enter', (tester) async {
    final records = _Records();
    await _pumpApp(tester, 'DOCTOR', '/doctor/patients', records: records);
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Kumari'));
    await tester.pumpAndSettle();
    expect(find.text('No visits recorded for this patient yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'New visit'));
    await tester.pumpAndSettle();
    expect(find.text('Health ID: MWH-AB1234'), findsOneWidget);
    expect(find.text('Clinic: Central Clinic'), findsOneWidget);

    await tester.enterText(_field('Primary Diagnosis *'), 'Acute viral fever');
    await tester.enterText(_field('Medicine Name *'), 'Paracetamol');
    await tester.enterText(_field('Dosage *'), '500mg TDS');
    await tester.enterText(_field('Duration *'), '5 days');
    // Wide screen: medicine, dosage and duration on one line.
    expect(tester.getTopLeft(_field('Duration *')).dy, tester.getTopLeft(_field('Medicine Name *')).dy);
    expect(find.text('Tip: Ctrl + Enter saves the visit'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // The save button keeps spinning behind the success dialog, so the app
    // never settles; pump long enough for the save and the dialog to appear.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(records.created, {
      'patient_id': 'p1',
      'doctor_id': 'd1',
      'diagnosis': 'Acute viral fever',
      'prescriptions': [
        {'medicine_name': 'Paracetamol', 'dosage': '500mg TDS', 'duration': '5 days'},
      ],
    });
    expect(find.text('Visit Notes Saved'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Patient Lookup'), findsOneWidget);
    expect(find.text('Acute viral fever'), findsOneWidget); // history refreshed
  });

  testWidgets('admin on PC: doctors in a grid, add-doctor opens as a dialog', (tester) async {
    await _pumpApp(tester, 'ADMIN', '/admin/doctors');
    expect(find.byType(NavigationRail), findsOneWidget);
    final a = tester.getTopLeft(find.text('Dr. Rao'));
    final b = tester.getTopLeft(find.text('Dr. Iyer'));
    expect(a.dy, b.dy); // side by side
    expect(a.dx, lessThan(b.dx));

    await tester.tap(find.text('Add Doctor'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Onboard New Doctor'), findsOneWidget);
  });

  testWidgets('patient is blocked from admin pages', (tester) async {
    await _pumpApp(tester, 'PATIENT', '/admin/clinics');
    expect(find.text('Access restricted'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('doctor on a phone gets the page without side nav', (tester) async {
    await _pumpApp(tester, 'DOCTOR', '/doctor/patients', size: const Size(400, 800));
    expect(find.text('Patient Lookup'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
