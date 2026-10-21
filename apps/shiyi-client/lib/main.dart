import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_state.dart';
import 'core/ui.dart';
import 'core/language.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await SharedPreferences.getInstance());
  await state.initialize();
  runApp(CyberVerseApp(state: state));
}

class CyberVerseApp extends StatelessWidget {
  final AppState state;
  const CyberVerseApp({required this.state, super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: tr("时忆 · 数字生命记忆空间"),
      debugShowCheckedModeBanner: false,
      theme: appTheme(state.appearance),
      locale: state.language == 'zh'
          ? const Locale('zh', 'CN')
          : const Locale('en'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 650) return child!;
          return MemoryBackdrop(
            strong: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (constraints.maxWidth > 1000)
                  SizedBox(width: 460, child: _DesktopBrand()),
                Container(
                  width: 440,
                  margin: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .18),
                        blurRadius: 60,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ],
            ),
          );
        },
      ),
      home: state.loggedIn
          ? HomeScreen(state: state)
          : AuthScreen(state: state),
    ),
  );
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 70),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BrandMark(),
            SizedBox(width: 12),
            Text(
              tr("时忆"),
              style: TextStyle(
                fontSize: 24,
                color: ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 62),
        Text(
          tr("让记忆拥有声音，\n让陪伴跨越时间。"),
          style: TextStyle(
            fontSize: 37,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr("数字生命 · 记忆留存 · 温暖陪伴"),
          style: TextStyle(color: muted, fontSize: 16),
        ),
        const SizedBox(height: 44),
        Row(
          children: List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Transform.rotate(
                angle: (i - 1) * .08,
                child: HumanAvatar(size: 84, variant: i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 64),
        const DemoTag(text: 'SHIYI / FLUTTER DEMO'),
        const SizedBox(height: 14),
        Text(tr("珍藏每一段值得被记住的相遇"), style: TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );
}
