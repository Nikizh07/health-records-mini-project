import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/records_provider.dart';

class RecordDetailScreen extends ConsumerWidget {
  final String recordId;
  final Map<String, dynamic>? initialRecordData;

  const RecordDetailScreen({
    super.key,
    required this.recordId,
    this.initialRecordData,
  });

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('EEE, dd MMM yyyy - hh:mm a').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _openReportUrl(BuildContext context, String url) async {
    // The backend currently returns a relative path (/uploads/...); resolve it
    // against the API host. Absolute URLs (e.g. S3 presigned) pass through as-is.
    final uri = Uri.parse(AppConstants.apiBaseUrl).resolve(url);
    try {
      // canLaunchUrl needs <queries> entries on Android 11+, so just try it.
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No app available to open this document.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If initialRecordData was passed via router extra, use it immediately
    if (initialRecordData != null) {
      return _buildContent(context, initialRecordData!);
    }

    // Otherwise fetch via provider
    final recordAsync = ref.watch(singleRecordProvider(recordId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit Details'),
      ),
      body: recordAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF006A6A)),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 54, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Failed to load record details',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(err.toString(), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(singleRecordProvider(recordId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (record) => _buildContent(context, record),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> record) {
    final diagnosis = record['diagnosis']?.toString() ?? 'No diagnosis recorded';
    final notes = record['notes']?.toString();
    final visitDateStr = record['visit_date']?.toString() ?? record['created_at']?.toString();
    final reportUrl = record['report_file_url']?.toString();

    final doctorMap = record['doctor'] as Map<String, dynamic>?;
    final doctorName = doctorMap?['name']?.toString() ?? 'Attending Clinician';
    final specialization = doctorMap?['specialization']?.toString() ?? 'General Practice';
    final clinicMap = doctorMap?['clinic'] as Map<String, dynamic>?;
    final clinicName = clinicMap?['name']?.toString() ?? 'Migrant Worker Health Clinic';
    final clinicLocation = clinicMap?['location']?.toString();

    final prescriptions = (record['prescriptions'] as List<dynamic>?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card: Doctor & Visit Info
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF006A6A).withValues(alpha: 0.12),
                          child: const Icon(Icons.medical_services, color: Color(0xFF006A6A), size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doctorName.startsWith('Dr.') ? doctorName : 'Dr. $doctorName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                specialization,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Color(0xFF006A6A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatDate(visitDateStr),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF006A6A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            clinicLocation != null ? '$clinicName ($clinicLocation)' : clinicName,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Diagnosis Section
            const Text(
              'Diagnosis & Clinical Findings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.health_and_safety, color: Color(0xFF006A6A), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        diagnosis,
                        style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Clinical Notes (if available)
            if (notes != null && notes.trim().isNotEmpty) ...[
              const Text(
                "Doctor's Notes & Advice",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    notes,
                    style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade800),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Prescriptions Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Prescriptions & Medications',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006A6A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${prescriptions.length} items',
                    style: const TextStyle(
                      color: Color(0xFF006A6A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (prescriptions.isEmpty)
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'No medication prescribed for this visit.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: prescriptions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final p = prescriptions[index] as Map<String, dynamic>;
                  final medName = p['medicine_name']?.toString() ?? 'Medicine';
                  final dosage = p['dosage']?.toString() ?? 'As advised';
                  final duration = p['duration']?.toString() ?? 'N/A';

                  return Card(
                    elevation: 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.teal.shade100),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF006A6A).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.medication, color: Color(0xFF006A6A), size: 22),
                      ),
                      title: Text(
                        medName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Dosage: $dosage • Duration: $duration',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),

            // Task 4: Medical Report Attachment Section
            if (reportUrl != null && reportUrl.trim().isNotEmpty) ...[
              const Text(
                'Attached Medical Document',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFF006A6A).withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.picture_as_pdf, color: Colors.orange.shade800, size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clinical Lab Report / File',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Uploaded document for this consultation',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openReportUrl(context, reportUrl),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF006A6A),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('View Report', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
