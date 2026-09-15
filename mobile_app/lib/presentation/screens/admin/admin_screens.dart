import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/responsive_card_list.dart';
import '../clinic/clinic_shell.dart';

/// Bottom sheet on phones, centred dialog on wide (PC / web) screens.
void _showFormSheet(BuildContext context, Widget sheet) {
  if (ClinicShell.isWide(context)) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: sheet,
        ),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }
}

// ============================================================================
// 3. ADMIN "STAFF" SCREEN: applications, staff accounts, invites
//    (AUTH_RBAC_CONSENT_PLAN.md Phase 4; API in backend/routes/staff.routes.js)
// ============================================================================

const _accent = Color(0xFF8338EC);

const _roleLabels = {
  'DOCTOR': 'Doctor',
  'RECEPTIONIST': 'Receptionist',
  'CLINIC_ADMIN': 'Clinic admin',
  'ADMIN': 'Platform admin',
};

class AdminStaffScreen extends ConsumerWidget {
  const AdminStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Permission gate lives in ClinicShell.
    final staffAsync = ref.watch(staffListProvider);
    final invitesAsync = ref.watch(staffInvitesProvider);
    void refresh() {
      ref.invalidate(staffListProvider);
      ref.invalidate(staffInvitesProvider);
    }

    final pendingCount =
        staffAsync.valueOrNull?.where((s) => s['status'] == 'PENDING').length ?? 0;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Staff'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: refresh),
          ],
          bottom: TabBar(tabs: [
            Tab(text: pendingCount > 0 ? 'Applications ($pendingCount)' : 'Applications'),
            const Tab(text: 'Staff'),
            const Tab(text: 'Invites'),
          ]),
        ),
        body: TabBarView(children: [
          _cards(staffAsync, refresh, (s) => s['status'] == 'PENDING',
              'No pending applications.', (s) => _StaffCard(member: s)),
          _cards(staffAsync, refresh, (s) => s['status'] != 'PENDING',
              'No staff accounts yet.', (s) => _StaffCard(member: s)),
          _cards(invitesAsync, refresh, (_) => true,
              'No invites yet.', (i) => _InviteCard(invite: i)),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showFormSheet(context, const _InviteSheet()),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Invite'),
        ),
      ),
    );
  }

  static Widget _cards(
    AsyncValue<List<Map<String, dynamic>>> value,
    VoidCallback refresh,
    bool Function(Map<String, dynamic>) keep,
    String empty,
    Widget Function(Map<String, dynamic>) card,
  ) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _accent)),
      error: (e, _) => AppErrorView(error: e, onRetry: refresh),
      data: (items) {
        final shown = items.where(keep).toList();
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: shown.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ])
              : ResponsiveCardList(itemCount: shown.length, itemBuilder: (_, i) => card(shown[i])),
        );
      },
    );
  }
}

Widget _statusChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );

Widget _detail(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
      ]),
    );

class _StaffCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> member;

  const _StaffCard({required this.member});

  @override
  ConsumerState<_StaffCard> createState() => _StaffCardState();
}

class _StaffCardState extends ConsumerState<_StaffCard> {
  bool _busy = false;

