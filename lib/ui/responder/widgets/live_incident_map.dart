import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_model.dart';
import '../../../core/services/responder_service.dart';

class LiveIncidentMap extends StatefulWidget {
  const LiveIncidentMap({super.key});

  @override
  State<LiveIncidentMap> createState() => _LiveIncidentMapState();
}

class _LiveIncidentMapState extends State<LiveIncidentMap> {
  final MapController _mapController = MapController();

  // Default disaster zone coordinates (fallback center)
  static const LatLng _defaultCenter = LatLng(23.2874, 72.3464);

  @override
  Widget build(BuildContext context) {
    final responderService = ResponderService.instance;

    return ListenableBuilder(
      listenable: responderService,
      builder: (context, _) {
        final allIncidents = responderService.filteredIncidents;
        final geoIncidents = allIncidents.where((i) => i.hasCoordinates).toList();
        final noGeoCount = allIncidents.length - geoIncidents.length;
        final selected = responderService.selectedIncident;

        // Compute initial center
        LatLng center = _defaultCenter;
        if (selected != null && selected.hasCoordinates) {
          center = LatLng(selected.lat!, selected.lng!);
        } else if (geoIncidents.isNotEmpty) {
          center = LatLng(geoIncidents.first.lat!, geoIncidents.first.lng!);
        }

        // Build markers
        final markers = geoIncidents.map((incident) {
          final isSelected = selected?.id == incident.id;
          final point = LatLng(incident.lat!, incident.lng!);

          return Marker(
            point: point,
            width: isSelected ? 48 : 36,
            height: isSelected ? 48 : 36,
            child: GestureDetector(
              onTap: () {
                responderService.selectIncident(incident);
                _mapController.move(point, 15.0);
              },
              child: _buildMapPin(incident, isSelected),
            ),
          );
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrowMap = constraints.maxWidth < 450;

            return Stack(
              children: [
                // FlutterMap Canvas
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 13.5,
                    minZoom: 4.0,
                    maxZoom: 18.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.crisismesh.commandcenter',
                      maxZoom: 19,
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),

                // Top Status Bar: GPS Metrics & Legend
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // GPS Status Pill
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.satellite_alt, size: 14, color: Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${geoIncidents.length} Mapped',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (noGeoCount > 0 && !isNarrowMap) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$noGeoCount No GPS',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Quick Legend (collapses on narrow views)
                      if (!isNarrowMap)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _LegendDot(color: Color(0xFFDC2626), label: 'Crit'),
                              SizedBox(width: 6),
                              _LegendDot(color: Color(0xFFEA580C), label: 'Urg'),
                              SizedBox(width: 6),
                              _LegendDot(color: Color(0xFFD97706), label: 'Need'),
                              SizedBox(width: 6),
                              _LegendDot(color: Color(0xFF16A34A), label: 'Done'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Map Navigation Controls (Zoom & Recenter)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Recenter Button
                      FloatingActionButton.small(
                        heroTag: 'map_recenter',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        tooltip: 'Recenter to active incidents',
                        onPressed: () {
                          if (geoIncidents.isNotEmpty) {
                            _mapController.move(LatLng(geoIncidents.first.lat!, geoIncidents.first.lng!), 14.0);
                          } else {
                            _mapController.move(_defaultCenter, 13.0);
                          }
                        },
                        child: const Icon(Icons.my_location, size: 18),
                      ),
                      const SizedBox(height: 8),

                      // Zoom In
                      FloatingActionButton.small(
                        heroTag: 'map_zoom_in',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        tooltip: 'Zoom in',
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom + 1);
                        },
                        child: const Icon(Icons.add, size: 18),
                      ),
                      const SizedBox(height: 6),

                      // Zoom Out
                      FloatingActionButton.small(
                        heroTag: 'map_zoom_out',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        tooltip: 'Zoom out',
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom - 1);
                        },
                        child: const Icon(Icons.remove, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMapPin(IncidentModel incident, bool isSelected) {
    Color pinColor;
    if (incident.isResolved) {
      pinColor = const Color(0xFF16A34A); // Emerald
    } else {
      switch (incident.priorityTier.toLowerCase()) {
        case 'critical':
          pinColor = const Color(0xFFDC2626); // Red
          break;
        case 'urgent':
          pinColor = const Color(0xFFEA580C); // Orange
          break;
        case 'needs':
          pinColor = const Color(0xFFD97706); // Amber
          break;
        default:
          pinColor = const Color(0xFF64748B);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: pinColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
          width: isSelected ? 3.0 : 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: pinColor.withValues(alpha: 0.4),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          _getCategoryIcon(incident.needType),
          size: isSelected ? 22 : 16,
          color: Colors.white,
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String? needType) {
    switch ((needType ?? '').toLowerCase()) {
      case 'medical':
        return Icons.medical_services;
      case 'trapped':
        return Icons.person_off;
      case 'fire':
        return Icons.local_fire_department;
      case 'water':
        return Icons.water_drop;
      case 'food':
        return Icons.restaurant;
      case 'shelter':
        return Icons.home_work;
      default:
        return Icons.emergency;
    }
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
        ),
      ],
    );
  }
}
