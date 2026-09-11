import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root screen — owns the step-switcher and back-button interception
// ─────────────────────────────────────────────────────────────────────────────

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState
    extends ConsumerState<BookAppointmentScreen> {
  // The teal brand colour used throughout the existing app
  static const Color _brandColor = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final notifier = ref.read(bookingNotifierProvider.notifier);

    // ── One-shot listener: show success dialog when booking completes ─────────
    // ref.listen fires whenever the watched value changes. We only react when
    // status flips to BookingStatus.success. This avoids the "show dialog in
    // build()" anti-pattern.
    ref.listen<BookingState>(bookingNotifierProvider, (previous, next) {
      if (previous?.status != BookingStatus.success &&
          next.status == BookingStatus.success) {
        _showSuccessDialog(context, next, notifier);
      }
    });

    // ── Step labels for the progress indicator ────────────────────────────────
    const stepLabels = ['Clinic', 'Doctor', 'Date & Time', 'Confirm'];

    return PopScope(
      // Intercept the Android back gesture: go back a step, not out of screen
      canPop: bookingState.currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Book Appointment',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: bookingState.currentStep > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: notifier.goBack,
                )
              : null,
        ),
        body: Column(
          children: [
            // ── Step progress indicator ─────────────────────────────────────
            _StepProgressBar(
              currentStep: bookingState.currentStep,
              labels: stepLabels,
              brandColor: _brandColor,
            ),

            // ── Active step content ─────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _buildStep(bookingState.currentStep),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return const _ClinicSelectionStep(key: ValueKey('step-clinic'));
      case 1:
        return const _DoctorSelectionStep(key: ValueKey('step-doctor'));
      case 2:
        return const _DateTimeStep(key: ValueKey('step-datetime'));
      case 3:
        return const _ConfirmStep(key: ValueKey('step-confirm'));
      default:
        return const SizedBox.shrink();
    }
  }

  void _showSuccessDialog(
    BuildContext context,
    BookingState state,
    BookingNotifier notifier,
  ) {
    // Extract optional reference ID from the confirmed booking payload
    final referenceId =
        state.confirmedBooking?['id']?.toString() ?? 'N/A';
    final doctorName =
        state.selectedDoctor?['name']?.toString() ?? 'Doctor';
    final clinicName =
        state.selectedClinic?['name']?.toString() ?? 'Clinic';
    final slotFormatted = state.selectedDateTime != null
        ? DateFormat('EEE, d MMM y  •  h:mm a')
            .format(state.selectedDateTime!)
        : '—';

    showDialog<void>(
      context: context,
      barrierDismissible: false, // user must press Done
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_outline,
                    size: 44, color: Colors.green.shade600),
              ),
              const SizedBox(height: 20),
              const Text(
                'Appointment Confirmed!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Summary inside the dialog
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogRow(Icons.person_outline, doctorName),
                    const SizedBox(height: 6),
                    _dialogRow(Icons.apartment_outlined, clinicName),
                    const SizedBox(height: 6),
                    _dialogRow(Icons.schedule_outlined, slotFormatted),
                    if (referenceId != 'N/A') ...[
                      const SizedBox(height: 6),
                      _dialogRow(Icons.confirmation_number_outlined,
                          'Ref: $referenceId'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF006A6A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    // Dialog lives on the root navigator; the screen's context
                    // resolves to the ShellRoute's nested one, so pop via the dialog.
                    Navigator.of(dialogContext).pop();
                    notifier.reset(); // wipe wizard state
                    context.go('/'); // back to Dashboard
                  },
                  child: const Text('Done', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step progress bar widget
// ─────────────────────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final List<String> labels;
  final Color brandColor;

  const _StepProgressBar({
    required this.currentStep,
    required this.labels,
    required this.brandColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line between circles
            final stepIndex = i ~/ 2;
            final isDone = currentStep > stepIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: isDone ? brandColor : Colors.grey.shade200,
              ),
            );
          }
          // Circle
          final stepIndex = i ~/ 2;
          final isDone = currentStep > stepIndex;
          final isActive = currentStep == stepIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? brandColor
                      : isActive
                          ? brandColor.withValues(alpha: 0.15)
                          : Colors.grey.shade100,
                  border: Border.all(
                    color: (isDone || isActive)
                        ? brandColor
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? brandColor : Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[stepIndex],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? brandColor : Colors.grey.shade500,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 0 — Clinic Selection
// ─────────────────────────────────────────────────────────────────────────────

class _ClinicSelectionStep extends ConsumerWidget {
  const _ClinicSelectionStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // clinicsProvider is a FutureProvider — .when() handles all three states
    final clinicsAsync = ref.watch(clinicsProvider);
    final locationAsync = ref.watch(userLocationProvider);

    return clinicsAsync.when(
      loading: () => const _LoadingBody(message: 'Finding nearby clinics…'),
      error: (err, _) => _ErrorBody(
        message: err.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.invalidate(clinicsProvider),
      ),
      data: (clinics) {
        if (clinics.isEmpty) {
          return const _EmptyBody(
            icon: Icons.apartment_outlined,
            message: 'No clinics available at the moment.',
          );
        }

        final hasLocation = locationAsync.value != null;

        return _SelectionList(
          header: 'Choose a Clinic',
          subtitle: hasLocation
              ? '${clinics.length} clinics available • Sorted by proximity'
              : '${clinics.length} clinics available',
          locationNotice: hasLocation
              ? null
              : 'Location access is off. Showing standard directory list.',
          onRetryLocation: hasLocation
              ? null
              : () {
                  ref.invalidate(userLocationProvider);
                  ref.invalidate(clinicsProvider);
                },
          items: clinics,
          titleKey: 'name',
          subtitleKey: 'location',
          leadingIcon: Icons.apartment_outlined,
          onSelect: (clinic) =>
              ref.read(bookingNotifierProvider.notifier).selectClinic(clinic),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Doctor Selection
// ─────────────────────────────────────────────────────────────────────────────

class _DoctorSelectionStep extends ConsumerWidget {
  const _DoctorSelectionStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final doctorsAsync = ref.watch(doctorsForClinicProvider);

    return doctorsAsync.when(
      loading: () => const _LoadingBody(message: 'Fetching available doctors…'),
      error: (err, _) => _ErrorBody(
        message: err.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.invalidate(doctorsForClinicProvider),
      ),
      data: (doctors) {
        if (doctors.isEmpty) {
          return _EmptyBody(
            icon: Icons.person_search_outlined,
            message:
                'No doctors available at ${bookingState.selectedClinic?['name'] ?? 'this clinic'} yet.',
          );
        }
        return _SelectionList(
          header: 'Choose a Doctor',
          subtitle:
              'at ${bookingState.selectedClinic?['name'] ?? 'selected clinic'}',
          items: doctors,
          titleKey: 'name',
          subtitleKey: 'specialization',
          leadingIcon: Icons.person_outline,
          onSelect: (doctor) =>
              ref.read(bookingNotifierProvider.notifier).selectDoctor(doctor),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Date & Time Picker
// ─────────────────────────────────────────────────────────────────────────────

class _DateTimeStep extends ConsumerWidget {
  const _DateTimeStep({super.key});

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final notifier = ref.read(bookingNotifierProvider.notifier);
    final dt = bookingState.selectedDateTime;

    final dateLabel = dt != null
        ? DateFormat('EEE, d MMMM yyyy').format(dt)
        : 'Tap to choose a date';
    final timeLabel =
        dt != null ? DateFormat('h:mm a').format(dt) : 'Tap to choose a time';
    final hasDate = dt != null;
    // We need both date and time before enabling Continue
    final canContinue = dt != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Selection summary card ────────────────────────────────────────
          _SummaryMiniCard(bookingState: bookingState),
          const SizedBox(height: 24),

          const Text(
            'Choose Date & Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a date, then a time slot for your appointment.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // ── Date picker tile ──────────────────────────────────────────────
          _DateTimeTile(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: dateLabel,
            isSelected: hasDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    dt ?? DateTime.now().add(const Duration(days: 1)),
                // Earliest selectable = tomorrow (can't book in the past)
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 90)),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: _brand,
                      onPrimary: Colors.white,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                // Keep the previously selected time, just update the date
                final existingTime = dt;
                final merged = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  existingTime?.hour ?? 9,
                  existingTime?.minute ?? 0,
                );
                notifier.selectDateTime(merged);
              }
            },
          ),
          const SizedBox(height: 12),

          // ── Time picker tile ──────────────────────────────────────────────
          _DateTimeTile(
            icon: Icons.access_time_outlined,
            label: 'Time',
            value: timeLabel,
            isSelected: dt != null && (dt.hour != 9 || dt.minute != 0),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: dt != null
                    ? TimeOfDay(hour: dt.hour, minute: dt.minute)
                    : const TimeOfDay(hour: 9, minute: 0),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: _brand,
                      onPrimary: Colors.white,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                final base = dt ?? DateTime.now().add(const Duration(days: 1));
                notifier.selectDateTime(DateTime(
                  base.year,
                  base.month,
                  base.day,
                  picked.hour,
                  picked.minute,
                ));
              }
            },
          ),

          const SizedBox(height: 32),

          // ── Continue button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    canContinue ? _brand : Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: canContinue ? notifier.proceedToConfirm : null,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Continue',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateTimeTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _brand : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: _brand, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.black87 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — Confirm & Submit
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmStep extends ConsumerWidget {
  const _ConfirmStep({super.key});

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final notifier = ref.read(bookingNotifierProvider.notifier);
    final isLoading = bookingState.status == BookingStatus.loading;
    final isSlotTaken = bookingState.status == BookingStatus.slotTaken;
    final isError = bookingState.status == BookingStatus.error;

    final slotFormatted = bookingState.selectedDateTime != null
        ? DateFormat('EEE, d MMMM yyyy  •  h:mm a')
            .format(bookingState.selectedDateTime!)
        : '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review & Confirm',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Please review your appointment details before confirming.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // ── Full summary card ─────────────────────────────────────────────
          _FullSummaryCard(
            bookingState: bookingState,
            slotFormatted: slotFormatted,
          ),
          const SizedBox(height: 20),

          // ── Slot-taken warning banner (409 response) ──────────────────────
          if (isSlotTaken) ...[
            _WarningBanner(
              message: bookingState.errorMessage ??
                  'This slot is already taken — please go back and choose a different time.',
              onGoBack: notifier.goBack,
            ),
            const SizedBox(height: 16),
          ],

          // ── Generic error message ─────────────────────────────────────────
          if (isError && !isSlotTaken) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bookingState.errorMessage ?? 'An unexpected error occurred.',
                      style: TextStyle(
                          fontSize: 13, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Confirm Booking button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: isSlotTaken ? Colors.grey.shade400 : _brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              // Disable the button while loading or after a slot-taken error
              // (user must go back and change time before retrying)
              onPressed: (isLoading || isSlotTaken)
                  ? null
                  : () => notifier.confirmBooking(),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                isLoading ? 'Booking…' : 'Confirm Booking',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'You can cancel or reschedule from My Appointments.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  final VoidCallback onGoBack;

  const _WarningBanner({required this.message, required this.onGoBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.amber.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Slot Already Taken',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onGoBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Choose a Different Time'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber.shade800,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Reusable scrollable list used for both clinic and doctor selection steps.
class _SelectionList extends StatelessWidget {
  final String header;
  final String subtitle;
  final String? locationNotice;
  final VoidCallback? onRetryLocation;
  final List<Map<String, dynamic>> items;
  final String titleKey;
  final String subtitleKey;
  final IconData leadingIcon;
  final void Function(Map<String, dynamic>) onSelect;

  const _SelectionList({
    required this.header,
    required this.subtitle,
    this.locationNotice,
    this.onRetryLocation,
    required this.items,
    required this.titleKey,
    required this.subtitleKey,
    required this.leadingIcon,
    required this.onSelect,
  });

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(header,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600)),
              if (locationNotice != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_off_outlined,
                          size: 14, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locationNotice!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                      if (onRetryLocation != null) ...[
                        InkWell(
                          onTap: onRetryLocation,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              final title = item[titleKey]?.toString() ?? '—';
              final sub = item[subtitleKey]?.toString() ?? '';
              final rawDist = item['distance_km'];
              final distanceKm = (rawDist is num) ? rawDist.toDouble() : null;

              return InkWell(
                onTap: () => onSelect(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(leadingIcon, color: _brand, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
                            if (sub.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(sub,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                            ],
                            if (distanceKm != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _brand.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.near_me_outlined,
                                            size: 12, color: _brand),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${distanceKm.toStringAsFixed(1)} km away',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _brand,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade400, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Mini summary card shown during date/time step (shows clinic + doctor chosen so far).
class _SummaryMiniCard extends StatelessWidget {
  final BookingState bookingState;

  const _SummaryMiniCard({required this.bookingState});

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow(
              Icons.apartment_outlined,
              bookingState.selectedClinic?['name']?.toString() ??
                  'Clinic'),
          const SizedBox(height: 6),
          _summaryRow(
              Icons.person_outline,
              bookingState.selectedDoctor?['name']?.toString() ??
                  'Doctor'),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _brand),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Full summary card on the Confirm step.
class _FullSummaryCard extends StatelessWidget {
  final BookingState bookingState;
  final String slotFormatted;

  const _FullSummaryCard({
    required this.bookingState,
    required this.slotFormatted,
  });

  static const Color _brand = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _summaryRow(
            Icons.apartment_outlined,
            'Clinic',
            bookingState.selectedClinic?['name']?.toString() ?? '—',
            bookingState.selectedClinic?['location']?.toString(),
          ),
          const Divider(height: 24),
          _summaryRow(
            Icons.person_outline,
            'Doctor',
            bookingState.selectedDoctor?['name']?.toString() ?? '—',
            bookingState.selectedDoctor?['specialization']?.toString(),
          ),
          const Divider(height: 24),
          _summaryRow(
            Icons.schedule_outlined,
            'Slot',
            slotFormatted,
            null,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
      IconData icon, String label, String value, String? sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _brand, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown while a FutureProvider is loading.
class _LoadingBody extends StatelessWidget {
  final String message;
  const _LoadingBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF006A6A)),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

/// Shown when a FutureProvider errors.
class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_outlined,
                size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a list returns empty.
class _EmptyBody extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyBody({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
