import 'package:flutter_test/flutter_test.dart';
import 'package:ascyn/features/xp/data/xp_ledger_service.dart';

void main() {
  test('day key uses previous day before 3AM local time', () {
    final t1 = DateTime(2026, 1, 16, 2, 30); // 2:30AM -> should be 2026-01-15
    final key1 = XpLedgerService.dayKeyWith3amBoundaryStatic(t1);
    expect(key1, equals('2026-01-15'));

    final t2 = DateTime(2026, 1, 16, 3, 0); // exactly 3:00AM -> same day
    final key2 = XpLedgerService.dayKeyWith3amBoundaryStatic(t2);
    expect(key2, equals('2026-01-16'));

    final t3 = DateTime(2026, 1, 16, 10, 0); // 10AM -> same day
    final key3 = XpLedgerService.dayKeyWith3amBoundaryStatic(t3);
    expect(key3, equals('2026-01-16'));
  });
}
