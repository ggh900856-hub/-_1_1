import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MontajApp());
}

class MontajApp extends StatelessWidget {
  const MontajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مونتاج',
      locale: const Locale('ar'),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0B0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE7E8EA),
          surface: Color(0xFF16181B),
          onSurface: Color(0xFFF2F3F5),
        ),
        fontFamily: null,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const StudioPage(),
    );
  }
}

class StylePreset {
  const StylePreset({
    required this.id,
    required this.label,
    required this.hold,
    required this.transitions,
    required this.contrast,
    required this.saturation,
    required this.letterbox,
  });

  final String id;
  final String label;
  final double hold;
  final List<String> transitions;
  final double contrast;
  final double saturation;
  final bool letterbox;
}

const styles = <StylePreset>[
  StylePreset(id: 'reels', label: 'ريلز', hold: 1.3, transitions: ['wipeleft', 'fade', 'zoomin'], contrast: 1.08, saturation: 1.1, letterbox: false),
  StylePreset(id: 'cinematic', label: 'سينمائي', hold: 2.6, transitions: ['fade', 'fadeblack', 'dissolve'], contrast: 1.04, saturation: 0.92, letterbox: true),
  StylePreset(id: 'ad', label: 'إعلان', hold: 1.5, transitions: ['fadewhite', 'zoomin', 'wipeleft'], contrast: 1.12, saturation: 1.08, letterbox: false),
  StylePreset(id: 'event', label: 'مناسبة', hold: 2.2, transitions: ['fade', 'circleopen', 'radial'], contrast: 1.05, saturation: 1.02, letterbox: false),
  StylePreset(id: 'travel', label: 'سفر', hold: 2.0, transitions: ['slideleft', 'smoothleft', 'fade'], contrast: 1.06, saturation: 1.08, letterbox: false),
  StylePreset(id: 'wedding', label: 'زفاف', hold: 2.8, transitions: ['fade', 'radial', 'circleopen'], contrast: 1.02, saturation: 0.96, letterbox: false),
  StylePreset(id: 'night', label: 'ليلي', hold: 2.4, transitions: ['fadeblack', 'fade', 'hblur'], contrast: 1.14, saturation: 0.8, letterbox: true),
  StylePreset(id: 'sport', label: 'رياضي', hold: 1.1, transitions: ['wipeleft', 'slideright', 'fadewhite'], contrast: 1.16, saturation: 1.12, letterbox: false),
  StylePreset(id: 'luxury', label: 'فخم', hold: 2.5, transitions: ['fade', 'circleopen', 'smoothleft'], contrast: 1.05, saturation: 0.98, letterbox: true),
  StylePreset(id: 'vlog', label: 'فلوج', hold: 1.8, transitions: ['smoothleft', 'slideleft', 'fade'], contrast: 1.04, saturation: 1.04, letterbox: false),
];

class CapColor {
  const CapColor(this.name, this.color);
  final String name;
  final Color color;
}

const capColors = <CapColor>[
  CapColor('أبيض', Color(0xFFF4F1EA)),
  CapColor('أسود', Color(0xFF0A0B0C)),
  CapColor('رملي', Color(0xFFD7C4A3)),
  CapColor('وردي', Color(0xFFD9A8A8)),
  CapColor('نعناعي', Color(0xFF9CBFB0)),
  CapColor('سماوي', Color(0xFF9BB4C4)),
];

class Shot {
  Shot({required this.path, required this.isImage, required this.name, required this.duration});
  final String path;
  final bool isImage;
  final String name;
  final double duration;
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _sub = TextEditingController();
  final List<Shot> _shots = [];

  int _style = 0;
  int _aspect = 0;
  int _color = 0;
  int _size = 1;
  int _place = 2;
  int _index = 0;
  bool _playing = false;
  bool _exporting = false;
  String _status = '';
  VideoPlayerController? _video;
  Timer? _timer;
  bool _alive = true;

  static const aspects = [
    ('ريلز', 720, 1280),
    ('يوتيوب', 1280, 720),
    ('مربع', 1080, 1080),
  ];

  StylePreset get style => styles[_style];

