import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_session.dart';
import '../services/api_config.dart';
import '../services/v2board_api.dart';
import '../theme/app_colors.dart';
import '../widgets/dz_ui.dart';
import 'privacy_screen.dart';
import 'tos_screen.dart';

/// 登录页（注册 / 找回密码统一跳转官网）
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthed;
  const AuthScreen({super.key, required this.onAuthed});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _api = V2BoardApi();
  final _config = ApiConfig();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  Future<void> _restoreEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final e = prefs.getString('last_login_email');
      if (e != null &&
          e.isNotEmpty &&
          mounted &&
          _emailController.text.isEmpty) {
        _emailController.text = e;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return; // 键盘「完成」与按钮同时触发时避免重复登录
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = '请输入正确的邮箱地址');
      HapticFeedback.selectionClick();
      return;
    }
    if (password.isEmpty) {
      setState(() => _message = '请输入密码');
      HapticFeedback.selectionClick();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      HapticFeedback.lightImpact();
      final response = await _api.login(email, password);

      final token = (response['data'] ?? {})['token'];
      if (token is String && token.isNotEmpty) {
        await _config.setToken(token);
        await _config.refreshAuthCache();
      }
      final authData = (response['data'] ?? {})['auth_data'];
      if (authData is String && authData.isNotEmpty) {
        await _config.setAuthData(authData);
        await _config.refreshAuthCache();
      }
      // 换了账号：不沿用上一个账号的订阅缓存与线路选择
      await AccountSession.onLogin(email);
      // 添加短暂延迟，确保数据已完全保存
      await Future.delayed(const Duration(milliseconds: 100));
      widget.onAuthed();
    } catch (e) {
      final msg = e is V2BoardApiException ? e.message : '网络异常，请检查网络后重试';
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _message = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: mq.size.height * 0.06),
                    const Entrance(child: BrandMark(height: 92)),
                    const SizedBox(height: 14),
                    const Entrance(
                      delayMs: 80,
                      child: Column(
                        children: [
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('全球优选加速 · 从容抵达世界每一处',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      letterSpacing: 2.4))),
                          SizedBox(height: 6),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('专属客户端 · 无需输入订阅 · 一键连接全球',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 11,
                                      letterSpacing: 1.6))),
                        ],
                      ),
                    ),
                    SizedBox(height: mq.size.height < 700 ? 26 : 40),
                    Entrance(delayMs: 160, child: _buildForm()),
                    const SizedBox(height: 22),
                    Entrance(
                      delayMs: 260,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _link('免费注册',
                              () => openSite(SiteLinks.register, context)),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            width: 1,
                            height: 12,
                            color: AppColors.borderStrong,
                          ),
                          _link('忘记密码',
                              () => openSite(SiteLinks.forgot, context)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    Entrance(delayMs: 320, child: _buildFooter()),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      radius: DzRadius.xl - 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('欢迎回来', style: DzText.title),
          const SizedBox(height: 4),
          const Text('登录你的账户，继续畅连全球', style: DzText.body),
          const SizedBox(height: 2),
          const Text('使用官网注册的邮箱和密码，线路自动就位', style: DzText.caption),
          const SizedBox(height: 22),
          _field(
            controller: _emailController,
            hint: '邮箱地址',
            icon: Icons.alternate_email_rounded,
            keyboard: TextInputType.emailAddress,
            action: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            autofill: const [AutofillHints.email, AutofillHints.username],
          ),
          const SizedBox(height: 12),
          _field(
            controller: _passwordController,
            focus: _passwordFocus,
            hint: '密码',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
            action: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            autofill: const [AutofillHints.password],
            suffix: IconButton(
              splashRadius: 18,
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 19,
                color: AppColors.textTertiary,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          AnimatedSize(
            duration: DzMotion.base,
            curve: DzMotion.ease,
            child: _message == null
                ? const SizedBox(height: 22)
                : Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: AppColors.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_message!,
                              style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
          ),
          GoldButton(
            label: '登 录',
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    FocusNode? focus,
    bool obscure = false,
    TextInputType? keyboard,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    Iterable<String>? autofill,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      obscureText: obscure,
      keyboardType: keyboard,
      textInputAction: action,
      onSubmitted: onSubmitted,
      autofillHints: autofill,
      autocorrect: false,
      enableSuggestions: !obscure,
      style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 15, letterSpacing: 0.3),
      cursorColor: AppColors.gold,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 19, color: AppColors.textTertiary),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
            const SizedBox(width: 2),
            const Icon(Icons.north_east_rounded,
                size: 13, color: AppColors.gold),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    TextStyle s(bool link) => TextStyle(
          color: link ? AppColors.textSecondary : AppColors.textTertiary,
          fontSize: 11.5,
          decoration: link ? TextDecoration.underline : null,
          decorationColor: AppColors.textTertiary,
        );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text('登录即表示同意 ', style: s(false)),
        GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TosScreen())),
          child: Text('服务条款', style: s(true)),
        ),
        Text(' 与 ', style: s(false)),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PrivacyScreen())),
          child: Text('隐私政策', style: s(true)),
        ),
      ],
    );
  }
}
