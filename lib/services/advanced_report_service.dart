// خدمة التقارير المتقدمة v10.1
// تجمع الإحصائيات حسب صورة الـ PV: المنتهية المشغولة لكل برنامج
// + تصنيف حسب الشبكات (كهرباء/غاز/ماء/كل الشبكات)
// + تصدير قائمة المنتهية المشغولة فقط (Excel) + صورها (ZIP) + PDF
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'database_service.dart';
import '../models/beneficiary.dart';

class ProgramAdvanced {
  final String program;
  final int quota;            // الحصة (إجمالي السجلات في البرنامج)
  final int occupied;         // عدد السكنات المشغولة (المنتهية المشغولة)
  final int elec;             // المنتهية المشغولة المربوطة بالكهرباء
  final int gas;              // المنتهية المشغولة المربوطة بالغاز
  final int water;            // المنتهية المشغولة المربوطة بالماء
  final int sew;              // المنتهية المشغولة المربوطة بالتطهير
  final int allNetworks;      // مربوطة بكل الشبكات (كهرباء+غاز+ماء)
  final int allFour;          // مربوطة بالأربعة (إضافي)
  ProgramAdvanced({
    required this.program,
    required this.quota,
    required this.occupied,
    required this.elec,
    required this.gas,
    required this.water,
    required this.sew,
    required this.allNetworks,
    required this.allFour,
  });
}

class AdvancedReportService {
  static final AdvancedReportService _i = AdvancedReportService._();
  factory AdvancedReportService() => _i;
  AdvancedReportService._();

  final _db = DatabaseService();

