// Drives the real clinic screens through the real router with fake services
// (no Firebase, no backend). Covers the PC/web layout and the doctor flow.
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/data/services/admin_service.dart';
import 'package:mobile_app/core/errors/api_exception.dart';
import 'package:mobile_app/data/services/appointment_service.dart';
import 'package:mobile_app/data/services/consent_service.dart';
import 'package:mobile_app/data/services/auth_service.dart';
import 'package:mobile_app/data/services/local_cache_service.dart';
import 'package:mobile_app/data/services/patient_service.dart';
import 'package:mobile_app/data/services/record_service.dart';
import 'package:mobile_app/data/services/secure_storage_service.dart';
import 'package:mobile_app/data/services/staff_service.dart';
import 'package:mobile_app/l10n/generated/app_localizations.dart';
import 'package:mobile_app/providers/admin_provider.dart';
import 'package:mobile_app/providers/appointment_provider.dart';
import 'package:mobile_app/providers/consent_provider.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/providers/records_provider.dart';
import 'package:mobile_app/routes/app_router.dart';

class _Credential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements AuthService {
  String? signedInEmail;
  @override
  User? get currentUser => null;
  @override
  Future<UserCredential> signInWithEmail(String email, String password) async {
    signedInEmail = email;
    return _Credential();
  }
  @override
  Future<UserCredential> signInWithGoogle() async => _Credential();
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'test-token';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Storage implements SecureStorageService {
  _Storage({this.token = 'test-token'});
  final String? token;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<String?> getPhoneNumber() async => null;
  @override
  Future<void> saveToken(String token) async {}
  @override
  Future<void> savePhoneNumber(String phoneNumber) async {}
  @override
  Future<void> savePatientIntent(bool asPatient) async {}
  @override
  Future<bool> getPatientIntent() async => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _patient = {'id': 'p1', 'name': 'Asha Kumari', 'health_id': 'MWH-AB1234', 'gender': 'Female'};

class _Patients extends PatientService {
  _Patients(this.profile) : super(dio: Dio());
  final Map<String, dynamic> profile;

  String? claimedDob;
  Map<String, String>? registered;

  @override
  Future<Map<String, dynamic>> registerAtDesk({
    required String idToken,
    required String name,
    required String dob,
    required String gender,
    required String languagePref,
    required String phone,
  }) async {
    registered = {'name': name, 'dob': dob, 'phone': phone};
    return {'id': 'p-new', 'name': name, 'health_id': 'MWH-NEW001', 'phone': '+91$phone', 'gender': gender, 'dob': '${dob}T00:00:00.000Z'};
  }

  @override
  Future<Map<String, dynamic>?> getMyProfile(String idToken) async => profile;

  @override
  Future<Map<String, dynamic>> claimPatient({required String idToken, required String dob}) async {
    claimedDob = dob;
    return {..._profile('PATIENT'), 'health_id': 'MWH-DESK01'};
  }

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
  int historyCalls = 0;
  bool consentRequired = false;

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
  }) async {
    historyCalls++;
    if (consentRequired) {
      throw ApiException('Ask for consent.', statusCode: 403, code: 'CONSENT_REQUIRED');
    }
    return List.of(records);
  }

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
  Future<List<Map<String, dynamic>>> getAllClinics({required String idToken}) async => [
        {'id': 'c1', 'name': 'Central', 'location': 'Sector 4', 'contact_number': '+913'},
      ];
}

class _Appointments extends AppointmentService {
  _Appointments() : super(dio: Dio());
  Map<String, String?>? walkIn;
  final confirmed = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getDoctors({required String idToken, required String clinicId}) async => [
        {'id': 'd1', 'name': 'Dr. Rao', 'specialization': 'GP'},
        {'id': 'd2', 'name': 'Iyer', 'specialization': 'Dermatology'},
      ];

  @override
  Future<List<Map<String, dynamic>>> getDoctorAppointments({
    required String idToken,
    String? doctorId,
    String? clinicId,
    String? date,
    String? status,
  }) async {
    return [
      {'id': 'a1', 'status': 'pending', 'slot_time': '2026-09-15T04:30:00Z', 'patient': _patient,
          'doctor': {'name': 'Dr. Rao'}, 'clinic': {'name': 'Central Clinic'}},
      {'id': 'a2', 'status': 'confirmed', 'slot_time': '2026-09-15T05:00:00Z', 'patient': _patient,
          'doctor': {'name': 'Iyer'}, 'clinic': {'name': 'Central Clinic'}},
    ];
  }

