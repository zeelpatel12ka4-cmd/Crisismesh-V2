import 'package:flutter/material.dart';
import '../../../core/services/responder_service.dart';

class ResponderHeader extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  const ResponderHeader({
    super.key,
    required this.onRefresh,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final session = ResponderAuthSession.instance;
    final profile = session.currentProfile;
    final responderService = ResponderService.instance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 680;
          final isVeryCompact = constraints.maxWidth < 480;

          return Row(
            children: [
              // Logo & Title
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.crisis_alert,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CRISIS MESH',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!isVeryCompact)
                    const Text(
                      'Responder Command Center',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
              const Spacer(),

              // Live Firestore Stream Badge
              if (!isCompact) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: responderService.isOffline
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: responderService.isOffline
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: responderService.isOffline
                              ? const Color(0xFFD97706)
                              : const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        responderService.isOffline ? 'Offline' : 'Live Stream',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: responderService.isOffline
                              ? const Color(0xFF92400E)
                              : const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Responder Profile Badge (Desktop & Tablet)
              if (profile != null && !isCompact) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield, size: 14, color: Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Text(
                        profile.callSign,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],

              // Refresh Button
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF475569)),
                tooltip: 'Refresh Stream',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onRefresh,
              ),

              // Logout Button
              IconButton(
                icon: const Icon(Icons.logout, size: 18, color: Color(0xFF64748B)),
                tooltip: 'Exit Command Center',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onLogout,
              ),
            ],
          );
        },
      ),
    );
  }
}
