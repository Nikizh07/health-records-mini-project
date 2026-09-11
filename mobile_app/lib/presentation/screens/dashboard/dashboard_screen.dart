import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import 'widgets/dashboard_header_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const Color _doctorColor = Color(0xFF006D77);
  static const Color _adminColor = Color(0xFF8338EC);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final l10n = AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('en'));

    // Extract role from backend payload (default to PATIENT)
    final userMap = authState.patientProfile?['user'] as Map<String, dynamic>?;
    final role = (userMap?['role'] ?? authState.patientProfile?['role'] ?? 'PATIENT')
        .toString()
        .toUpperCase();

    final rawName = authState.patientProfile?['name']?.toString() ?? 'User';
    final healthId = authState.patientProfile?['health_id']?.toString() ?? 'MWH-PENDING';

    // Header parameters configured by role
    String headerTitle = rawName;
    String headerBadge = 'Health ID: $healthId';
    IconData headerIcon = Icons.badge_outlined;

    if (role == 'DOCTOR') {
      headerTitle = rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
      headerBadge = 'Clinical Practitioner';
      headerIcon = Icons.medical_services_outlined;
    } else if (role == 'ADMIN') {
      headerBadge = 'System Administrator';
      headerIcon = Icons.admin_panel_settings_outlined;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getRoleAppBarTitle(role, l10n)),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: l10n.profile,
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      drawer: _buildDrawer(context, ref, headerTitle, headerBadge, l10n),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardHeaderCard(
              title: headerTitle,
              badgeText: headerBadge,
              icon: headerIcon,
              role: role,
            ),
            const SizedBox(height: 28),
            Text(
              l10n.quickActions,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ..._buildRoleQuickActions(context, role, l10n),
            const SizedBox(height: 24),
            _buildInfoCard(role),
          ],
        ),
      ),
    );
  }

  String _getRoleAppBarTitle(String role, AppLocalizations l10n) {
    switch (role) {
      case 'DOCTOR':
        return l10n.doctorPortal;
      case 'ADMIN':
        return l10n.adminConsole;
      case 'PATIENT':
      default:
        return l10n.clinicHealthHub;
    }
  }

  List<Widget> _buildRoleQuickActions(
    BuildContext context,
    String role,
    AppLocalizations l10n,
  ) {
    final List<(IconData, String, String, String)> actions;
    final Color color;

    if (role == 'DOCTOR') {
      color = _doctorColor;
      actions = [
        (Icons.calendar_today_outlined, "Today's Appointments", 'View queue and scheduled consultations', '/doctor/today-appointments'),
        (Icons.post_add_outlined, 'Add Visit Record', 'Log diagnoses, prescriptions & lab results', '/doctor/add-record'),
        (Icons.folder_shared_outlined, l10n.healthRecords, 'Look up patient clinical history', '/records'),
      ];
    } else if (role == 'ADMIN') {
      color = _adminColor;
      actions = [
        (Icons.medical_services_outlined, 'Manage Doctors', 'Onboard clinicians and assign specializations', '/admin/doctors'),
        (Icons.apartment_outlined, 'Manage Clinics', 'Configure clinics, branches and schedules', '/admin/clinics'),
        (Icons.folder_open_outlined, 'System Health Records', 'Review clinic health data', '/records'),
      ];
    } else {
      color = AppColors.primary;
      actions = [
        (Icons.folder_shared_outlined, l10n.healthRecords, 'Records, prescriptions & lab reports', '/records'),
        (Icons.calendar_month_outlined, l10n.myAppointments, 'Upcoming and past visits', '/appointments'),
        (Icons.add_task_outlined, l10n.bookAppointment, 'Schedule a visit at a nearby clinic', '/book-appointment'),
      ];
    }

    return [
      for (final (icon, title, subtitle, route) in actions) ...[
        _buildActionTile(context, icon, title, subtitle, route, color),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _buildActionTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String route,
    Color color,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => context.push(route),
      ),
    );
  }

  Widget _buildInfoCard(String role) {
    final isPatient = role == 'PATIENT';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPatient ? 'Your records travel with you' : 'Confidential patient data',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                Text(
                  isPatient
                      ? 'Doctors at any participating clinic can see your medical history, so every visit starts with the full picture.'
                      : 'Signed in with ${role.toLowerCase()} access. Only open records you need for care.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    WidgetRef ref,
    String name,
    String badge,
    AppLocalizations l10n,
  ) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 36, color: AppColors.primary),
            ),
            accountName: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(badge),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: Text(l10n.dashboard),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.profile),
            onTap: () {
              Navigator.pop(context);
              context.push('/profile');
            },
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade700),
            title: Text(l10n.logout, style: TextStyle(color: Colors.red.shade700)),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}