  @override
  Future<Map<String, dynamic>> createWalkIn({required String idToken, required String patientId, String? doctorId}) async {
    walkIn = {'patient_id': patientId, 'doctor_id': doctorId};
    return {'id': 'a3'};
  }

  @override
  Future<Map<String, dynamic>> confirmAppointment({required String idToken, required String appointmentId}) async {
    confirmed.add(appointmentId);
    return {'id': appointmentId, 'status': 'confirmed'};
  }
}

class _Consents extends ConsentService {
  _Consents({this.onGrant}) : super(dio: Dio());

  /// What the backend granting access does to the rest of the app.
  final VoidCallback? onGrant;
  final calls = <String>[];
  List<Map<String, dynamic>> pendingList = [];
  String status = 'PENDING';

  @override
  Future<Map<String, dynamic>> request({required String idToken, required String patientId}) async {
    calls.add('request $patientId');
    return {'id': 'c1', 'status': 'PENDING'};
  }

  @override
  Future<Map<String, dynamic>> get({required String idToken, required String consentId}) async {
    if (status == 'APPROVED') onGrant?.call();
    return {'id': consentId, 'status': status};
  }

  @override
  Future<Map<String, dynamic>> redeem({required String idToken, required String patientId, required String code}) async {
    calls.add('redeem $code');
    onGrant?.call();
    return {'id': 'c2', 'status': 'APPROVED'};
  }

  @override
  Future<Map<String, dynamic>> emergency({required String idToken, required String patientId, required String reason}) async {
    calls.add('emergency $reason');
    onGrant?.call();
    return {'id': 'c3', 'status': 'APPROVED'};
  }

  @override
  Future<List<Map<String, dynamic>>> pending({required String idToken}) async => pendingList;

  @override
  Future<void> respond({required String idToken, required String consentId, required bool approve}) async {
    calls.add('respond $consentId $approve');
    // As the backend does: an answered request is no longer pending.
    pendingList = [for (final c in pendingList) if (c['id'] != consentId) c];
  }

  @override
  Future<Map<String, dynamic>> createShareCode({required String idToken}) async {
    calls.add('share-code');
    return {'id': 's1', 'code': '424242'};
  }

  @override
  Future<Map<String, dynamic>> mine({required String idToken}) async => {
        'consents': [
          {'id': 'g1', 'status': 'APPROVED', 'method': 'APP', 'granted_until': '2099-01-01T00:00:00Z',
              'doctor': {'name': 'Rao'}, 'clinic': {'name': 'Central Clinic'}},
        ],
        'access_log': [
          {'id': 'l1', 'via': 'EMERGENCY', 'action': 'READ_HISTORY', 'created_at': '2026-09-15T09:00:00Z',
              'user': {'doctor': {'name': 'Dr. Far', 'clinic': {'name': 'Riverside'}}},
              'consent': {'reason': 'Unconscious on arrival, need allergy history'}},
        ],
      };

  @override
  Future<void> revoke({required String idToken, required String consentId}) async => calls.add('revoke $consentId');

  @override
  Future<List<Map<String, dynamic>>> accessAudit({required String idToken}) async => [
        {'id': 'l1', 'via': 'EMERGENCY', 'action': 'READ_HISTORY', 'created_at': '2026-09-15T09:00:00Z',
            'user': {'doctor': {'name': 'Dr. Far', 'clinic': {'name': 'Riverside'}}},
            'patient': {'name': 'Asha Kumari', 'health_id': 'MWH-AB1234'},
            'consent': {'reason': 'Unconscious on arrival, need allergy history'}},
      ];
}

class _Staff extends StaffService {
  _Staff() : super(dio: Dio());
  final actions = <String>[];

