import 'package:flutter_test/flutter_test.dart';
import 'package:fido/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    testWidgets('вызывает действие после указанной задержки', (tester) async {
      var callCount = 0;
      final debouncer = Debouncer(duration: const Duration(milliseconds: 100));

      debouncer.run(() => callCount++);
      expect(callCount, 0); // Еще не вызвано

      await tester.pump(const Duration(milliseconds: 50));
      expect(callCount, 0); // Еще ждём

      await tester.pump(const Duration(milliseconds: 60));
      expect(callCount, 1); // Вызвано!

      debouncer.dispose();
    });

    testWidgets('отменяет предыдущий вызов при новом', (tester) async {
      var callCount = 0;
      final debouncer = Debouncer(duration: const Duration(milliseconds: 100));

      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);
      debouncer.run(() => callCount++);

      await tester.pump(const Duration(milliseconds: 50));
      expect(callCount, 0); // Ничего не вызвано

      await tester.pump(const Duration(milliseconds: 60));
      expect(callCount, 1); // Только последний вызов

      debouncer.dispose();
    });

    testWidgets('cancel отменяет ожидающий вызов', (tester) async {
      var callCount = 0;
      final debouncer = Debouncer(duration: const Duration(milliseconds: 100));

      debouncer.run(() => callCount++);
      debouncer.cancel();

      await tester.pump(const Duration(milliseconds: 200));
      expect(callCount, 0); // Не вызвано после cancel

      debouncer.dispose();
    });
  });
}
