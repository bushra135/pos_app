import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Keeps camera failures recoverable and shows the browser's actual reason.
class ScannerErrorPanel extends StatelessWidget {
  const ScannerErrorPanel({
    super.key,
    required this.error,
    required this.onRetry,
  });
  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final detail = error.errorDetails?.message;
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'Allow camera access in your browser settings, then retry.'
                    : 'Camera could not start. Close other camera tabs. On iPhone, try turning off Low Power Mode, then retry.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry camera'),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can also close this view and enter the barcode manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