  @override
  Future<List<Map<String, dynamic>>> listStaff({required String idToken, String? status}) async => [
        {'id': 'u1', 'email': 'rao@clinic.in', 'role': 'DOCTOR', 'status': 'ACTIVE', 'clinic': {'name': 'Central'},
            'doctor': {'name': 'Dr. Rao', 'specialization': 'GP'}},
        {'id': 'u2', 'email': 'iyer@clinic.in', 'role': 'DOCTOR', 'status': 'PENDING', 'clinic': {'name': 'Central'},
            'doctor': {'name': 'Dr. Iyer', 'specialization': 'Dermatology', 'registration_number': 'TN-12345',
                'registration_council': 'TNMC'}},
        {'id': 'u3', 'phone': '+919000000003', 'role': 'RECEPTIONIST', 'status': 'ACTIVE', 'clinic': {'name': 'Central'}},
      ];

  @override
  Future<List<Map<String, dynamic>>> listInvites({required String idToken}) async => [
        {'id': 'i1', 'name': 'Meena', 'role': 'CLINIC_ADMIN', 'email': 'meena@clinic.in', 'state': 'OPEN',
            'expires_at': '2026-09-29T00:00:00Z', 'clinic': {'name': 'Central'}},
      ];

  @override
  Future<void> act({required String idToken, required String userId, required String action}) async =>
      actions.add('$action $userId');
}

