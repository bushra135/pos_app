import 'package:flutter/material.dart';

/// Displays both existing image URLs and images saved inside product records.
class ProductImage extends StatefulWidget {
  const ProductImage({
    super.key,
    required this.source,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final String source;
  final Widget placeholder;
  final BoxFit fit;

  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  ImageProvider<Object>? _provider;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _resolveImage();
  }

  void _resolveImage() {
    final source = widget.source.trim();
    _provider = null;
    try {
      if (source.startsWith('data:image/')) {
        _provider = MemoryImage(Uri.parse(source).data!.contentAsBytes());
      } else if (source.startsWith('https://') ||
          source.startsWith('http://')) {
        _provider = NetworkImage(source);
      }
    } on FormatException {
      // A damaged saved image must not prevent the product from rendering.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) return widget.placeholder;
    return Image(
      image: _provider!,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => widget.placeholder,
    );
  }
}
