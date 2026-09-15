import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';

/// A verified email with no invite applies as a doctor
/// (POST /api/staff/applications), then waits here until a clinic admin
/// approves it.
class StaffApplicationScreen extends ConsumerStatefulWidget {
  const StaffApplicationScreen({super.key});

  @override
  ConsumerState<StaffApplicationScreen> createState() => _StaffApplicationScreenState();
}

class _StaffApplicationScreenState extends ConsumerState<StaffApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _specialization = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _council = TextEditingController();
  String? _clinicId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _specialization, _registrationNumber, _council]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authTokenProvider);
    if (token == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(staffServiceProvider).apply(idToken: token, application: {
        'name': _name.text.trim(),
        'specialization': _specialization.text.trim(),
        'registration_number': _registrationNumber.text.trim(),
        if (_council.text.trim().isNotEmpty) 'registration_council': _council.text.trim(),
        'clinic_id': _clinicId,
      });
      await ref.read(authNotifierProvider.notifier).recheck(); // → PENDING
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final pending = auth.patientProfile?['status'] == 'PENDING';

    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (next.route != null && next.route != '/staff-apply') {
        context.go(next.route!);
      } else if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: Colors.red.shade700),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(pending ? 'Application pending' : 'Apply as a doctor'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: pending ? _pendingView(auth) : _form(),
          ),
        ),
      ),
    );
  }

  Widget _pendingView(AuthState auth) {
    final clinic = (auth.patientProfile?['clinic'] as Map?)?['name'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.hourglass_top_rounded, size: 64, color: AppColors.primary),
        const SizedBox(height: 16),
        Text('Waiting for approval', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'A clinic administrator${clinic != null ? ' at $clinic' : ''} checks your registration '
          'number. You get access to the doctor portal once they approve it.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: auth.isLoading ? null : ref.read(authNotifierProvider.notifier).recheck,
          child: const Text('Check again'),
        ),
      ],
    );
  }

  Widget _form() {
    final clinics = ref.watch(adminClinicsProvider);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'No invite was found for this account. Doctors can apply here; a clinic '
            'administrator verifies the registration number before approving.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'At least 2 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _specialization,
            decoration: const InputDecoration(
                labelText: 'Specialization *',
                hintText: 'e.g. General Practice',
                prefixIcon: Icon(Icons.medical_information_outlined)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Specialization is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registrationNumber,
            decoration: const InputDecoration(
                labelText: 'Registration number *', prefixIcon: Icon(Icons.verified_user_outlined)),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Registration number is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _council,
            decoration: const InputDecoration(
                labelText: 'Registration council',
                hintText: 'e.g. Tamil Nadu Medical Council',
                prefixIcon: Icon(Icons.account_balance_outlined)),
          ),
          const SizedBox(height: 12),
          clinics.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Text('Failed to load clinics: $e', style: const TextStyle(color: Colors.red)),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _clinicId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Clinic *', prefixIcon: Icon(Icons.apartment_outlined)),
              items: [
                for (final c in list)
                  DropdownMenuItem(value: c['id'].toString(), child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _clinicId = v),
              validator: (v) => v == null ? 'Please select a clinic' : null,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting...' : 'Submit application'),
          ),
        ],
      ),
    );
  }
}
