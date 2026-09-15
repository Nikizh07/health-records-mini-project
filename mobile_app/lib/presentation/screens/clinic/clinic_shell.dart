import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';

/// Wraps every signed-in page.
/// - Waits for session restore and sends signed-out users to /login
///   (matters on web, where a reload can land on any URL).
/// - Gates /doctor/* and /admin/* by permission (see [routePermissions]).
/// - Gives clinic staff a persistent side navigation on wide (PC / web)
///   screens. Patients and phone-sized screens get the page unchanged.
class ClinicShell extends ConsumerWidget {
  final String path;
  final Widget child;

  const ClinicShell({super.key, required this.path, required this.child});

  static const double wideBreakpoint = 800;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideBreakpoint;

  /// The permission each staff page needs. Mirrors the API gate it calls.
  static const routePermissions = {
    '/doctor/today-appointments': 'appointment:manage',
    '/doctor/add-record': 'record:write',
    '/doctor/patients': 'record:read',
    '/admin/staff': 'staff:manage',
    '/admin/clinics': 'clinic:update',
  };

  /// Staff pages need their permission; an unknown /doctor or /admin page is
  /// closed; everything else is open.
  static bool canAccess(String path, bool Function(String) can) {
    for (final MapEntry(:key, :value) in routePermissions.entries) {
      if (path.startsWith(key)) return can(value);
    }
    return !path.startsWith('/doctor') && !path.startsWith('/admin');
  }

  static const _staffNav = [
    (Icons.dashboard_outlined, 'Dashboard', '/'),
    (Icons.calendar_today_outlined, 'Queue', '/doctor/today-appointments'),
    (Icons.post_add_outlined, 'New visit', '/doctor/add-record'),
    (Icons.person_search_outlined, 'Patients', '/doctor/patients'),
    (Icons.badge_outlined, 'Staff', '/admin/staff'),
    (Icons.apartment_outlined, 'Clinics', '/admin/clinics'),
    (Icons.account_circle_outlined, 'Profile', '/profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);

    if (auth.status == AuthStatus.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Signed out, or signed in without a usable profile (unregistered,
    // unverified email, pending application): send them to that step.
    final redirect = auth.status == AuthStatus.initial ? '/login' : auth.route;
    if (redirect != null && redirect != '/') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(redirect);
      });
      return const Scaffold();
    }

    final role = auth.role;
    final page = canAccess(path, auth.can) ? child : _AccessRestricted(role: role);

    if (auth.can('self:profile') || !isWide(context)) return page;

    final nav = [
      for (final d in _staffNav)
        if (canAccess(d.$3, auth.can)) d,
    ];
    final selected =
        nav.indexWhere((d) => d.$3 == '/' ? path == '/' : path.startsWith(d.$3));
    final extended = MediaQuery.sizeOf(context).width >= 1200;

    return Scaffold(
      body: Row(
        children: [
          Material(
            color: AppColors.surface,
            child: Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    extended: extended,
                    backgroundColor: AppColors.surface,
                    labelType: extended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    selectedIndex: selected < 0 ? null : selected,
                    onDestinationSelected: (i) => context.go(nav[i].$3),
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Icon(Icons.local_hospital_rounded,
                          color: AppColors.primary, size: 32),
                    ),
                    destinations: [
                      for (final (icon, label, _) in nav)
                        NavigationRailDestination(icon: Icon(icon), label: Text(label)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _AccessRestricted extends StatelessWidget {
  final String role;

  const _AccessRestricted({required this.role});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access restricted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'This page is for clinic staff. Your current role is $role.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
