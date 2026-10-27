import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../services/open_food_facts.dart';
import '../common.dart';
import 'food_editor_page.dart';

/// Scans a product barcode and returns the matching [Food] (looked up on the
/// phone, then in Open Food Facts). Unknown products can be added by hand.
class BarcodePage extends StatefulWidget {
  const BarcodePage({super.key});

  @override
  State<BarcodePage> createState() => _BarcodePageState();
}

class _BarcodePageState extends State<BarcodePage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128],
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _found(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.stop();
    Food? food;
    String? error;
    try {
      food = await OpenFoodFacts.lookup(code);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    if (food != null) {
      Navigator.pop(context, food);
      return;
    }
    final add = await confirm(
      context,
      error == null ? context.tr('productNotFound') : context.tr('lookupFailed'),
      body: error == null ? context.tr('productNotFoundBody', {'code': code}) : '${context.tr('lookupFailedBody')}\n\n$error',
      ok: context.tr('addByHand'),
    );
    if (!mounted) return;
    if (add) {
      final created = await Navigator.push<Food>(context, MaterialPageRoute(builder: (_) => FoodEditorPage(barcode: code)));
      if (mounted && created != null) {
        Navigator.pop(context, created);
        return;
      }
    }
    setState(() => _busy = false);
    await _controller.start();
  }

  Future<void> _typeCode() async {
    final code = await promptText(context, context.tr('typeBarcode'), keyboard: TextInputType.number);
    if (code != null && code.trim().isNotEmpty) _found(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('scanBarcode')),
        actions: [
          IconButton(icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.keyboard_outlined), tooltip: context.tr('typeBarcode'), onPressed: _typeCode),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (code != null) _found(code);
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${context.tr('cameraError')}\n${error.errorCode.name}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : Text(context.tr('scanHint'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)])),
        ),
      ]),
    );
  }
}
