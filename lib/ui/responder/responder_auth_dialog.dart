import 'package:flutter/material.dart';
import '../../core/services/responder_service.dart';

/// Professional authorization screen for Emergency Responders and Incident Commanders
class ResponderAuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const ResponderAuthScreen({
    super.key,
    required this.onAuthenticated,
  });

  @override
  State<ResponderAuthScreen> createState() => _ResponderAuthScreenState();
}

class _ResponderAuthScreenState extends State<ResponderAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _callSignController = TextEditingController(text: 'Commander Alpha');
  final _pinController = TextEditingController(text: 'CRISIS2026');
  String _selectedRole = 'Incident Commander';
  String _selectedSector = 'Sector North (HQ)';
  String? _authError;
  bool _isLoading = false;

  final List<String> _roles = [
    'Incident Commander',
    'Field Paramedic / Triage',
    'Search & Rescue Unit',
    'Disaster Logistics Dispatcher',
    'Structural Engineer',
  ];

  final List<String> _sectors = [
    'Sector North (HQ)',
    'Sector South',
    'Sector East (Coastal)',
    'Sector West (Mountain)',
    'Mobile Field Hospital',
  ];

  @override
  void dispose() {
    _callSignController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _submitAuth() {
    setState(() {
      _authError = null;
      _isLoading = true;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      return;
    }

    final success = ResponderAuthSession.instance.login(
      callSign: _callSignController.text.trim(),
      role: _selectedRole,
      sector: _selectedSector,
      pin: _pinController.text.trim(),
    );

    if (success) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _isLoading = false;
        _authError = 'Invalid Access PIN. Contact Crisis Command Dispatch.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header badge & title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFDC2626),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crisis Mesh Command',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Responder Authorization Gate',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 20),

                // Error banner
                if (_authError != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _authError!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Call Sign Input
                const Text(
                  'Responder Call Sign / Unit ID',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _callSignController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Medic-Alpha, Rescue-4',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a responder call sign';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Role Dropdown
                const Text(
                  'Operational Role',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.work_outline, size: 20),
                  ),
                  items: _roles.map((r) {
                    return DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRole = val);
                  },
                ),
                const SizedBox(height: 16),

                // Sector Dropdown
                const Text(
                  'Assigned Disaster Sector',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSector,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.place_outlined, size: 20),
                  ),
                  items: _sectors.map((s) {
                    return DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSector = val);
                  },
                ),
                const SizedBox(height: 16),

                // Access PIN Input
                const Text(
                  'Command Security PIN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pinController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Enter Emergency Command PIN',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'PIN is required for command authorization';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Login Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Authorize & Launch Command Center',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Authorized Personnel Only • All actions logged to Incident Audit Trail',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
