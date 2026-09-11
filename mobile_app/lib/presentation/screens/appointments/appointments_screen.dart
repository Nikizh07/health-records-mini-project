import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/appointment_service.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/offline_banner.dart';

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  static const Color _brandColor = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(myAppointmentsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'My Appointments',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(myAppointmentsProvider),
            ),
          ],
          bottom: const TabBar(
            labelColor: _brandColor,
            unselectedLabelColor: Colors.black54,
            indicatorColor: _brandColor,
            indicatorWeight: 3,
            tabs: [
              Tab(
                icon: Icon(Icons.upcoming_outlined, size: 20),
                text: 'Upcoming',
              ),
              Tab(
                icon: Icon(Icons.history_outlined, size: 20),
                text: 'Past & History',
              ),
            ],
          ),
        ),
        body: appointmentsAsync.when(
          loading: () => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: _brandColor),
                SizedBox(height: 16),
                Text('Loading appointments...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  Text(
                    err.toString().replaceAll('Exception: ', ''),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(myAppointmentsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          data: (result) {
            final appointments = result.data;
            final now = DateTime.now();

            // Categorize into Upcoming vs Past
            final upcoming = <Map<String, dynamic>>[];
            final past = <Map<String, dynamic>>[];

            for (final appt in appointments) {
              final status = (appt['status'] ?? 'pending').toString().toLowerCase();
              final rawSlot = appt['slot_time']?.toString();
              final slotTime = rawSlot != null ? DateTime.tryParse(rawSlot)?.toLocal() : null;

              if (status == 'cancelled' || status == 'completed') {
                past.add(appt);
              } else if (slotTime != null && slotTime.isBefore(now)) {
                // If slot time has passed, treat as past
                past.add(appt);
              } else {
                upcoming.add(appt);
              }
            }

            final tabView = TabBarView(
              children: [
                _AppointmentListView(
                  appointments: upcoming,
                  isUpcomingTab: true,
                  onRefresh: () async => ref.refresh(myAppointmentsProvider),
                  onReschedule: (appt) => _handleReschedule(context, appt),
                  onCancel: (appt) => _handleCancel(context, appt),
                ),
                _AppointmentListView(
                  appointments: past,
                  isUpcomingTab: false,
                  onRefresh: () async => ref.refresh(myAppointmentsProvider),
                ),
              ],
            );

            if (result.isOffline) {
              return Column(
                children: [
                  OfflineBanner(lastUpdated: result.lastUpdated),
                  Expanded(child: tabView),
                ],
              );
            }

            return tabView;
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/book-appointment'),
          backgroundColor: _brandColor,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Book Appointment'),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Reschedule Action Handler
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _handleReschedule(
    BuildContext context,
    Map<String, dynamic> appointment,
  ) async {
    final appointmentId = appointment['id']?.toString();
    if (appointmentId == null) return;

    final rawSlot = appointment['slot_time']?.toString();
    final currentSlot = rawSlot != null ? DateTime.tryParse(rawSlot)?.toLocal() : null;
    final doctor = appointment['doctor'] as Map<String, dynamic>?;
    final doctorName = doctor?['name']?.toString() ?? 'Doctor';

    // 1. Pick Date
    final initialDate = currentSlot != null && currentSlot.isAfter(DateTime.now())
        ? currentSlot
        : DateTime.now().add(const Duration(days: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      helpText: 'Select New Appointment Date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _brandColor,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null || !context.mounted) return;

    // 2. Pick Time
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: currentSlot != null
          ? TimeOfDay(hour: currentSlot.hour, minute: currentSlot.minute)
          : const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select New Time Slot',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _brandColor,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedTime == null || !context.mounted) return;

    // 3. Merge date and time into UTC ISO-8601
    final newSlotDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    final newSlotIso = newSlotDateTime.toUtc().toIso8601String();

    // 4. Call PUT /api/appointments/:id with progress indicator
    final token = ref.read(authTokenProvider);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not authenticated. Please log in again.')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _brandColor),
                SizedBox(height: 16),
                Text('Rescheduling appointment...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final service = ref.read(appointmentServiceProvider);
      await service.rescheduleAppointment(
        idToken: token,
        appointmentId: appointmentId,
        slotTime: newSlotIso,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog (on root navigator)
        ref.invalidate(myAppointmentsProvider);

        final formattedNewDate = DateFormat('EEE, d MMM yyyy • h:mm a').format(newSlotDateTime);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade700,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rescheduled with $doctorName to $formattedNewDate',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } on SlotTakenException {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog (on root navigator)
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 36),
            title: const Text('Slot Already Taken'),
            content: const Text(
              'This slot is already booked for this doctor. Please choose another date or time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brandColor),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _handleReschedule(context, appointment); // Retry picker
                },
                child: const Text('Pick Another Time'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog (on root navigator)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            content: Text(e.toString().replaceAll('Exception: ', '')),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Cancel Action Handler
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _handleCancel(
    BuildContext context,
    Map<String, dynamic> appointment,
  ) async {
    final appointmentId = appointment['id']?.toString();
    if (appointmentId == null) return;

    final doctor = appointment['doctor'] as Map<String, dynamic>?;
    final doctorName = doctor?['name']?.toString() ?? 'Doctor';
    final rawSlot = appointment['slot_time']?.toString();
    final slotDate = rawSlot != null ? DateTime.tryParse(rawSlot)?.toLocal() : null;
    final formattedDate = slotDate != null
        ? DateFormat('EEE, d MMM yyyy • h:mm a').format(slotDate)
        : 'the scheduled time';

    // Show Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Appointment?'),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel your appointment with $doctorName on $formattedDate?\n\nThis will free up the slot for other patients.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Appointment'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final token = ref.read(authTokenProvider);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not authenticated. Please log in again.')),
      );
      return;
    }

    try {
      final service = ref.read(appointmentServiceProvider);
      await service.cancelAppointment(
        idToken: token,
        appointmentId: appointmentId,
      );

      if (context.mounted) {
        ref.invalidate(myAppointmentsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.grey.shade800,
            behavior: SnackBarBehavior.floating,
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Appointment cancelled successfully.'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            content: Text(e.toString().replaceAll('Exception: ', '')),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appointment List View with RefreshIndicator and Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentListView extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final bool isUpcomingTab;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic>)? onReschedule;
  final void Function(Map<String, dynamic>)? onCancel;

  const _AppointmentListView({
    required this.appointments,
    required this.isUpcomingTab,
    required this.onRefresh,
    this.onReschedule,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isUpcomingTab
                            ? Icons.event_available_outlined
                            : Icons.history_toggle_off,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isUpcomingTab
                            ? 'No Upcoming Appointments'
                            : 'No Past Appointments Found',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isUpcomingTab
                            ? 'Book an appointment with a clinic doctor to get started.'
                            : 'Your completed or cancelled visits will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: appointments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final appt = appointments[index];
          return _AppointmentCard(
            appointment: appt,
            isUpcoming: isUpcomingTab,
            onReschedule: onReschedule != null ? () => onReschedule!(appt) : null,
            onCancel: onCancel != null ? () => onCancel!(appt) : null,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appointment Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final bool isUpcoming;
  final VoidCallback? onReschedule;
  final VoidCallback? onCancel;

  const _AppointmentCard({
    required this.appointment,
    required this.isUpcoming,
    this.onReschedule,
    this.onCancel,
  });

  static const Color _brandColor = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    final status = (appointment['status'] ?? 'pending').toString().toLowerCase();

    final doctor = appointment['doctor'] as Map<String, dynamic>?;
    final clinic = appointment['clinic'] as Map<String, dynamic>?;

    final docName = doctor?['name']?.toString() ?? 'Doctor';
    final docSpecialization = doctor?['specialization']?.toString() ?? 'General Practice';
    final clinicName = clinic?['name']?.toString() ?? 'Clinic';
    final clinicLocation = clinic?['location']?.toString() ?? '';

    final rawSlot = appointment['slot_time']?.toString();
    final slotDate = rawSlot != null ? DateTime.tryParse(rawSlot)?.toLocal() : null;
    final formattedDate = slotDate != null
        ? DateFormat('EEE, d MMMM yyyy').format(slotDate)
        : 'Date N/A';
    final formattedTime = slotDate != null
        ? DateFormat('h:mm a').format(slotDate)
        : 'Time N/A';

    final canModify = isUpcoming && (status == 'pending' || status == 'confirmed');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Row: Doctor Info & Status Badge ────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _brandColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: _brandColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        docName.startsWith('Dr.') ? docName : 'Dr. $docName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        docSpecialization,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const Divider(height: 24),

            // ── Middle Section: Clinic & Slot Details ─────────────────────────
            Row(
              children: [
                Icon(Icons.apartment_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    clinicLocation.isNotEmpty
                        ? '$clinicName • $clinicLocation'
                        : clinicName,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: _brandColor),
                const SizedBox(width: 6),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time_outlined, size: 16, color: _brandColor),
                const SizedBox(width: 6),
                Text(
                  formattedTime,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            // ── Bottom Action Buttons for Upcoming Appointments ──────────────
            if (canModify) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                    label: const Text('Reschedule'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Badge with Color Coding
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'confirmed':
        bgColor = Colors.teal.shade50;
        textColor = Colors.teal.shade800;
        icon = Icons.check_circle_outline;
        label = 'Confirmed';
        break;
      case 'completed':
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade800;
        icon = Icons.task_alt;
        label = 'Completed';
        break;
      case 'cancelled':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade800;
        icon = Icons.cancel_outlined;
        label = 'Cancelled';
        break;
      case 'pending':
      default:
        bgColor = Colors.amber.shade50;
        textColor = Colors.amber.shade900;
        icon = Icons.hourglass_empty;
        label = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
