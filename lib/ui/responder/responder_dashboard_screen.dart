import 'package:flutter/material.dart';
import '../../core/services/responder_service.dart';
import 'responder_auth_dialog.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/incident_details_panel.dart';
import 'widgets/incident_queue_list.dart';
import 'widgets/kpi_summary_cards.dart';
import 'widgets/live_incident_map.dart';
import 'widgets/responder_header.dart';

class ResponderDashboardScreen extends StatefulWidget {
  final ResponderDataProvider? customProvider;

  const ResponderDashboardScreen({
    super.key,
    this.customProvider,
  });

  @override
  State<ResponderDashboardScreen> createState() => _ResponderDashboardScreenState();
}

class _ResponderDashboardScreenState extends State<ResponderDashboardScreen> {
  int _mobileSelectedTabIndex = 0; // 0: Queue, 1: Map, 2: Details
  int _tabletSelectedTabIndex = 0; // 0: Map, 1: Details

  @override
  void initState() {
    super.initState();
    // Initialize stream subscription
    ResponderService.instance.init(provider: widget.customProvider);
    ResponderAuthSession.instance.addListener(_onAuthChanged);
    ResponderService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    ResponderAuthSession.instance.removeListener(_onAuthChanged);
    ResponderService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _onServiceChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authSession = ResponderAuthSession.instance;

    // 1. Authorization Gate: require authenticated responder
    if (!authSession.isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: ResponderAuthScreen(
          onAuthenticated: () {
            setState(() {});
          },
        ),
      );
    }

    final responderService = ResponderService.instance;

    // 2. Authenticated Responder Dashboard
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header Bar
            ResponderHeader(
              onRefresh: () => responderService.init(provider: widget.customProvider),
              onLogout: () => authSession.logout(),
            ),

            // Offline Warning Ribbon (if offline)
            if (responderService.isOffline)
              ResponderOfflineBanner(
                onRetry: () => responderService.init(provider: widget.customProvider),
              ),

            // Top KPI Summary Metrics Cards
            const KpiSummaryCards(),

            // Responsive Workspace Area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  // DESKTOP LAYOUT (>= 1100px): 3-Column Split
                  if (width >= 1100) {
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Column: Incident Queue (380px)
                        SizedBox(
                          width: 380,
                          child: IncidentQueueList(),
                        ),

                        // Center Column: Live Geospatial Map (Flex 1)
                        Expanded(
                          child: LiveIncidentMap(),
                        ),

                        // Right Column: Incident Dossier & Status Stepper (400px)
                        SizedBox(
                          width: 400,
                          child: IncidentDetailsPanel(),
                        ),
                      ],
                    );
                  }

                  // TABLET LAYOUT (768px - 1099px): 2-Column with Tabbed Map/Details
                  if (width >= 768) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Column: Incident Queue (350px)
                        const SizedBox(
                          width: 350,
                          child: IncidentQueueList(),
                        ),

                        // Right Column: Tabbed View (Map / Details)
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                color: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    _TabletTabButton(
                                      label: '🗺️ Live Map',
                                      isSelected: _tabletSelectedTabIndex == 0,
                                      onTap: () => setState(() => _tabletSelectedTabIndex = 0),
                                    ),
                                    const SizedBox(width: 8),
                                    _TabletTabButton(
                                      label: '📋 Incident Dossier',
                                      isSelected: _tabletSelectedTabIndex == 1,
                                      onTap: () => setState(() => _tabletSelectedTabIndex = 1),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              Expanded(
                                child: _tabletSelectedTabIndex == 0
                                    ? const LiveIncidentMap()
                                    : const IncidentDetailsPanel(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  // MOBILE / COMPACT WEB (< 768px): Single-Column with Bottom / Segmented Tabs
                  return Column(
                    children: [
                      // View Switcher Bar
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _MobileTabItem(
                                icon: Icons.format_list_bulleted,
                                label: 'Queue',
                                isSelected: _mobileSelectedTabIndex == 0,
                                onTap: () => setState(() => _mobileSelectedTabIndex = 0),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MobileTabItem(
                                icon: Icons.map_outlined,
                                label: 'Live Map',
                                isSelected: _mobileSelectedTabIndex == 1,
                                onTap: () => setState(() => _mobileSelectedTabIndex = 1),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MobileTabItem(
                                icon: Icons.description_outlined,
                                label: 'Dossier',
                                isSelected: _mobileSelectedTabIndex == 2,
                                onTap: () => setState(() => _mobileSelectedTabIndex = 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),

                      // Active View
                      Expanded(
                        child: IndexedStack(
                          index: _mobileSelectedTabIndex,
                          children: const [
                            IncidentQueueList(),
                            LiveIncidentMap(),
                            IncidentDetailsPanel(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletTabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabletTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

class _MobileTabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MobileTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
