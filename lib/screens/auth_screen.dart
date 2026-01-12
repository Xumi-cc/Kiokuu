import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../providers/music_provider.dart';
import '../utils/snackbar_utils.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isDiscordLoading = false;
  bool _obscurePassword = true;

  // Controllers
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      bool success;
      if (_isLogin) {
        success = await _api.login(
          _usernameController.text,
          _passwordController.text,
        );
      } else {
        success = await _api.signup(
          _usernameController.text,
          _emailController.text,
          _passwordController.text,
        );
        if (success) {
          if (mounted) {
            AppSnackbar.success(context, 'Account created! Please login.');
            _toggleAuthMode();
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      setState(() => _isLoading = false);

      if (success && _isLogin) {
        if (mounted) {
          context.read<MusicProvider>().refreshAuthToken();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else if (!success) {
        if (mounted) {
          AppSnackbar.error(
            context,
            _isLogin ? 'Invalid credentials' : 'Signup failed. Try again.',
          );
        }
      }
    } catch (e) {
      // Ensure loading state is reset on any error
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.error(
          context,
          'Connection failed. Please check your internet and try again.',
        );
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    final result = await _api.signInWithGoogle();

    setState(() => _isGoogleLoading = false);

    if (result['success'] == true) {
      if (mounted) {
        context.read<MusicProvider>().refreshAuthToken();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      if (mounted) {
        AppSnackbar.error(context, result['error'] ?? 'Google Sign-In failed');
      }
    }
  }

  Future<void> _signInWithDiscord() async {
    setState(() => _isDiscordLoading = true);

    final result = await _api.signInWithDiscord();

    setState(() => _isDiscordLoading = false);

    if (result['success'] == true) {
      if (mounted) {
        context.read<MusicProvider>().refreshAuthToken();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else if (result['pending'] == true) {
      // Desktop flow - waiting for browser callback
      if (mounted) {
        AppSnackbar.info(
          context,
          message: 'Complete sign-in in your browser...',
        );
      }
    } else {
      if (mounted) {
        AppSnackbar.error(context, result['error'] ?? 'Discord Sign-In failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final screenWidth = constraints.maxWidth;

          // Responsive thresholds
          final isSmallScreen = screenHeight < 800;
          final isWideScreen = screenWidth > 500;

          // Responsive spacing
          final double topSpacing = isSmallScreen ? 24 : 48;
          final double logoSize = isSmallScreen ? 80 : 100;
          final double sectionSpacing = isSmallScreen ? 20 : 32;
          final double elementSpacing = isSmallScreen ? 16 : 24;
          final double formMaxWidth = isWideScreen ? 400.0 : double.infinity;

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: isSmallScreen ? 16 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: formMaxWidth),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: topSpacing),

                        // Logo
                        Center(
                          child: SizedBox(
                            width: logoSize,
                            height: logoSize,
                            child: SvgPicture.asset(
                              'assets/images/kiokuu_white.svg',
                              width: logoSize,
                              height: logoSize,
                            ),
                          ),
                        ),
                        SizedBox(height: sectionSpacing),

                        // Title & Subtitle (Login only)
                        if (_isLogin) ...[
                          Center(
                            child: Text(
                              'Welcome back',
                              style: GoogleFonts.inter(
                                fontSize: isSmallScreen ? 20 : 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Sign in to your account to continue',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          SizedBox(height: sectionSpacing),
                        ],

                        // Form fields (passed spacing)
                        _buildFormFields(elementSpacing),

                        SizedBox(height: sectionSpacing),

                        // Submit Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F6BF6),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color.fromRGBO(
                                79,
                                107,
                                246,
                                0.6,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isLogin ? 'Sign in' : 'Create Account',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),

                        SizedBox(height: sectionSpacing),

                        // Divider
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(color: Colors.white24),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR CONTINUE WITH',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(color: Colors.white24),
                            ),
                          ],
                        ),

                        SizedBox(height: isSmallScreen ? 16 : 24),

                        // Social buttons
                        Row(
                          children: [
                            Expanded(
                              child: _buildSocialButton(
                                icon: _buildGoogleIcon(),
                                label: 'Google',
                                isLoading: _isGoogleLoading,
                                onPressed: _signInWithGoogle,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildSocialButton(
                                icon: _buildDiscordIcon(),
                                label: 'Discord',
                                isLoading: _isDiscordLoading,
                                onPressed: _signInWithDiscord,
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: isSmallScreen ? 24 : 40),

                        // Toggle Login/Signup
                        Center(
                          child: TextButton(
                            onPressed: _toggleAuthMode,
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.white54,
                                ),
                                children: [
                                  TextSpan(
                                    text: _isLogin
                                        ? "Don't have an account?  "
                                        : 'Already Have An Account?  ',
                                  ),
                                  TextSpan(
                                    text: 'Sign up',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF4F6BF6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
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
        },
      ),
    );
  }

  Widget _buildFormFields(double spacing) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username Field (Signup only)
          if (!_isLogin) ...[
            _buildLabel('Username'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _usernameController,
              hintText: 'Enter your Username',
              validator: (value) =>
                  value!.isEmpty ? 'Username is required' : null,
            ),
            SizedBox(height: spacing),
          ],

          // Username Field (Login) or Email Field (Signup)
          _buildLabel(_isLogin ? 'Username' : 'Email'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _isLogin ? _usernameController : _emailController,
            hintText: _isLogin ? 'Enter your username' : 'Enter your email',
            keyboardType: _isLogin
                ? TextInputType.text
                : TextInputType.emailAddress,
            validator: (value) {
              if (value!.isEmpty) {
                return '${_isLogin ? 'Username' : 'Email'} is required';
              }
              if (!_isLogin && !value.contains('@')) {
                return 'Invalid email';
              }
              return null;
            },
          ),
          SizedBox(height: spacing),

          // Password Field
          _buildLabel('Password'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _passwordController,
            hintText: 'Enter your password',
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white38,
                size: 20,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            validator: (value) {
              if (value!.isEmpty) return 'Password is required';
              if (value.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ),

          // Forgot password (Login only)
          if (_isLogin) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  AppSnackbar.info(
                    context,
                    message: 'Forgot password feature coming soon!',
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF4F6BF6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
      validator: validator,
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.inter(fontSize: 15, color: Colors.white38),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildSocialButton({
    required Widget icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }

  Widget _buildDiscordIcon() {
    return const Icon(Icons.discord, size: 22, color: Color(0xFF5865F2));
  }
}

// Custom painter for Google icon
class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.fill;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill;

    final path = Path();

    path.addArc(Rect.fromCircle(center: center, radius: radius), -0.5, 5.5);

    final innerRadius = radius * 0.55;
    path.addArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      5.0,
      -5.5,
    );

    canvas.save();
    canvas.clipPath(path);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -0.8,
      1.5,
      true,
      bluePaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.7,
      1.5,
      true,
      greenPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.2,
      1.5,
      true,
      yellowPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.5,
      1.8,
      true,
      redPaint,
    );

    canvas.restore();

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.5, h * 0.4, w * 0.5, h * 0.2),
      const Radius.circular(1),
    );
    canvas.drawRRect(barRect, bluePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
