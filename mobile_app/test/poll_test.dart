// schedulePoll (lib/core/utils/poll.dart) drives every polling provider in the
// app, so it is tested on its own: no widgets, no frames, just the clock.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/utils/poll.dart';

/// Stands in for the real lifecycle listener, which needs a browser tab.
class _Visible extends AppVisible {
  @override
  bool build() => true;

  void show() => state = true;
  void hide() => state = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int fetches;
  late ProviderContainer container;
  late _Visible visible;

  final counter = FutureProvider.autoDispose<int>((ref) async {
    schedulePoll(ref);
    return ++fetches;
  });

  setUp(() {
    fetches = 0;
    visible = _Visible();
    container = ProviderContainer(overrides: [appVisibleProvider.overrideWith(() => visible)]);
    addTearDown(container.dispose);
  });

  test('polls every 10 s while a screen is watching', () {
    fakeAsync((async) {
      container.listen(counter, (_, _) {});
      async.elapse(const Duration(seconds: 35));
      expect(fetches, 4); // the first read, then 10 / 20 / 30 s
    });
  });

  test('stops while the tab is hidden, and refreshes on the way back', () {
    fakeAsync((async) {
      container.listen(counter, (_, _) {});
      async.elapse(const Duration(seconds: 25));
      expect(fetches, 3);

      visible.hide();
      async.elapse(const Duration(minutes: 5));
      expect(fetches, 3, reason: 'a background tab must not call the API');

      visible.show();
      async.elapse(const Duration(milliseconds: 1)); // Riverpod refreshes on the event loop
      expect(fetches, 4, reason: 'coming back shows fresh data, not a 5-minute-old page');

      async.elapse(const Duration(seconds: 25));
      expect(fetches, 6); // polling resumed
    });
  });

  test('nothing watching means nothing polling', () {
    fakeAsync((async) {
      final sub = container.listen(counter, (_, _) {});
      async.elapse(const Duration(seconds: 25));
      expect(fetches, 3);

      sub.close();
      async.elapse(const Duration(minutes: 5));
      expect(fetches, 3);
    });
  });
}
