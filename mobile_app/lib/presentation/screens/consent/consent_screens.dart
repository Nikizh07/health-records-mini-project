import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/errors/api_exception.dart';
import '../../../data/services/consent_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/consent_provider.dart';
import '../../widgets/app_error_view.dart';

// ============================================================================
// CONSENT (AUTH_RBAC_CONSENT_PLAN.md Phase 8)
// ============================================================================
// Doctor : ConsentGate — request access, enter a share code, or emergency.
// Patient: ConsentPopupHost (the allow/deny popup) and PrivacyScreen.
// audit:read: AccessAuditScreen.
// ============================================================================

const _teal = Color(0xFF006D77);
const _danger = Color(0xFFC62828);

String _msg(Object e) => e.toString().replaceAll('Exception: ', '');

/// The backend refused a record because there is no care link or consent.
bool isConsentRequired(Object? error) =>
    error is ApiException && error.code == 'CONSENT_REQUIRED';

String _drName(Object? name) {
  final n = name?.toString() ?? 'A doctor';
  return n.startsWith('Dr.') ? n : 'Dr. $n';
}

String _when(Object? iso) {
  final t = DateTime.tryParse(iso?.toString() ?? '');
  return t == null ? '' : DateFormat('dd MMM, HH:mm').format(t.toLocal());
}

/// Who read the records, as the access log describes them.
String _actor(Map<String, dynamic> log) {
  final user = log['user'] as Map<String, dynamic>?;
  final doctor = user?['doctor'] as Map<String, dynamic>?;
  if (doctor?['name'] != null) return _drName(doctor!['name']);
  return user?['email']?.toString() ?? user?['role']?.toString() ?? 'Removed account';
}

String _clinicOf(Map<String, dynamic> log) =>
    ((log['user'] as Map<String, dynamic>?)?['doctor'] as Map<String, dynamic>?)
        ?['clinic']?['name']
        ?.toString() ??
    '';

const _actionLabels = {
  'READ_HISTORY': 'opened the history',
  'READ_RECORD': 'opened a visit',
  'WRITE_RECORD': 'saved a visit',
  'INTERACTION_CHECK': 'ran a drug check',
  'UPLOAD_REPORT': 'uploaded a report',
};

// ────────────────────────────────────────────────────────────────────────────
// Doctor: the gate in front of a patient's history
// ────────────────────────────────────────────────────────────────────────────

class ConsentGate extends ConsumerStatefulWidget {
  final Map<String, dynamic> patient;

  /// Called once access is granted: reload whatever was refused.
  final VoidCallback onGranted;

  const ConsentGate({super.key, required this.patient, required this.onGranted});

  @override
  ConsumerState<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends ConsumerState<ConsentGate> {
  String? _requestId;
  String? _note;
  bool _busy = false;

  String get _patientId => widget.patient['id'].toString();
  String get _name => widget.patient['name']?.toString() ?? 'this patient';

  Future<void> _guard(Future<void> Function(ConsentService s, String token) body) async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await body(ref.read(consentServiceProvider), ref.read(authTokenProvider) ?? '');
    } catch (e) {
      if (mounted) setState(() => _note = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestAccess() => _guard((service, token) async {
        final consent = await service.request(idToken: token, patientId: _patientId);
        if (mounted) setState(() => _requestId = consent['id']?.toString());
      });

  Future<void> _enterShareCode() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _ShareCodeDialog());
    if (code == null) return;
    await _guard((service, token) async {
      await service.redeem(idToken: token, patientId: _patientId, code: code);
      widget.onGranted();
    });
  }

