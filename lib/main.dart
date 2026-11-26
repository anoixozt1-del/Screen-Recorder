import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ======================= SAZLAMALAR =======================
class Cfg {
  static late SharedPreferences _p;
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static int get res => _p.getInt('res') ?? 1080;
  static set res(int v) => _p.setInt('res', v);
  static int get fps => _p.getInt('fps') ?? 30;
  static set fps(int v) => _p.setInt('fps', v);
  static int get bitrate => _p.getInt('bitrate') ?? 8;
  static set bitrate(int v) => _p.setInt('bitrate', v);
  static int get audio => _p.getInt('audio') ?? 1; // 0 yok, 1 mikrofon
  static set audio(int v) => _p.setInt('audio', v);
  static bool get wm => _p.getBool('wm') ?? true; // watermark ilkibashda acyk
  static set wm(bool v) => _p.setBool('wm', v);
  static int get shotDelay => _p.getInt('shotDelay') ?? 5;
  static set shotDelay(int v) => _p.setInt('shotDelay', v);
  static int get autoStop => _p.getInt('autoStop') ?? 0;
  static set autoStop(int v) => _p.setInt('autoStop', v);
  static bool get haptic => _p.getBool('haptic') ?? true;
  static set haptic(bool v) => _p.setBool('haptic', v);
  static String get prefix => _p.getString('prefix') ?? 'PartsezRec';
  static set prefix(String v) => _p.setString('prefix', v);
}

// ======================= WATERMARK =======================
class WmBadge extends StatelessWidget {
  final double scale;
  const WmBadge({super.key, this.scale = 1});
  static const String txt = 'Partsez recVideo';

  Widget _t(Color c, double d) => Transform.translate(
        offset: Offset(d, d),
        child: Text(txt,
            style: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: c)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(10 * scale),
        boxShadow: [
          BoxShadow(
              color: const Color(0x99000000),
              blurRadius: 14 * scale,
              spreadRadius: 1 * scale)
        ],
      ),
      child: Stack(children: [
        _t(const Color(0xFF2B2B4A), 2.4 * scale),
        _t(const Color(0xFF3F3F6E), 1.6 * scale),
        _t(const Color(0xFF5A5A9A), 0.8 * scale),
        _t(Colors.white, 0),
      ]),
    );
  }
}

// Ekranyn ustunde yuzyan overlay (wideoda gorunmegi ucin)
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.bottomRight,
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomRight,
              child: WmBadge()),
        ),
      ),
    ),
  ));
}

// Skrinsuta watermark cyzmak (Canvas)
Future<Uint8List> stampImage(Uint8List src) async {
  final codec = await ui.instantiateImageCodec(src);
  final img = (await codec.getNextFrame()).image;
  final w = img.width.toDouble();
  final h = img.height.toDouble();
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec);
  cv.drawImage(img, Offset.zero, Paint());

  final fs = (w < h ? w : h) / 34;
  TextPainter tp(Color c) => TextPainter(
        text: TextSpan(
            text: WmBadge.txt,
            style: TextStyle(
                fontSize: fs,
                fontWeight: FontWeight.w900,
                letterSpacing: fs * 0.04,
                color: c)),
        textDirection: TextDirection.ltr,
      )..layout();

  final main = tp(Colors.white);
  final padX = fs * 0.7;
  final padY = fs * 0.4;
  final bw = main.width + padX * 2;
  final bh = main.height + padY * 2;
  final m = fs;
  final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w - bw - m, h - bh - m * 1.6, bw, bh),
      Radius.circular(fs * 0.7));

  cv.drawRRect(
      rect.inflate(fs * 0.2),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fs * 0.5));
  cv.drawRRect(rect, Paint()..color = const Color(0xB3000000));

  final ox = rect.left + padX;
  final oy = rect.top + padY;
  final layers = [
    [3, const Color(0xFF2B2B4A)],
    [2, const Color(0xFF3F3F6E)],
    [1, const Color(0xFF5A5A9A)],
  ];
  for (final l in layers) {
    final d = (l[0] as int) * fs * 0.05;
    tp(l[1] as Color).paint(cv, Offset(ox + d, oy + d));
  }
  main.paint(cv, Offset(ox, oy));

  final out = await rec.endRecording().toImage(img.width, img.height);
  final bd = await out.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

// ======================= APP =======================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cfg.init();
  runApp(const RecApp());
}

