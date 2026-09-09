import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  late AnimationController _animController;
  bool _isScanned = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _isScanned = true;
        HapticFeedback.mediumImpact();
        try {
          await _controller.stop();
        } catch (_) {}
        if (mounted) {
          Navigator.pop(context, raw.trim());
        }
        break;
      }
    }
  }

  void _openManualEntry() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Manual Key Payload'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the public contact QR JSON payload below:',
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
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.paste, size: 16),
              label: const Text('Paste from Clipboard'),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  textController.text = data!.text!;
                }
              },
            ),
          ],
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
              Navigator.pop(ctx, textController.text.trim());
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Contact QR Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Toggle Flash',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: 'Switch Camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Live Camera Stream
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam_off, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        'Camera unavailable (${error.errorCode.name})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You can still exchange keys by pasting the contact payload manually.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.paste),
                        label: const Text('Enter Payload Manually'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _openManualEntry,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Custom Viewfinder Overlay
          CustomPaint(
            size: Size.infinite,
            painter: _ScannerOverlayPainter(
              animationValue: _animController.value,
            ),
          ),

          // Bottom Instruction Banner & Manual Button
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'Point camera at another phone\'s Crisis Mesh QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.keyboard, color: Colors.white),
                  label: const Text('Or Enter / Paste Key Manually', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _openManualEntry,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double animationValue;

  _ScannerOverlayPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    const boxSize = 250.0;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2.3;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // Darkened backdrop outside cutout
    final backgroundPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(backgroundPath, backgroundPaint);

    // Corner targeting lines
    final cornerPaint = Paint()
      ..color = const Color(0xFF0F766E)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const cornerLength = 28.0;
    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top + 12), cornerPaint);
    canvas.drawLine(Offset(left + 12, top), Offset(left + cornerLength, top), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(left + boxSize - cornerLength, top), Offset(left + boxSize - 12, top), cornerPaint);
    canvas.drawLine(Offset(left + boxSize, top + 12), Offset(left + boxSize, top + cornerLength), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, top + boxSize - cornerLength), Offset(left, top + boxSize - 12), cornerPaint);
    canvas.drawLine(Offset(left + 12, top + boxSize), Offset(left + cornerLength, top + boxSize), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + boxSize - cornerLength, top + boxSize), Offset(left + boxSize - 12, top + boxSize), cornerPaint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize - 12), Offset(left + boxSize, top + boxSize - cornerLength), cornerPaint);

    // Laser scan bar
    final scanBarPaint = Paint()
      ..color = const Color(0xFF14B8A6).withValues(alpha: 0.8)
      ..strokeWidth = 2;
    final scanY = top + (boxSize * animationValue);
    canvas.drawLine(Offset(left + 10, scanY), Offset(left + boxSize - 10, scanY), scanBarPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}
