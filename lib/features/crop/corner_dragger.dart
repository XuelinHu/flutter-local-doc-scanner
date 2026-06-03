import 'package:flutter/material.dart';

class CornerDragger extends StatelessWidget {
  const CornerDragger({
    required this.center,
    required this.onPanUpdate,
    super.key,
  });

  final Offset center;
  final ValueChanged<DragUpdateDetails> onPanUpdate;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 24,
      top: center.dy - 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onPanUpdate,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: 28,
            height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF005A6F),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 10,
                color: Color(0x33000000),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
