import 'package:flutter/material.dart';
import 'theme.dart';
import 'pages/splash_page.dart';
import 'app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.init();
  runApp(QuansferApp(appState: appState));
}

class QuansferApp extends StatelessWidget {
  final AppState appState;
  const QuansferApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    // Rebuilds mínimos cuando cambie baseUrl
    return AnimatedBuilder(
      animation: appState,
      builder: (_, __) {
        return MaterialApp(
          title: 'Quansfer',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: SplashPage(appState: appState), // pasa el estado
        );
      },
    );
  }
}
