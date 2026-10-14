import 'dart:convert';
import 'package:flutter/material.dart';

/// Shows a preview of the patient message before sending.
/// Displays the pictogram chart, spoken text with English glosses,
/// language fallback warnings, and any blockers that prevent sending.
class PatientMessagePreviewDialog extends StatelessWidget {
  final Map<String, dynamic> previewData;

  const PatientMessagePreviewDialog({
    super.key,
    required this.previewData,
  });

  @override
  Widget build(BuildContext context) {
    final segments = previewData['segments'] as List? ?? [];
    final chartDataUri = previewData['chart']?.toString();
    final languageUsed = previewData['language_used']?.toString() ?? 'en';
    final requestedLanguage = previewData['requested_language']?.toString();
    final supported = previewData['supported'] as bool? ?? true;
    final blockers = previewData['blockers'] as List? ?? [];

    final hasBlockers = blockers.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF006D77),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Message Preview',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language warning banner
                    if (!supported && requestedLanguage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$requestedLanguage is not available — sending in English',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Blockers (fail-closed warnings)
                    if (hasBlockers) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.block, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Cannot send message',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final blocker in blockers)
                              Padding(
                                padding: const EdgeInsets.only(left: 30, top: 4),
                                child: Text(
                                  '• ${blocker.toString()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Pictogram chart
                    if (chartDataUri != null) ...[
                      const Text(
                        'Visual Schedule',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Center(
                          child: _buildChartImage(chartDataUri),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Audio segments
                    if (segments.isNotEmpty) ...[
                      const Text(
                        'Voice Instructions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Patient will receive ${segments.length} voice note${segments.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < segments.length; i++)
                        _buildSegmentCard(segments[i] as Map<String, dynamic>, i + 1, languageUsed),
                    ],
                  ],
                ),
              ),
            ),

            // Footer actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: hasBlockers ? null : () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send),
                    label: const Text('Send to Patient'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartImage(String dataUri) {
    try {
      // Data URI format: data:image/png;base64,<base64data>
      if (dataUri.startsWith('data:image/png;base64,')) {
        final base64Data = dataUri.substring('data:image/png;base64,'.length);
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Chart preview unavailable',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          },
        );
      } else {
        return Text(
          'Invalid chart format',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        );
      }
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Failed to load chart',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSegmentCard(Map<String, dynamic> segment, int index, String language) {
    final text = segment['text']?.toString() ?? '';
    final gloss = segment['gloss']?.toString();
    final key = segment['key']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF006D77).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF006D77),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.volume_up, size: 18, color: Color(0xFF006D77)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Main text in target language
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF2B2D42),
              ),
            ),
          ),
          // English gloss
          if (gloss != null && gloss.isNotEmpty && language != 'en') ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'English: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Expanded(
                  child: Text(
                    gloss,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
