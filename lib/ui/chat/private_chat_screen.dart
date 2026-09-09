import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/database/database_service.dart';
import '../../core/mesh/mesh_service.dart';
import '../../core/models/contact_model.dart';
import '../../core/models/private_message_model.dart';

class PrivateChatScreen extends StatefulWidget {
  final ContactModel contact;

  const PrivateChatScreen({
    super.key,
    required this.contact,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<PrivateMessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  late String _conversationId;
  late ContactModel _currentContact;

  @override
  void initState() {
    super.initState();
    _currentContact = widget.contact;
    _initConversation();
  }

  Future<void> _initConversation() async {
    final localId = CryptoService.instance.isInitialized
        ? CryptoService.instance.derivedDeviceId
        : MeshService.instance.localDeviceId;
    _conversationId = DatabaseService.computeConversationId(localId, _currentContact.deviceId);

    // Register mesh callbacks
    MeshService.instance.setPrivateMessageCallback((envelope, plaintext) async {
      if (envelope.conversationId == _conversationId) {
        await _loadMessages();
      }
    });

    MeshService.instance.setAckCallback((ack) async {
      await _loadMessages();
    });

    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    final msgs = await DatabaseService.instance.getConversationMessages(_conversationId);
    final contactUpdate = await DatabaseService.instance.getContact(_currentContact.deviceId);

    if (mounted) {
      setState(() {
        _messages = msgs;
        if (contactUpdate != null) _currentContact = contactUpdate;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_currentContact.trustStatus == ContactTrustStatus.keyChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send: Security keys for this contact have changed! Re-verify via QR first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    _textController.clear();

    try {
      final messageId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Extract peer key ID
      final recipientKeyId = 'X25519-${_currentContact.encryptionPublicKey.substring(0, 8).toUpperCase()}';

      // 1. Encrypt message with ChaCha20-Poly1305 and sign with Ed25519
      final envelope = await CryptoService.instance.encryptPrivateMessage(
        plaintext: text,
        messageId: messageId,
        conversationId: _conversationId,
        recipientDeviceId: _currentContact.deviceId,
        recipientX25519KeyB64: _currentContact.encryptionPublicKey,
        recipientX25519KeyId: recipientKeyId,
        timestampMs: now,
      );

      // 2. Save to local database with PENDING status
      final localMessage = PrivateMessageModel(
        messageId: messageId,
        conversationId: _conversationId,
        senderDeviceId: MeshService.instance.localDeviceId,
        recipientDeviceId: _currentContact.deviceId,
        plaintextBody: text,
        ciphertext: envelope.ciphertext,
        nonce: envelope.nonce,
        authTag: envelope.authTag,
        senderX25519Pub: envelope.senderX25519Pub,
        senderEd25519Pub: envelope.senderEd25519Pub,
        signature: envelope.signature,
        status: PrivateMessageStatus.pending,
        timestamp: now,
        expiresAt: now + CryptoService.privateMessageExpiryHorizon.inMilliseconds,
        isOutgoing: true,
        acknowledged: false,
      );

      await DatabaseService.instance.savePrivateMessage(localMessage);
      await _loadMessages();

      // 3. Broadcast over mesh
      final sentCount = await MeshService.instance.broadcastPrivateEnvelope(envelope);
      if (sentCount > 0) {
        await DatabaseService.instance.updatePrivateMessageStatus(messageId, PrivateMessageStatus.sent);
      }
      await _loadMessages();
    } catch (e) {
      debugPrint('[PrivateChatScreen] Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error encrypting/sending message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyChanged = _currentContact.trustStatus == ContactTrustStatus.keyChanged;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentContact.displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Icon(
                  _currentContact.trustStatus == ContactTrustStatus.qrVerified
                      ? Icons.verified
                      : isKeyChanged
                          ? Icons.warning
                          : Icons.help_outline,
                  size: 11,
                  color: isKeyChanged ? Colors.redAccent : Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_currentContact.deviceId} • ${_currentContact.trustStatus.label}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isKeyChanged ? Colors.redAccent : Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Security Alert Banner if KEY_CHANGED
          if (isKeyChanged)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFFEE2E2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.gpp_maybe, color: Color(0xFFDC2626), size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SECURITY WARNING: Cryptographic keys for this contact have CHANGED. Outgoing messaging is disabled to prevent impersonation. Please re-verify via in-person QR scan.',
                      style: TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Message List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'End-to-End Encrypted',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Messages are encrypted with ChaCha20-Poly1305 and relayed offline.\nPlaintext never touches relays or Firebase.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return _buildMessageBubble(msg);
                        },
                      ),
          ),

          // Input Bar
          _buildInputBar(isKeyChanged),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(PrivateMessageModel msg) {
    final isMe = msg.isOutgoing;
    final timeStr = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));

    Widget statusIcon;
    switch (msg.status) {
      case PrivateMessageStatus.delivered:
        statusIcon = const Icon(Icons.done_all, size: 14, color: Colors.tealAccent);
        break;
      case PrivateMessageStatus.sent:
        statusIcon = const Icon(Icons.done, size: 14, color: Colors.white70);
        break;
      case PrivateMessageStatus.pending:
      default:
        statusIcon = const Icon(Icons.access_time, size: 12, color: Colors.white70);
        break;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF0F766E) : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.plaintextBody ?? '[Ciphertext - Decryption unavailable]',
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  statusIcon,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool disabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !disabled,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: disabled ? 'Messaging blocked due to key change' : 'Type encrypted message...',
                  hintStyle: const TextStyle(fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  filled: true,
                  fillColor: disabled ? Colors.grey.shade100 : Colors.grey.shade50,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: disabled ? Colors.grey : const Color(0xFF0F766E),
              ),
              onPressed: disabled || _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
