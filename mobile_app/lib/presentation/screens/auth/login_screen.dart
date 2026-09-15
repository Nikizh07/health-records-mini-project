import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final String _selectedCountryCode = '+91';

  /// Staff mostly use the web portal; patients mostly use the phone app.
  bool _staff = kIsWeb;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleEmail({bool create = false}) {
    if (_formKey.currentState?.validate() ?? false) {
      ref
          .read(authNotifierProvider.notifier)
          .signInWithEmail(_emailController.text, _passwordController.text, create: create);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (!_emailPattern.hasMatch(email)) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter your email address first.')));
      return;
    }
    try {
      await ref.read(authNotifierProvider.notifier).sendPasswordReset(email);
      messenger.showSnackBar(SnackBar(content: Text('Password reset link sent to $email.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700));
    }
  }

  void _handleSendOtp() {
    if (_formKey.currentState?.validate() ?? false) {
      final fullPhoneNumber = '$_selectedCountryCode${_phoneController.text.trim()}';
      ref.read(authNotifierProvider.notifier).sendOtp(fullPhoneNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // Listen to state changes to navigate or show errors
    ref.listen<AuthState>(authNotifierProvider, (previous, next) {
      // This screen stays mounted under the OTP screen. Only react while it is
      // on top, otherwise "Resend" pushes a second OTP screen and every error
      // snackbar appears twice.
      if (ModalRoute.of(context)?.isCurrent != true) return;

      if (next.route != null) {
        context.go(next.route!);
      } else if (next.status == AuthStatus.otpSent) {
        context.push('/verify-otp');
      } else if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });

    // Checking for a saved session on app start
    if (authState.status == AuthStatus.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    const muted = TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.local_hospital_rounded, size: 38, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Migrant Health Hub',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your health records and clinic appointments in one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Patient'), icon: Icon(Icons.person_outline)),
                        ButtonSegment(value: true, label: Text('Clinic staff'), icon: Icon(Icons.badge_outlined)),
                      ],
                      selected: {_staff},
                      onSelectionChanged: (s) => setState(() => _staff = s.first),
                    ),
                    const SizedBox(height: 16),

                    if (_staff)
                      _staffCard(authState, muted)
                    else
                    // Phone sign-in
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Sign in with your mobile number',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text("We'll send a 6-digit verification code by SMS.", style: muted),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.telephoneNumberNational],
                              onFieldSubmitted: (_) => _handleSendOtp(),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Mobile number',
                                hintText: '9876543210',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(left: 16, right: 10),
                                  child: Text(
                                    _selectedCountryCode,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              ),
                              validator: (value) {
                                final digits = value?.trim() ?? '';
                                if (digits.isEmpty) {
                                  return 'Phone number is required';
                                }
                                if (digits.length != 10) {
                                  return 'Enter a valid 10-digit mobile number';
                                }
                                if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                                  return 'Must start with 6, 7, 8 or 9 (valid Indian mobile)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: authState.isLoading ? null : _handleSendOtp,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('Send code'),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Guest login is for local testing only: hidden in release
                    // builds (debug + the profile `web-doctor` build keep it),
                    // and the backend refuses anonymous tokens in production.
                    if (!kReleaseMode && !_staff) ...[
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or', style: muted),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: authState.isLoading
                            ? null
                            : () => ref.read(authNotifierProvider.notifier).signInAsGuest(),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Continue as guest'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Test build: use guest mode if SMS verification is not configured.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                    const SizedBox(height: 32),

                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.translate_rounded, size: 16, color: AppColors.textMuted),
                        SizedBox(width: 6),
                        Text(
                          'English • हिंदी • தமிழ்',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
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

  Widget _staffCard(AuthState authState, TextStyle muted) {
    final busy = authState.isLoading;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Clinic staff sign-in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Doctors, receptionists and clinic administrators.', style: muted),
              const SizedBox(height: 20),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) => _emailPattern.hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _handleEmail(),
                decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _handleForgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              FilledButton(
                onPressed: busy ? null : _handleEmail,
                child: busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : () => _handleEmail(create: true),
                child: const Text('Create account'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: muted)),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: busy ? null : () => ref.read(authNotifierProvider.notifier).signInWithGoogle(),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: const Text('Continue with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
