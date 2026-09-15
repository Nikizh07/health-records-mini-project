import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';

/// A clinic registered a patient on this phone before they had the app
/// (POST /api/patients/claim). The date of birth proves it is theirs.
class ClaimProfileScreen extends ConsumerStatefulWidget {
  const ClaimProfileScreen({super.key});

  @override
  ConsumerState<ClaimProfileScreen> createState() => _ClaimProfileScreenState();
}

class _ClaimProfileScreenState extends ConsumerState<ClaimProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dob = TextEditingController();

  @override
  void dispose() {
    _dob.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dob.text) ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (picked != null) _dob.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);

    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (next.route != null && next.route != '/claim') {
        context.go(next.route!);
      } else if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: Colors.red.shade700),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.assignment_ind_outlined, size: 64, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text('Your clinic profile',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'A clinic has already registered a patient with ${auth.phoneNumber ?? 'this mobile number'}. '
                      'Confirm your date of birth to see your health ID, appointments and records.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _dob,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: 'Date of birth',
                        hintText: 'YYYY-MM-DD',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        suffixIcon: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
                      ),
                      validator: (v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v?.trim() ?? '') &&
                              DateTime.tryParse(v!.trim()) != null
                          ? null
                          : 'Enter the date as YYYY-MM-DD',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.isLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                ref.read(authNotifierProvider.notifier).claimProfile(_dob.text.trim());
                              }
                            },
                      child: const Text('Link my profile'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Not you? The clinic may have typed the wrong number. Ask them to correct it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref.read(authNotifierProvider.notifier).signOut();
                        if (context.mounted) context.go('/login');
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
