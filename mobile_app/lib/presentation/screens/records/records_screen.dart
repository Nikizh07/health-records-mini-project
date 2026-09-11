import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../providers/records_provider.dart';
import '../../widgets/offline_banner.dart';

class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(patientRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Health Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Records',
            onPressed: () => ref.refresh(patientRecordsProvider),
          ),
        ],
      ),
      body: recordsAsync.when(
        // ── Loading ──────────────────────────────────────────────────────────
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF006A6A)),
              SizedBox(height: 16),
              Text(
                'Fetching digital health history...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),

        // ── Error: no cache available either ─────────────────────────────────
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_outlined, size: 60, color: Colors.red.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Unable to load medical records',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString().replaceAll('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => ref.refresh(patientRecordsProvider),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF006A6A)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),

        // ── Data: live or offline cache ───────────────────────────────────────
        data: (result) {
          final records = result.data;

          // Build the main content widget (empty-state or list)
          Widget content;

          if (records.isEmpty) {
            content = Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006A6A).withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.folder_open_outlined,
                        size: 64,
                        color: Color(0xFF006A6A),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Medical Records Found',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You do not have any consultation records yet. '
                      'Records and prescriptions created by clinic doctors will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => ref.refresh(patientRecordsProvider),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Check for Updates'),
                    ),
                  ],
                ),
              ),
            );
          } else {
            content = RefreshIndicator(
              color: const Color(0xFF006A6A),
              onRefresh: () async => ref.refresh(patientRecordsProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final recordId = record['id']?.toString() ?? '';
                  final diagnosis =
                      record['diagnosis']?.toString() ?? 'General Consultation';
                  final visitDate = record['visit_date']?.toString() ??
                      record['created_at']?.toString();
                  final doctorMap = record['doctor'] as Map<String, dynamic>?;
                  final doctorName =
                      doctorMap?['name']?.toString() ?? 'Attending Doctor';
                  final prescriptions =
                      (record['prescriptions'] as List<dynamic>?) ?? [];
                  final hasReport = record['report_file_url'] != null &&
                      record['report_file_url'].toString().trim().isNotEmpty;

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.push('/records/$recordId', extra: record),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date badge + doctor row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF006A6A)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.event,
                                          size: 13, color: Color(0xFF006A6A)),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(visitDate),
                                        style: const TextStyle(
                                          color: Color(0xFF006A6A),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline,
                                        size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text(
                                      doctorName.startsWith('Dr.')
                                          ? doctorName
                                          : 'Dr. $doctorName',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Diagnosis title
                            Text(
                              diagnosis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),

                            // Chips row
                            Row(
                              children: [
                                if (prescriptions.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: Colors.teal.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.medication_outlined,
                                            size: 13,
                                            color: Colors.teal.shade800),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${prescriptions.length} Meds',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (hasReport)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.orange.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.attachment,
                                            size: 13,
                                            color: Colors.orange.shade900),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Report Attached',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const Spacer(),
                                const Icon(Icons.chevron_right,
                                    size: 18, color: Colors.grey),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }

          // Wrap content with offline banner when serving from cache
          if (result.isOffline) {
            return Column(
              children: [
                OfflineBanner(lastUpdated: result.lastUpdated),
                Expanded(child: content),
              ],
            );
          }

          return content;
        },
      ),
    );
  }
}
