import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/app_colors.dart';
import '../services/barcode_catalog_service.dart';

/// Owns the lookup lifecycle independently of product form rebuilds.
class BarcodeLookupPanel extends StatefulWidget {
  const BarcodeLookupPanel({
    super.key,
    required this.barcode,
    required this.catalog,
    required this.onProduct,
    required this.onBusyChanged,
    this.enabled = true,
  });
  final TextEditingController barcode;
  final BarcodeCatalogService catalog;
  final ValueChanged<CatalogProduct> onProduct;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  @override
  State<BarcodeLookupPanel> createState() => BarcodeLookupPanelState();
}

class BarcodeLookupPanelState extends State<BarcodeLookupPanel> {
  bool _loading = false;
  String? _message;

  /// Barcode that no catalogue knew; offers a web search for it.
  String? _missingCode;
  int _generation = 0;
  Timer? _watchdog;

  @override
  void dispose() {
    _generation++;
    _watchdog?.cancel();
    super.dispose();
  }

  void _finish(int generation, String message) {
    if (!mounted || generation != _generation) return;
    _watchdog?.cancel();
    setState(() {
      _loading = false;
      _message = message;
    });
    widget.onBusyChanged(false);
  }

  Future<void> lookup() async {
    if (_loading || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    final code = widget.barcode.text.trim();
    if (code.isEmpty) {
      setState(() => _message = 'Enter or scan a barcode first.');
      return;
    }
    final generation = ++_generation;
    setState(() {
      _missingCode = null;
      _loading = true;
      _message = 'Looking up barcode: $code…';
    });
    widget.onBusyChanged(true);
    // Up to three sources are tried in turn (ShopPad stores, Open Food Facts, UPCitemdb).
    _watchdog = Timer(const Duration(seconds: 11), () {
      _finish(
        generation,
        'The catalogue did not respond. Try again or enter the product manually.',
      );
      if (mounted && generation == _generation) _generation++;
    });
    try {
      final product = await widget.catalog.lookup(code).timeout(const Duration(seconds: 10));
      if (!mounted || generation != _generation) return;
      if (widget.barcode.text.trim() != code) {
        _finish(generation, 'Barcode changed. Search again for the new barcode.');
        return;
      }
      if (product == null) {
        _finish(
          generation,
          'Not found in ShopPad or the free product catalogues. Search the web for the name, then enter the details. Once saved, other stores will find it automatically.',
        );
        if (mounted && generation == _generation) setState(() => _missingCode = code);
      } else {
        widget.onProduct(product);
        _finish(
          generation,
          product.suggestedPrice > 0
              ? 'Product found. Empty fields were filled, including a price another store uses. Review the price and enter your stock.'
              : 'Product found. Empty fields were filled; review the details and set your price and stock.',
        );
      }
    } on CatalogLookupException catch (error) {
      _finish(generation, error.message);
    } on TimeoutException {
      _finish(generation, 'Product lookup timed out. Try again or enter the details manually.');
    } catch (error, stack) {
      debugPrint('Catalogue lookup failed: $error $stack');
      _finish(generation, 'Lookup failed. Check your connection or enter the details manually.');
    }
  }

  void _stop() {
    final generation = _generation;
    _finish(generation, 'Lookup stopped. You can enter the details manually.');
    _generation++;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FilledButton.icon(
        onPressed: _loading || !widget.enabled ? null : lookup,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore_rounded),
        label: Text(_loading ? 'Finding product…' : 'Find product info · free'),
      ),
      if (_loading)
        TextButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Stop lookup'),
        ),
      const SizedBox(height: 8),
      const Text(
        'Product information · fills empty fields only. Stock is yours to set; a price from another store is only a suggestion.',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      if (_message != null)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_message!, style: const TextStyle(color: AppColors.primaryDark, fontSize: 12)),
              if (_missingCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _searchWeb(_missingCode!),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search Google'),
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  Future<void> _searchWeb(String code) async {
    final uri = Uri.https('www.google.com', '/search', {'q': code});
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Could not open the browser.')));
    }
  }
}