  // ─────────────────────────────────────────────
  // ① حساب المنتهية المشغولة لكل برنامج + الشبكات
  // ─────────────────────────────────────────────
  Future<List<ProgramAdvanced>> computePerProgram() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        program,
        COUNT(*) AS quota,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة'
                 THEN 1 ELSE 0 END) AS occupied,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة' AND electricity=1
                 THEN 1 ELSE 0 END) AS elec,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة' AND gas=1
                 THEN 1 ELSE 0 END) AS gas,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة' AND water=1
                 THEN 1 ELSE 0 END) AS water,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة' AND sewage=1
                 THEN 1 ELSE 0 END) AS sew,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة'
                  AND electricity=1 AND gas=1 AND water=1
                 THEN 1 ELSE 0 END) AS all3,
        SUM(CASE WHEN done=1 AND status='منتهية ومشغولة'
                  AND electricity=1 AND gas=1 AND water=1 AND sewage=1
                 THEN 1 ELSE 0 END) AS all4
      FROM beneficiaries
      WHERE program IS NOT NULL AND program != ''
      GROUP BY program
      ORDER BY MIN(created_at) ASC
    ''');
    return rows.map((r) => ProgramAdvanced(
      program:     (r['program'] ?? '').toString(),
      quota:       (r['quota']    as int? ?? 0),
      occupied:    (r['occupied'] as int? ?? 0),
      elec:        (r['elec']     as int? ?? 0),
      gas:         (r['gas']      as int? ?? 0),
      water:       (r['water']    as int? ?? 0),
      sew:         (r['sew']      as int? ?? 0),
      allNetworks: (r['all3']     as int? ?? 0),
      allFour:     (r['all4']     as int? ?? 0),
    )).toList();
  }

  // ─────────────────────────────────────────────
  // ② قائمة المنتهية المشغولة فقط (لبرنامج أو الكل)
  // ─────────────────────────────────────────────
  Future<List<Beneficiary>> getOccupiedFinishedList({String? program}) async {
    final db = await _db.database;
    final where = StringBuffer("done=1 AND status='منتهية ومشغولة'");
    final args = <Object?>[];
    if (program != null && program.isNotEmpty) {
      where.write(' AND program = ?');
      args.add(program);
    }
    final maps = await db.query('beneficiaries',
        where: where.toString(), whereArgs: args, orderBy: 'last_name, first_name');
    return maps.map(Beneficiary.fromMap).toList();
  }

  // ─────────────────────────────────────────────
  // ③ تصدير قائمة المنتهية المشغولة → Excel
  // ─────────────────────────────────────────────
  Future<String> exportOccupiedListExcel({String? program}) async {
    final list = await getOccupiedFinishedList(program: program);
    if (list.isEmpty) throw Exception('لا توجد سكنات منتهية ومشغولة');

    final excel = Excel.createExcel();
    final sheet = excel['المنتهية_المشغولة'];
    const headers = [
      'الرقم', 'الإسم واللقب', 'تاريخ الميلاد', 'مكان الميلاد',
      'العنوان', 'البرنامج',
      'كهرباء', 'غاز', 'مياه', 'تطهير',
      'كل الشبكات', 'الحالة',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      final row = i + 1;
      final cell = (int c, dynamic v) => sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
          .value = (v is int ? IntCellValue(v) : TextCellValue(v.toString()));
      cell(0, i + 1);
      cell(1, b.displayName);
      cell(2, b.birthDate ?? '');
      cell(3, b.birthPlace ?? '');
      cell(4, b.address ?? '');
      cell(5, b.program ?? '');
      cell(6, b.electricity);
      cell(7, b.gas);
      cell(8, b.water);
      cell(9, b.sewage);
      cell(10, (b.electricity == 1 && b.gas == 1 && b.water == 1) ? 1 : 0);
      cell(11, b.status);
    }

    final dl = Directory('/storage/emulated/0/Download/تقارير_متقدمة_v10');
    if (!await dl.exists()) await dl.create(recursive: true);
    final safe = (program ?? 'الكل').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(dl.path, 'منتهية_مشغولة_${safe}_$ts.xlsx');
    await File(path).writeAsBytes(excel.encode()!);
    await OpenFile.open(path);
    return path;
  }

  // ─────────────────────────────────────────────
  // ④ تصدير صور المنتهية المشغولة فقط → ZIP
  // ─────────────────────────────────────────────
  Future<String> exportOccupiedFinishedPhotosZip({String? program}) async {
    final db = await _db.database;
    final where = StringBuffer(
        "done=1 AND status='منتهية ومشغولة' "
        "AND image_file_name IS NOT NULL AND image_file_name != ''");
    final args = <Object?>[];
    if (program != null && program.isNotEmpty) {
      where.write(' AND program = ?');
      args.add(program);
    }
    final rows = await db.query('beneficiaries',
        columns: ['image_file_name', 'image_path', 'first_name', 'last_name', 'program'],
        where: where.toString(), whereArgs: args);
    if (rows.isEmpty) throw Exception('لا توجد صور للمنتهية المشغولة');

    final archive = Archive();
    int n = 0;
    for (final r in rows) {
      final path = (r['image_path'] ?? '').toString();
      final name = (r['image_file_name'] ?? '').toString();
      if (path.isEmpty || name.isEmpty) continue;
      final f = File(path);
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      // تسمية الملف داخل الأرشيف: البرنامج/اسم_لقب_filename
      final prog = (r['program'] ?? 'عام').toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fn   = (r['first_name'] ?? '').toString().trim();
      final ln   = (r['last_name']  ?? '').toString().trim();
      final ext  = p.extension(name).isEmpty ? '.jpg' : p.extension(name);
      final entry = '$prog/${ln}_${fn}_$name'.replaceAll(' ', '_');
      archive.addFile(ArchiveFile(
          entry.endsWith(ext) ? entry : '$entry$ext',
          bytes.length, bytes));
      n++;
    }
    if (n == 0) throw Exception('لا توجد صور صالحة للتصدير');

    final dl = Directory('/storage/emulated/0/Download/تقارير_متقدمة_v10');
    if (!await dl.exists()) await dl.create(recursive: true);
    final safe = (program ?? 'الكل').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final fp   = p.join(dl.path, 'صور_منتهية_مشغولة_${safe}_$n\_$ts.zip');
    final bytes = ZipEncoder().encode(archive)!;
    await File(fp).writeAsBytes(bytes);
    return fp;
  }

  // ─────────────────────────────────────────────
  // ⑤ تصدير تقرير PDF متقدم — حسب صورة الـ PV
  // ─────────────────────────────────────────────
  Future<String> exportAdvancedPdf({
    required String wilaya,
    required String daira,
    required String baladia,
    required String reportNumber,
    required String dateAr,
  }) async {
    final stats = await computePerProgram();

    // تحميل خط Cairo من الأصول
    final fontReg  = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));

    final theme = pw.ThemeData.withFont(base: fontReg, bold: fontBold);

    final pdf = pw.Document(theme: theme);

    pw.Widget _kpi(String label, int v, PdfColor color) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
          color: color, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(children: [
        pw.Text('$v',
            style: pw.TextStyle(fontSize: 22, color: PdfColors.white,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(label, textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.white)),
      ]),
    );

    final totalQuota = stats.fold<int>(0, (s, e) => s + e.quota);
    final totalOcc   = stats.fold<int>(0, (s, e) => s + e.occupied);
    final totalElec  = stats.fold<int>(0, (s, e) => s + e.elec);
    final totalGas   = stats.fold<int>(0, (s, e) => s + e.gas);
    final totalWater = stats.fold<int>(0, (s, e) => s + e.water);
    final totalAll3  = stats.fold<int>(0, (s, e) => s + e.allNetworks);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => [
        // ── ترويسة
        pw.Center(child: pw.Text('الجمهورية الجزائرية الديمقراطية الشعبية',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline))),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('رقم: $reportNumber',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('ولاية: $wilaya',  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('دائرة: $daira',  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('بلدية: $baladia',style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ]),
        ]),
        pw.Divider(color: PdfColors.indigo900, thickness: 1),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('تقرير إحصائي متقدم — السكن الريفي',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900))),
        pw.Center(child: pw.Text('بتاريخ: $dateAr',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800))),
        pw.SizedBox(height: 14),

        // ── KPIs
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: [
          _kpi('إجمالي الحصة',     totalQuota, PdfColors.indigo700),
          _kpi('منتهية ومشغولة',   totalOcc,   PdfColors.teal700),
          _kpi('بكل الشبكات',      totalAll3,  PdfColors.green800),
          _kpi('برامج',            stats.length, PdfColors.deepPurple),
        ]),
        pw.SizedBox(height: 14),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: [
          _kpi('كهرباء',  totalElec,  PdfColors.amber800),
          _kpi('غاز',     totalGas,   PdfColors.orange800),
          _kpi('ماء',     totalWater, PdfColors.blue700),
        ]),
        pw.SizedBox(height: 16),

        // ── جدول البرامج
        pw.Text('تفصيل المنتهية المشغولة حسب كل برنامج',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900)),
        pw.SizedBox(height: 6),
        pw.Table.fromTextArray(
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {0: pw.Alignment.centerRight},
          headers: const [
            'البرنامج', 'الحصة', 'منتهية ومشغولة',
            'كهرباء', 'غاز', 'ماء', 'كل الشبكات',
          ],
          data: [
            for (final r in stats)
              [r.program, r.quota, r.occupied, r.elec, r.gas, r.water, r.allNetworks],
            ['الإجمالي', totalQuota, totalOcc, totalElec, totalGas, totalWater, totalAll3],
          ],
          cellHeight: 22,
        ),

        pw.SizedBox(height: 18),
        pw.Text('ملاحظات:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900)),
        pw.Bullet(text: 'الأرقام تخص فقط السكنات المنتهية والمشغولة المعاينة ميدانياً.'),
        pw.Bullet(text: 'عمود "كل الشبكات" = مربوطة بالكهرباء والغاز والماء معاً.'),
        pw.Bullet(text: 'المصدر: قاعدة بيانات تطبيق إحصاء السكن الريفي v10.1.'),
      ],
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.center,
        child: pw.Text('تطبيق التقارير المتقدمة v10.1 — صفحة ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ),
    ));

    final dl = Directory('/storage/emulated/0/Download/تقارير_متقدمة_v10');
    if (!await dl.exists()) await dl.create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fp = p.join(dl.path, 'تقرير_متقدم_${reportNumber.replaceAll('/', '-')}_$ts.pdf');
    await File(fp).writeAsBytes(await pdf.save());
    await OpenFile.open(fp);
    return fp;
  }
}
