import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/utils/csv.dart';

void main() {
  test('quotes what needs it and reads it back the same', () {
    final rows = [
      ['title', 'note'],
      ['Hades', 'plain'],
      ['Zelda, Tears', 'He said "wow"\non two lines'],
      ['', null],
    ];
    final text = toCsv(rows);
    expect(text, startsWith('title,note\r\nHades,plain\r\n"Zelda, Tears","He said ""wow""\non two lines"\r\n'));
    expect(parseCsv(text), [
      ['title', 'note'],
      ['Hades', 'plain'],
      ['Zelda, Tears', 'He said "wow"\non two lines'],
      ['', ''],
    ]);
  });

  test('a cell a spreadsheet would run as a formula is written as text', () {
    expect(toCsv([['=HYPERLINK("x")', '-3', '+1 more', '@me']]), '"\'=HYPERLINK(""x"")",-3,\'+1 more,\'@me\r\n');
  });

  test('reads a byte order mark, LF line ends, blank lines and no line end at the end', () {
    expect(parseCsv('\uFEFFa,b\n\n1,2\n3,"4"'), [
      ['a', 'b'],
      ['1', '2'],
      ['3', '4'],
    ]);
  });
}
