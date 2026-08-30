import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/database/database_service.dart';
import '../core/models/message_model.dart';
import '../core/triage/severity_engine.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _uuid = const Uuid();
  final _descriptionController = TextEditingController();
  final String _deviceId = 'DEV-${const Uuid().v4().substring(0, 8)}';

  String _selectedCategory = 'medical';
  double? _latitude;
  double? _longitude;
  bool _isFetchingLocation = false;
  bool _useDemoLocation = false;

  // Real-time triage status
  int _currentScore = 1;
  String _currentTier = 'Low';
  List<String> _matchedKeywords = [];
  String _explanation = 'No critical keywords matched -> LOW/UNCLASSIFIED';

  // Persistence list
  List<MessageModel> _messageHistory = [];

  // Dropdown categories as per specification
  final List<String> _categories = [
    'medical',
    'trapped',
    'fire',
    'water',
    'food',
    'shelter',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessageHistory();
    _descriptionController.addListener(_onDescriptionChanged);
    _fetchLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Reload the message list from the database.
  Future<void> _loadMessageHistory() async {
    final list = await DatabaseService.instance.getMessages();
    setState(() {
      _messageHistory = list;
    });
  }

  /// Triggered whenever description text changes to compute real-time triage.
  void _onDescriptionChanged() {
    final triageResult = SeverityEngine.triage(
      description: _descriptionController.text,
      needType: _selectedCategory,
    );

    setState(() {
      _currentScore = triageResult.score;
      _currentTier = triageResult.tier;
      _matchedKeywords = triageResult.matchedKeywords;
      _explanation = triageResult.explanation;
    });
  }

  /// Refreshes geolocation or checks permission.
  Future<void> _fetchLocation() async {
    if (_useDemoLocation) return;

    setState(() {
      _isFetchingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _isFetchingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _latitude = null;
            _longitude = null;
            _isFetchingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _isFetchingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      ).catchError((_) async {
        return await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 4),
            );
      });

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (e) {
      setState(() {
        _latitude = null;
        _longitude = null;
      });
    } finally {
      setState(() {
        _isFetchingLocation = false;
      });
    }
  }

  /// Sets coordinate mode (GPS vs Mock/Demo)
  void _toggleDemoLocation(bool? value) {
    setState(() {
      _useDemoLocation = value ?? false;
      if (_useDemoLocation) {
        _latitude = 37.7749;
        _longitude = -122.4194;
      } else {
        _latitude = null;
        _longitude = null;
        _fetchLocation();
      }
    });
  }

  /// Creates and saves the SOS report in Phase 1 SQLite structure.
  Future<void> _broadcastSos() async {
    final String description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency details.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // Capture location parameters
    final double? finalLat = _latitude;
    final double? finalLng = _longitude;

    // Run final triage calculations
    final triageResult = SeverityEngine.triage(
      description: description,
      needType: _selectedCategory,
    );

    final sosMessage = MessageModel(
      id: _uuid.v4(),
      type: 'broadcast',
      senderId: _deviceId,
      payload: description,
      needType: _selectedCategory,
      lat: finalLat,
      lng: finalLng,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      hopCount: 0,
      priorityTier: triageResult.tier,
      priorityScore: triageResult.score,
      synced: false,
    );

    await DatabaseService.instance.saveMessage(sosMessage);

    // Show success dialog or snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SOS created locally (Severity Score: ${triageResult.score}/10)'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }

    _descriptionController.clear();
    _loadMessageHistory();
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'Critical':
        return const Color(0xFFEF4444); // Red
      case 'Urgent':
        return const Color(0xFFF97316); // Orange
      case 'Needs':
        return const Color(0xFF3B82F6); // Blue
      default:
        return const Color(0xFF6B7280); // Grey
    }
  }

  Color _getTierBgColor(String tier) {
    switch (tier) {
      case 'Critical':
        return const Color(0xFFFEE2E2); // Soft Red
      case 'Urgent':
        return const Color(0xFFFFEDD5); // Soft Orange
      case 'Needs':
        return const Color(0xFFDBEAFE); // Soft Blue
      default:
        return const Color(0xFFF3F4F6); // Soft Grey
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Crisis Mesh',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4B5563)),
            onPressed: () {
              _loadMessageHistory();
              _fetchLocation();
            },
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Inputs & Controls (Takes up 55% of screen width)
          Expanded(
            flex: 11,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Form Card
                  Card(
                    color: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'REPORT CRISIS INCIDENT',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF374151),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Need Category Dropdown
                          DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: 'Need Category',
                              labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _categories.map((cat) {
                              return DropdownMenuItem<String>(
                                value: cat,
                                child: Text(
                                  cat.toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedCategory = val;
                                  _onDescriptionChanged();
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Incident Details input
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 4,
                            maxLength: 250,
                            style: const TextStyle(color: Color(0xFF111827)),
                            decoration: InputDecoration(
                              labelText: 'Describe the situation...',
                              labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                              alignLabelWithHint: true,
                              hintText: 'Include hazards, number of victims, injuries, etc.',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Real-time Triage Preview Card
                  Card(
                    color: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'OFFLINE TRIAGE ANALYTICS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4B5563),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Score and Tier badges
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: _getTierBgColor(_currentTier),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _getTierColor(_currentTier), width: 1),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Text(
                                  'TIER: ${_currentTier.toUpperCase()}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _getTierColor(_currentTier),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFD1D5DB)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Text(
                                  'SCORE: $_currentScore/10',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Matched Keywords
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Matched Keywords: ',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563)),
                                ),
                                TextSpan(
                                  text: _matchedKeywords.isEmpty
                                      ? 'none'
                                      : _matchedKeywords.join(', '),
                                  style: TextStyle(
                                    color: _matchedKeywords.isEmpty
                                        ? const Color(0xFF6B7280)
                                        : const Color(0xFF111827),
                                    fontWeight: _matchedKeywords.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Rule explanation
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Triage Logic: ',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563)),
                                ),
                                TextSpan(
                                  text: _explanation,
                                  style: const TextStyle(color: Color(0xFF111827)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Location Control Card
                  Card(
                    color: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'LOCATION COORDINATES',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4B5563),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              if (_isFetchingLocation)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4B5563)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Coordinates printout
                          Row(
                            children: [
                              Expanded(
                                child: _buildCoordinateTile(
                                  'LATITUDE',
                                  _latitude != null
                                      ? _latitude!.toStringAsFixed(6)
                                      : 'UNAVAILABLE',
                                  _latitude != null ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCoordinateTile(
                                  'LONGITUDE',
                                  _longitude != null
                                      ? _longitude!.toStringAsFixed(6)
                                      : 'UNAVAILABLE',
                                  _longitude != null ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),

                          // Warnings if GPS is unavailable
                          if (_latitude == null && _longitude == null && !_isFetchingLocation) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB), // Soft yellow warning
                                border: Border.all(color: const Color(0xFFFCD34D)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Real GPS unavailable. Ensure location permissions are active and GPS hardware is turned on.',
                                      style: TextStyle(
                                        color: Color(0xFF92400E),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          // Fetch GPS Button & Demo Switch
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isFetchingLocation ? null : _fetchLocation,
                                icon: const Icon(Icons.my_location, size: 16),
                                label: const Text('GET GPS LOCATION'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF374151),
                                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  const Text(
                                    'Demo Coordinates',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4B5563),
                                    ),
                                  ),
                                  Checkbox(
                                    value: _useDemoLocation,
                                    onChanged: _toggleDemoLocation,
                                    activeColor: const Color(0xFF3B82F6),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Large emergency SOS broadcast button
                  ElevatedButton(
                    onPressed: _broadcastSos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444), // Crimson Red
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.gpp_maybe, size: 24),
                        SizedBox(width: 10),
                        Text(
                          'BROADCAST SOS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Divider between input and history columns
          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE5E7EB)),

          // Right column: Persisted message history (Takes up 45% of screen width)
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LOCAL LOGGED ALERTS',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF374151),
                          letterSpacing: 1.0,
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${_messageHistory.length} reports',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF4B5563)),
                        ),
                        backgroundColor: const Color(0xFFF3F4F6),
                        padding: EdgeInsets.zero,
                      )
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
                Expanded(
                  child: _messageHistory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                'No local reports logged yet.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messageHistory.length,
                          itemBuilder: (context, index) {
                            final msg = _messageHistory[index];
                            return _buildMessageCard(msg);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateTile(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(MessageModel msg) {
    final date = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    final hasLoc = msg.lat != null && msg.lng != null;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Need category
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    msg.needType?.toUpperCase() ?? 'BROADCAST',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),

                // Priority Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getTierBgColor(msg.priorityTier),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${msg.priorityTier.toUpperCase()} (${msg.priorityScore})',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getTierColor(msg.priorityTier),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Payload / Description
            Text(
              msg.payload ?? '',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 10),

            // Metadata: GPS, Timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      hasLoc ? Icons.location_on : Icons.location_off,
                      size: 14,
                      color: hasLoc ? Colors.green.shade600 : Colors.red.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasLoc
                          ? '${msg.lat!.toStringAsFixed(4)}, ${msg.lng!.toStringAsFixed(4)}'
                          : 'Location Unavailable',
                      style: TextStyle(
                        fontSize: 11,
                        color: hasLoc ? const Color(0xFF4B5563) : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
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