Map<String, dynamic> _profile(String role) => switch (role) {
      'DOCTOR' => {'id': 'd1', 'name': 'Dr. Rao', 'clinic': {'name': 'Central Clinic'}, 'user': {'role': 'DOCTOR'},
          'permissions': ['patient:register', 'patient:lookup', 'appointment:manage', 'record:read', 'record:write',
              'interaction:check', 'report:upload', 'consent:request', 'consent:emergency']},
      'PENDING_DOCTOR' => {'name': 'Iyer', 'status': 'PENDING', 'permissions': <String>[],
          'clinic': {'name': 'Central Clinic'}, 'user': {'role': 'DOCTOR'}},
      'RECEPTIONIST' => {'name': 'Front Desk', 'role': 'RECEPTIONIST', 'status': 'ACTIVE', 'user': {'role': 'RECEPTIONIST'},
          'clinic': {'id': 'c1', 'name': 'Central Clinic'},
          'permissions': ['patient:register', 'patient:lookup', 'appointment:manage']},
      'UNVERIFIED' => {'next': 'VERIFY_EMAIL'},
      'STAFF_APPLY' => {'next': 'STAFF_APPLY'},
      'CLAIM' => {'next': 'CLAIM'},
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
  _Staff? staff,
  _Auth? auth,
  _Patients? patients,
  _Appointments? appointments,
  _Consents? consents,
  String? token = 'test-token',
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  appRouter.go(location);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth ?? _Auth()),
      secureStorageServiceProvider.overrideWithValue(_Storage(token: token)),
      patientServiceProvider.overrideWithValue(patients ?? _Patients(_profile(role))),
      recordServiceProvider.overrideWithValue(records ?? _Records()),
      adminServiceProvider.overrideWithValue(_Admin()),
      staffServiceProvider.overrideWithValue(staff ?? _Staff()),
      appointmentServiceProvider.overrideWithValue(appointments ?? _Appointments()),
      consentServiceProvider.overrideWithValue(consents ?? _Consents()),
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

  /// Doctor lands on a patient whose records the backend refuses until consent.
  Future<(_Records, _Consents)> openConsentGate(WidgetTester tester) async {
    final records = _Records()..consentRequired = true;
    final consents = _Consents(onGrant: () => records.consentRequired = false);
    await _pumpApp(tester, 'DOCTOR', '/doctor/patients', records: records, consents: consents);
    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Kumari'));
    await tester.pumpAndSettle();
    expect(find.text('Consent needed'), findsOneWidget);
    return (records, consents);
  }

  testWidgets('consent gate: the doctor asks, the patient allows, the history loads', (tester) async {
    final (records, consents) = await openConsentGate(tester);
    records.records.add({'id': 'r9', 'diagnosis': 'Old fracture', 'visit_date': '2026-01-02T10:00:00Z',
        'doctor': {'name': 'Rao'}, 'prescriptions': []});

    // The waiting card spins, so the app never settles: pump by hand.
    await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(consents.calls, ['request p1']);
    expect(find.textContaining('Waiting for Asha Kumari'), findsOneWidget);
    expect(find.text('Old fracture'), findsNothing);

    // The patient taps Allow on their phone; the 3 s poll picks it up.
    consents.status = 'APPROVED';
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Old fracture'), findsOneWidget);
    expect(find.text('Consent needed'), findsNothing);
  });

  testWidgets('consent gate: a share code unlocks the history', (tester) async {
    final (_, consents) = await openConsentGate(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Enter share code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '424242');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(consents.calls, ['redeem 424242']);
    expect(find.text('Consent needed'), findsNothing);
    expect(find.text('No visits recorded for this patient yet.'), findsOneWidget);
  });

  testWidgets('consent gate: emergency access needs a real reason', (tester) async {
    final (_, consents) = await openConsentGate(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Emergency access'));
    await tester.pumpAndSettle();
    final open = find.widgetWithText(FilledButton, 'Open records');
    expect(tester.widget<FilledButton>(open).onPressed, isNull); // empty reason
    await tester.enterText(find.byType(TextField).last, 'too short');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(open).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Unconscious on arrival, need allergy history');
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(consents.calls, ['emergency Unconscious on arrival, need allergy history']);
    expect(find.text('Consent needed'), findsNothing);
  });

  testWidgets('patient: the popup asks before a doctor sees the history', (tester) async {
    final consents = _Consents()
      ..pendingList = [
        {'id': 'c9', 'doctor': {'name': 'Far'}, 'clinic': {'name': 'Riverside Clinic'}},
      ];
    await _pumpApp(tester, 'PATIENT', '/', consents: consents, size: const Size(400, 800));

    expect(find.text('Share your medical history?'), findsOneWidget);
    expect(find.textContaining('Dr. Far, Riverside Clinic'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pumpAndSettle();
    expect(consents.calls, ['respond c9 true']);
  });

  testWidgets('patient: answering the popup closes it for good', (tester) async {
    final consents = _Consents()
      ..pendingList = [
        {'id': 'c9', 'doctor': {'name': 'Far'}, 'clinic': {'name': 'Riverside Clinic'}},
      ];
    await _pumpApp(tester, 'PATIENT', '/', consents: consents, size: const Size(400, 800));

    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pumpAndSettle();

    // The refresh that follows the answer must not ask again with the stale list.
    expect(consents.calls, ['respond c9 true']);
    expect(find.text('Share your medical history?'), findsNothing);
  });

  testWidgets('patient: the privacy screen revokes a grant and shows emergency access', (tester) async {
    final consents = _Consents();
    await _pumpApp(tester, 'PATIENT', '/privacy', consents: consents, size: const Size(400, 800));

    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('EMERGENCY'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(consents.calls, ['revoke g1']);

    await tester.tap(find.text('Create share code'));
    await tester.pumpAndSettle();
    expect(find.text('424242'), findsOneWidget);
  });

  testWidgets('admin: the access log names the patient and the emergency reason', (tester) async {
    await _pumpApp(tester, 'ADMIN', '/admin/audit');
    expect(find.text('Access log'), findsWidgets);
    expect(find.textContaining('Dr. Far → Asha Kumari'), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Unconscious on arrival, need allergy history'), findsOneWidget);
  });

  testWidgets('admin on PC: staff screen approves an application, invite opens as a dialog', (tester) async {
    final staff = _Staff();
    await _pumpApp(tester, 'ADMIN', '/admin/staff', staff: staff);
    expect(find.byType(NavigationRail), findsOneWidget);
    // Admin nav is filtered by permission: no queue, visits or patient history.
    expect(find.text('Clinics'), findsOneWidget);
    expect(find.text('Queue'), findsNothing);
    expect(find.text('New visit'), findsNothing);
    expect(find.text('Patients'), findsNothing);

    // Applications tab first: only the pending doctor, with the registration number to check.
    expect(find.text('Applications (1)'), findsOneWidget);
    expect(find.text('Dr. Iyer'), findsOneWidget);
    expect(find.text('Dr. Rao'), findsNothing);
    expect(find.text('Reg. no. TN-12345 (TNMC)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(staff.actions, ['approve u2']);

    await tester.tap(find.text('Staff').last);
    await tester.pumpAndSettle();
    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('+919000000003'), findsOneWidget); // receptionist named by phone
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disable').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disable')); // confirm
    await tester.pumpAndSettle();
    expect(staff.actions, ['approve u2', 'disable u1']);

    await tester.tap(find.text('Invites'));
    await tester.pumpAndSettle();
    expect(find.text('Meena'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);

    // The action snackbars sit over the button on the shell's full-width Scaffold.
    ScaffoldMessenger.of(tester.element(find.byType(TabBar))).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Invite'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Invite Staff'), findsOneWidget);
    expect(find.text('Clinic *'), findsOneWidget); // platform admin picks the clinic
  });

  testWidgets('receptionist on PC: registers a walk-in, books a doctor, confirms in the clinic queue', (tester) async {
    final patients = _Patients(_profile('RECEPTIONIST'));
    final records = _Records();
    final appointments = _Appointments();
    await _pumpApp(tester, 'RECEPTIONIST', '/doctor/patients',
        patients: patients, records: records, appointments: appointments);
    // Front desk nav: queue and patients, never visits or admin.
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('New visit'), findsNothing);
    expect(find.text('Staff'), findsNothing);

    await tester.tap(find.text('Register patient'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Full name *'), 'Ravi Das');
    await tester.enterText(_field('Mobile number *'), '9876543210');
    await tester.enterText(_field('Date of birth * (YYYY-MM-DD)'), '1990-02-03');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();
    expect(patients.registered, {'name': 'Ravi Das', 'dob': '1990-02-03', 'phone': '9876543210'});

    // The new patient is selected: demographics only, and no records call at all.
    expect(find.text('MWH-NEW001'), findsWidgets); // search chip + panel
    expect(find.text('Medical history is only visible to doctors.'), findsOneWidget);
    expect(records.historyCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Walk-in'));
    await tester.pumpAndSettle();
    expect(find.text('Book with which doctor?'), findsOneWidget);
    await tester.tap(find.text('Dr. Iyer'));
    await tester.pumpAndSettle();
    expect(appointments.walkIn, {'patient_id': 'p-new', 'doctor_id': 'd2'});

    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.text('Clinic Queue'), findsOneWidget);
    // Every doctor at the clinic, each card naming theirs; no consult buttons.
    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('Dr. Iyer'), findsOneWidget);
    expect(find.textContaining('Start Consultation'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm')); // only the pending one has it
    await tester.pumpAndSettle();
    expect(appointments.confirmed, ['a1']);
    expect(records.historyCalls, 0);
  });

  testWidgets('staff tab: email sign-in with a pending application lands on the pending screen', (tester) async {
    final auth = _Auth();
    await _pumpApp(tester, 'PENDING_DOCTOR', '/login', auth: auth, token: null);
    expect(find.text('Sign in with your mobile number'), findsOneWidget); // patient tab by default off web

    await tester.tap(find.text('Clinic staff'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'iyer@clinic.in');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(auth.signedInEmail, 'iyer@clinic.in');
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.textContaining('Central Clinic'), findsOneWidget);
  });

  testWidgets('patient tab: Google sign-in without a phone is asked to link one', (tester) async {
    // The backend says STAFF_APPLY for any verified email with no profile; the
    // patient side overrides that with the phone step.
    await _pumpApp(tester, 'STAFF_APPLY', '/login', token: null);
    expect(find.text('Use email and password'), findsOneWidget); // patient side only
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Add your mobile number'), findsOneWidget);
    expect(find.text('Clinic staff'), findsNothing);
    expect(find.text('Waiting for approval'), findsNothing);
  });

  testWidgets('a clinic-registered phone claims its profile by date of birth', (tester) async {
    final patients = _Patients(_profile('CLAIM'));
    await _pumpApp(tester, 'CLAIM', '/', patients: patients, size: const Size(400, 800));
    expect(find.text('Your clinic profile'), findsOneWidget);

    await tester.tap(find.text('Link my profile'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the date as YYYY-MM-DD'), findsOneWidget);
    expect(patients.claimedDob, isNull);

    await tester.enterText(find.byType(TextFormField), '1988-04-12');
    await tester.tap(find.text('Link my profile'));
    await tester.pumpAndSettle();
    expect(patients.claimedDob, '1988-04-12');
    expect(find.text('Your clinic profile'), findsNothing);
    expect(find.textContaining('MWH-DESK01'), findsWidgets); // on the dashboard
  });

  testWidgets('an unverified email is sent from any page to verification', (tester) async {
    await _pumpApp(tester, 'UNVERIFIED', '/admin/staff');
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text("I've verified"), findsOneWidget);
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
