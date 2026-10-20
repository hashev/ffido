import 'dart:async';
import 'package:flutter/material.dart';

/// Refresh only the visible screen after returning from the background.
mixin RefreshOnResume<T extends StatefulWidget> on State<T> {
  late final AppLifecycleListener _lifecycle;
  bool _refreshingOnResume = false;
  bool get resumeRefreshEnabled => true;
  Future<void> refreshOnResume();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!mounted ||
            _refreshingOnResume ||
            !resumeRefreshEnabled ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        _refreshingOnResume = true;
        unawaited(
          refreshOnResume().whenComplete(() => _refreshingOnResume = false),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}
