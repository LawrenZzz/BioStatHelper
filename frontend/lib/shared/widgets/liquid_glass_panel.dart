import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 28,
    this.maxWidth,
    this.maxHeight,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double? maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark
        ? colorScheme.surface.withValues(alpha: 0.50)
        : Colors.white.withValues(alpha: 0.44);
    final constraints = BoxConstraints(
      maxWidth: maxWidth ?? double.infinity,
      maxHeight: maxHeight ?? double.infinity,
    );

    return ConstrainedBox(
      constraints: constraints,
      child: GlassContainer(
        useOwnLayer: true,
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
        settings: LiquidGlassSettings(
          glassColor: tint,
          blur: 7,
          saturation: 1.16,
          chromaticAberration: 0.0018,
          lightAngle: 82,
          lightIntensity: isDark ? 0.62 : 0.95,
        ),
        padding: padding,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }
}

class LiquidGlassAlertDialog extends StatelessWidget {
  const LiquidGlassAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.insetPadding =
        const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    this.titlePadding = const EdgeInsets.fromLTRB(24, 22, 24, 0),
    this.contentPadding = const EdgeInsets.fromLTRB(24, 16, 24, 8),
    this.actionsPadding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsets insetPadding;
  final EdgeInsetsGeometry titlePadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height -
        media.viewInsets.vertical -
        insetPadding.vertical -
        12;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      child: LiquidGlassPanel(
        padding: EdgeInsets.zero,
        borderRadius: 30,
        maxWidth: 560,
        maxHeight: maxHeight.clamp(280.0, media.size.height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: titlePadding,
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ) ??
                      const TextStyle(fontSize: 20),
                  child: title!,
                ),
              ),
            if (content != null)
              Flexible(
                fit: FlexFit.loose,
                child: Padding(
                  padding: contentPadding,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium ??
                        const TextStyle(fontSize: 14),
                    child: content!,
                  ),
                ),
              ),
            if (actions != null && actions!.isNotEmpty)
              Padding(
                padding: actionsPadding,
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showLiquidGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: false,
    showDragHandle: false,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colorScheme.scrim.withValues(alpha: 0.36),
    builder: (sheetContext) {
      return LiquidGlassBottomSheet(
        showDragHandle: showDragHandle,
        child: builder(sheetContext),
      );
    },
  );
}

class LiquidGlassBottomSheet extends StatelessWidget {
  const LiquidGlassBottomSheet({
    super.key,
    required this.child,
    this.showDragHandle = false,
  });

  final Widget child;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LiquidGlassPanel(
        padding: EdgeInsets.zero,
        borderRadius: 30,
        maxHeight: media.size.height * 0.92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDragHandle)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            Flexible(
              fit: FlexFit.loose,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
