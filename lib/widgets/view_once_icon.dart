import 'package:flutter/material.dart';

/// The circled "1" used for view-once photos.
class ViewOnceIcon extends StatelessWidget {
  const ViewOnceIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.filled = false,
  });

  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: Border.all(color: color, width: 1.6),
      ),
      child: Text(
        '1',
        style: TextStyle(
          fontSize: size * 0.55,
          height: 1,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.black : color,
        ),
      ),
    );
  }
}