  @override
  void dispose() {
    _alive = false;
    _timer?.cancel();
    _video?.dispose();
    _title.dispose();
    _sub.dispose();
    super.dispose();
  }

  Future<void> _add({required bool images}) async {
    if (_shots.length >= 8) {
      _toast('الحد ٨ لقطات');
      return;
    }
    final picked = images ? await _picker.pickMultiImage() : await _picker.pickMultiVideo();
    if (picked.isEmpty) return;
    final room = 8 - _shots.length;
    for (final file in picked.take(room)) {
      final path = file.path;
      final duration = images ? style.hold : await _probe(path);
      if (!mounted) return;
      setState(() {
        _shots.add(Shot(
          path: path,
          isImage: images,
          name: file.name,
          duration: duration < 0.4 ? 2 : duration,
        ));
      });
    }
  }

  Future<double> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final raw = session.getMediaInformation()?.getDuration();
      final value = double.tryParse(raw ?? '') ?? 0;
      if (value > 0.3) return value;
    } catch (_) {}
    return 4;
  }
void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final video = _video;
    _video = null;
    await video?.pause();
    await video?.dispose();
    if (_alive && mounted) setState(() => _playing = false);
  }

  Future<void> _play() async {
    if (_shots.isEmpty) return;
    await _stop();
    if (!mounted) return;
    setState(() {
      _playing = true;
      _index = _index.clamp(0, _shots.length - 1);
    });
    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    if (!_playing || _shots.isEmpty) return;
    final shot = _shots[_index];
    final hold = shot.isImage ? style.hold : (shot.duration < style.hold ? shot.duration : style.hold);
    if (!shot.isImage) {
      final controller = VideoPlayerController.file(File(shot.path));
      _video = controller;
      try {
        await controller.initialize();
        await controller.setLooping(false);
        await controller.play();
        if (mounted) setState(() {});
      } catch (_) {
        _toast('تعذر تشغيل ${shot.name}');
      }
    } else if (mounted) {
      setState(() {});
    }
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (hold * 1000).round()), () async {
      if (!_alive || !_playing) return;
      await _video?.pause();
      await _video?.dispose();
      _video = null;
      if (!_alive) return;
      if (_index >= _shots.length - 1) {
        if (mounted) setState(() => _playing = false);
        return;
      }
      setState(() => _index += 1);
      await _showCurrent();
    });
  }

  Future<void> _export() async {
    if (_shots.isEmpty || _exporting) return;
    setState(() {
      _exporting = true;
      _status = 'بيجهّز اللقطات…';
    });
    await _stop();
    try {
      final dir = await getTemporaryDirectory();
      final work = Directory('\( {dir.path}/montaj_ \){DateTime.now().millisecondsSinceEpoch}');
      await work.create(recursive: true);
      final size = aspects[_aspect];
      final width = size.$2;
      final height = size.$3;
      final copied = <File>[];
      final durations = <double>[];
      for (var i = 0; i < _shots.length; i++) {
        final shot = _shots[i];
        final ext = _ext(shot.path, shot.isImage);
        final file = File('${work.path}/clip_$i.$ext');
        await File(shot.path).copy(file.path);
        copied.add(file);
        final hold = shot.isImage ? style.hold : (shot.duration < style.hold ? shot.duration : style.hold);
        durations.add(hold.clamp(0.8, 8));
      }
      setState(() => _status = 'بيكتب العبارة…');
      final png = File('${work.path}/caption.png');
      await _captionPng(
        text: _title.text,
        sub: _sub.text,
        color: capColors[_color].color,
        fontSize: [72, 104, 140][_size].toDouble() * (width / 720),
        yFactor: [0.22, 0.5, 0.78][_place],
        width: width,
        height: height,
        out: png,
      );
      setState(() => _status = 'بيمنتج الـ MP4…');
      final out = File('${work.path}/montaj.mp4');
      final command = _command(
        clips: copied,
        images: _shots.map((s) => s.isImage).toList(),
        durations: durations,
        caption: png,
        out: out,
        width: width,
        height: height,
      );
      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) {
        throw Exception('فشل الحفظ');
      }
      setState(() => _status = 'جاهز');
      await Share.shareXFiles([XFile(out.path)], subject: 'مونتاج', text: 'مونتاج');
      _toast('اتحفظ ملف MP4');
    } catch (_) {
      _toast('فشل حفظ MP4');
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _status = '';
        });
      }
    }
  }

  String _ext(String path, bool image) {
    final raw = path.split('.').last.toLowerCase();
    if (!image) return 'mp4';
    if (raw == 'png' || raw == 'webp' || raw == 'jpg' || raw == 'jpeg') {
      return raw == 'jpeg' ? 'jpg' : raw;
    }
    return 'jpg';
  }
