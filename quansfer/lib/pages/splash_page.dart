import 'package:flutter/material.dart';
import '../widgets/brand_logo.dart';
import 'home_page.dart';
import '../app_state.dart';

class SplashPage extends StatefulWidget {
  final AppState appState;
  const SplashPage({super.key, required this.appState});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..forward();
  late final Animation<double> _scale =
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => HomePage(appState: widget.appState),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ScaleTransition(
          scale: _scale,
          child: const BrandLogo(size: 120, showWordmark: true),
        ),
      ),
    );
  }
}
