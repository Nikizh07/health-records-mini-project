import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';

/// Email sign-up, link not clicked yet. The backend accepts an invite or an
/// application only from a verified email.
class EmailVerificationScreen extends ConsumerWidget {
  const EmailVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final notifier = ref.read(authNotifierProvider.notifier);
    final email = ref.read(authServiceProvider).currentUser?.email ?? 'your email address';

    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (next.route != null && next.route != '/verify-email') {
        context.go(next.route!);
      } else if (next.status == AuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: Colors.red.shade700),
        );
      }
    });

    Future<void> check() async {
      await notifier.recheck();
      if (context.mounted && ref.read(authNotifierProvider).status == AuthStatus.needsEmailVerification) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not verified yet. Open the link in the email, then try again.')),
        );
      }
    }

    Future<void> resend() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await notifier.resendEmailVerification();
        messenger.showSnackBar(SnackBar(content: Text('Verification email sent to $email.')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Verify your email',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a link to $email. Open it, then come back here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: auth.isLoading ? null : check,
                    child: const Text("I've verified"),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: auth.isLoading ? null : resend, child: const Text('Resend email')),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await notifier.signOut();
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
    );
  }
}