  Future<void> _emergency() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _EmergencyDialog());
    if (reason == null) return;
    await _guard((service, token) async {
      await service.emergency(idToken: token, patientId: _patientId, reason: reason);
      widget.onGranted();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_requestId != null) {
      return _WaitingForApproval(
        consentId: _requestId!,
        patientName: _name,
        onGranted: widget.onGranted,
        onEnded: (note) => setState(() {
          _requestId = null;
          _note = note;
        }),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.lock_outline, color: _teal),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Consent needed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              "$_name isn't under your care, so their history stays private. "
              'Ask them to allow access on their phone, or enter the 6-digit code they show you.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (_note != null) ...[
              const SizedBox(height: 12),
              Text(_note!, style: const TextStyle(color: _danger)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _requestAccess,
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('Request access'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _enterShareCode,
                  icon: const Icon(Icons.pin_outlined, size: 18),
                  label: const Text('Enter share code'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _emergency,
                  icon: const Icon(Icons.emergency_outlined, size: 18),
                  label: const Text('Emergency access'),
                  style: TextButton.styleFrom(foregroundColor: _danger),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Polls the doctor's request every 3 s (consentStatusProvider) until the
/// patient answers it.
class _WaitingForApproval extends ConsumerWidget {
  final String consentId;
  final String patientName;
  final VoidCallback onGranted;
  final void Function(String note) onEnded;

  const _WaitingForApproval({
    required this.consentId,
    required this.patientName,
    required this.onGranted,
    required this.onEnded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(consentStatusProvider(consentId), (_, next) {
      switch (next.valueOrNull?['status']) {
        case 'APPROVED':
          onGranted();
        case 'DENIED':
          onEnded('$patientName denied the request.');
        case 'EXPIRED':
        case 'REVOKED':
          onEnded('The request timed out. Ask again, or use a share code.');
      }
    });
    ref.watch(consentStatusProvider(consentId)); // keeps the poll running

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Waiting for $patientName to allow access on their phone…'),
          ),
          TextButton(
            onPressed: () => onEnded('Request cancelled.'),
            child: const Text('Cancel'),
          ),
        ]),
      ),
    );
  }
}

class _ShareCodeDialog extends StatefulWidget {
  const _ShareCodeDialog();

  @override
  State<_ShareCodeDialog> createState() => _ShareCodeDialogState();
}

class _ShareCodeDialogState extends State<_ShareCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter share code'),
      content: TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        decoration: const InputDecoration(
          labelText: '6-digit code',
          helperText: 'The patient makes it in their app. It works once, for 10 minutes.',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) => v.length == 6 ? Navigator.pop(context, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _code.text.length == 6 ? () => Navigator.pop(context, _code.text) : null,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

class _EmergencyDialog extends StatefulWidget {
  const _EmergencyDialog();

  @override
  State<_EmergencyDialog> createState() => _EmergencyDialogState();
}

class _EmergencyDialogState extends State<_EmergencyDialog> {
  static const _minReason = 20;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final short = _reason.text.trim().length < _minReason;
    return AlertDialog(
      title: const Text('Emergency access'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use this only when the patient cannot answer. Access lasts 4 hours '
            'and is shown to the patient and your clinic, with this reason.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason *',
              errorText: short && _reason.text.isNotEmpty ? 'At least $_minReason characters.' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: short ? null : () => Navigator.pop(context, _reason.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: _danger),
          child: const Text('Open records'),
        ),
      ],
    );
  }
}

/// The same gate as a dialog, for the visit form and the interaction check.
/// Resolves true once access is granted.
Future<bool> showConsentGateDialog(BuildContext context, Map<String, dynamic> patient) async {
  final granted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ConsentGate(
          patient: patient,
          onGranted: () => Navigator.pop(dialogContext, true),
        ),
      ),
    ),
  );
  return granted ?? false;
}

// ────────────────────────────────────────────────────────────────────────────
// Patient: the allow / deny popup, hosted by ClinicShell
// ────────────────────────────────────────────────────────────────────────────

class ConsentPopupHost extends ConsumerStatefulWidget {
  final Widget child;

  const ConsentPopupHost({super.key, required this.child});

  @override
  ConsumerState<ConsentPopupHost> createState() => _ConsentPopupHostState();
}

class _ConsentPopupHostState extends ConsumerState<ConsentPopupHost> {
  bool _open = false;

  /// Requests this session has already answered. A poll that was in flight
  /// while the patient tapped comes back still listing them, and without this
  /// the popup would open again on a request that is already settled.
  final _answered = <String>{};

