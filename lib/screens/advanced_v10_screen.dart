// شاشة التقارير المتقدمة v10.1
// تعرض حسب صورة الـ PV: المنتهية المشغولة لكل برنامج + الشبكات
// مع 4 أزرار تصدير: PDF · Excel (قائمة) · صور (ZIP) · الكل
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/advanced_report_service.dart';
import '../services/database_service.dart';

class AdvancedV10Screen extends StatefulWidget {
  const AdvancedV10Screen({super.key});

  @override
  State<AdvancedV10Screen> createState() => _AdvancedV10ScreenState();
}

class _AdvancedV10ScreenState extends State<AdvancedV10Screen> {
  final _svc = AdvancedReportService();
  final _db  = DatabaseService();
  late Future<List<ProgramAdvanced>> _future;
  bool _busy = false;
  String? _filterProgram; // null = الكل

  // بيانات الترويسة الافتراضية (مطابقة لصورة الـ PV)
  final _wilayaCtrl  = TextEditingController(text: 'المدية');
  final _dairaCtrl   = TextEditingController(text: 'تابلاط');
  final _baladiaCtrl = TextEditingController(text: 'الحوضان');
  final _numCtrl     = TextEditingController(text: '2026/001');

  @override
  void initState() {
    super.initState();
    _future = _svc.computePerProgram();
  }

  @override
  void dispose() {
    _wilayaCtrl.dispose();
    _dairaCtrl.dispose();
    _baladiaCtrl.dispose();
    _numCtrl.dispose();
    super.dispose();
  }

