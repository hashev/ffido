import 'package:flutter/material.dart';

/// Универсальный виджет загрузки с индикатором
class LoadingWidget extends StatelessWidget {
  final String? message;
  final bool showAppBar;
  final String? appBarTitle;

  const LoadingWidget({
    super.key,
    this.message,
    this.showAppBar = false,
    this.appBarTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(title: Text(appBarTitle ?? 'Загрузка'), centerTitle: true)
          : null,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              message ?? 'Загрузка...',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
    );
  }
}
