import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state.dart';
import '../core/auth_gateway.dart';
import '../core/ui.dart';
import '../core/language.dart';
import '../core/service_copy.dart';

class AuthScreen extends StatefulWidget {
  final AppState state;
  const AuthScreen({required this.state, super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final user = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController(),
      nickname = TextEditingController(),
      phone = TextEditingController(),
      code = TextEditingController();
  String mode = 'phone';
  bool consent = false, obscure = true, busy = false, sending = false;
  bool authorizing = false;
  String? error, challengePhone;
  SmsChallenge? challenge;
  DateTime? retryAt;
  Timer? timer;
  int get remaining => retryAt == null
      ? 0
      : ((retryAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 300);
  bool get register => mode == 'register';
  bool get locked => busy || sending;

  @override
  void dispose() {
    timer?.cancel();
    for (final c in [user, password, repeat, nickname, phone, code]) {
      c.dispose();
    }
    super.dispose();
  }

  void switchMode(String value) {
    setState(() {
      mode = value;
      error = null;
    });
    form.currentState?.reset();
  }

  Future<void> sendCode() async {
    if (!consent || locked || remaining > 0) return;
    final invalid = AppState.phoneError(phone.text);
    if (invalid != null) {
      setState(() => error = tr(invalid));
      return;
    }
    final target = phone.text.trim();
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final next = await widget.state.requestSms(target, consent: consent);
      if (!mounted) return;
      setState(() {
        challenge = next;
        challengePhone = target;
        code.clear();
        retryAt = DateTime.now().add(Duration(seconds: next.retryAfter));
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {});
        if (remaining == 0) t.cancel();
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> submit() async {
    if (!consent || locked || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (mode == 'phone') {
        if (challenge == null || challengePhone != phone.text.trim()) {
          throw StateError(tr("请先为当前手机号获取验证码"));
        }
        await widget.state.loginPhone(
          phone.text,
          code.text,
          challenge!.id,
          consent: consent,
        );
      } else if (register) {
        await widget.state.register(
          user.text,
          password.text,
          nickname.text,
          consent: consent,
        );
      } else {
        await widget.state.login(user.text, password.text, consent: consent);
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> wechat() async {
    if (!consent || locked) return;
    setState(() {
      busy = true;
      authorizing = true;
      error = null;
    });
    WechatChallenge? ticket;
    try {
      ticket = await widget.state.beginWechat(consent: consent);
      if (!mounted) {
        await widget.state.authGateway.cancelWechat(ticket);
        return;
      }
      final success = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.white,
        builder: (_) =>
            WechatAuthorization(state: widget.state, challenge: ticket!),
      );
      if (success != true) await widget.state.authGateway.cancelWechat(ticket);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          authorizing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: MemoryBackdrop(
      strong: true,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LanguageButton(onToggle: widget.state.toggleLanguage),
                    const Spacer(),
                    const DemoTag(),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  key: const Key('auth_brand'),
                  height: 270,
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BrandMark(size: 210),
                      SizedBox(height: 10),
                      Text(
                        tr("时忆"),
                        style: TextStyle(
                          fontSize: 30,
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final entry in {
                      'phone': tr("手机号登录"),
                      'account': tr("账号登录"),
                      'register': tr("注册账号"),
                    }.entries)
                      Expanded(
                        child: InkWell(
                          key: Key('mode_${entry.key}'),
                          onTap: locked ? null : () => switchMode(entry.key),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: mode == entry.key
                                  ? green.withValues(alpha: .10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              entry.value,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: mode == entry.key ? green : muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (mode == 'phone') ...[
                  FieldLabel(tr("手机号")),
                  TextFormField(
                    key: const Key('phone'),
                    controller: phone,
                    enabled: !locked,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational,
                    ],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: InputDecoration(
                      prefixText: '+86  ',
                      hintText: tr("请输入 11 位手机号"),
                      prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
                    ),
                    onChanged: (_) {
                      if (challengePhone != phone.text) {
                        setState(() {
                          challenge = null;
                          code.clear();
                        });
                      }
                    },
                    validator: (v) =>
                        translatedError(AppState.phoneError(v ?? '')),
                  ),
                  FieldLabel(tr("验证码")),
                  TextFormField(
                    key: const Key('sms_code'),
                    controller: code,
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onFieldSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: tr("请输入 6 位验证码"),
                      prefixIcon: const Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                      ),
                      suffixIcon: TextButton(
                        key: const Key('send_sms'),
                        onPressed: consent && !locked && remaining == 0
                            ? sendCode
                            : null,
                        child: Text(
                          sending
                              ? tr("获取中…")
                              : remaining > 0
                              ? tr("{0} 秒后重发", [remaining])
                              : tr("获取验证码"),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                        ? null
                        : tr("请输入 6 位验证码"),
                  ),
                  const SizedBox(height: 10),
                  if (widget.state.authGateway.isDemo)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        challenge?.demoCode == null
                            ? tr("演示模式：不会发送短信，可使用测试手机号体验。")
                            : tr("演示验证码：{0} · 5 分钟内有效（未发送短信）", [
                                challenge!.demoCode,
                              ]),
                        key: const Key('sms_hint'),
                        style: const TextStyle(color: green, fontSize: 11),
                      ),
                    ),
                ] else ...[
                  FieldLabel(tr("用户名")),
                  TextFormField(
                    key: const Key('username'),
                    controller: user,
                    enabled: !locked,
                    decoration: InputDecoration(
                      hintText: tr("请输入用户名"),
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) =>
                        translatedError(AppState.usernameError(v ?? '')),
                  ),
                  if (register) ...[
                    FieldLabel(tr("昵称")),
                    TextFormField(
                      controller: nickname,
                      enabled: !locked,
                      maxLength: 20,
                      decoration: InputDecoration(
                        hintText: tr("希望大家怎么称呼你"),
                        counterText: '',
                      ),
                    ),
                  ],
                  FieldLabel(tr("密码")),
                  TextFormField(
                    key: const Key('password'),
                    controller: password,
                    enabled: !locked,
                    obscureText: obscure,
                    onFieldSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: register ? tr("8–64 位，包含字母与数字") : tr("请输入密码"),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: obscure ? tr("显示密码") : tr("隐藏密码"),
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (v) => register
                        ? translatedError(AppState.passwordError(v ?? ''))
                        : (v == null || v.isEmpty ? tr("请输入密码") : null),
                  ),
                  if (register) ...[
                    FieldLabel(tr("确认密码")),
                    TextFormField(
                      controller: repeat,
                      enabled: !locked,
                      obscureText: obscure,
                      decoration: InputDecoration(hintText: tr("请再次输入密码")),
                      validator: (v) =>
                          v != password.text ? tr("两次输入的密码不一致") : null,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    tr("账号密码登录为本机演示账户。"),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      tr(error!),
                      key: const Key('auth_error'),
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Checkbox(
                        key: const Key('consent'),
                        value: consent,
                        onChanged: locked
                            ? null
                            : (v) => setState(() => consent = v!),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            tr("我已阅读并同意 "),
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          InkWell(
                            onTap: () => showPolicy(context, false),
                            child: Text(
                              tr("《用户协议》"),
                              style: TextStyle(fontSize: 11, color: green),
                            ),
                          ),
                          Text(
                            tr("与"),
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                          InkWell(
                            onTap: () => showPolicy(context, true),
                            child: Text(
                              tr("《隐私政策》"),
                              style: TextStyle(fontSize: 11, color: green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('auth_submit'),
                    onPressed: consent && !locked ? submit : null,
                    child: busy && !authorizing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            mode == 'phone'
                                ? tr("验证并登录")
                                : register
                                ? tr("注册并登录")
                                : tr("登  录"),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        tr("其他登录方式"),
                        style: TextStyle(
                          fontSize: 10,
                          color: muted.withValues(alpha: .8),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('wechat_login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF159A59),
                      side: BorderSide(
                        color: const Color(0xFF159A59).withValues(alpha: .3),
                      ),
                    ),
                    onPressed: consent && !locked ? wechat : null,
                    icon: const Icon(Icons.wechat, size: 25),
                    label: Text(
                      widget.state.authGateway.isDemo
                          ? tr("微信登录 · 演示")
                          : tr("微信登录"),
                    ),
                  ),
                ),
                if (mode == 'account')
                  Center(
                    child: TextButton(
                      onPressed: locked
                          ? null
                          : () => setState(() {
                              user.text = 'demo';
                              password.text = 'Demo12345';
                              error = null;
                            }),
                      child: Text(
                        tr("填入演示账号  demo / Demo12345"),
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WechatAuthorization extends StatefulWidget {
  final AppState state;
  final WechatChallenge challenge;
  const WechatAuthorization({
    required this.state,
    required this.challenge,
    super.key,
  });
  @override
  State<WechatAuthorization> createState() => _WechatAuthorizationState();
}

class _WechatAuthorizationState extends State<WechatAuthorization> {
  bool busy = false;
  String? error;
  Future<void> complete() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final done = await widget.state.finishWechat(
        widget.challenge,
        consent: true,
        demoApproved: widget.state.authGateway.isDemo,
      );
      if (!mounted) return;
      if (done) {
        Navigator.pop(context, true);
      } else {
        setState(() => error = tr("尚未完成授权，请先在授权页面完成操作。"));
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAuthorization() async {
    try {
      if (!await launchUrl(
        widget.challenge.authorizationUrl!,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError(tr("无法打开授权页面，请重试"));
      }
    } catch (_) {
      if (mounted) setState(() => error = tr("无法打开授权页面，请检查浏览器设置后重试。"));
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = widget.state.authGateway.isDemo;
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wechat, color: Color(0xFF159A59), size: 48),
              const SizedBox(height: 16),
              Text(
                demo ? tr("微信授权体验") : tr("微信登录授权"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                demo
                    ? tr("当前为时忆内部演示，不会打开微信或读取你的微信资料。确认后将使用独立的“微信体验用户”进入应用。")
                    : tr("前往授权页面完成微信验证，返回后点击“我已完成授权”。只有服务器验证通过才会登录。"),
                style: const TextStyle(color: muted, height: 1.7),
                textAlign: TextAlign.center,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    tr(error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 22),
              if (!demo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: busy ? null : openAuthorization,
                      child: Text(tr("打开微信授权页面")),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('wechat_confirm'),
                  onPressed: busy ? null : complete,
                  child: Text(
                    busy
                        ? tr("正在验证…")
                        : demo
                        ? tr("确认体验登录")
                        : tr("我已完成授权"),
                  ),
                ),
              ),
              TextButton(
                key: const Key('wechat_cancel'),
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: Text(tr("取消")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showPolicy(BuildContext context, bool privacy) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(privacy ? tr("隐私政策") : tr("用户协议"))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DemoTag(text: tr("演示文案 · 待正式审核")),
          const SizedBox(height: 22),
          Text(
            privacy ? tr("你的数据，由你掌握") : tr("欢迎使用时忆"),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(tr("Demo 版本：2026 年 10 月 18 日"), style: TextStyle(color: muted)),
          const SizedBox(height: 24),
          Text(tr('生活记录补充说明'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            tr(
              '生活记录、照片、草稿、评论、点赞、收藏、关注和浏览历史仅保存在当前设备或浏览器，并按本地账号区分。发布不会上传到公共社区。可在记录详情删除自己的帖子，在设置删除当前本地账号时一并删除这些数据。示例作者和故事为虚构展示，照片不代表真实发帖者。',
            ),
            style: const TextStyle(height: 1.9),
          ),
          const SizedBox(height: 24),
          Text(tr('声音录入补充说明'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            tr(
              '仅在点击录音并授权后使用麦克风；离开页面即停止。声音样本在创建时保存在本机，不会自动上传或用于训练。请仅录入本人或已获授权的声音。',
            ),
            style: const TextStyle(height: 1.9),
          ),
          const SizedBox(height: 24),
          Text(
            tr(privacy ? voicePrivacyPolicy : voiceServiceTerms),
            style: const TextStyle(height: 1.9),
          ),
        ],
      ),
    ),
  ),
);
