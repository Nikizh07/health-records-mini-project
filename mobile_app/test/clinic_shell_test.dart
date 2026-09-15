import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/presentation/screens/clinic/clinic_shell.dart';

// Permission lists as sent by /patients/me (backend/config/permissions.js).
bool Function(String) _as(List<String> permissions) => permissions.contains;

final _patient = _as(['self:profile', 'consent:respond']);
final _doctor = _as(['patient:register', 'patient:lookup', 'appointment:manage', 'record:read',
    'record:write', 'interaction:check', 'report:upload', 'consent:request', 'consent:emergency']);
final _admin = _as(['staff:manage', 'clinic:update', 'clinic:create', 'audit:read']);
final _receptionist = _as(['patient:register', 'patient:lookup', 'appointment:manage']);
final _pending = _as([]);

void main() {
  test('clinic permission gate', () {
    expect(ClinicShell.canAccess('/admin/staff', _admin), isTrue);
    expect(ClinicShell.canAccess('/admin/clinics', _doctor), isFalse);
    expect(ClinicShell.canAccess('/admin/clinics', _patient), isFalse);
    expect(ClinicShell.canAccess('/doctor/patients', _doctor), isTrue);
    expect(ClinicShell.canAccess('/doctor/add-record', _admin), isFalse); // ADMIN lost record access
    expect(ClinicShell.canAccess('/doctor/patients', _admin), isFalse);
    expect(ClinicShell.canAccess('/doctor/today-appointments', _patient), isFalse);
    expect(ClinicShell.canAccess('/doctor/today-appointments', _receptionist), isTrue);
    expect(ClinicShell.canAccess('/doctor/add-record', _receptionist), isFalse);
    expect(ClinicShell.canAccess('/doctor/today-appointments', _pending), isFalse);
    expect(ClinicShell.canAccess('/doctor/unknown-page', _doctor), isFalse);
    expect(ClinicShell.canAccess('/records', _patient), isTrue);
    expect(ClinicShell.canAccess('/', _patient), isTrue);
  });
}
