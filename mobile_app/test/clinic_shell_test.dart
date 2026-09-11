import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/presentation/screens/clinic/clinic_shell.dart';

void main() {
  test('clinic role gate', () {
    expect(ClinicShell.canAccess('/admin/doctors', 'ADMIN'), isTrue);
    expect(ClinicShell.canAccess('/admin/clinics', 'DOCTOR'), isFalse);
    expect(ClinicShell.canAccess('/admin/clinics', 'PATIENT'), isFalse);
    expect(ClinicShell.canAccess('/doctor/patients', 'DOCTOR'), isTrue);
    expect(ClinicShell.canAccess('/doctor/add-record', 'ADMIN'), isTrue);
    expect(ClinicShell.canAccess('/doctor/today-appointments', 'PATIENT'), isFalse);
    expect(ClinicShell.canAccess('/records', 'PATIENT'), isTrue);
    expect(ClinicShell.canAccess('/', 'PATIENT'), isTrue);
  });
}
