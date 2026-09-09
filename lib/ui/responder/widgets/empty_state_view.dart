import 'package:flutter/material.dart';
import '../../../core/services/responder_service.dart';

/// Clean, professional empty, loading, offline, and error states for Responder Command Center
class ResponderEmptyStateView extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onAction;
  final String? actionLabel;

  const ResponderEmptyStateView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.iconColor = const Color(0xFF64748B),
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading shimmer / indicator card for lists and panels
class ResponderLoadingView extends StatelessWidget {
  final String label;

  const ResponderLoadingView({
    super.key,
    this.label = 'Connecting to Firestore real-time stream...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Non-intrusive banner indicating Firestore connection issues
class ResponderOfflineBanner extends StatelessWidget {
  final ResponderConnectionState? state;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const ResponderOfflineBanner({
    super.key,
    this.state,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPermission = state == ResponderConnectionState.permissionDenied;
    final bool isUnavailable = state == ResponderConnectionState.serviceUnavailable;

    final Color bgColor = isPermission ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
    final Color borderColor = isPermission ? const Color(0xFFFECACA) : const Color(0xFFFDE68A);
    final Color textColor = isPermission ? const Color(0xFF991B1B) : const Color(0xFF92400E);
    final Color btnColor = isPermission ? const Color(0xFFDC2626) : const Color(0xFFB45309);
    final IconData icon = isPermission
        ? Icons.lock_outline_rounded
        : (isUnavailable ? Icons.sync_problem_rounded : Icons.cloud_off_rounded);

    final String text = isPermission
        ? 'Security Rules Denied: Missing permissions for /sos_reports. Remote real-time updates blocked.'
        : (isUnavailable
            ? 'Cloud Service Unavailable: Unable to reach Cloud Firestore servers. Retrying...'
            : 'Offline Mode: No Internet connection. Reading cached reports from local store.');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: btnColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: btnColor,
              ),
              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
