import 'package:flutter/material.dart';
import 'translations.dart';

// Only explicit application copy is translated. User-authored content is kept.
class AppLanguage {
  static String code = 'zh';
}

String? translatedError(String? value) => value == null ? null : tr(value);

String localized(BuildContext context, String value) {
  Localizations.maybeLocaleOf(context);
  return tr(value);
}

String tr(String source, [List<Object?> arguments = const []]) {
  var result = AppLanguage.code == 'en' ? (english[source] ?? source) : source;
  for (var i = 0; i < arguments.length; i++) {
    result = result.replaceAll('{$i}', '${arguments[i]}');
  }
  return result;
}

class LanguageButton extends StatelessWidget {
  final Future<void> Function() onToggle;
  const LanguageButton({required this.onToggle, super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const Key('language_toggle'),
    icon: const Icon(Icons.translate_rounded, size: 18),
    label: Text(AppLanguage.code == 'zh' ? 'EN' : '中文'),
    onPressed: () async {
      try {
        await onToggle();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(tr('语言设置保存失败，请重试'))));
        }
      }
    },
  );
}