String _command({
    required List<File> clips,
    required List<bool> images,
    required List<double> durations,
    required File caption,
    required File out,
    required int width,
    required int height,
  }) {
    final td = 0.4;
    final preset = style;
    final fit = preset.letterbox
        ? 'scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:black'
        : 'scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height';
    final grade = 'eq=contrast=\( {preset.contrast.toStringAsFixed(2)}:saturation= \){preset.saturation.toStringAsFixed(2)}';
    final args = <String>['-y'];
    for (var i = 0; i < clips.length; i++) {
      final d = durations[i].toStringAsFixed(2);
      if (images[i]) {
        args.addAll(['-loop', '1', '-framerate', '30', '-t', d, '-i', clips[i].path]);
      } else {
        args.addAll(['-t', d, '-i', clips[i].path]);
      }
    }
    args.addAll(['-i', caption.path]);
    final filters = <String>[];
    for (var i = 0; i < clips.length; i++) {
      final d = durations[i].toStringAsFixed(2);
      filters.add(
        '[$i:v]$fit,fps=30,format=yuv420p,trim=start=0:end=$d,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=$d,trim=duration=$d,setpts=PTS-STARTPTS,$grade[v$i]',
      );
    }
    var last = 'v0';
    if (clips.length > 1) {
      var acc = 0.0;
      for (var i = 0; i < clips.length - 1; i++) {
        acc += durations[i];
        final offset = (acc - td * (i + 1)).toStringAsFixed(2);
        final name = preset.transitions[i % preset.transitions.length];
        final outLabel = i == clips.length - 2 ? 'vmixed' : 'vx$i';
        filters.add('[\( last][v \){i + 1}]xfade=transition=\( name:duration= \){td.toStringAsFixed(2)}:offset=$offset[$outLabel]');
        last = outLabel;
      }
    }
    final capIndex = clips.length;
    filters.add('[$last][$capIndex:v]overlay=0:0:format=auto[outv]');
    final total = (durations.fold<double>(0, (a, b) => a + b) - td * (clips.length - 1)).clamp(0.8, 180).toStringAsFixed(2);
    args.addAll([
      '-f', 'lavfi', '-t', total, '-i', 'anullsrc=r=44100:cl=stereo',
      '-filter_complex', filters.join(';'),
      '-map', '[outv]',
      '-map', '${clips.length + 1}:a',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p',
      '-profile:v', 'baseline',
      '-level', '3.1',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-shortest',
      '-movflags', '+faststart',
      out.path,
    ]);
    return args.map(_quote).join(' ');
  }

  String _quote(String value) {
    if (value.contains(' ') || value.contains("'")) {
      return "'${value.replaceAll("'", r"'\''")}'";
    }
    return value;
  }

  Future<void> _captionPng({
    required String text,
    required String sub,
    required Color color,
    required double fontSize,
    required double yFactor,
    required int width,
    required int height,
    required File out,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final line = text.trim();
    if (line.isNotEmpty) {
      final main = TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1.12,
            shadows: const [Shadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 2))],
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: width * 0.88);
      TextPainter? extra;
      var block = main.height;
      final second = sub.trim();
      if (second.isNotEmpty) {
        extra = TextPainter(
          text: TextSpan(
            text: second,
            style: TextStyle(color: color, fontSize: fontSize * 0.42, fontWeight: FontWeight.w600, height: 1.2),
          ),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          maxLines: 2,
        )..layout(maxWidth: width * 0.8);
        block += 14 + extra.height;
      }
      final top = (height * yFactor - block / 2)
          .clamp(height * 0.06, height - block - height * 0.06)
          .toDouble();
      main.paint(canvas, Offset((width - main.width) / 2, top));
      extra?.paint(canvas, Offset((width - extra.width) / 2, top + main.height + 14));
    }
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final shot = _shots.isEmpty ? null : _shots[_index.clamp(0, _shots.length - 1)];
    final ratio = aspects[_aspect].$2 / aspects[_aspect].$3;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0B0C),
        title: const Text('مونتاج'),
        actions: [
          TextButton(
            onPressed: _shots.isEmpty || _exporting ? null : _export,
            child: Text(_exporting ? 'بيحفظ…' : 'احفظ MP4'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          AspectRatio(
            aspectRatio: ratio.clamp(0.45, 1.8).toDouble(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: const Color(0xFF111214),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (shot == null)
                      const Center(child: Text('أضف فيديو أو صورة', style: TextStyle(color: Color(0xFF9AA0A6))))
                    else if (!shot.isImage && _video != null && _video!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _video!.value.size.width,
                          height: _video!.value.size.height,
                          child: VideoPlayer(_video!),
                        ),
                      )
                    else if (shot.isImage)
                      Image.file(File(shot.path), fit: BoxFit.cover)
                    else
                      const Center(child: Icon(Icons.movie_outlined)),
                    if (_title.text.trim().isNotEmpty)
                      Align(
                        alignment: [Alignment.topCenter, Alignment.center, Alignment.bottomCenter][_place],
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _title.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: capColors[_color].color,
                              fontSize: [28, 40, 52][_size].toDouble(),
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              shadows: const [Shadow(color: Colors.black, blurRadius: 12)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _btn('أضف فيديو', Icons.video_library_outlined, () => _add(images: false))),
              const SizedBox(width: 8),
              Expanded(child: _btn('أضف صورة', Icons.image_outlined, () => _add(images: true))),
              const SizedBox(width: 8),
              _btn(_playing ? 'وقف' : 'شغّل', _playing ? Icons.pause : Icons.play_arrow, () {
                if (_playing) {
                  _stop();
                } else {
                  _play();
                }
              }),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Color(0xFF9AA0A6))),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _shots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final item = _shots[i];
                return GestureDetector(
                  onTap: () async {
                    await _stop();
                    setState(() => _index = i);
                  },
                  child: Container(
                    width: 120,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: i == _index ? const Color(0xFF22262C) : const Color(0xFF16181B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.isImage ? 'صورة' : 'فيديو', style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0A6))),
                        const SizedBox(height: 4),
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () async {
                              await _stop();
                              setState(() {
                                _shots.removeAt(i);
                                if (_index >= _shots.length) _index = 0;
                              });
                            },
                            child: const Icon(Icons.close, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text('الأسلوب'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < styles.length; i++)
                ChoiceChip(
                  label: Text(styles[i].label),
                  selected: _style == i,
                  onSelected: (_) => setState(() => _style = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('المقاس'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < aspects.length; i++)
                ChoiceChip(
                  label: Text(aspects[i].$1),
                  selected: _aspect == i,
                  onSelected: (_) => setState(() => _aspect = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            maxLength: 42,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'عبارة كبيرة', counterText: ''),
          ),
          TextField(
            controller: _sub,
            maxLength: 36,
            decoration: const InputDecoration(labelText: 'سطر تاني'),
          ),
          const SizedBox(height: 8),
          const Text('لون العبارة'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < capColors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _color = i),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: capColors[i].color,
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == i ? Colors.white : Colors.white24, width: _color == i ? 3 : 1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(['كبير', 'أكبر', 'عملاق'][i]),
                  selected: _size == i,
                  onSelected: (_) => setState(() => _size = i),
                ),
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(['أعلى', 'وسط', 'أسفل'][i]),
                  selected: _place == i,
                  onSelected: (_) => setState(() => _place = i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, IconData icon, VoidCallback onTap) {
    return FilledButton.icon(
      onPressed: _exporting ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFE7E8EA),
        foregroundColor: const Color(0xFF0A0B0C),
        minimumSize: const Size(0, 48),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}