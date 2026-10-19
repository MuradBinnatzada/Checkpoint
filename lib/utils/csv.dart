/// Comma-separated values as spreadsheets read and write them (RFC 4180): a
/// field with a comma, a quote or a line break is quoted, and quotes inside it
/// are doubled.
library;

/// [rows] as CSV text, one line per row, ending lines with CRLF.
String toCsv(List<List<Object?>> rows) {
  final out = StringBuffer();
  for (final row in rows) {
    out
      ..write(row.map(_field).join(','))
      ..write('\r\n');
  }
  return out.toString();
}

String _field(Object? value) {
  final text = value?.toString() ?? '';
  // A leading =, +, - or @ makes a spreadsheet run the cell as a formula.
  final safe = text.isNotEmpty && '=+-@'.contains(text[0]) && double.tryParse(text) == null
      ? "'$text"
      : text;
  if (!safe.contains(RegExp(r'[",\r\n]'))) return safe;
  return '"${safe.replaceAll('"', '""')}"';
}

/// The rows of CSV [text]. Takes a byte order mark, CRLF or LF line ends,
/// quoted fields with commas, doubled quotes and line breaks in them, and a
/// last line without a line end. Blank lines are left out.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = text.startsWith('\uFEFF') ? 1 : 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.single.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      quoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
