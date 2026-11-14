import 'package:flutter/material.dart';

/// A big round button for small fingers; dimmed when disabled.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.color,
    required this.tooltip,
    this.size = 76,
    this.dimmed,
  });

  /// Defaults to "disabled"; false keeps a busy button fully visible.
  final bool? dimmed;

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dim = dimmed ?? onTap == null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: dim ? 0.35 : 1,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          elevation: dim ? 0 : 8,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
