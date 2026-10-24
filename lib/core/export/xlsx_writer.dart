import 'dart:typed_data';

import 'zip_writer.dart';

/// Tablo dosyasında bir sayfa: başlıklar ve satırlar.
///
/// Hücre türleri: [String] metin, [num] sayı, [DateTime] tarih-saat (gerçek
/// tarih olarak; Calc'ta sıralanır ve hesaplanır), [bool] "evet/hayır", null boş.
class XlsxSheet {
  const XlsxSheet(this.name, this.headers, this.rows, {this.widths});
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;

  /// Sütun genişlikleri (karakter); verilmezse içerikten tahmin edilir.
  final List<double>? widths;
}

/// LibreOffice Calc, Excel ve Google E-Tablolar'ın açtığı .xlsx üretir.
/// Paket gerektirmez: sıkıştırmasız ZIP içinde Office Open XML parçaları.
/// Her sayfada başlık satırı kalın ve sabit, filtre açık.
Uint8List buildXlsx(List<XlsxSheet> sheets, {DateTime? time}) {
  final zip = ZipWriter(time: time);
  final names = _uniqueNames([for (final s in sheets) s.name]);
  final n = sheets.length;
  zip.addText(
    '[Content_Types].xml',
    '$_xmlHead<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= n; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  zip.addText(
    '_rels/.rels',
    '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  zip.addText(
    'xl/workbook.xml',
    '$_xmlHead<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < n; i++) '<sheet name="${xmlEscape(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
  );
  zip.addText(
    'xl/_rels/workbook.xml.rels',
    '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= n; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
  );
  zip.addText('xl/styles.xml', _styles);
  for (var i = 0; i < n; i++) {
    zip.addText('xl/worksheets/sheet${i + 1}.xml', sheetXml(sheets[i]));
  }
  return zip.finish();
}

/// Paylaşırken dosya türü.
const xlsxMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

// Stil 0: normal, 1: kalın başlık, 2: tarih-saat (yyyy-mm-dd hh:mm).
const _styles = '$_xmlHead<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// XML'de geçersiz denetim karakterlerini atar, özel karakterleri kaçışlar.
String xmlEscape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var i = index + 1;
  var s = '';
  while (i > 0) {
    final r = (i - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    i = (i - 1) ~/ 26;
  }
  return s;
}

/// Tablo programlarının tarih sayısı: 1899-12-30'dan bu yana gün (kesirli).
double excelSerial(DateTime d) {
  final u = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  return u.difference(DateTime.utc(1899, 12, 30)).inSeconds / 86400;
}

String sheetXml(XlsxSheet s) {
  final cols = s.headers.length;
  final widths = s.widths ??
      [
        for (var c = 0; c < cols; c++)
          [
            s.headers[c].length + 2,
            for (final r in s.rows.take(200))
              if (c < r.length) _displayLength(r[c]),
          ].reduce((a, b) => a > b ? a : b).clamp(6, 50).toDouble(),
      ];
  final b = StringBuffer()
    ..write(_xmlHead)
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
    ..write('<cols>');
  for (var c = 0; c < widths.length; c++) {
    b.write('<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" customWidth="1"/>');
  }
  b
    ..write('</cols><sheetData>')
    ..write('<row r="1">');
  for (var c = 0; c < cols; c++) {
    b.write('<c r="${columnName(c)}1" t="inlineStr" s="1"><is><t>${xmlEscape(s.headers[c])}</t></is></c>');
  }
  b.write('</row>');
  for (var r = 0; r < s.rows.length; r++) {
    final row = s.rows[r];
    b.write('<row r="${r + 2}">');
    for (var c = 0; c < row.length && c < cols; c++) {
      final ref = '${columnName(c)}${r + 2}';
      final v = row[c];
      if (v == null) continue;
      if (v is bool) {
        b.write('<c r="$ref" t="inlineStr"><is><t>${v ? 'evet' : 'hayır'}</t></is></c>');
      } else if (v is num) {
        if (v.isFinite) b.write('<c r="$ref"><v>$v</v></c>');
      } else if (v is DateTime) {
        b.write('<c r="$ref" s="2"><v>${excelSerial(v)}</v></c>');
      } else {
        b.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(v.toString())}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b
    ..write('</sheetData>')
    ..write('<autoFilter ref="A1:${columnName(cols - 1)}${s.rows.length + 1}"/>')
    ..write('</worksheet>');
  return b.toString();
}

int _displayLength(Object? v) => switch (v) {
      null => 0,
      DateTime() => 16,
      _ => v.toString().length,
    };

/// Sayfa adı: en fazla 31 karakter, []:*?/\ olmadan, tekrarsız.
List<String> _uniqueNames(List<String> raw) {
  final out = <String>[];
  for (final r in raw) {
    var name = r.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (name.isEmpty) name = 'Sayfa';
    if (name.length > 31) name = name.substring(0, 31);
    var candidate = name;
    for (var i = 2; out.contains(candidate); i++) {
      final suffix = ' ($i)';
      candidate = name.length + suffix.length > 31 ? name.substring(0, 31 - suffix.length) + suffix : name + suffix;
    }
    out.add(candidate);
  }
  return out;
}
