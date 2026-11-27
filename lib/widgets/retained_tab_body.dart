import 'package:flutter/material.dart';

/// Retain only explicitly safe tabs after first use. Camera/checkout tabs are
/// removed on departure, while retained tabs keep their local view state.
class RetainedTabBody extends StatefulWidget {
  const RetainedTabBody({
    super.key,
    required this.index,
    required this.retained,
    required this.builder,
  });
  final int index;
  final Set<int> retained;
  final Widget Function(int index) builder;
  @override
  State<RetainedTabBody> createState() => _RetainedTabBodyState();
}

class _RetainedTabBodyState extends State<RetainedTabBody> {
  final _visited = <int>{};
  @override
  Widget build(BuildContext context) {
    _visited.removeWhere((index) => !widget.retained.contains(index));
    if (widget.retained.contains(widget.index)) _visited.add(widget.index);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final index in _visited)
          Offstage(
            key: ValueKey('retained-$index'),
            offstage: index != widget.index,
            child: ExcludeFocus(
              excluding: index != widget.index,
              child: TickerMode(enabled: index == widget.index, child: widget.builder(index)),
            ),
          ),
        if (!widget.retained.contains(widget.index))
          KeyedSubtree(
            key: ValueKey('active-${widget.index}'),
            child: widget.builder(widget.index),
          ),
      ],
    );
  }
}
