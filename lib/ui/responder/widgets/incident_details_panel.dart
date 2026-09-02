import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/incident_model.dart';
import '../../../core/services/responder_service.dart';
import '../../../core/triage/severity_engine.dart';
import 'empty_state_view.dart';

class IncidentDetailsPanel extends StatefulWidget {
  const IncidentDetailsPanel({super.key});

  @override
  State<IncidentDetailsPanel> createState() => _IncidentDetailsPanelState();
}

class _IncidentDetailsPanelState extends State<IncidentDetailsPanel> {
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customUnitController = TextEditingController();
  bool _isUpdating = false;

  @override
  void dispose() {
    _notesController.dispose();
    _customUnitController.dispose();
    super.dispose();
  }

  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
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

  Future<void> _handleAssign(IncidentModel incident) async {
    final session = ResponderAuthSession.instance;
    final responderCallSign = session.responderCallSign;

    setState(() => _isUpdating = true);
    try {
      await ResponderService.instance.assignIncident(
        incidentId: incident.id,
        responderId: responderCallSign,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incident ${incident.id.substring(0, 8)} assigned to $responderCallSign'),
            backgroundColor: const Color(0xFF2563EB),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assignment failed: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _handleEnRoute(IncidentModel incident) async {
    final session = ResponderAuthSession.instance;
    final responderCallSign = incident.assignedTo ?? session.responderCallSign;

    setState(() => _isUpdating = true);
    try {
      await ResponderService.instance.markEnRoute(
        incidentId: incident.id,
        responderId: responderCallSign,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unit $responderCallSign marked EN ROUTE to incident.'),
            backgroundColor: const Color(0xFF7C3AED),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _showResolveDialog(IncidentModel incident) async {
    _notesController.clear();
    final session = ResponderAuthSession.instance;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Text('Mark Incident Resolved', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm resolution for SOS: ${incident.id}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Field Resolution Notes (Optional):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Victims extricated safely, first aid rendered, site cleared.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                setState(() => _isUpdating = true);
                try {
                  await ResponderService.instance.resolveIncident(
                    incidentId: incident.id,
                    responderId: incident.assignedTo ?? session.responderCallSign,
                    notes: _notesController.text.trim(),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Incident successfully resolved and archived.'),
                        backgroundColor: Color(0xFF16A34A),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Resolution failed: $e'), backgroundColor: const Color(0xFFDC2626)),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isUpdating = false);
                }
              },
              child: const Text('Confirm Resolution'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final responderService = ResponderService.instance;

    return ListenableBuilder(
      listenable: responderService,
      builder: (context, _) {
        final incident = responderService.selectedIncident;

        if (incident == null) {
          return const ResponderEmptyStateView(
            title: 'No Incident Selected',
            message: 'Select an SOS emergency report from the priority queue or map to inspect dossier and dispatch response.',
            icon: Icons.touch_app_outlined,
          );
        }

        final tierColor = _getTierColor(incident.priorityTier);
        final triageResult = SeverityEngine.triage(
          description: incident.payload ?? '',
          needType: incident.needType ?? '',
        );

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              left: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Panel Header Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.06),
                  border: Border(
                    bottom: BorderSide(color: tierColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tierColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            incident.priorityTier.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Score ${incident.priorityScore}/10',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: tierColor,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                          onPressed: () => responderService.selectIncident(null),
                          tooltip: 'Close Dossier',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SOS Report ID: ${incident.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Dossier Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Workflow Stepper
                      _buildStatusStepper(incident),
                      const SizedBox(height: 20),

                      // Emergency Description Section
                      const Text(
                        'EMERGENCY SITUATION REPORT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          incident.payload?.isNotEmpty == true
                              ? incident.payload!
                              : 'No textual description provided by sender.',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Triage Engine Diagnosis
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF), // Blue 50
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.psychology, size: 16, color: Color(0xFF2563EB)),
                                SizedBox(width: 6),
                                Text(
                                  'Automated Triage Analysis',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              triageResult.explanation,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            if (triageResult.matchedKeywords.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children: triageResult.matchedKeywords.map((kw) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF93C5FD)),
                                    ),
                                    child: Text(
                                      kw,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Geospatial Coordinates Section
                      const Text(
                        'LOCATION & GEODATA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              incident.hasCoordinates ? Icons.location_on : Icons.location_off,
                              size: 20,
                              color: incident.hasCoordinates ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    incident.hasCoordinates
                                        ? '${incident.lat!.toStringAsFixed(6)}, ${incident.lng!.toStringAsFixed(6)}'
                                        : 'No GPS Coordinates Available',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  Text(
                                    incident.hasCoordinates ? 'Stored from Victim Node GPS' : 'Mesh broadcast without location fix',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            if (incident.hasCoordinates)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 16, color: Color(0xFF64748B)),
                                tooltip: 'Copy Coordinates',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: '${incident.lat}, ${incident.lng}'));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Coordinates copied to clipboard')),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Network & Mesh Provenance
                      const Text(
                        'MESH & CLOUD PROVENANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _MetadataRow(label: 'Origin Sender Node', value: incident.senderId),
                            const SizedBox(height: 6),
                            _MetadataRow(
                              label: 'Mesh Relay Hops',
                              value: incident.hopCount == 0 ? '0 (Direct / Origin Node)' : '${incident.hopCount} Hops Relayed',
                            ),
                            if (incident.bridgeDeviceId != null) ...[
                              const SizedBox(height: 6),
                              _MetadataRow(label: 'Cloud Bridge Node', value: incident.bridgeDeviceId!),
                            ],
                            const SizedBox(height: 6),
                            _MetadataRow(
                              label: 'Report Timestamp',
                              value: DateTime.fromMillisecondsSinceEpoch(incident.timestamp).toLocal().toString().substring(0, 19),
                            ),
                          ],
                        ),
                      ),

                      // Resolution Notes Display (if resolved)
                      if (incident.isResolved && incident.resolutionNotes != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'FIELD RESOLUTION DOSSIER',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16A34A),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.verified, size: 16, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Resolved by ${incident.assignedTo ?? "Responder Unit"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                incident.resolutionNotes!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF14532D),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Action Buttons Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: _buildActionButtons(incident),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusStepper(IncidentModel incident) {
    int currentStep = 0;
    if (incident.isOpen) currentStep = 0;
    if (incident.isAssigned) currentStep = 1;
    if (incident.isEnRoute) currentStep = 2;
    if (incident.isResolved) currentStep = 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepCircle(step: 1, label: 'Open', isActive: currentStep >= 0, isCurrent: currentStep == 0),
              _StepLine(isActive: currentStep >= 1),
              _StepCircle(step: 2, label: 'Assigned', isActive: currentStep >= 1, isCurrent: currentStep == 1),
              _StepLine(isActive: currentStep >= 2),
              _StepCircle(step: 3, label: 'En Route', isActive: currentStep >= 2, isCurrent: currentStep == 2),
              _StepLine(isActive: currentStep >= 3),
              _StepCircle(step: 4, label: 'Resolved', isActive: currentStep >= 3, isCurrent: currentStep == 3),
            ],
          ),
          if (incident.assignedTo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Assigned Unit: ${incident.assignedTo}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2563EB),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(IncidentModel incident) {
    if (_isUpdating) {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
        ),
      );
    }

    if (incident.isOpen) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB), // Blue 600
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.assignment_ind_outlined, size: 18),
              label: const Text('Assign Response Unit', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => _handleAssign(incident),
            ),
          ),
        ],
      );
    }

    if (incident.isAssigned) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED), // Purple 600
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.directions_run_outlined, size: 18),
              label: const Text('Deploy Unit / En Route', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => _handleEnRoute(incident),
            ),
          ),
        ],
      );
    }

    if (incident.isEnRoute) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A), // Green 600
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Mark Incident Resolved', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => _showResolveDialog(incident),
            ),
          ),
        ],
      );
    }

    // Resolved state
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, color: Color(0xFF16A34A), size: 20),
          SizedBox(width: 8),
          Text(
            'Incident Successfully Resolved',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int step;
  final String label;
  final bool isActive;
  final bool isCurrent;

  const _StepCircle({
    required this.step,
    required this.label,
    required this.isActive,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFFCBD5E1);
    Color fg = const Color(0xFF64748B);

    if (isActive) {
      bg = isCurrent ? const Color(0xFFDC2626) : const Color(0xFF0F172A);
      fg = Colors.white;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool isActive;

  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: isActive ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
