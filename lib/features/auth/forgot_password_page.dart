import 'package:flutter/material.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/features/services/notification_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await BackendService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If an account exists for this email, a verification code has been sent.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(
          context,
          e,
          contextMessage: 'We couldn\'t send a reset code. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final data = await BackendService.resetPassword(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
        password: _passwordController.text,
      );
      await NotificationService().refreshTokenRegistration();
      if (!mounted) return;
      if (data.containsKey('session') || data.containsKey('user')) {
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Please sign in with your new password.'),
        ),
      );
      Navigator.pop(context, false);
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(
          context,
          e,
          contextMessage: 'We couldn\'t reset your password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _codeSent
                    ? 'Enter the 6-digit code sent to ${_emailController.text.trim()} and choose a new password.'
                    : 'Enter your account email. We\'ll send a 6-digit verification code.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                readOnly: _codeSent,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) => val == null || val.isEmpty || !val.contains('@')
                    ? 'Enter a valid email'
                    : null,
              ),
              if (_codeSent) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    prefixIcon: Icon(Icons.password),
                    hintText: '123456',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  validator: (val) =>
                      val == null || val.length != 6 ? 'Enter 6-digit code' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'New password (min 8 characters)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter a new password';
                    if (val.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_codeSent ? _resetPassword : _sendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_codeSent ? 'Reset password' : 'Send code'),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _codeSent = false;
                            _otpController.clear();
                            _passwordController.clear();
                          }),
                  child: const Text('Change email'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
