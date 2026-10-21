import 'package:flutter/material.dart';
import 'models.dart';
import 'language.dart';

const ink = Color(0xFF08265E);
const green = Color(0xFF1677FF);
const muted = Color(0xFF6F86AA);
const canvas = Color(0xFFF3F8FF);
const line = Color(0xFFDCEAFF);
const cyan = Color(0xFF28D7EA);
const violet = Color(0xFF716BFF);

Color appearanceColor(String appearance) => switch (appearance) {
  'aurora' => const Color(0xFF7857F5),
  'ocean' => const Color(0xFF009EB4),
  _ => green,
};

Color appearanceCanvas(String appearance) => switch (appearance) {
  'aurora' => const Color(0xFFF7F4FF),
  'ocean' => const Color(0xFFF0FBFC),
  _ => canvas,
};

ThemeData appTheme([String appearance = 'sky']) {
  final primary = appearanceColor(appearance);
  final background = appearanceCanvas(appearance);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: Colors.white.withValues(alpha: .94),
    ),
    fontFamily: 'NotoSansSC',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ink,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.6),
      bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .86),
      hintStyle: const TextStyle(color: muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: ink,
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? primary : muted,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? primary : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}

void toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(tr(text))));
String errorText(Object e) => tr(
  e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''),
);
Future<bool> confirm(
  BuildContext context,
  String title,
  String content,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('确认')),
          ),
        ],
      ),
    ) ??
    false;

class SectionLabel extends StatelessWidget {
  final String label, subtitle;
  final Widget? trailing;
  const SectionLabel(
    this.label, {
    this.subtitle = '',
    this.trailing,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label), style: Theme.of(context).textTheme.titleMedium),
              if (subtitle.isNotEmpty)
                Text(
                  tr(subtitle),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color == Colors.white
          ? Colors.white.withValues(alpha: .82)
          : color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: .9)),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Material(color: Colors.transparent, child: child),
  );
}

class AiContentLabel extends StatelessWidget {
  const AiContentLabel({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.auto_awesome_outlined, size: 13, color: muted),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          localized(context, '内容由AI生成'),
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ),
    ],
  );
}

class DemoTag extends StatelessWidget {
  final String text;
  const DemoTag({this.text = '本地 DEMO', super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          cyan.withValues(alpha: .10),
        ],
      ),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
      ),
    ),
    child: Text(
      localized(context, text),
      style: const TextStyle(
        color: green,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({this.size = 42, super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      'assets/branding/logo.png',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => CustomPaint(painter: _BrandPainter()),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [cyan, green, violet],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .12
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * .12, size.height * .58)
      ..cubicTo(
        size.width * .25,
        size.height * .25,
        size.width * .43,
        size.height * .28,
        size.width * .52,
        size.height * .53,
      )
      ..cubicTo(
        size.width * .63,
        size.height * .82,
        size.width * .82,
        size.height * .78,
        size.width * .88,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .78,
        size.height * .27,
        size.width * .64,
        size.height * .30,
        size.width * .52,
        size.height * .53,
      )
      ..cubicTo(
        size.width * .39,
        size.height * .79,
        size.width * .22,
        size.height * .80,
        size.width * .12,
        size.height * .58,
      );
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .12),
      size.width * .075,
      Paint()..shader = paint.shader,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MemoryBackdrop extends StatelessWidget {
  final Widget child;
  final bool strong;
  const MemoryBackdrop({required this.child, this.strong = false, super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                primary.withValues(alpha: strong ? .18 : .08),
                cyan.withValues(alpha: strong ? .18 : .07),
                Colors.white,
              ],
              stops: const [0, .34, .68, 1],
            ),
          ),
        ),
        CustomPaint(
          painter: MemoryFlowPainter(
            color: primary,
            opacity: strong ? .34 : .16,
          ),
        ),
        child,
      ],
    );
  }
}

class MemoryFlowPainter extends CustomPainter {
  final Color color;
  final double opacity;
  const MemoryFlowPainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final path = Path()
        ..moveTo(-size.width * .2, size.height * (.62 + i * .045))
        ..cubicTo(
          size.width * .18,
          size.height * (.40 + i * .03),
          size.width * .43,
          size.height * (.93 - i * .035),
          size.width * 1.18,
          size.height * (.57 + i * .025),
        );
      glow
        ..color = Color.lerp(
          color,
          cyan,
          i / 4,
        )!.withValues(alpha: opacity * (1 - i * .12))
        ..strokeWidth = 18 - i * 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);
      canvas.drawPath(path, glow);
      glow
        ..strokeWidth = 1.2
        ..maskFilter = null
        ..color = Colors.white.withValues(alpha: .72);
      canvas.drawPath(path, glow);
    }
    final dot = Paint()..color = color.withValues(alpha: opacity);
    for (var i = 0; i < 22; i++) {
      final x = ((i * 67) % 101) / 100 * size.width;
      final y = ((i * 43) % 89) / 100 * size.height;
      canvas.drawCircle(Offset(x, y), i % 4 == 0 ? 3.2 : 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant MemoryFlowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}

class HumanAvatar extends StatelessWidget {
  final DigitalHuman? human;
  final double size;
  final int variant;
  const HumanAvatar({this.human, this.size = 56, this.variant = 0, super.key});
  @override
  Widget build(BuildContext context) {
    final bytes = human?.photoBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: Container(
        width: size,
        height: size,
        color: Color(human?.color ?? 0xFFE0EEE7),
        child: bytes == null
            ? (human == null || human!.sample
                  ? Image.asset(
                      'assets/portraits/${human == null ? ['lin', 'su', 'xia'][variant % 3] : switch (human!.id) {
                              'sample_su' => 'su',
                              'sample_xia' => 'xia',
                              _ => 'lin',
                            }}.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -.25),
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.person_outline_rounded,
                        color: green,
                      ),
                    )
                  : const Icon(Icons.person_outline_rounded, color: green))
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.person_rounded, color: green),
              ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 9),
    child: Text(tr(text), style: Theme.of(context).textTheme.titleMedium),
  );
}
