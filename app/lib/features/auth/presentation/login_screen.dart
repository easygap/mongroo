import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'auth_scene.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _showValidationErrors = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      if (!_showValidationErrors) {
        setState(() => _showValidationErrors = true);
      }
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        _emailFocusNode.requestFocus();
      } else {
        _passwordFocusNode.requestFocus();
      }
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final error = await ref.read(authControllerProvider.notifier).login(
          email: email,
          password: password,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorMessage = error;
    });
  }

  void _clearServerError(String _) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScene(
      navigationLocked: _submitting,
      title: '로그인',
      description: '이메일로 기록을 이어가세요.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: _showValidationErrors
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.isEmpty || !email.contains('@')
                      ? '올바른 이메일을 입력해 주세요.'
                      : null;
                },
                onChanged: _clearServerError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                enabled: !_submitting,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                    onPressed: _submitting
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value ?? '').length < 8 ? '비밀번호는 8자 이상 입력해 주세요.' : null,
                onChanged: _clearServerError,
                onFieldSubmitted: (_) {
                  if (!_submitting) _submit();
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                AuthInlineError(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              Semantics(
                button: true,
                enabled: !_submitting,
                liveRegion: _submitting,
                label: _submitting ? '로그인 중' : '로그인',
                onTap: _submitting ? null : _submit,
                child: ExcludeSemantics(
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(_submitting ? '로그인 중…' : '로그인'),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '또는',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                key: const Key('open-local-trial'),
                onPressed: _submitting ? null : () => context.push('/trial'),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('회원가입 없이 3분 체험'),
              ),
              const SizedBox(height: 7),
              Text(
                '체험 기록은 서버로 보내지 않고 이 기기에만 저장해요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : () => context.push('/signup'),
                child: const Text('계정이 없나요? 가입하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
