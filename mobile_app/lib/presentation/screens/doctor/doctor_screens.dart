import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/doctor_provider.dart';
import '../../../providers/records_provider.dart';

// ============================================================================
// 1. DOCTOR'S "TODAY'S APPOINTMENTS" SCREEN (Day 20 - Task 1)
// ============================================================================

class DoctorTodayAppointmentsScreen extends ConsumerWidget {
  const DoctorTodayAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userMap = authState.patientProfile?['user'] as Map<String, dynamic>?;
    final role = (userMap?['role'] ?? authState.patientProfile?['role'] ?? 'PATIENT')
        .toString()
        .toUpperCase();

    // Guard: Doctor & Admin only
    if (role != 'DOCTOR' && role != 'ADMIN') {
      return Scaffold(
        appBar: AppBar(title: const Text("Today's Appointments")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Access Restricted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This portal is only accessible to verified Clinical Practitioners (DOCTOR role). Your current role is $role.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedDate = ref.watch(doctorSelectedDateProvider);
    final statusFilter = ref.watch(doctorStatusFilterProvider);
    final appointmentsAsync = ref.watch(doctorTodayAppointmentsProvider);

    final isToday = _isSameDay(selectedDate, DateTime.now());
    final dateDisplay = isToday
        ? "Today, ${DateFormat('MMM d, yyyy').format(selectedDate)}"
        : DateFormat('EEE, MMM d, yyyy').format(selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Doctor Queue"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Queue',
            onPressed: () => ref.invalidate(doctorTodayAppointmentsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Date Selector & Header Banner ────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF006D77).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: Color(0xFF006D77),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateDisplay,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2B2D42),
                              ),
                            ),
                            Text(
                              'Patient Consultations',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (!isToday)
                          TextButton(
                            onPressed: () {
                              ref.read(doctorSelectedDateProvider.notifier).state =
                                  DateTime.now();
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Today'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.event, color: Color(0xFF006D77)),
                          tooltip: 'Pick Date',
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 90)),
                              lastDate: DateTime.now().add(const Duration(days: 90)),
                            );
                            if (picked != null) {
                              ref.read(doctorSelectedDateProvider.notifier).state = picked;
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Status Filter Chips ──────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        label: 'All',
                        isSelected: statusFilter == null,
                        onSelected: () =>
                            ref.read(doctorStatusFilterProvider.notifier).state = null,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Pending',
                        isSelected: statusFilter == 'pending',
                        onSelected: () =>
                            ref.read(doctorStatusFilterProvider.notifier).state = 'pending',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Confirmed',
                        isSelected: statusFilter == 'confirmed',
                        onSelected: () =>
                            ref.read(doctorStatusFilterProvider.notifier).state = 'confirmed',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Completed',
                        isSelected: statusFilter == 'completed',
                        onSelected: () =>
                            ref.read(doctorStatusFilterProvider.notifier).state = 'completed',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Cancelled',
                        isSelected: statusFilter == 'cancelled',
                        onSelected: () =>
                            ref.read(doctorStatusFilterProvider.notifier).state = 'cancelled',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Appointment Queue List ───────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(doctorTodayAppointmentsProvider);
              },
              child: appointmentsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF006D77)),
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
                          'Failed to load queue',
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
                          onPressed: () => ref.invalidate(doctorTodayAppointmentsProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (appointments) {
                  if (appointments.isEmpty) {
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
                                  color: const Color(0xFF006D77).withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.event_available,
                                  size: 56,
                                  color: Color(0xFF006D77),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No Appointments Scheduled',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2B2D42),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                statusFilter != null
                                    ? 'No $statusFilter appointments found for this date.'
                                    : 'There are no patient visits booked for this date.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: appointments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final appt = appointments[index];
                      final patient =
                          appt['patient'] as Map<String, dynamic>? ?? {};
                      final clinic =
                          appt['clinic'] as Map<String, dynamic>? ?? {};
                      return _DoctorAppointmentCard(
                        appointment: appt,
                        onConsult: () {
                          // ── Change A: pass a clean typed map as go_router extra ──
                          // We extract only the fields the form needs so it never has
                          // to do multi-level null-safe access into the raw API map.
                          context.push('/doctor/add-record', extra: {
                            'patient_id': appt['patient_id']?.toString() ??
                                patient['id']?.toString() ??
                                '',
                            'patient_name': patient['name']?.toString() ??
                                'Unnamed Patient',
                            'health_id': patient['health_id']?.toString() ??
                                'MWH-N/A',
                            'appointment_id': appt['id']?.toString() ?? '',
                            'clinic_name':
                                clinic['name']?.toString() ?? 'Clinic',
                          });
                        },
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

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFF006D77),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: isSelected ? const Color(0xFF006D77) : Colors.grey.shade300,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Doctor Appointment Card Widget
// ────────────────────────────────────────────────────────────────────────────

class _DoctorAppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final VoidCallback onConsult;

  const _DoctorAppointmentCard({
    required this.appointment,
    required this.onConsult,
  });

  @override
  Widget build(BuildContext context) {
    final patient = appointment['patient'] as Map<String, dynamic>? ?? {};
    final clinic = appointment['clinic'] as Map<String, dynamic>? ?? {};
    final status = (appointment['status'] ?? 'pending').toString().toLowerCase();

    // Format time slot
    String timeStr = 'Time N/A';
    if (appointment['slot_time'] != null) {
      try {
        final dt = DateTime.parse(appointment['slot_time'].toString()).toLocal();
        timeStr = DateFormat('hh:mm a').format(dt);
      } catch (_) {
        timeStr = appointment['slot_time'].toString();
      }
    }

    final patientName = patient['name']?.toString() ?? 'Unnamed Patient';
    final healthId = patient['health_id']?.toString() ?? 'MWH-N/A';
    final phone = patient['phone']?.toString() ?? 'No phone';
    final clinicName = clinic['name']?.toString() ?? 'Clinic';

    Color statusColor;
    Color statusBgColor;
    String statusLabel;

    switch (status) {
      case 'confirmed':
        statusColor = const Color(0xFF006D77);
        statusBgColor = const Color(0xFFE0F2F1);
        statusLabel = 'CONFIRMED';
        break;
      case 'completed':
        statusColor = const Color(0xFF2E7D32);
        statusBgColor = const Color(0xFFE8F5E9);
        statusLabel = 'COMPLETED';
        break;
      case 'cancelled':
        statusColor = const Color(0xFFC62828);
        statusBgColor = const Color(0xFFFFEBEE);
        statusLabel = 'CANCELLED';
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFFE65100);
        statusBgColor = const Color(0xFFFFF3E0);
        statusLabel = 'PENDING';
        break;
    }

    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCompleted ? Colors.green.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Patient Name & Status Chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF006D77).withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: Color(0xFF006D77), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blueGrey.shade200),
                        ),
                        child: Text(
                          'ID: $healthId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Middle: Appointment Details
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Color(0xFF006D77)),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        phone,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.apartment_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    clinicName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Action Button
            SizedBox(
              width: double.infinity,
              child: isCompleted
                  ? OutlinedButton.icon(
                      onPressed: onConsult,
                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      label: const Text(
                        'Record Completed (Add Another Note)',
                        style: TextStyle(color: Colors.green),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    )
                  : isCancelled
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Visit Cancelled'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: onConsult,
                          icon: const Icon(Icons.assignment_turned_in, size: 18),
                          label: const Text('Start Consultation & Add Notes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006D77),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. PATIENT SEARCH SECTION (Standalone path — no appointment context)
// ============================================================================
//
// This widget replaces the raw "Patient UUID *" TextFormField.
//
// UX flow:
//   1. Doctor types a name fragment ("Ahmad") or a Health ID prefix ("MWH-AB").
//   2. On tap of the search icon (or keyboard submit), calls
//      GET /api/patients/search?q=<query> via patientServiceProvider.
//   3. Up to 10 results are shown in a dismissable list.
//   4. Tapping a result fires onPatientSelected(patient) which stores the
//      patient map in _DoctorAddRecordScreenState._selectedPatient.
//   5. A green confirmation chip replaces the list. The chip has an X button
//      to clear and search again.
//
// The parent (_DoctorAddRecordScreenState) is responsible for:
//   - Storing the selected patient in _selectedPatient.
//   - Reading _selectedPatient['id'] in _submitRecord().
// ============================================================================

class _PatientSearchSection extends ConsumerStatefulWidget {
  final void Function(Map<String, dynamic> patient) onPatientSelected;
  final Map<String, dynamic>? selectedPatient;

  const _PatientSearchSection({
    required this.onPatientSelected,
    required this.selectedPatient,
  });

  @override
  ConsumerState<_PatientSearchSection> createState() =>
      _PatientSearchSectionState();
}

class _PatientSearchSectionState extends ConsumerState<_PatientSearchSection> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchError = 'Enter at least 2 characters to search.';
        _results = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _results = [];
    });

    try {
      final token = ref.read(authTokenProvider);
      if (token == null) {
        setState(() {
          _searchError = 'Not authenticated.';
          _isSearching = false;
        });
        return;
      }
      final service = ref.read(patientServiceProvider);
      final results = await service.searchPatients(
        idToken: token,
        query: query,
      );
      setState(() {
        _results = results;
        _isSearching = false;
        if (results.isEmpty) {
          _searchError =
              'No patients found matching "$query". Try a different name or Health ID.';
        }
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString().replaceAll('Exception: ', '');
        _isSearching = false;
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _results = [];
      _searchError = null;
      _searchController.clear();
    });
    // Notify parent to clear selected patient — pass an empty sentinel
    // by calling onPatientSelected with a map that has a null id,
    // which _submitRecord treats as "no patient".
    // We do this via the parent setState wrapper in onPatientSelected.
    // Use a dedicated null-signal approach: the parent checks _selectedPatient == null.
    // But we can't set _selectedPatient to null from here directly — we rely on
    // the parent rebuilding this widget with selectedPatient: null.
    // So we expose a callback via onPatientSelected with a sentinel {} map
    // and the parent handles clearing _selectedPatient by detecting empty id.
    widget.onPatientSelected({'id': '', '_clear': true});
  }

  @override
  Widget build(BuildContext context) {
    // If a patient is already selected, show confirmation chip + clear button
    if (widget.selectedPatient != null &&
        (widget.selectedPatient!['_clear'] != true) &&
        (widget.selectedPatient!['id']?.toString().isNotEmpty ?? false)) {
      final p = widget.selectedPatient!;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Patient Identification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      const Color(0xFF006D77).withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.person,
                    color: Color(0xFF006D77),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name']?.toString() ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: Colors.blueGrey.shade200),
                            ),
                            child: Text(
                              p['health_id']?.toString() ?? 'MWH-N/A',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                          ),
                          if (p['gender'] != null) ...[ 
                            const SizedBox(width: 6),
                            Text(
                              p['gender'].toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default: show search field + results list
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Identification',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Search by patient name or Health ID (e.g. MWH-AB1234)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          // ── Search Input ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Ahmad Razif or MWH-ABC123',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _isSearching ? null : _doSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Search',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),

          // ── Error / Empty State ──────────────────────────────────
          if (_searchError != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _searchError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Search Results List ──────────────────────────────────
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      '${_results.length} result${_results.length == 1 ? '' : 's'} — tap to select',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ...List.generate(_results.length, (index) {
                    final p = _results[index];
                    final isLast = index == _results.length - 1;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => widget.onPatientSelected(p),
                          borderRadius: isLast
                              ? const BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                )
                              : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFF006D77)
                                      .withValues(alpha: 0.1),
                                  child: const Icon(
                                    Icons.person,
                                    color: Color(0xFF006D77),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['name']?.toString() ?? 'Unknown',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                              border: Border.all(
                                                  color: Colors
                                                      .blueGrey.shade200),
                                            ),
                                            child: Text(
                                              p['health_id']?.toString() ??
                                                  'MWH-N/A',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    Colors.blueGrey.shade800,
                                              ),
                                            ),
                                          ),
                                          if (p['phone'] != null) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              p['phone'].toString(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast) const Divider(height: 1),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
// ============================================================================
// 2. DOCTOR "ADD VISIT NOTES" SCREEN (Day 20 - Task 2)
// ============================================================================

class DoctorAddRecordScreen extends ConsumerStatefulWidget {
  /// Non-null when launched from the appointment queue (appointment path).
  /// Contains clean typed keys: patient_id, patient_name, health_id,
  /// appointment_id, clinic_name.
  /// Null when launched from the standalone "Add Visit Record" quick action.
  final Map<String, dynamic>? initialAppointmentData;

  const DoctorAddRecordScreen({
    super.key,
    this.initialAppointmentData,
  });

  @override
  ConsumerState<DoctorAddRecordScreen> createState() =>
      _DoctorAddRecordScreenState();
}

class _PrescriptionEntry {
  final TextEditingController medicineController;
  final TextEditingController dosageController;
  final TextEditingController durationController;

  _PrescriptionEntry({
    String medicine = '',
    String dosage = '',
    String duration = '',
  })  : medicineController = TextEditingController(text: medicine),
        dosageController = TextEditingController(text: dosage),
        durationController = TextEditingController(text: duration);

  void dispose() {
    medicineController.dispose();
    dosageController.dispose();
    durationController.dispose();
  }
}

class _DoctorAddRecordScreenState extends ConsumerState<DoctorAddRecordScreen> {
  final _formKey = GlobalKey<FormState>();

  // Standalone path: holds the patient selected via search widget.
  // Appointment path: patient_id comes directly from initialAppointmentData.
  Map<String, dynamic>? _selectedPatient;

  final _diagnosisController = TextEditingController();
  final _notesController = TextEditingController();

  final List<_PrescriptionEntry> _prescriptions = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Start with 1 initial prescription entry for convenience
    _prescriptions.add(_PrescriptionEntry());
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    for (final p in _prescriptions) {
      p.dispose();
    }
    super.dispose();
  }

  void _addPrescription() {
    setState(() {
      _prescriptions.add(_PrescriptionEntry());
    });
  }

  void _removePrescription(int index) {
    if (_prescriptions.length > index) {
      setState(() {
        _prescriptions[index].dispose();
        _prescriptions.removeAt(index);
      });
    }
  }

  Future<void> _submitRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ── Change C: resolve patient_id from the correct source per entry path ──
    //
    // Appointment path: patient_id was pre-filled by the appointment queue
    //   and is stored in initialAppointmentData under the 'patient_id' key
    //   (the clean map we built in Change A).
    //
    // Standalone path: the doctor searched for and selected a patient via
    //   _PatientSearchSection; the result is stored in _selectedPatient.
    //
    // Both paths eventually pass the same patientId to createMedicalRecord.
    final String? patientId;
    if (widget.initialAppointmentData != null) {
      patientId = widget.initialAppointmentData!['patient_id']?.toString();
    } else {
      patientId = _selectedPatient?['id']?.toString();
    }

    if (patientId == null || patientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialAppointmentData != null
                ? 'Patient ID is missing from the appointment data.'
                : 'Please search for and select a patient first.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final token = ref.read(authTokenProvider);
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not authenticated. Please log in.')),
      );
      return;
    }

    // Format prescriptions payload
    final formattedPrescriptions = <Map<String, String>>[];
    for (int i = 0; i < _prescriptions.length; i++) {
      final item = _prescriptions[i];
      final med = item.medicineController.text.trim();
      final dos = item.dosageController.text.trim();
      final dur = item.durationController.text.trim();

      // If any field is populated in this row, validate that all 3 are present
      if (med.isNotEmpty || dos.isNotEmpty || dur.isNotEmpty) {
        if (med.isEmpty || dos.isEmpty || dur.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Prescription #${i + 1} is incomplete. Please provide Medicine, Dosage, and Duration.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        formattedPrescriptions.add({
          'medicine_name': med,
          'dosage': dos,
          'duration': dur,
        });
      }
    }

    final appointmentId =
        widget.initialAppointmentData?['appointment_id']?.toString();
    final authState = ref.read(authNotifierProvider);
    final doctorId = widget.initialAppointmentData?['doctor_id']?.toString() ??
        widget.initialAppointmentData?['doctor']?['id']?.toString() ??
        authState.patientProfile?['id']?.toString() ??
        authState.patientProfile?['doctor']?['id']?.toString();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final recordService = ref.read(recordServiceProvider);
      await recordService.createMedicalRecord(
        idToken: token,
        patientId: patientId,
        doctorId: doctorId,
        appointmentId: appointmentId,
        diagnosis: _diagnosisController.text.trim(),
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        prescriptions: formattedPrescriptions.isNotEmpty ? formattedPrescriptions : null,
      );

      // Invalidate appointment queue so the status updates to 'completed'
      ref.invalidate(doctorTodayAppointmentsProvider);

      if (!mounted) return;

      // Show success dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
              SizedBox(width: 10),
              Text('Visit Notes Saved'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The medical consultation record has been logged successfully.',
              ),
              if (appointmentId != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.task_alt, color: Color(0xFF2E7D32), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Appointment status marked as COMPLETED.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (formattedPrescriptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${formattedPrescriptions.length} prescription(s) attached.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                context.pop(); // return to queue
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006D77),
                foregroundColor: Colors.white,
              ),
              child: const Text('Back to Queue'),
            ),
          ],
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
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.initialAppointmentData;
    // Read from the clean typed keys set by Change A in onConsult.
    // Appointment path: appointment != null, keys are patient_name / health_id / clinic_name.
    // Standalone path: appointment == null, the _PatientSearchSection widget handles display.
    final patientName = appointment?['patient_name']?.toString() ?? 'Patient';
    final healthId = appointment?['health_id']?.toString() ?? 'MWH-N/A';
    final clinicName = appointment?['clinic_name']?.toString() ?? 'Clinic';


    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Add Visit Notes'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Patient Context Banner ────────────────────────
              if (appointment != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF006D77).withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF006D77).withValues(alpha: 0.1),
                        child: const Icon(Icons.person, color: Color(0xFF006D77), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2B2D42),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Health ID: $healthId',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Clinic: $clinicName',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                // ── Change B: Standalone path — patient search widget ─────
                // Replaces the raw "Patient UUID *" TextFormField.
                // The widget handles its own search state and calls back here
                // when the doctor selects a patient from the results list.
                _PatientSearchSection(
                  onPatientSelected: (patient) {
                    setState(() {
                      // _clearSelection sends {'id': '', '_clear': true} as a sentinel
                      // to signal that the doctor wants to clear their selection.
                      // Any other map is a real patient.
                      if (patient['_clear'] == true) {
                        _selectedPatient = null;
                      } else {
                        _selectedPatient = patient;
                      }
                    });
                  },
                  selectedPatient: _selectedPatient,
                ),
                const SizedBox(height: 20),
              ],

              // ── 2. Clinical Diagnosis & Notes ─────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.healing, color: Color(0xFF006D77), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Clinical Assessment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2B2D42),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _diagnosisController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Primary Diagnosis *',
                        hintText: 'e.g. Acute Viral Upper Respiratory Tract Infection',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) {
                          return 'Diagnosis is required — cannot be blank';
                        }
                        if (v.length < 3) {
                          return 'Enter a meaningful diagnosis (at least 3 characters)';
                        }
                        if (v.length > 500) {
                          return 'Diagnosis is too long (max 500 characters)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: "Doctor's Notes & Advice (Optional)",
                        hintText: 'Clinical observations, patient advice, follow-up recommendations...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── 3. Dynamic Prescriptions Section ──────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.medication_liquid, color: Color(0xFF006D77), size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Prescriptions',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2B2D42),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF006D77).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_prescriptions.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF006D77),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addPrescription,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Add Medicine'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF006D77),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_prescriptions.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.no_photography, size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No prescriptions added yet.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _addPrescription,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add First Medicine'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _prescriptions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _prescriptions[index];
                    return _PrescriptionCard(
                      index: index,
                      entry: item,
                      onDelete: () => _removePrescription(index),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // Button to add another prescription
              if (_prescriptions.isNotEmpty)
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _addPrescription,
                    icon: const Icon(Icons.add, size: 18, color: Color(0xFF006D77)),
                    label: const Text(
                      'Add Another Prescription',
                      style: TextStyle(color: Color(0xFF006D77), fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF006D77)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

              const SizedBox(height: 32),

              // ── 4. Submit Button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitRecord,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _isSubmitting ? 'Saving Visit Record...' : 'Complete & Save Visit Record',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006D77),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Prescription Row Card Widget
// ────────────────────────────────────────────────────────────────────────────

class _PrescriptionCard extends StatelessWidget {
  final int index;
  final _PrescriptionEntry entry;
  final VoidCallback onDelete;

  const _PrescriptionCard({
    required this.index,
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006D77).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '#${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF006D77),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Medication',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  tooltip: 'Remove Prescription',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: entry.medicineController,
              decoration: InputDecoration(
                labelText: 'Medicine Name *',
                hintText: 'e.g. Amoxicillin / Paracetamol',
                prefixIcon: const Icon(Icons.medication, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (val) {
                final v = val?.trim() ?? '';
                if (v.isEmpty) return 'Medicine name is required';
                if (v.length < 2) return 'Enter a valid medicine name';
                if (v.length > 100) return 'Name too long (max 100 chars)';
                return null;
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: entry.dosageController,
                    decoration: InputDecoration(
                      labelText: 'Dosage *',
                      hintText: 'e.g. 500mg TDS',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (val) {
                      final v = val?.trim() ?? '';
                      if (v.isEmpty) return 'Dosage is required';
                      if (v.length < 2) return 'Enter valid dosage (e.g. 500mg)';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: entry.durationController,
                    decoration: InputDecoration(
                      labelText: 'Duration *',
                      hintText: 'e.g. 5 days',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (val) {
                      final v = val?.trim() ?? '';
                      if (v.isEmpty) return 'Duration required';
                      if (v.length < 2) return 'Enter valid duration';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