  Future<void> _ask(Map<String, dynamic> consent) async {
    final id = consent['id'].toString();
    _open = true;
    final clinic = (consent['clinic'] as Map?)?['name']?.toString() ?? 'a clinic';
    // Closed with the dialog's own context: under the ShellRoute, this
    // context's Navigator is the nested one (see MEMORY.md).
    final approve = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share your medical history?'),
        content: Text(
          '${_drName((consent['doctor'] as Map?)?['name'])}, $clinic wants to see '
          'your medical history for 24 hours.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Deny')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Allow')),
        ],
      ),
    );
    if (approve == null || !mounted) {
      _open = false;
      return;
    }
    _answered.add(id);
    try {
      await ref.read(consentServiceProvider).respond(
            idToken: ref.read(authTokenProvider) ?? '',
            consentId: id,
            approve: approve,
          );
    } catch (e) {
      // It was not recorded, so let the next poll ask again.
      _answered.remove(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
    // Only now: until the answer is sent, the request is still pending and a
    // tick in between would put the same popup straight back up.
    _open = false;
    ref.invalidate(pendingConsentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingConsentsProvider, (_, next) {
      // asData, not valueOrNull: every poll passes through a refreshing state
      // that still carries the *previous* list, and asking on that reopens the
      // popup the patient has just answered.
      final waiting = next.asData?.value ?? const [];
      if (_open) return;
      for (final consent in waiting) {
        if (_answered.contains(consent['id'].toString())) continue;
        _ask(consent);
        return;
      }
    });
    ref.watch(pendingConsentsProvider); // keeps the 10 s poll running

    return widget.child;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Patient: privacy screen — share code, active grants, access history
// ────────────────────────────────────────────────────────────────────────────

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _createCode(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code = await ref.read(consentServiceProvider).createShareCode(
            idToken: ref.read(authTokenProvider) ?? '',
          );
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Your share code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              code['code']?.toString() ?? '',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 8),
            ),
            const SizedBox(height: 8),
            const Text('Show it to the doctor. It works once, for 10 minutes.'),
          ]),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
          ],
        ),
      );
      ref.invalidate(myConsentsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, Map<String, dynamic> consent) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(consentServiceProvider).revoke(
            idToken: ref.read(authTokenProvider) ?? '',
            consentId: consent['id'].toString(),
          );
      ref.invalidate(myConsentsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Access revoked.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myConsentsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Privacy & access'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(myConsentsProvider),
          ),
        ],
      ),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _teal)),
        error: (e, _) => AppErrorView(error: e, onRetry: () => ref.invalidate(myConsentsProvider)),
        data: (data) {
          final now = DateTime.now();
          final grants = [
            for (final c in (data['consents'] as List? ?? const []).cast<Map<String, dynamic>>())
              if (c['status'] == 'APPROVED' &&
                  (DateTime.tryParse(c['granted_until']?.toString() ?? '')?.isAfter(now) ?? false))
                c,
          ];
          final log = (data['access_log'] as List? ?? const []).cast<Map<String, dynamic>>();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Share code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'For a doctor who needs your history now. One code, 10 minutes, one use.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _createCode(context, ref),
                        icon: const Icon(Icons.pin_outlined, size: 18),
                        label: const Text('Create share code'),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Who can see your history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (grants.isEmpty)
                Text('Nobody outside your care team right now.', style: TextStyle(color: Colors.grey.shade600))
              else
                for (final c in grants)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        c['method'] == 'EMERGENCY' ? Icons.emergency_outlined : Icons.verified_user_outlined,
                        color: c['method'] == 'EMERGENCY' ? _danger : _teal,
                      ),
                      title: Text(_drName((c['doctor'] as Map?)?['name'])),
                      subtitle: Text(
                        '${(c['clinic'] as Map?)?['name'] ?? ''} · until ${_when(c['granted_until'])}'
                        '${c['method'] == 'EMERGENCY' ? '\nEmergency access: ${c['reason'] ?? ''}' : ''}',
                      ),
                      trailing: TextButton(
                        onPressed: () => _revoke(context, ref, c),
                        child: const Text('Revoke'),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              const Text('Access history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (log.isEmpty)
                Text('No one has opened your records yet.', style: TextStyle(color: Colors.grey.shade600))
              else
                for (final l in log) AccessLogTile(log: l),
            ],
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// audit:read — the clinic's access log
// ────────────────────────────────────────────────────────────────────────────

class AccessAuditScreen extends ConsumerWidget {
  const AccessAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(accessAuditProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Access log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(accessAuditProvider),
          ),
        ],
      ),
      body: audit.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(error: e, onRetry: () => ref.invalidate(accessAuditProvider)),
        data: (logs) => logs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text('Nobody has opened a patient record yet.',
                      style: TextStyle(color: Colors.grey.shade600)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                itemBuilder: (_, i) => AccessLogTile(log: logs[i], showPatient: true),
              ),
      ),
    );
  }
}

/// One access-log row, for the patient's history and the clinic audit list.
/// Emergency access is called out in red: it is the one grant nobody approved.
class AccessLogTile extends StatelessWidget {
  final Map<String, dynamic> log;
  final bool showPatient;

  const AccessLogTile({super.key, required this.log, this.showPatient = false});

  @override
  Widget build(BuildContext context) {
    final via = log['via']?.toString() ?? '';
    final emergency = via == 'EMERGENCY';
    final reason = (log['consent'] as Map?)?['reason']?.toString();
    final patient = log['patient'] as Map?;
    final clinic = _clinicOf(log);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: emergency ? _danger : Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(emergency ? Icons.emergency_outlined : Icons.visibility_outlined,
            color: emergency ? _danger : _teal),
        title: Text(
          showPatient
              ? '${_actor(log)} → ${patient?['name'] ?? 'Patient'} (${patient?['health_id'] ?? ''})'
              : _actor(log),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text([
          if (clinic.isNotEmpty) clinic,
          _actionLabels[log['action']] ?? log['action']?.toString() ?? '',
          _when(log['created_at']),
        ].where((s) => s.isNotEmpty).join(' · ')),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: (emergency ? _danger : _teal).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(via,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: emergency ? _danger : _teal)),
        ),
        isThreeLine: emergency && reason != null,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: emergency && reason != null
            ? () => showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Emergency access'),
                    content: Text(reason),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
                    ],
                  ),
                )
            : null,
      ),
    );
  }
}
