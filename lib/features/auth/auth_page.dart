import 'package:flutter/material.dart';
import 'package:manchi_app/features/auth/forgot_password_page.dart';
import 'package:manchi_app/features/pages/home_page.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/features/services/notification_service.dart';
import 'package:manchi_app/utils/user_facing_errors.dart';

class AuthPage extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const AuthPage({
    super.key,
    this.onLoginSuccess,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _otpSent = false;
  bool _isLogin = true;
  /// For login: true = password, false = OTP.
  bool _loginWithPassword = true;
  bool _obscurePassword = true;

  bool _hasUppercase(String value) => RegExp(r'[A-Z]').hasMatch(value);
  bool _hasLowercase(String value) => RegExp(r'[a-z]').hasMatch(value);
  bool _hasSpecialChar(String value) =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(value);

  Widget _passwordRule(String label, bool satisfied) {
    final color = satisfied ? Colors.green : Colors.grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          satisfied ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: satisfied ? Colors.green : Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _passwordStrengthHint() {
    final password = _passwordController.text;
    return SizedBox(
      height: 18,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _passwordRule('Uppercase', _hasUppercase(password)),
              const SizedBox(width: 10),
              _passwordRule('Lowercase', _hasLowercase(password)),
              const SizedBox(width: 10),
              _passwordRule('Special', _hasSpecialChar(password)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // --- Login ---
        if (_loginWithPassword) {
          final password = _passwordController.text;
          final data = await BackendService.signInWithPassword(email, password);
          if (data.containsKey('session') || data.containsKey('user')) {
            _onAuthSuccess();
            return;
          }
          throw Exception('We couldn\'t sign you in. Please try again.');
        } else {
          // OTP login
          if (!_otpSent) {
            await BackendService.sendOtp(email);
            if (mounted) {
              setState(() {
                _otpSent = true;
                _isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('OTP sent to your email')),
              );
            }
            return;
          } else {
            final data = await BackendService.verifyOtp(email, _otpController.text.trim());
            if (data.containsKey('session') || data.containsKey('user')) {
              _onAuthSuccess();
              return;
            }
            throw Exception('That code didn\'t work. Please check it or request a new code.');
          }
        }
      } else {
        // --- Sign Up ---
        final password = _passwordController.text;
        if (password.length < 6) {
          throw Exception('Password must be at least 6 characters.');
        }
        final data = await BackendService.signUpWithPassword(email, password);
        if (mounted) {
          if (data.containsKey('session') || data.containsKey('user')) {
            _onAuthSuccess();
            return;
          }
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        UserFacingErrors.showErrorSnackBar(
          context,
          e,
          contextMessage: _isLogin
              ? 'We couldn\'t sign you in. Please try again.'
              : 'We couldn\'t create your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onAuthSuccess() {
    NotificationService().refreshTokenRegistration();
    if (!mounted) return;
    if (widget.onLoginSuccess != null) {
      widget.onLoginSuccess!();
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  void _resetOtpStep() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Sign Up')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 100,
                  child: Image.asset(
                    isDark ? 'assets/darkmanchi.png' : 'assets/lightmanchi.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.lock_outline, size: 80, color: Color(0xFFD50000));
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                if (!_otpSent) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _isLogin = true;
                            _otpSent = false;
                            _otpController.clear();
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _isLogin ? const Color(0xFFE53935) : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Login',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: _isLogin ? FontWeight.bold : FontWeight.normal,
                                color: _isLogin ? const Color(0xFFE53935) : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _isLogin = false;
                            _otpSent = false;
                            _otpController.clear();
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: !_isLogin ? const Color(0xFFE53935) : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Sign Up',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: !_isLogin ? FontWeight.bold : FontWeight.normal,
                                color: !_isLogin ? const Color(0xFFE53935) : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  _otpSent
                      ? 'Enter the 6-digit code sent to ${_emailController.text.trim()}'
                      : _isLogin
                          ? (_loginWithPassword
                              ? 'Sign in with your email and password'
                              : 'Enter your email to receive a login code')
                          : 'Create an account with email and password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Email (always when not in OTP step)
                if (!_otpSent)
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (val) =>
                        val == null || val.isEmpty || !val.contains('@') ? 'Enter a valid email' : null,
                    keyboardType: TextInputType.emailAddress,
                  ),

                // Password: sign up (always when not OTP), login with password
                if (!_otpSent && (_isLogin ? _loginWithPassword : true)) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: _isLogin ? 'Password' : 'Password (min 6 characters)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    onChanged: (_) {
                      if (!_isLogin) setState(() {});
                    },
                    validator: (val) {
                      if (_isLogin) return val == null || val.isEmpty ? 'Enter your password' : null;
                      if (val == null || val.isEmpty) return 'Enter a password';
                      if (val.length < 6) return 'At least 6 characters';
                      if (!_hasUppercase(val) ||
                          !_hasLowercase(val) ||
                          !_hasSpecialChar(val)) {
                        return 'Use 1 uppercase, 1 lowercase and 1 special character';
                      }
                      return null;
                    },
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 6),
                    _passwordStrengthHint(),
                  ],
                  if (_isLogin && _loginWithPassword) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                final result = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordPage(),
                                  ),
                                );
                                if (result == true && mounted) {
                                  _onAuthSuccess();
                                }
                              },
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
                ],

                // Login: choose Password vs OTP (clear visual state)
                if (!_otpSent && _isLogin) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() => _loginWithPassword = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _loginWithPassword ? const Color(0xFFE53935) : Colors.grey.shade200,
                            foregroundColor:
                                _loginWithPassword ? Colors.white : Colors.black87,
                            elevation: _loginWithPassword ? 2 : 0,
                          ),
                          child: const Text('Password'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() => _loginWithPassword = false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                !_loginWithPassword ? const Color(0xFFE53935) : Colors.grey.shade200,
                            foregroundColor:
                                !_loginWithPassword ? Colors.white : Colors.black87,
                            elevation: !_loginWithPassword ? 2 : 0,
                          ),
                          child: const Text('OTP link'),
                        ),
                      ),
                    ],
                  ),
                ],

                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      prefixIcon: Icon(Icons.password),
                      hintText: '123456',
                    ),
                    validator: (val) => val == null || val.length != 6 ? 'Enter 6-digit code' : null,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _otpSent
                              ? 'Verify & Login'
                              : _isLogin
                                  ? (_loginWithPassword ? 'Sign in' : 'Send code')
                                  : 'Create account',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
                if (_otpSent)
                  TextButton(
                    onPressed: _resetOtpStep,
                    child: const Text('Change email'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
