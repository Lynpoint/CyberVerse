import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'language.dart';
import 'ui.dart';

Uri? voicePreviewUri({
  required bool web,
  required Uri page,
  String? configured,
}) {
  final value =
      configured ?? const String.fromEnvironment('SHIYI_VOICE_PREVIEW_URL');
  final local = web && ['localhost', '127.0.0.1', '::1'].contains(page.host);
  if (value.isEmpty && !local) return null;
  final uri = Uri.tryParse(
    value.isEmpty ? 'http://127.0.0.1:15173/shiyi-voice.html' : value,
  );
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.replace(
    queryParameters: {...uri.queryParameters, 'lang': AppLanguage.code},
  );
}

Future<void> openVoicePreview(BuildContext context) async {
  final uri = voicePreviewUri(web: kIsWeb, page: Uri.base);
  if (uri == null) {
    toast(context, tr('请先配置真实语音页面地址'));
    return;
  }
  try {
    final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!opened && context.mounted) toast(context, tr('无法打开语音页面，请检查联调服务'));
  } catch (_) {
    if (context.mounted) toast(context, tr('无法打开语音页面，请检查联调服务'));
  }
}
