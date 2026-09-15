import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/doctor_provider.dart';

// ============================================================================
// FRONT DESK (AUTH_RBAC_CONSENT_PLAN.md Phase 6)
// ============================================================================
// Clinic staff without record access (receptionist, clinic admin) use the
// doctor's queue and patient lookup screens; these are the pieces they get in
// place of the clinical ones. Nothing here calls /records.
// ============================================================================

String _message(Object e) => e.toString().replaceAll('Exception: ', '');

String _drName(Object? name) {
  final n = name?.toString() ?? 'Doctor';
  return n.startsWith('Dr.') ? n : 'Dr. $n';
}

/// Doctors at the signed-in staff member's clinic (the walk-in picker).
final _clinicDoctorsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final clinicId =
          (ref.watch(authNotifierProvider).patientProfile?['clinic']
                  as Map?)?['id']
              ?.toString();
      if (clinicId == null) {
        throw Exception('No clinic is assigned to this account.');
      }
      return ref
          .watch(appointmentServiceProvider)
          .getDoctors(
            idToken: ref.watch(authTokenProvider) ?? '',
            clinicId: clinicId,
          );
    });

// ── Register a walk-in patient (POST /patients/register) ────────────────────

/// Returns the registered patient, or null if the dialog was closed.
Future<Map<String, dynamic>?> showRegisterPatientDialog(BuildContext context) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _RegisterPatientDialog(),
    );

class _RegisterPatientDialog extends ConsumerStatefulWidget {
  const _RegisterPatientDialog();

  @override
  ConsumerState<_RegisterPatientDialog> createState() =>
      _RegisterPatientDialogState();
}

class _RegisterPatientDialogState
    extends ConsumerState<_RegisterPatientDialog> {
  static const _genders = ['Male', 'Female', 'Other'];
  static const _languages = [
    'Bengali',
    'Hindi',
    'English',
    'Tamil',
    'Malayalam',
    'Odia',
    'Telugu',
    'Assamese',
  ];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  String _gender = 'Male';
  String _language = 'Hindi';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final patient = await ref
          .read(patientServiceProvider)
          .registerAtDesk(
            idToken: ref.read(authTokenProvider) ?? '',
            name: _name.text.trim(),
            dob: _dob.text.trim(),
            gender: _gender,
            languagePref: _language,
            phone: _phone.text.trim(),
          );
      if (mounted) Navigator.pop(context, patient);
    } catch (e) {
      // A phone already on file comes back as "…already registered… (MWH-…)".
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Register patient'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter the name' : null,
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number *',
                    helperText:
                        'They sign in with this number later to see their records',
                  ),
                  validator: (v) =>
                      (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                      ? 'Enter the mobile number'
                      : null,
                ),
                TextFormField(
                  controller: _dob,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Date of birth * (YYYY-MM-DD)',
                  ),
                  validator: (v) {
                    final dob = (v ?? '').trim();
                    final parsed = DateTime.tryParse(dob);
                    return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob) ||
                            parsed == null ||
                            parsed.isAfter(DateTime.now())
                        ? 'Enter the date as YYYY-MM-DD'
                        : null;
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: [
                    for (final g in _genders)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => _gender = v ?? _gender,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(
                    labelText: 'Preferred language',
                  ),
                  items: [
                    for (final l in _languages)
                      DropdownMenuItem(value: l, child: Text(l)),
                  ],
                  onChanged: (v) => _language = v ?? _language,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Register'),
        ),
      ],
    );
  }
}

// ── Patient panel: demographics + walk-in with a doctor picker ─────────────

class FrontDeskPatientPanel extends ConsumerWidget {
  final Map<String, dynamic> patient;

  const FrontDeskPatientPanel({super.key, required this.patient});

  Future<void> _bookWalkIn(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final doctor = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _DoctorPickerDialog(),
    );
    if (doctor == null) return;
    try {
      await ref
          .read(appointmentServiceProvider)
          .createWalkIn(
            idToken: ref.read(authTokenProvider) ?? '',
            patientId: patient['id'].toString(),
            doctorId: doctor['id'].toString(),
          );
      ref.invalidate(doctorTodayAppointmentsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Walk-in booked with ${_drName(doctor['name'])}. It's in today's queue.",
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dob = DateTime.tryParse(patient['dob']?.toString() ?? '');
    final rows = [
      ('Health ID', patient['health_id']),
      ('Phone', patient['phone']),
      ('Gender', patient['gender']),
      (
        'Date of birth',
        dob == null ? null : DateFormat('dd MMM yyyy').format(dob),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              patient['name']?.toString() ?? 'Unnamed Patient',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2B2D42),
              ),
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          label,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                      Expanded(child: Text(value.toString())),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            Text(
              'Medical history is only visible to doctors.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _bookWalkIn(context, ref),
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: const Text('Walk-in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorPickerDialog extends ConsumerWidget {
  const _DoctorPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SimpleDialog(
      title: const Text('Book with which doctor?'),
      children: ref
          .watch(_clinicDoctorsProvider)
          .when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_message(e)),
              ),
            ],
            data: (doctors) => doctors.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No doctors at this clinic yet.'),
                    ),
                  ]
                : [
                    for (final d in doctors)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, d),
                        child: ListTile(
                          leading: const Icon(Icons.medical_services_outlined),
                          title: Text(_drName(d['name'])),
                          subtitle: Text(d['specialization']?.toString() ?? ''),
                        ),
                      ),
                  ],
          ),
    );
  }
}

// ── Queue card actions: confirm / cancel ────────────────────────────────────

class FrontDeskQueueActions extends ConsumerWidget {
  final Map<String, dynamic> appointment;

  const FrontDeskQueueActions({super.key, required this.appointment});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required bool confirm,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!confirm) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel appointment?'),
          content: const Text(
            'The slot is freed and the patient sees it as cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cancel appointment'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    final service = ref.read(appointmentServiceProvider);
    final token = ref.read(authTokenProvider) ?? '';
    final id = appointment['id'].toString();
    try {
      confirm
          ? await service.confirmAppointment(idToken: token, appointmentId: id)
          : await service.cancelAppointment(idToken: token, appointmentId: id);
      ref.invalidate(doctorTodayAppointmentsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            confirm ? 'Appointment confirmed.' : 'Appointment cancelled.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = appointment['status']?.toString();
    if (status != 'pending' && status != 'confirmed') {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => _run(context, ref, confirm: false),
          child: const Text('Cancel'),
        ),
        if (status == 'pending') ...[
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _run(context, ref, confirm: true),
            child: const Text('Confirm'),
          ),
        ],
      ],
    );
  }
}