  Future<void> _act(String action, String done) async {
    final m = widget.member;
    if (action != 'approve') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == 'reject' ? 'Reject application?' : 'Disable account?'),
          content: Text(action == 'reject'
              ? 'The application is removed. They can apply again.'
              : 'They are signed out of every call until an admin enables the account again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action == 'reject' ? 'Reject' : 'Disable')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final token = ref.read(authTokenProvider);
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(staffServiceProvider).act(idToken: token, userId: m['id'].toString(), action: action);
      ref.invalidate(staffListProvider);
      ref.invalidate(clinicsProvider); // approved doctors become bookable
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final doctor = m['doctor'] as Map<String, dynamic>?;
    final status = m['status']?.toString() ?? 'ACTIVE';
    final name = doctor?['name']?.toString() ?? m['email']?.toString() ?? m['phone']?.toString() ?? 'Staff member';
    final contact = [m['email'], m['phone']].whereType<String>().join(' • ');
    final clinic = (m['clinic'] as Map?)?['name']?.toString();
    final registration = doctor?['registration_number']?.toString();
    final council = doctor?['registration_council']?.toString();
    final myId = (ref.watch(authNotifierProvider).patientProfile?['user'] as Map?)?['id'];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2B2D42))),
              ),
              _statusChip(_roleLabels[m['role']] ?? '${m['role']}', _accent),
              const SizedBox(width: 6),
              _statusChip(status, switch (status) {
                'PENDING' => Colors.orange.shade800,
                'DISABLED' => Colors.red.shade700,
                _ => Colors.green.shade700,
              }),
            ]),
            if (doctor?['specialization'] != null) _detail(Icons.medical_information_outlined, doctor!['specialization'].toString()),
            if (registration != null)
              _detail(Icons.verified_user_outlined,
                  'Reg. no. $registration${council != null ? ' ($council)' : ''}'),
            if (contact.isNotEmpty && contact != name) _detail(Icons.contact_mail_outlined, contact),
            if (clinic != null) _detail(Icons.apartment, clinic),
            if (m['id'] != myId) ...[
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (status == 'PENDING') ...[
                  TextButton(onPressed: _busy ? null : () => _act('reject', 'Application rejected.'), child: const Text('Reject')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _busy ? null : () => _act('approve', 'Approved: $name can now sign in.'), child: const Text('Approve')),
                ] else if (status == 'DISABLED')
                  OutlinedButton(onPressed: _busy ? null : () => _act('approve', '$name is enabled again.'), child: const Text('Enable'))
                else
                  OutlinedButton(onPressed: _busy ? null : () => _act('disable', '$name is disabled.'), child: const Text('Disable')),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> invite;

  const _InviteCard({required this.invite});

  @override
  Widget build(BuildContext context) {
    final state = invite['state']?.toString() ?? 'OPEN';
    final contact = [invite['email'], invite['phone']].whereType<String>().join(' • ');
    final expires = DateTime.tryParse(invite['expires_at']?.toString() ?? '');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(invite['name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2B2D42))),
              ),
              _statusChip(_roleLabels[invite['role']] ?? '${invite['role']}', _accent),
              const SizedBox(width: 6),
              _statusChip(state, switch (state) {
                'ACCEPTED' => Colors.green.shade700,
                'EXPIRED' => Colors.grey.shade700,
                _ => Colors.orange.shade800,
              }),
            ]),
            if (contact.isNotEmpty) _detail(Icons.contact_mail_outlined, contact),
            if ((invite['clinic'] as Map?)?['name'] != null) _detail(Icons.apartment, (invite['clinic'] as Map)['name'].toString()),
            if (state == 'OPEN' && expires != null)
              _detail(Icons.schedule, 'Expires ${DateFormat('d MMM yyyy').format(expires.toLocal())}'),
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet();

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _specialization = TextEditingController();
  String _role = 'DOCTOR';
  String? _clinicId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _specialization]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authTokenProvider);
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(staffServiceProvider).createInvite(idToken: token, invite: {
        'role': _role,
        'name': _name.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_role == 'DOCTOR') 'specialization': _specialization.text.trim(),
        'clinic_id': ?_clinicId,
      });
      ref.invalidate(staffInvitesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Invite created. Ask them to sign in with that email or phone.'),
        backgroundColor: Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey.shade50,
      );

  @override
  Widget build(BuildContext context) {
    // A clinic admin always invites into their own clinic (the API defaults it).
    final pickClinic = ref.watch(authNotifierProvider).role == 'ADMIN';
    final eitherContact = _email.text.trim().isNotEmpty || _phone.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.person_add_alt_1, color: _accent),
                SizedBox(width: 10),
                Text('Invite Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2B2D42))),
              ]),
              const SizedBox(height: 6),
              Text('No email is sent: tell them to sign in with this email or phone. The invite lasts 14 days.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: _decoration('Role *', Icons.badge_outlined),
                items: [
                  for (final r in ['DOCTOR', 'RECEPTIONIST', 'CLINIC_ADMIN'])
                    DropdownMenuItem(value: r, child: Text(_roleLabels[r]!)),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: _decoration('Full Name *', Icons.person_outline),
                validator: (v) => (v ?? '').trim().length < 2 ? 'At least 2 characters' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration('Email', Icons.email_outlined),
                onChanged: (_) => setState(() {}),
                validator: (v) => eitherContact ? null : 'Enter an email or a phone number',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: _decoration('Phone', Icons.phone_outlined, hint: 'e.g. +919876543210'),
                onChanged: (_) => setState(() {}),
              ),
              if (_role == 'DOCTOR') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _specialization,
                  decoration: _decoration('Medical Specialization *', Icons.medical_information_outlined,
                      hint: 'e.g. General Practice'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Specialization is required' : null,
                ),
              ],
              if (pickClinic) ...[
                const SizedBox(height: 16),
                ref.watch(adminClinicsProvider).when(
                      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (e, _) => Text('Failed to load clinics: $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
                      data: (clinics) => DropdownButtonFormField<String>(
                        initialValue: _clinicId,
                        isExpanded: true,
                        decoration: _decoration('Clinic *', Icons.apartment_outlined),
                        items: [
                          for (final c in clinics)
                            DropdownMenuItem(value: c['id'].toString(), child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _clinicId = v),
                        validator: (v) => v == null ? 'Please select a clinic' : null,
                      ),
                    ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined),
                  label: Text(_saving ? 'Creating...' : 'Create Invite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. ADMIN "MANAGE CLINICS" SCREEN (Day 20 - Task 4)
// ============================================================================

class AdminManageClinicsScreen extends ConsumerStatefulWidget {
  const AdminManageClinicsScreen({super.key});

  @override
  ConsumerState<AdminManageClinicsScreen> createState() => _AdminManageClinicsScreenState();
}

class _AdminManageClinicsScreenState extends ConsumerState<AdminManageClinicsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // Role gate lives in ClinicShell.
    final clinicsAsync = ref.watch(adminClinicsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Clinic Facilities'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Clinics',
            onPressed: () => ref.invalidate(adminClinicsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search clinic name or location...',
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8338EC)),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF8338EC).withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                });
              },
            ),
          ),

          // ── Clinics List ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(adminClinicsProvider);
              },
              child: clinicsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8338EC)),
                ),
                error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        const Text(
                          'Failed to load clinics',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          err.toString().replaceAll('Exception: ', ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(adminClinicsProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (clinics) {
                  final filtered = clinics.where((c) {
                    final name = (c['name'] ?? '').toString().toLowerCase();
                    final loc = (c['location'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || loc.contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8338EC).withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.apartment,
                                  size: 56,
                                  color: Color(0xFF8338EC),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No clinics matching "$_searchQuery"'
                                    : 'No Clinics Available',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2B2D42),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try searching with a different name or location.'
                                    : 'Clinic facilities will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ResponsiveCardList(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final clinic = filtered[index];
                      return _ClinicFacilityCard(
                        clinic: clinic,
                        onEdit: () => _openEditClinicModal(context, clinic),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditClinicModal(BuildContext context, Map<String, dynamic> clinic) {
    _showFormSheet(context, _EditClinicModalSheet(clinic: clinic));
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Clinic Facility Card Widget
// ────────────────────────────────────────────────────────────────────────────

class _ClinicFacilityCard extends StatelessWidget {
  final Map<String, dynamic> clinic;
  final VoidCallback onEdit;

  const _ClinicFacilityCard({
    required this.clinic,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final name = clinic['name']?.toString() ?? 'Clinic';
    final location = clinic['location']?.toString() ?? 'Location N/A';
    final contactNumber = clinic['contact_number']?.toString() ?? 'No phone';
    final lat = clinic['latitude'];
    final lng = clinic['longitude'];

    final hasCoordinates = lat != null && lng != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: Name + GPS Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF8338EC).withValues(alpha: 0.1),
                  child: const Icon(Icons.apartment, color: Color(0xFF8338EC), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasCoordinates ? Colors.green.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasCoordinates ? Colors.green.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: hasCoordinates ? Colors.green.shade700 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasCoordinates ? '$lat, $lng' : 'GPS coordinates not set',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: hasCoordinates ? Colors.green.shade800 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Location
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Contact Number
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  contactNumber,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Edit Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF8338EC)),
                label: const Text(
                  'Edit Clinic Details',
                  style: TextStyle(color: Color(0xFF8338EC), fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8338EC)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Edit Clinic Modal Sheet
// ────────────────────────────────────────────────────────────────────────────

class _EditClinicModalSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> clinic;

  const _EditClinicModalSheet({required this.clinic});

  @override
  ConsumerState<_EditClinicModalSheet> createState() => _EditClinicModalSheetState();
}

class _EditClinicModalSheetState extends ConsumerState<_EditClinicModalSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _contactController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.clinic['name']?.toString() ?? '');
    _locationController =
        TextEditingController(text: widget.clinic['location']?.toString() ?? '');
    _contactController =
        TextEditingController(text: widget.clinic['contact_number']?.toString() ?? '');
    _latController =
        TextEditingController(text: widget.clinic['latitude']?.toString() ?? '');
    _lngController =
        TextEditingController(text: widget.clinic['longitude']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _contactController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _submitClinicUpdate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final token = ref.read(authTokenProvider);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    final clinicId = widget.clinic['id']?.toString() ?? '';
    if (clinicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinic ID is missing.')),
      );
      return;
    }

    // Parse lat/lng
    double? latitude;
    double? longitude;
    if (_latController.text.trim().isNotEmpty) {
      latitude = double.tryParse(_latController.text.trim());
    }
    if (_lngController.text.trim().isNotEmpty) {
      longitude = double.tryParse(_lngController.text.trim());
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final adminService = ref.read(adminServiceProvider);
      await adminService.updateClinic(
        idToken: token,
        clinicId: clinicId,
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        contactNumber: _contactController.text.trim(),
        latitude: latitude,
        longitude: longitude,
      );

      // Invalidate providers so patient appointment booking and admin lists refresh
      ref.invalidate(adminClinicsProvider);
      ref.invalidate(clinicsProvider);
      ref.invalidate(staffListProvider);

      if (!mounted) return;
      Navigator.pop(context); // Close bottom sheet

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Clinic "${_nameController.text.trim()}" updated successfully!'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle & Header
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.edit_location_alt, color: Color(0xFF8338EC)),
                  SizedBox(width: 10),
                  Text(
                    'Edit Clinic Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B2D42),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Update clinic name, address, contact, and GPS coordinates for distance sorting.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // ── 1. Clinic Name ────────────────────────────────────
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Clinic Name *',
                  prefixIcon: const Icon(Icons.apartment),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Clinic name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 2. Clinic Location / Address ──────────────────────
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location / Physical Address *',
                  hintText: 'e.g. Block 4, Puchong Industrial Area',
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Location is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 3. Contact Number ─────────────────────────────────
              TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Contact Phone Number *',
                  hintText: 'e.g. +60123456789',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Please enter a valid contact number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 4. GPS Coordinates ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'e.g. 3.0333',
                        prefixIcon: const Icon(Icons.my_location, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          if (double.tryParse(val.trim()) == null) {
                            return 'Invalid number';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'e.g. 101.6167',
                        prefixIcon: const Icon(Icons.my_location, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          if (double.tryParse(val.trim()) == null) {
                            return 'Invalid number';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── 5. Submit Button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitClinicUpdate,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Updating...' : 'Save Clinic Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8338EC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

