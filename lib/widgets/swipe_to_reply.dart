import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Drag a message to the right to reply to it.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, this.onReply});

  final Widget child;

  /// Null turns swiping off.
  final VoidCallback? onReply;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  /// How far to drag before letting go replies.
  static const _trigger = 56.0;
  static const _max = 80.0;

  double _dx = 0;
  bool _dragging = false;

  void _update(DragUpdateDetails d) {
    final dx = (_dx + d.delta.dx).clamp(0.0, _max);
    if (_dx < _trigger && dx >= _trigger) HapticFeedback.selectionClick();
    setState(() {
      _dragging = true;
      _dx = dx;
    });
  }

  void _end([DragEndDetails? _]) {
    if (_dx >= _trigger) widget.onReply?.call();
    setState(() {
      _dragging = false;
      _dx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 14,
            child: Opacity(
              opacity: (_dx / _trigger).clamp(0.0, 1.0),
              child: const CircleAvatar(
                radius: 15,
                backgroundColor: Colors.black26,
                child: Icon(Icons.reply, size: 18, color: Colors.white),
              ),
            ),
          ),
          AnimatedContainer(
            // Follow the finger exactly, then spring back when let go.
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
