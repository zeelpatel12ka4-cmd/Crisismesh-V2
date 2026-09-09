import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/database/database_service.dart';
import '../../core/models/contact_model.dart';
import 'widgets/qr_code_widget.dart';
import 'qr_scanner_screen.dart';
import '../chat/private_chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<ContactModel> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final contacts = await DatabaseService.instance.getAllContacts();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

  Future<void> _showMyQrDialog() async {
    final crypto = CryptoService.instance;
    if (!crypto.isInitialized) await crypto.init();

    final myDeviceId = crypto.derivedDeviceId;
    final mySignPub = crypto.publicKeyBase64 ?? '';
    final myEncPub = crypto.x25519PublicKeyBase64 ?? '';
    final fingerprint = ContactModel.computeFingerprint(
      signingPublicKeyB64: mySignPub,
      encryptionPublicKeyB64: myEncPub,
    );

    final contact = ContactModel(
      deviceId: myDeviceId,
      displayName: 'My Device ($myDeviceId)',
      signingPublicKey: mySignPub,
      encryptionPublicKey: myEncPub,
      fingerprint: fingerprint,
      trustStatus: ContactTrustStatus.qrVerified,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastSeenAt: DateTime.now().millisecondsSinceEpoch,
    );

    final qrPayload = contact.toQrPayload();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.qr_code_2, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('My Emergency QR'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Show this QR to a nearby responder to establish trusted end-to-end encrypted messaging.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              QrCodeWidget(data: qrPayload, size: 200),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Text(
                      myDeviceId,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fingerprint: $fingerprint',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Key Payload'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: qrPayload));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Public key payload copied to clipboard')),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openQrScanner() async {
    final scannedPayload = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (scannedPayload != null && scannedPayload.isNotEmpty) {
      await _processScannedPayload(scannedPayload);
    }
  }

  Future<void> _showAddContactDialog() async {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.person_add, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Add Trusted Contact'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0F766E)),
                label: const Text(
                  'Scan with Camera',
                  style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openQrScanner();
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('OR PASTE PAYLOAD', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Paste the public QR JSON payload from another Crisis Mesh device:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '{"v":1,"type":"crisis_mesh_contact"...}',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.paste, size: 16),
                    label: const Text('Paste'),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        textController.text = data!.text!;
                      }
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    child: const Text('Load Demo Peer'),
                    onPressed: () {
                      // Demo peer helper
                      final demo = ContactModel(
                        deviceId: 'DEV-B2C3D4E5',
                        displayName: 'Responder Bravo',
                        signingPublicKey: 'n/Lw99rY1e2oP7Q+xN7Xp6A1mG0j8K2eF5rT4uW1vX0=',
                        encryptionPublicKey: 'uB2F6zL7kM9pQ3rT1vW5xY8zA2cE4gI6kM8oQ0sU2wY=',
                        fingerprint: 'B2C3:D4E5:F6A7:8901',
                        trustStatus: ContactTrustStatus.qrVerified,
                        createdAt: DateTime.now().millisecondsSinceEpoch,
                        lastSeenAt: DateTime.now().millisecondsSinceEpoch,
                      );
                      textController.text = demo.toQrPayload();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final payload = textController.text.trim();
              Navigator.pop(ctx);
              _processScannedPayload(payload);
            },
            child: const Text('Verify & Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _processScannedPayload(String payload) async {
    final parsed = ContactModel.fromQrPayload(payload);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR Payload: Malformed format or invalid keys.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if contact already exists
    final existing = await DatabaseService.instance.getContact(parsed.deviceId);
    if (existing != null) {
      if (existing.signingPublicKey != parsed.signingPublicKey ||
          existing.encryptionPublicKey != parsed.encryptionPublicKey) {
        // KEY CHANGE DETECTED
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text('SECURITY WARNING'),
              ],
            ),
            content: Text(
              'Security keys for contact ${existing.displayName} (${existing.deviceId}) have CHANGED!\n\n'
              'Old Fingerprint: ${existing.fingerprint}\n'
              'New Fingerprint: ${parsed.fingerprint}\n\n'
              'This could indicate an impersonation attempt or device reset. Do you explicitly verify and trust the new keys?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Reject'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final updated = parsed.copyWith(trustStatus: ContactTrustStatus.qrVerified);
                  await DatabaseService.instance.saveContact(updated);
                  await _loadContacts();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact re-verified with new keys.')),
                  );
                },
                child: const Text('Trust New Keys'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // Explicit User Confirmation Dialog
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.verified_user, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Confirm Contact Trust'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID: ${parsed.deviceId}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Name: ${parsed.displayName}'),
            const SizedBox(height: 4),
            Text('Fingerprint:\n${parsed.fingerprint}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 12),
            const Text(
              'Confirming will establish this contact as QR_VERIFIED for end-to-end encrypted messaging.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final verified = parsed.copyWith(trustStatus: ContactTrustStatus.qrVerified);
              await DatabaseService.instance.saveContact(verified);
              await _loadContacts();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added trusted contact: ${parsed.displayName}')),
              );
            },
            child: const Text('Trust & Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Contacts (E2EE)'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Contact QR',
            onPressed: _openQrScanner,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Show My QR',
            onPressed: _showMyQrDialog,
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Contact Manually',
            onPressed: _showAddContactDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQrScanner,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan QR'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_person, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'No Contacts Added Yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Scan emergency QR codes in person with your camera to enable private 1-to-1 encrypted messaging over the offline mesh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan Contact QR Code'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: _openQrScanner,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Show My QR Code'),
                          onPressed: _showMyQrDialog,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.paste, size: 16),
                          label: const Text('Enter Payload Manually'),
                          onPressed: _showAddContactDialog,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contacts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return _buildContactTile(contact);
                  },
                ),
    );
  }

  Widget _buildContactTile(ContactModel contact) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (contact.trustStatus) {
      case ContactTrustStatus.qrVerified:
        badgeColor = const Color(0xFF10B981);
        badgeIcon = Icons.verified;
        badgeText = 'QR Verified';
        break;
      case ContactTrustStatus.keyChanged:
        badgeColor = const Color(0xFFEF4444);
        badgeIcon = Icons.warning_amber_rounded;
        badgeText = 'KEY CHANGED';
        break;
      case ContactTrustStatus.unverified:
        badgeColor = Colors.amber.shade700;
        badgeIcon = Icons.help_outline;
        badgeText = 'Unverified';
        break;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: contact.trustStatus == ContactTrustStatus.keyChanged
              ? Colors.red.shade300
              : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: badgeColor.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: badgeColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                contact.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 12, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(contact.deviceId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(
              'FP: ${contact.fingerprint}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        trailing: const Icon(Icons.chat_bubble_outline, color: Color(0xFF0F766E)),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrivateChatScreen(contact: contact),
            ),
          ).then((_) => _loadContacts());
        },
      ),
    );
  }
}
