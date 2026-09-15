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

  /// What the fake pre-flight check reports back. Tests set this before
  /// driving the screen.
  List<Map<String, dynamic>> conflicts = const [];
  bool aiAvailable = false;
  int checkCalls = 0;
  List<Map<String, String>>? checkedPrescriptions;

  @override
  Future<Map<String, dynamic>> checkDrugInteractions({
    required String idToken,
    required String patientId,
    required List<Map<String, String>> prescriptions,
  }) async {
    checkCalls++;
    checkedPrescriptions = prescriptions;
    return {
      'check_id': 'chk-1',
      'conflicts': conflicts,
      'ai_available': aiAvailable,
    };
  }

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
    String? checkId,
    String? overrideReason,
  }) async {
    created = {
      'patient_id': patientId,
      'doctor_id': doctorId,
      'diagnosis': diagnosis,
      'prescriptions': prescriptions,
      'check_id': checkId,
      'override_reason': overrideReason,
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
      'DOCTOR' => {'id': 'd1', 'name': 'Dr. Rao', 'clinic': {'name': 'Central Clinic'}, 'user': {'role': 'DOCTOR'},
          'permissions': ['patient:register', 'patient:lookup', 'appointment:manage', 'record:read', 'record:write',
              'interaction:check', 'report:upload', 'consent:request', 'consent:emergency']},
      'ADMIN' => {'name': 'System Administrator', 'role': 'ADMIN', 'user': {'role': 'ADMIN'},
          'permissions': ['staff:manage', 'clinic:update', 'clinic:create', 'audit:read']},
      _ => {'id': 'p9', 'name': 'Pat', 'health_id': 'MWH-X', 'user': {'role': 'PATIENT'},
          'permissions': ['self:profile', 'consent:respond']},
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


/// Walks the doctor from patient lookup into a filled-in visit form, ready to
/// save. Mirrors the first test's path so the interaction cases start from a
/// realistic screen rather than a hand-built widget.
Future<void> _openVisitForm(
  WidgetTester tester,
  _Records records, {
  String medicine = 'Ibuprofen 400mg',
}) async {
  await _pumpApp(tester, 'DOCTOR', '/doctor/patients', records: records);
  await tester.enterText(find.byType(TextField), 'Asha');
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Asha Kumari'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'New visit'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('Primary Diagnosis *'), 'Back pain');
  await tester.enterText(_field('Medicine Name *'), medicine);
  await tester.enterText(_field('Dosage *'), '400mg BD');
  await tester.enterText(_field('Duration *'), '5 days');
  await tester.pumpAndSettle();
}

/// The visit form scrolls, so the save button sits below the fold on an
/// 800px-tall test view and a bare tap() misses it.
Future<void> _tapSave(WidgetTester tester, String label, {bool settle = true}) async {
  final button = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // The button keeps spinning behind the success dialog, so the app never
    // settles; pump long enough for the save and the dialog instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _enterReason(WidgetTester tester, String reason) async {
  final field = find.widgetWithText(TextField, 'Reason for prescribing anyway *');
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, reason);
  await tester.pumpAndSettle();
}

const _criticalCrossClinic = {
  'new_drug': 'Ibuprofen 400mg',
  'existing_drug': 'Warfarin 5mg',
  'severity': 'CRITICAL',
  'clinic_name': 'Riverside Clinic',
  'prescribed_on': '2026-08-14T09:00:00Z',
  'explanation': 'Ibuprofen raises bleeding risk when combined with Warfarin.',
  'suggested_alternative': 'Acetaminophen',
  'source': 'TABLE',
  'confidence': 'CERTAIN',
  'scope': 'EXISTING',
};

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
      // A clean check still links the save, so the audit row records that the
      // drugs were checked and nothing was found.
      'check_id': 'chk-1',
      'override_reason': null,
    });
    // One press, not two: a clean result falls straight through to the save.
    expect(records.checkCalls, 1);
    expect(find.text('Visit Notes Saved'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Patient Lookup'), findsOneWidget);
    expect(find.text('Acute viral fever'), findsOneWidget); // history refreshed
  });

  testWidgets('conflict: banner blocks the save until a reason is given', (tester) async {
    final records = _Records()..conflicts = [Map.of(_criticalCrossClinic)];
    await _openVisitForm(tester, records);

    // First press runs the check and stops — nothing is saved yet.
    await _tapSave(tester, 'Complete & Save Visit Record');
    expect(records.checkCalls, 1);
    expect(records.created, isNull);

    // The banner names the other clinic and the date, which is the whole point.
    expect(find.text('1 drug interaction found'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('Ibuprofen 400mg + Warfarin 5mg'), findsOneWidget);
    expect(find.text('Already taking — Riverside Clinic · 14 Aug 2026'), findsOneWidget);
    expect(find.text('Consider instead: Acetaminophen'), findsOneWidget);

    // Pressing save again without a reason still refuses.
    await _tapSave(tester, 'Save Anyway');
    expect(records.created, isNull);
    expect(
      find.textContaining('Enter why this prescription should go ahead'),
      findsOneWidget,
    );

    await _enterReason(tester, 'INR monitored weekly; patient counselled.');
    await _tapSave(tester, 'Save Anyway', settle: false);

    expect(records.created?['check_id'], 'chk-1');
    expect(records.created?['override_reason'], 'INR monitored weekly; patient counselled.');
    expect(find.text('Visit Notes Saved'), findsOneWidget);
    // The check is not re-run just because the doctor pressed save again.
    expect(records.checkCalls, 1);
  });

  testWidgets('same-visit conflict never renders a null clinic', (tester) async {
    final records = _Records()
      ..conflicts = [
        {
          'new_drug': 'Warfarin 5mg',
          'existing_drug': 'Ibuprofen 400mg',
          'severity': 'CRITICAL',
          'clinic_name': null,
          'prescribed_on': null,
          'explanation': 'Combined use sharply increases bleeding risk.',
          'suggested_alternative': 'Acetaminophen',
          'source': 'TABLE',
          'confidence': 'CERTAIN',
          'scope': 'SAME_VISIT',
        },
      ];
    await _openVisitForm(tester, records, medicine: 'Warfarin 5mg');

    await _tapSave(tester, 'Complete & Save Visit Record');
    expect(find.text('Both drugs are in this prescription'), findsOneWidget);
    // The EXISTING wording would have printed an empty clinic here.
    expect(find.textContaining('Already taking'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('an ASSUMED duration is labelled as such', (tester) async {
    final records = _Records()
      ..conflicts = [
        {..._criticalCrossClinic, 'confidence': 'ASSUMED'},
      ];
    await _openVisitForm(tester, records);
    await _tapSave(tester, 'Complete & Save Visit Record');
    expect(find.text('Duration unclear — assumed still active'), findsOneWidget);
  });

  testWidgets('no conflicts: one press saves, and no all-clear is claimed', (tester) async {
    final records = _Records()..conflicts = const [];
    await _openVisitForm(tester, records);

    await _tapSave(tester, 'Complete & Save Visit Record', settle: false);

    expect(records.checkCalls, 1);
    expect(records.created?['check_id'], 'chk-1');
    expect(records.created?['override_reason'], isNull);
    expect(find.text('Visit Notes Saved'), findsOneWidget);
    // ai_available is false today, but with nothing found we make no claim at
    // all rather than showing a green light we cannot back up.
    expect(find.textContaining('AI check unavailable'), findsNothing);
  });

  testWidgets('the AI caveat rides along with the banner', (tester) async {
    final records = _Records()
      ..aiAvailable = false
      ..conflicts = [Map.of(_criticalCrossClinic)];
    await _openVisitForm(tester, records);
    await _tapSave(tester, 'Complete & Save Visit Record');
    expect(find.textContaining('AI check unavailable'), findsOneWidget);
  });

  testWidgets('editing a drug after a warning forces a re-check', (tester) async {
    final records = _Records()..conflicts = [Map.of(_criticalCrossClinic)];
    await _openVisitForm(tester, records);
    await _tapSave(tester, 'Complete & Save Visit Record');
    expect(find.text('1 drug interaction found'), findsOneWidget);

    // Swap the drug for a safe one: the stale verdict must go with it.
    records.conflicts = const [];
    await tester.enterText(_field('Medicine Name *'), 'Cetirizine 10mg');
    await tester.pumpAndSettle();
    expect(find.text('1 drug interaction found'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Complete & Save Visit Record'), findsOneWidget);

    await _tapSave(tester, 'Complete & Save Visit Record', settle: false);

    expect(records.checkCalls, 2); // re-checked, not saved against the old verdict
    expect(records.checkedPrescriptions?.first['medicine_name'], 'Cetirizine 10mg');
    expect(records.created?['override_reason'], isNull);
  });

  testWidgets('admin on PC: doctors in a grid, add-doctor opens as a dialog', (tester) async {
    await _pumpApp(tester, 'ADMIN', '/admin/doctors');
    expect(find.byType(NavigationRail), findsOneWidget);
    // Admin nav is filtered by permission: no queue, visits or patient history.
    expect(find.text('Clinics'), findsOneWidget);
    expect(find.text('Queue'), findsNothing);
    expect(find.text('New visit'), findsNothing);
    expect(find.text('Patients'), findsNothing);
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
