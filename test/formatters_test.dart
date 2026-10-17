import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/utils/formatters.dart';

void main() {
  test('fmtThousands groups the digits of a count', () {
    expect(fmtThousands(0), '0');
    expect(fmtThousands(999), '999');
    expect(fmtThousands(1000), '1,000');
    expect(fmtThousands(1280), '1,280');
    expect(fmtThousands(1234567), '1,234,567');
  });

  test('fmtMonthYear names the month and year as stored', () {
    expect(fmtMonthYear(DateTime.utc(2026, 3, 4)), 'Mar 2026');
    expect(fmtMonthYear(DateTime.utc(2025, 12, 31)), 'Dec 2025');
  });
}