  String get _dateAr {
    final now = DateTime.now();
    const days   = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    const months = ['جانفي','فيفري','مارس','أفريل','ماي','جوان',
                    'جويلية','أوت','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  Future<void> _wrap(Future<void> Function() job, String okMsg) async {
    setState(() => _busy = true);
    try {
      await job();
      _snack(okMsg, true);
    } catch (e) {
      _snack('❌ $e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, bool ok) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ));

  // ── أزرار التصدير ─────────────────────────────
  Future<void> _exportPdf() => _wrap(() async {
        await _svc.exportAdvancedPdf(
          wilaya:       _wilayaCtrl.text.trim(),
          daira:        _dairaCtrl.text.trim(),
          baladia:      _baladiaCtrl.text.trim(),
          reportNumber: _numCtrl.text.trim(),
          dateAr:       _dateAr,
        );
      }, '✅ تم إنشاء التقرير PDF');

  Future<void> _exportExcel() => _wrap(() async {
        final path = await _svc.exportOccupiedListExcel(program: _filterProgram);
        await Share.shareXFiles([XFile(path)],
            text: 'قائمة المنتهية المشغولة');
      }, '✅ تم تصدير Excel');

  Future<void> _exportPhotos() => _wrap(() async {
        final path = await _svc.exportOccupiedFinishedPhotosZip(program: _filterProgram);
        await Share.shareXFiles([XFile(path)],
            text: 'صور المنتهية المشغولة');
      }, '✅ تم تصدير الصور');

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    final results = <String>[];
    try {
      results.add(await _svc.exportAdvancedPdf(
        wilaya: _wilayaCtrl.text.trim(),
        daira: _dairaCtrl.text.trim(),
        baladia: _baladiaCtrl.text.trim(),
        reportNumber: _numCtrl.text.trim(),
        dateAr: _dateAr,
      ));
      try { results.add(await _svc.exportOccupiedListExcel(program: _filterProgram)); }
      catch (_) {}
      try { results.add(await _svc.exportOccupiedFinishedPhotosZip(program: _filterProgram)); }
      catch (_) {}
      _snack('✅ تم تصدير ${results.length} ملف', true);
    } catch (e) {
      _snack('❌ $e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── الواجهة ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('📊 التقارير المتقدمة v10.1'),
        backgroundColor: const Color(0xFF1A237E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _svc.computePerProgram()),
          ),
        ],
      ),
      body: Stack(children: [
        FutureBuilder<List<ProgramAdvanced>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('❌ ${snap.error}'));
            }
            final stats = snap.data ?? [];
            return _buildContent(stats);
          },
        ),
        if (_busy)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ]),
    );
  }

  Widget _buildContent(List<ProgramAdvanced> stats) {
    final totalQuota = stats.fold<int>(0, (s, e) => s + e.quota);
    final totalOcc   = stats.fold<int>(0, (s, e) => s + e.occupied);
    final totalElec  = stats.fold<int>(0, (s, e) => s + e.elec);
    final totalGas   = stats.fold<int>(0, (s, e) => s + e.gas);
    final totalWater = stats.fold<int>(0, (s, e) => s + e.water);
    final totalAll3  = stats.fold<int>(0, (s, e) => s + e.allNetworks);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── ترويسة قابلة للتعديل
        _card(
          title: '📋 بيانات المحضر (للتقرير)',
          color: Colors.indigo,
          child: Column(children: [
            _field(_wilayaCtrl,  'الولاية',    Icons.location_city),
            const SizedBox(height: 8),
            _field(_dairaCtrl,   'الدائرة',    Icons.map_outlined),
            const SizedBox(height: 8),
            _field(_baladiaCtrl, 'البلدية',    Icons.location_on_outlined),
            const SizedBox(height: 8),
            _field(_numCtrl,     'رقم المحضر', Icons.tag),
          ]),
        ),

        const SizedBox(height: 12),

        // ── KPIs
        Row(children: [
          Expanded(child: _kpiCard('إجمالي الحصة',   totalQuota, const Color(0xFF1A237E), Icons.home_work)),
          const SizedBox(width: 8),
          Expanded(child: _kpiCard('منتهية مشغولة', totalOcc,   const Color(0xFF00897B), Icons.check_circle)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _kpiCard('كل الشبكات', totalAll3, const Color(0xFF2E7D32), Icons.workspace_premium)),
          const SizedBox(width: 8),
          Expanded(child: _kpiCard('كهرباء',    totalElec, const Color(0xFFFF8F00), Icons.bolt)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _kpiCard('غاز', totalGas,   const Color(0xFFE65100), Icons.local_fire_department)),
          const SizedBox(width: 8),
          Expanded(child: _kpiCard('ماء', totalWater, const Color(0xFF1565C0), Icons.water_drop)),
        ]),

        const SizedBox(height: 16),

        // ── فلتر البرنامج
        _card(
          title: '🔍 فلتر البرنامج (للتصدير)',
          color: Colors.deepPurple,
          child: DropdownButtonFormField<String?>(
            value: _filterProgram,
            decoration: const InputDecoration(
              labelText: 'البرنامج',
              prefixIcon: Icon(Icons.folder_outlined),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('الكل (جميع البرامج)')),
              for (final s in stats)
                DropdownMenuItem(value: s.program, child: Text(s.program)),
            ],
            onChanged: (v) => setState(() => _filterProgram = v),
          ),
        ),

        const SizedBox(height: 12),

        // ── جدول البرامج
        _card(
          title: '🏗️ تفصيل المنتهية المشغولة حسب كل برنامج',
          color: const Color(0xFF1A237E),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF1A237E)),
              headingTextStyle: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 12),
              dataTextStyle: const TextStyle(fontSize: 12),
              columns: const [
                DataColumn(label: Text('البرنامج')),
                DataColumn(label: Text('الحصة'),    numeric: true),
                DataColumn(label: Text('مشغولة'),  numeric: true),
                DataColumn(label: Text('كهرباء'),  numeric: true),
                DataColumn(label: Text('غاز'),      numeric: true),
                DataColumn(label: Text('ماء'),      numeric: true),
                DataColumn(label: Text('كل الشبكات'), numeric: true),
              ],
              rows: [
                for (final s in stats)
                  DataRow(cells: [
                    DataCell(Text(s.program)),
                    DataCell(Text('${s.quota}')),
                    DataCell(Text('${s.occupied}',
                        style: const TextStyle(fontWeight: FontWeight.bold,
                            color: Color(0xFF00897B)))),
                    DataCell(Text('${s.elec}')),
                    DataCell(Text('${s.gas}')),
                    DataCell(Text('${s.water}')),
                    DataCell(Text('${s.allNetworks}',
                        style: const TextStyle(fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32)))),
                  ]),
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFFE8EAF6)),
                  cells: [
                    const DataCell(Text('الإجمالي',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalQuota',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalOcc',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalElec',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalGas',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalWater',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$totalAll3',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── أزرار التصدير
        _card(
          title: '📤 التصدير',
          color: Colors.teal,
          child: Column(children: [
            _exportBtn('📄 تصدير تقرير PDF متقدم',
                Icons.picture_as_pdf, Colors.red.shade700, _exportPdf),
            const SizedBox(height: 8),
            _exportBtn('📊 تصدير قائمة Excel — منتهية مشغولة',
                Icons.grid_on, Colors.green.shade700, _exportExcel),
            const SizedBox(height: 8),
            _exportBtn('🖼️ تصدير صور المنتهية المشغولة (ZIP)',
                Icons.image, Colors.indigo.shade700, _exportPhotos),
            const SizedBox(height: 8),
            _exportBtn('📦 تصدير الكل (PDF + Excel + صور)',
                Icons.download_for_offline, Colors.deepPurple.shade700, _exportAll),
          ]),
        ),

        const SizedBox(height: 8),
        const Center(
          child: Text('تطبيق التقارير المتقدمة v10.1 · مساعد فقط',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ]),
    );
  }

  // ── widgets مساعدة ─────────────────────────────
  Widget _card({required String title, required Color color, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black12.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold,
              fontSize: 14, color: color)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _kpiCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3),
            blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(NumberFormat.decimalPattern('ar').format(value),
              style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _exportBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
