import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is on screen.
///
/// On web this follows the browser tab: a clinic PC with the portal open in a
/// background tab reports false. Kept out of autoDispose on purpose — one
/// lifecycle listener for the whole app, however many pollers come and go.
final appVisibleProvider = NotifierProvider<AppVisible, bool>(AppVisible.new);

class AppVisible extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onShow: () => state = true,
      onHide: () => state = false,
    );
    ref.onDispose(listener.dispose);
    return switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.paused || AppLifecycleState.hidden => false,
      _ => true,
    };
  }
}

/// Re-runs the calling provider every [every], but only while a screen is
/// watching it *and* the app is on screen.
///
/// A hidden tab stops calling the API altogether; coming back to it refreshes
/// straight away, rather than showing what was on screen when it was left.
/// Call it once, at the top of a provider body.
void schedulePoll(Ref ref, [Duration every = const Duration(seconds: 10)]) {
  Timer? timer;

  ref.listen(appVisibleProvider, (_, visible) {
    timer?.cancel();
    timer = null;
    // The rebuild runs schedulePoll again, which starts the next tick.
    if (visible) ref.invalidateSelf();
  });

  if (ref.read(appVisibleProvider)) {
    timer = Timer(every, ref.invalidateSelf);
  }
  ref.onDispose(() => timer?.cancel());
}
