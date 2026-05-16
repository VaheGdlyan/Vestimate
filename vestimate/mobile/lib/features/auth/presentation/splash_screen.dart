import 'package:flutter/material.dart';
import 'package:vestimate/core/theme/theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _fadeController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
      ),
    );

    _taglineOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _logoController.forward();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _fadeController.forward().then((_) {
          widget.onComplete();
        });
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        return Opacity(
          opacity: 1 - _fadeController.value,
          child: Scaffold(
            backgroundColor: V.bg,
            body: Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo Mark
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(V.r20),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [V.accent, V.accentSoft],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: V.accent.withOpacity(0.15),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'V',
                                style: TextStyle(
                                  fontFamily: V.fontFamily,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: V.bg,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: V.s24),

                      // App Name
                      Opacity(
                        opacity: _textOpacity.value,
                        child: const Text(
                          'VESTIMATE',
                          style: TextStyle(
                            fontFamily: V.fontFamily,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: V.textPrimary,
                            letterSpacing: 6,
                          ),
                        ),
                      ),

                      const SizedBox(height: V.s8),

                      // Tagline
                      Opacity(
                        opacity: _taglineOpacity.value,
                        child: const Text(
                          'Your AI-Powered Wardrobe',
                          style: TextStyle(
                            fontFamily: V.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: V.textTertiary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
