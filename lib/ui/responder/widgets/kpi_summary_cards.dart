import 'package:flutter/material.dart';
import '../../../core/services/responder_service.dart';

class KpiSummaryCards extends StatelessWidget {
  const KpiSummaryCards({super.key});

  @override
  Widget build(BuildContext context) {
    final responderService = ResponderService.instance;

    return ListenableBuilder(
      listenable: responderService,
      builder: (context, _) {
        final criticalCount = responderService.criticalCount;
        final urgentCount = responderService.urgentCount;
        final needsCount = responderService.needsCount;
        final resolvedCount = responderService.resolvedCount;
        final totalActive = responderService.totalActiveCount;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _KpiCard(
                  label: 'CRITICAL',
                  count: criticalCount,
                  sublabel: 'Tier 1 • Score 9-10',
                  icon: Icons.emergency,
                  color: const Color(0xFFDC2626), // Red 600
                  isSelected: responderService.selectedTierFilter.toLowerCase() == 'critical',
                  onTap: () {
                    if (responderService.selectedTierFilter.toLowerCase() == 'critical') {
                      responderService.setTierFilter('All');
                    } else {
                      responderService.setTierFilter('Critical');
                      responderService.setStatusFilter('Active');
                    }
                  },
                ),
                const SizedBox(width: 10),
                _KpiCard(
                  label: 'URGENT',
                  count: urgentCount,
                  sublabel: 'Tier 2 • Score 6-8',
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFEA580C), // Orange 600
                  isSelected: responderService.selectedTierFilter.toLowerCase() == 'urgent',
                  onTap: () {
                    if (responderService.selectedTierFilter.toLowerCase() == 'urgent') {
                      responderService.setTierFilter('All');
                    } else {
                      responderService.setTierFilter('Urgent');
                      responderService.setStatusFilter('Active');
                    }
                  },
                ),
                const SizedBox(width: 10),
                _KpiCard(
                  label: 'NEEDS',
                  count: needsCount,
                  sublabel: 'Tier 3 • Score 3-5',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFFD97706), // Amber 600
                  isSelected: responderService.selectedTierFilter.toLowerCase() == 'needs',
                  onTap: () {
                    if (responderService.selectedTierFilter.toLowerCase() == 'needs') {
                      responderService.setTierFilter('All');
                    } else {
                      responderService.setTierFilter('Needs');
                      responderService.setStatusFilter('Active');
                    }
                  },
                ),
                const SizedBox(width: 10),
                _KpiCard(
                  label: 'RESOLVED',
                  count: resolvedCount,
                  sublabel: 'Closed / Handled',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF16A34A), // Emerald 600
                  isSelected: responderService.selectedStatusFilter.toLowerCase() == 'resolved',
                  onTap: () {
                    if (responderService.selectedStatusFilter.toLowerCase() == 'resolved') {
                      responderService.setStatusFilter('Active');
                    } else {
                      responderService.setStatusFilter('resolved');
                      responderService.setTierFilter('All');
                    }
                  },
                ),
                const SizedBox(width: 10),
                _KpiCard(
                  label: 'ACTIVE QUEUE',
                  count: totalActive,
                  sublabel: 'Pending Response',
                  icon: Icons.list_alt,
                  color: const Color(0xFF0F172A), // Slate 900
                  isSelected: responderService.selectedStatusFilter == 'Active' &&
                      responderService.selectedTierFilter == 'All',
                  onTap: () {
                    responderService.setStatusFilter('Active');
                    responderService.setTierFilter('All');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final int count;
  final String sublabel;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _KpiCard({
    required this.label,
    required this.count,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(minWidth: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? color : const Color(0xFF64748B),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
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
