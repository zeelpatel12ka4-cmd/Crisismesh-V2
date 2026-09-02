import 'package:flutter/material.dart';
import '../../../core/services/responder_service.dart';
import 'empty_state_view.dart';
import 'incident_card.dart';

class IncidentQueueList extends StatefulWidget {
  const IncidentQueueList({super.key});

  @override
  State<IncidentQueueList> createState() => _IncidentQueueListState();
}

class _IncidentQueueListState extends State<IncidentQueueList> {
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'All',
    'medical',
    'trapped',
    'fire',
    'water',
    'food',
    'shelter',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responderService = ResponderService.instance;

    return ListenableBuilder(
      listenable: responderService,
      builder: (context, _) {
        if (responderService.isLoading) {
          return const ResponderLoadingView(
            label: 'Streaming real-time incident queue...',
          );
        }

        if (responderService.errorMessage != null && responderService.allIncidents.isEmpty) {
          return ResponderEmptyStateView(
            title: 'Connection Issue',
            message: responderService.errorMessage!,
            icon: Icons.cloud_off,
            iconColor: const Color(0xFFDC2626),
            actionLabel: 'Retry Stream',
            onAction: () => responderService.init(),
          );
        }

        final incidents = responderService.filteredIncidents;
        final selectedIncident = responderService.selectedIncident;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              right: BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search & Filter Header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => responderService.setSearchQuery(val),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search keyword, victim ID, triage...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  responderService.setSearchQuery('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Tier Filters Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All Tiers',
                            isSelected: responderService.selectedTierFilter == 'All',
                            onTap: () => responderService.setTierFilter('All'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '🔴 Critical',
                            isSelected: responderService.selectedTierFilter == 'Critical',
                            onTap: () => responderService.setTierFilter('Critical'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '🟠 Urgent',
                            isSelected: responderService.selectedTierFilter == 'Urgent',
                            onTap: () => responderService.setTierFilter('Urgent'),
                          ),
                          const SizedBox(width: 6),
                          _FilterChip(
                            label: '🟡 Needs',
                            isSelected: responderService.selectedTierFilter == 'Needs',
                            onTap: () => responderService.setTierFilter('Needs'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Status & Category Row
                    Row(
                      children: [
                        // Status Filter Dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: responderService.selectedStatusFilter,
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              labelText: 'Status',
                            ),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                            items: const [
                              DropdownMenuItem(value: 'Active', child: Text('Active Queue')),
                              DropdownMenuItem(value: 'All', child: Text('All Statuses')),
                              DropdownMenuItem(value: 'open', child: Text('Open / Pending')),
                              DropdownMenuItem(value: 'assigned', child: Text('Assigned')),
                              DropdownMenuItem(value: 'en_route', child: Text('En Route')),
                              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                            ],
                            onChanged: (val) {
                              if (val != null) responderService.setStatusFilter(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Category Filter Dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: responderService.selectedCategoryFilter,
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              labelText: 'Need Category',
                            ),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                            items: _categories.map((c) {
                              return DropdownMenuItem(
                                value: c,
                                child: Text(c == 'All' ? 'All Needs' : c.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) responderService.setCategoryFilter(val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Queue Count Sub-Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${incidents.length} Incident${incidents.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Priority Sorted',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              // Incidents List
              Expanded(
                child: incidents.isEmpty
                    ? ResponderEmptyStateView(
                        title: 'No Matching Incidents',
                        message: 'No reports match your current filter and search criteria.',
                        icon: Icons.filter_list_off,
                        actionLabel: 'Reset Filters',
                        onAction: () {
                          _searchController.clear();
                          responderService.setSearchQuery('');
                          responderService.setTierFilter('All');
                          responderService.setStatusFilter('Active');
                          responderService.setCategoryFilter('All');
                        },
                      )
                    : ListView.builder(
                        itemCount: incidents.length,
                        itemBuilder: (context, index) {
                          final incident = incidents[index];
                          final isSelected = selectedIncident?.id == incident.id;

                          return IncidentCard(
                            incident: incident,
                            isSelected: isSelected,
                            onTap: () => responderService.selectIncident(incident),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
