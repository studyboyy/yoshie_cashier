import 'package:flutter_cashier/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receiptDateTime', () {
    test('formats with two-digit day and time', () {
      final value = DateTime(2026, 6, 2, 9, 5);
      expect(receiptDateTime(value), '02/06/2026 09:05');
    });

    test('formats midnight correctly', () {
      final value = DateTime(2026, 1, 15, 0, 0);
      expect(receiptDateTime(value), '15/01/2026 00:00');
    });
  });

  group('centerReceiptText', () {
    test('centers short text', () {
      expect(centerReceiptText('POS', 7), '  POS');
    });

    test('truncates text longer than width', () {
      expect(centerReceiptText('LONGTEXT', 4), 'LONG');
    });

    test('returns as-is when exact width', () {
      expect(centerReceiptText('ABCD', 4), 'ABCD');
    });
  });

  group('rupiah', () {
    test('formats positive number', () {
      expect(rupiah(1250000), 'Rp 1.250.000');
    });

    test('formats zero', () {
      expect(rupiah(0), 'Rp 0');
    });

    test('formats negative number', () {
      expect(rupiah(-5000), 'Rp -5.000');
    });
  });
}
