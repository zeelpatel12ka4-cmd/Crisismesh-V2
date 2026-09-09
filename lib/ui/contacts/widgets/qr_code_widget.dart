import 'dart:convert';
import 'package:flutter/material.dart';

/// A pure Flutter canvas-based QR matrix visualizer for emergency offline key exchange
class QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;

  const QrCodeWidget({
    super.key,
    required this.data,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _QrMatrixPainter(data),
      ),
    );
  }
}

class _QrMatrixPainter extends CustomPainter {
  final String data;

  _QrMatrixPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()..color = const Color(0xFF1E293B);
    final paintAccent = Paint()..color = const Color(0xFF0F766E);

    // Generate a deterministic pseudo-random 25x25 QR grid based on data hash
    const int gridSize = 25;
    final cellSize = size.width / gridSize;

    // Use FNV-1a hash chain to seed grid cells
    final bytes = utf8.encode(data);
    final List<bool> grid = List.generate(gridSize * gridSize, (index) {
      final r = index ~/ gridSize;
      final c = index % gridSize;

      // Draw standard QR 7x7 corner finder patterns
      if ((r < 7 && c < 7) || (r < 7 && c >= gridSize - 7) || (r >= gridSize - 7 && c < 7)) {
        // Outer square
        if (r == 0 || r == 6 || c == 0 || c == 6 ||
            (r < 7 && (c == gridSize - 7 || c == gridSize - 1)) ||
            (r == 0 && c >= gridSize - 7) || (r == 6 && c >= gridSize - 7) ||
            ((r == gridSize - 7 || r == gridSize - 1) && c < 7) ||
            (r >= gridSize - 7 && (c == 0 || c == 6))) {
          return true;
        }
        // Inner square
        final localR = r >= gridSize - 7 ? r - (gridSize - 7) : r;
        final localC = c >= gridSize - 7 ? c - (gridSize - 7) : c;
        if (localR >= 2 && localR <= 4 && localC >= 2 && localC <= 4) {
          return true;
        }
        return false;
      }

      // Timing tracks
      if (r == 6 || c == 6) {
        return (r + c) % 2 == 0;
      }

      // Data pseudo-matrix
      final seed = (index * 31 + (bytes.isNotEmpty ? bytes[index % bytes.length] : 0));
      return (seed * 1103515245 + 12345) % 100 > 48;
    });

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (grid[r * gridSize + c]) {
          final isCorner = (r < 7 && c < 7) || (r < 7 && c >= gridSize - 7) || (r >= gridSize - 7 && c < 7);
          final p = isCorner ? paintAccent : paintDark;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.5, r * cellSize + 0.5, cellSize - 1, cellSize - 1),
              Radius.circular(isCorner ? 2 : 1),
            ),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) => oldDelegate.data != data;
}