class RecApp extends StatelessWidget {
  const RecApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Partsez recVideo',
      theme: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: const Color(0xFF12121A)),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool rec = false;
  bool busy = false;
  int sec = 0;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  String fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ---------- rugsatlar ----------
  Future<bool> _perms() async {
    if (Cfg.audio == 1) {
      final m = await Permission.microphone.request();
      if (!m.isGranted) {
        toast('Mikrofon rugsady berilmedi');
        return false;
      }
    }
    await Permission.notification.request();
    if (Cfg.wm) {
      bool g = await FlutterOverlayWindow.isPermissionGranted();
      if (!g) {
        await FlutterOverlayWindow.requestPermission();
        toast('Watermark ucin rugsat beriň we yzyna gaydyp tazeden basyň');
        return false;
      }
    }
    return true;
  }

  Future<void> _showOv() async {
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 110,
        width: 340,
        alignment: OverlayAlignment.bottomRight,
        flag: OverlayFlag.clickThrough,
        enableDrag: false,
        overlayTitle: 'Partsez recVideo',
        overlayContent: 'Watermark',
      );
    } catch (_) {}
  }

  Future<void> _hideOv() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  Future<void> setWm(bool v) async {
    setState(() => Cfg.wm = v);
    if (rec) {
      if (v) {
        await _showOv();
      } else {
        await _hideOv();
      }
    }
  }

  // ---------- wideo yazgy ----------
  Future<void> startRec() async {
    if (rec || busy) return;
    if (!await _perms()) return;
    final name = '${Cfg.prefix}_${DateTime.now().millisecondsSinceEpoch}';
    bool ok = false;
    try {
      ok = Cfg.audio == 1
          ? await FlutterScreenRecording.startRecordScreenAndAudio(name)
          : await FlutterScreenRecording.startRecordScreen(name);
    } catch (e) {
      toast('Yalnys: $e');
    }
    if (!ok) {
      toast('Yazgy baslamady');
      return;
    }
    if (Cfg.wm) await _showOv();
    if (Cfg.haptic) HapticFeedback.mediumImpact();
    setState(() {
      rec = true;
      sec = 0;
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => sec++);
      if (Cfg.autoStop > 0 && sec >= Cfg.autoStop * 60) stopRec();
    });
    toast('Yazgy basladi. Home basyp isleyan programmana gecin');
  }

  Future<void> stopRec() async {
    if (!rec) return;
    _t?.cancel();
    setState(() {
      rec = false;
      busy = true;
    });
    try {
      final path = await FlutterScreenRecording.stopRecordScreen;
      await _hideOv();
      await Gal.putVideo(path, album: 'PartsezRec');
      if (Cfg.haptic) HapticFeedback.mediumImpact();
      toast('Wideo galereya saklandy');
    } catch (e) {
      await _hideOv();
      toast('Yalnys: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- skrinsut ----------
  Future<void> shot() async {
    if (rec || busy) return;
    final d = Cfg.shotDelay;
    setState(() => busy = true);
    try {
      final ok = await FlutterScreenRecording.startRecordScreen(
          'shot_${DateTime.now().millisecondsSinceEpoch}');
      if (!ok) {
        toast('Rugsat berilmedi');
        return;
      }
      toast('$d sekuntdan son surat alynar. Home basyp ekrana gecin');
      await Future.delayed(Duration(seconds: d + 1));
      final path = await FlutterScreenRecording.stopRecordScreen;
      Uint8List? b = await VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: ImageFormat.PNG,
          timeMs: d * 1000,
          quality: 100);
      if (b == null) {
        toast('Surat alynmady');
        return;
      }
      if (Cfg.wm) b = await stampImage(b);
      final f = File(
          '${Directory.systemTemp.path}/${Cfg.prefix}_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(b);
      await Gal.putImage(f.path, album: 'PartsezRec');
      try {
        await f.delete();
        await File(path).delete();
      } catch (_) {}
      if (Cfg.haptic) HapticFeedback.mediumImpact();
      toast('Skrinsut galereya saklandy');
    } catch (e) {
      toast('Yalnys: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- modal kömekçileri ----------
  Future<void> modal(String title, IconData ic, Color col,
      List<Widget> Function(StateSetter s) build) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: StatefulBuilder(
          builder: (ctx, s) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(ic, color: col, size: 28),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                ...build(s),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Yap')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget lbl(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(color: Colors.white70)),
      );

  Widget note(String t) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(t,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      );

  Widget chips(StateSetter s, List<String> l, int sel, void Function(int) on,
      Color col) {
    return Wrap(spacing: 8, runSpacing: 4, children: [
      for (int i = 0; i < l.length; i++)
        ChoiceChip(
          label: Text(l[i]),
          selected: i == sel,
          selectedColor: col,
          onSelected: (_) {
            on(i);
            s(() {});
          },
        ),
    ]);
  }

  // ---------- 6 sany modal ----------
  void openVideo() {
    const c = Color(0xFFFF7043);
    const rs = [480, 720, 1080, 1440];
    const fp = [24, 30, 60];
    modal('Wideo', Icons.videocam, c, (s) => [
          lbl('Resolution'),
          chips(s, rs.map((e) => '${e}p').toList(), rs.indexOf(Cfg.res),
              (i) => Cfg.res = rs[i], c),
          lbl('FPS'),
          chips(s, fp.map((e) => '$e').toList(), fp.indexOf(Cfg.fps),
              (i) => Cfg.fps = fp[i], c),
          lbl('Bitrate: ${Cfg.bitrate} Mbps'),
          Slider(
            value: Cfg.bitrate.toDouble(),
            min: 2,
            max: 20,
            divisions: 18,
            activeColor: c,
            onChanged: (v) {
              Cfg.bitrate = v.round();
              s(() {});
            },
          ),
          note(
              'Bellik: bu bahalar saklanyar. Android plugin olary hazir kabul etmeyar, native birikdirme indiki etapda.'),
        ]);
  }

  void openAudio() {
    const c = Color(0xFF29B6F6);
    modal('Ses', Icons.mic, c, (s) => [
          lbl('Ses cesmesi'),
          chips(s, ['Ses yok', 'Mikrofon'], Cfg.audio, (i) => Cfg.audio = i, c),
          note('Telefonyn ici sesi bu plugin bilen yazyp bolmayar.'),
        ]);
  }

  void openWm() {
    const c = Color(0xFFEC407A);
    modal('Watermark', Icons.branding_watermark, c, (s) => [
          const SizedBox(height: 12),
          const Center(child: WmBadge(scale: 1.4)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Watermark acyk'),
            value: Cfg.wm,
            activeColor: c,
            onChanged: (v) async {
              await setWm(v);
              s(() {});
            },
          ),
          note('Sag asaky burcda. Wideoda we skrinsutda gorunyar.'),
        ]);
  }

  void openShot() {
    const c = Color(0xFF26A69A);
    const ds = [3, 5, 10];
    modal('Skrinsut', Icons.photo_camera, c, (s) => [
          lbl('Gijikdirme (sekunt)'),
          chips(s, ds.map((e) => '$e s').toList(), ds.indexOf(Cfg.shotDelay),
              (i) => Cfg.shotDelay = ds[i], c),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              shot();
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text('Indi al'),
          ),
          note(
              'Rugsat soralanda tassyklan, son Home basyp isleyan ekranyna geciň.'),
        ]);
  }

  void openTools() {
    const c = Color(0xFF00ACC1);
    const au = [0, 1, 5, 10, 30];
    modal('Gurallar', Icons.build, c, (s) => [
          lbl('Awto-duruzmak'),
          chips(s, au.map((e) => e == 0 ? 'Yok' : '$e min').toList(),
              au.indexOf(Cfg.autoStop), (i) => Cfg.autoStop = au[i], c),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Titremek (basla/duruz)'),
            value: Cfg.haptic,
            activeColor: c,
            onChanged: (v) {
              Cfg.haptic = v;
              s(() {});
            },
          ),
        ]);
  }

  void openGeneral() {
    const c = Color(0xFF7986CB);
    modal('Umumy', Icons.settings, c, (s) => [
          lbl('Fayl ady (prefiks)'),
          TextField(
            controller: TextEditingController(text: Cfg.prefix),
            onChanged: (v) {
              final x = v.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
              Cfg.prefix = x.isEmpty ? 'PartsezRec' : x;
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          note('Saklanyan yeri: Galereya > PartsezRec albomy.'),
        ]);
  }

  // ---------- UI ----------
  Widget card(String t, String sub, IconData ic, List<Color> cols,
      VoidCallback tap,
      {Widget? trail}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: cols),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: cols.first.withOpacity(.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6))
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(16)),
                  child: Icon(ic, size: 30, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(sub,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                trail ?? const Icon(Icons.chevron_right, color: Colors.white70),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(children: [
              const Expanded(
                child: Text('Partsez recVideo',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: rec ? Colors.red : Colors.white12,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(rec ? 'REC  ${fmt(sec)}' : 'Tayyar',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                card(
                    'Wideo',
                    '${Cfg.res}p  -  ${Cfg.fps} FPS  -  ${Cfg.bitrate} Mbps',
                    Icons.videocam,
                    const [Color(0xFFFF5252), Color(0xFFFF9800)],
                    openVideo),
                card(
                    'Ses',
                    Cfg.audio == 1 ? 'Mikrofon acyk' : 'Ses yok',
                    Icons.mic,
                    const [Color(0xFF2979FF), Color(0xFF00B0FF)],
                    openAudio),
                card(
                  'Watermark',
                  Cfg.wm ? 'Acyk - Partsez recVideo' : 'Yapyk',
                  Icons.branding_watermark,
                  const [Color(0xFFD81B60), Color(0xFFF06292)],
                  openWm,
                  trail: Switch(
                      value: Cfg.wm,
                      activeColor: Colors.white,
                      onChanged: (v) => setWm(v)),
                ),
                card(
                    'Skrinsut',
                    '${Cfg.shotDelay} sekunt gijikdirme',
                    Icons.photo_camera,
                    const [Color(0xFF1B9E5A), Color(0xFF26C6A0)],
                    openShot),
                card(
                    'Gurallar',
                    Cfg.autoStop == 0
                        ? 'Awto-duruzmak yok'
                        : 'Awto-duruz: ${Cfg.autoStop} min',
                    Icons.build,
                    const [Color(0xFF00838F), Color(0xFF26C6DA)],
                    openTools),
                card(
                    'Umumy',
                    'Fayl ady: ${Cfg.prefix}',
                    Icons.settings,
                    const [Color(0xFF3949AB), Color(0xFF7986CB)],
                    openGeneral),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : (rec ? stopRec : startRec),
                  icon: Icon(rec ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(rec ? 'Duruz  ${fmt(sec)}' : 'Yazgyny basla'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rec ? Colors.orange : Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (rec || busy) ? null : shot,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Skrinsut'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B9E5A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
