import 'package:flutter/material.dart';
import '../../../core/models/incident_model.dart';

class IncidentCard extends StatelessWidget {
  final IncidentModel incident;
  final bool isSelected;
  final VoidCallback onTap;

  const IncidentCard({
    super.key,
    required this.incident,
    required this.isSelected,
    required this.onTap,
  });

  Color _getTierColor() {
    switch (incident.priorityTier.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626); // Red 600
      case 'urgent':
        return const Color(0xFFEA580C); // Orange 600
      case 'needs':
        return const Color(0xFFD97706); // Amber 600
      default:
        return const Color(0xFF64748B); // Slate 500
    }
  }

  Color _getStatusColor() {
    switch (incident.status.toLowerCase()) {
      case IncidentStatus.open:
        return const Color(0xFF64748B);
      case IncidentStatus.assigned:
        return const Color(0xFF2563EB); // Blue 600
      case IncidentStatus.enRoute:
        return const Color(0xFF7C3AED); // Purple 600
      case IncidentStatus.resolved:
        return const Color(0xFF16A34A); // Emerald 600
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _getCategoryIcon() {
    switch ((incident.needType ?? '').toLowerCase()) {
      case 'medical':
        return Icons.medical_services_outlined;
      case 'trapped':
        return Icons.person_off_outlined;
      case 'fire':
        return Icons.local_fire_department_outlined;
      case 'water':
        return Icons.water_drop_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'shelter':
        return Icons.home_work_outlined;
      default:
        return Icons.crisis_alert;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor();
    final statusColor = _getStatusColor();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? tierColor : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: tierColor.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Tier Pill, Score, Need Category, Time ago
            Row(
              children: [
                // Tier & Score Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getCategoryIcon(), size: 12, color: tierColor),
                      const SizedBox(width: 3),
                      Text(
                        '${incident.priorityTier.toUpperCase()} (${incident.priorityScore})',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: tierColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Category Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    incident.needType?.toUpperCase() ?? 'GENERAL',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                const Spacer(),

                // Time ago
                Text(
                  incident.formattedTimeAgo,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Description Payload
            Text(
              incident.payload?.isNotEmpty == true ? incident.payload! : 'Emergency SOS broadcast received without description.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: const Color(0xFF0F172A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),

            // Bottom Row: Status Badge, Hop Count, GPS indicator
            Row(
              children: [
                // Status Pill
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            incident.isAssigned && incident.assignedTo != null
                                ? 'Assigned (${incident.assignedTo})'
                                : IncidentStatus.format(incident.status),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Hop Count Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hub, size: 10, color: Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Text(
                        incident.hopCount == 0 ? 'Direct' : '${incident.hopCount}h',
                        style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Phase 7 Authenticity Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: incident.authenticityStatus == 'verified'
                        ? const Color(0xFFF0FDF4)
                        : (incident.authenticityStatus == 'invalid_signature'
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: incident.authenticityStatus == 'verified'
                          ? const Color(0xFFBBF7D0)
                          : (incident.authenticityStatus == 'invalid_signature'
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFE2E8F0)),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        incident.authenticityStatus == 'verified'
                            ? Icons.verified_rounded
                            : (incident.authenticityStatus == 'invalid_signature'
                                ? Icons.gpp_bad_rounded
                                : Icons.shield_outlined),
                        size: 10,
                        color: incident.authenticityStatus == 'verified'
                            ? const Color(0xFF15803D)
                            : (incident.authenticityStatus == 'invalid_signature'
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        incident.authenticityStatus == 'verified'
                            ? 'Verified'
                            : (incident.authenticityStatus == 'invalid_signature'
                                ? 'Tampered'
                                : 'Unverified'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: incident.authenticityStatus == 'verified'
                              ? const Color(0xFF15803D)
                              : (incident.authenticityStatus == 'invalid_signature'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // GPS Indicator
                if (incident.hasCoordinates)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 12, color: Color(0xFF10B981)),
                      SizedBox(width: 2),
                      Text(
                        'GPS',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  )
                else
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: 12, color: Color(0xFF94A3B8)),
                      SizedBox(width: 2),
                      Text(
                        'No GPS',
                        style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
