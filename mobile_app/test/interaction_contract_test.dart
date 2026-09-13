// Verifies the Flutter client and the Node API agree on the interaction
// contract — the field names RecordService reads must be the ones the backend
// actually sends. Everything else in the suite uses a fake service, so this is
// the only place that mismatch would surface.
//
// It needs a backend on TEST_API_BASE_URL (default http://127.0.0.1:3996/api)
// with a doctor token in TEST_ID_TOKEN, and SKIPS ITSELF when that is not
// running, so `flutter test` stays green in CI and on a normal machine.
//
//   dart define: --dart-define=TEST_API_BASE_URL=... --dart-define=TEST_ID_TOKEN=...
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/data/services/record_service.dart';

const _baseUrl = String.fromEnvironment(
  'TEST_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:3996/api',
);
const _idToken = String.fromEnvironment('TEST_ID_TOKEN');
const _patientId = String.fromEnvironment('TEST_PATIENT_ID');

void main() {
  // flutter_test installs an HttpOverrides that fails every real request.
  setUpAll(() => HttpOverrides.global = null);

  test('checkDrugInteractions parses what the API actually returns', () async {
    if (_idToken.isEmpty || _patientId.isEmpty) {
      markTestSkipped('No live backend configured; set TEST_ID_TOKEN / TEST_PATIENT_ID.');
      return;
    }

    final service = RecordService(dio: Dio(BaseOptions(baseUrl: _baseUrl)));
    final result = await service.checkDrugInteractions(
      idToken: _idToken,
      patientId: _patientId,
      prescriptions: [
        {'medicine_name': 'Ibuprofen 400mg', 'dosage': '400mg BD', 'duration': '5 days'},
      ],
    );

    // The three keys the screen reads off the envelope.
    expect(result['check_id'], isA<String>());
    expect(result['ai_available'], isA<bool>());
    expect(result['conflicts'], isA<List>());

    final conflicts = (result['conflicts'] as List)
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    expect(conflicts, isNotEmpty, reason: 'seeded patient should be on warfarin');

    // Every key _InteractionBanner and _ConflictTile read.
    final c = conflicts.first;
    expect(c['new_drug'], isA<String>());
    expect(c['existing_drug'], isA<String>());
    expect(c['severity'], 'CRITICAL');
    expect(c['explanation'], isA<String>());
    expect(c['suggested_alternative'], isA<String>());
    expect(c['confidence'], isA<String>());
    expect(c['scope'], 'EXISTING');
    expect(c['clinic_name'], isA<String>());
    // The banner does DateTime.tryParse on this, so it must be parseable.
    expect(DateTime.tryParse(c['prescribed_on'].toString()), isNotNull);
  });

  test('a conflicted save is refused without a reason, accepted with one', () async {
    if (_idToken.isEmpty || _patientId.isEmpty) {
      markTestSkipped('No live backend configured.');
      return;
    }

    final service = RecordService(dio: Dio(BaseOptions(baseUrl: _baseUrl)));
    final rx = [
      {'medicine_name': 'Ibuprofen 400mg', 'dosage': '400mg BD', 'duration': '5 days'},
    ];
    final check = await service.checkDrugInteractions(
      idToken: _idToken,
      patientId: _patientId,
      prescriptions: rx,
    );
    final checkId = check['check_id'].toString();

    // Exactly what the screen sends when the doctor skips the reason box.
    await expectLater(
      service.createMedicalRecord(
        idToken: _idToken,
        patientId: _patientId,
        diagnosis: 'Contract test',
        prescriptions: rx,
        checkId: checkId,
      ),
      throwsA(isA<Exception>()),
    );

    final saved = await service.createMedicalRecord(
      idToken: _idToken,
      patientId: _patientId,
      diagnosis: 'Contract test',
      prescriptions: rx,
      checkId: checkId,
      overrideReason: 'Contract test override.',
    );
    expect(saved['id'], isA<String>());
  });
}
