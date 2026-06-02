import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

class OciDeckApp extends StatelessWidget {
  const OciDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OciDeck',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}
