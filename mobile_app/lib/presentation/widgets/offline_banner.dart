import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Small, non-intrusive banner shown when displaying cached offline data.
class OfflineBanner extends StatelessWidget {
  final DateTime? lastUpdated;

  const OfflineBanner({super.key, this.lastUpdated});

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'earlier';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF3CD), // Soft warm amber
        border: Border(
          bottom: BorderSide(color: Color(0xFFFFEEBA)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: Color(0xFF856404),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing offline data • Last updated ${_formatTimestamp(lastUpdated)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF856404),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
