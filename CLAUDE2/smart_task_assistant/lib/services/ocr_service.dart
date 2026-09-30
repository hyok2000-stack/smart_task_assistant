import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// OCR 文本识别服务：拍照/选图 → 离线识别文字。
///
/// 使用 ML Kit on-device 模型（中文简体），不依赖 Google Play Services，
/// 华为等无 GMS 设备可用，完全离线免费。
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  final ImagePicker _picker = ImagePicker();

  /// 拍照并识别文字。返回识别的文本，取消/失败返回 null。
  Future<String?> captureAndRecognize() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920, // 限制分辨率，加快识别速度
        imageQuality: 85,
      );
      if (photo == null) return null; // 用户取消
      return await recognizeImage(File(photo.path));
    } catch (e) {
      debugPrint('OCR 拍照失败: $e');
      return null;
    }
  }

  /// 从相册选图并识别文字。返回识别的文本，取消/失败返回 null。
  Future<String?> pickAndRecognize() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (image == null) return null;
      return await recognizeImage(File(image.path));
    } catch (e) {
      debugPrint('OCR 选图失败: $e');
      return null;
    }
  }

  /// 对图片文件做 OCR 识别（中文简体模型）。
  Future<String?> recognizeImage(File imageFile) async {
    final recognizer = TextRecognizer(
      script: TextRecognitionScript.chinese,
    );
    try {
      // 复制到应用缓存目录再用 fromFilePath——避开相册/相机缓存路径的
      // 权限与生命周期问题（部分华为设备上直接用原路径会原生崩溃）。
      final cacheDir = await getTemporaryDirectory();
      final ocrFile = File('${cacheDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await imageFile.copy(ocrFile.path);

      final inputImage = InputImage.fromFilePath(ocrFile.path);
      final RecognizedText result = await recognizer.processImage(inputImage);

      final text = result.text.trim();
      debugPrint('OCR 识别结果 (${text.length} 字): '
          '${text.substring(0, text.length > 50 ? 50 : text.length)}...');

      // 识别完清理临时文件
      try { await ocrFile.delete(); } catch (_) {}
      return text.isNotEmpty ? text : null;
    } catch (e) {
      debugPrint('OCR 识别失败: $e');
      return null;
    } finally {
      await recognizer.close();
    }
  }

  /// 将 OCR 文本智能拆分为任务字段：
  /// - 时间：识别日期/时间表述（明天/后天/X月X日/HH:mm/X点 等），转成 DateTime
  /// - 标题：优先取含"事由/关于/标题"的行，否则取第一个较长的实质行
  /// - 详情：其余行合并
  /// 返回 (title, content, dueTime)。
  ({String title, String content, DateTime? dueTime}) extractTaskFields(
      String ocrText) {
    var lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return (title: '', content: '', dueTime: null);

    final now = DateTime.now();

    // ===== 1. 提取时间 =====
    DateTime? dueTime;
    // 从所有行里找时间表述（去掉已匹配的部分）
    final timePatterns = <RegExp>[
      // X月X日（可带 HH:mm / X点X分 / 上午/下午）
      RegExp(r'(\d{1,2})月(\d{1,2})日'),
      // 明天/后天/大后天
      RegExp(r'(明天|后天|大后天)'),
      // X号
      RegExp(r'(\d{1,2})号'),
      // 今天内的时间：HH:mm 或 X点（X分）
      RegExp(r'(\d{1,2})[:：点](\d{0,2})分?'),
      // X天后 / X小时后
      RegExp(r'(\d+)天后'),
      RegExp(r'(\d+)小时后'),
    ];

    String timeSource = lines.join('\n');
    outer:
    for (final pattern in timePatterns) {
      final m = pattern.firstMatch(timeSource);
      if (m == null) continue;

      final matched = m.group(0)!;
      switch (pattern.pattern) {
        case r'(\d{1,2})月(\d{1,2})日':
          final month = int.tryParse(m.group(1)!) ?? now.month;
          final day = int.tryParse(m.group(2)!) ?? now.day;
          var year = now.year;
          if (month < now.month || (month == now.month && day < now.day)) {
            year++; // 日期已过，视为明年
          }
          dueTime = _withTimeOfDay(DateTime(year, month, day), timeSource, now);
          break outer;
        case r'(明天|后天|大后天)':
          final days = matched == '明天' ? 1 : (matched == '后天' ? 2 : 3);
          dueTime =
              _withTimeOfDay(DateTime(now.year, now.month, now.day + days),
                  timeSource, now);
          break outer;
        case r'(\d{1,2})号':
          final day = int.tryParse(m.group(1)!) ?? now.day;
          var year = now.year;
          var month = now.month;
          if (day < now.day) {
            month++; // 本月已过，视为下月
            if (month > 12) { month = 1; year++; }
          }
          dueTime = _withTimeOfDay(DateTime(year, month, day), timeSource, now);
          break outer;
        case r'(\d{1,2})[:：点](\d{0,2})分?':
          // 只有时刻无日期 → 今天（已过则明天）
          var hour = int.tryParse(m.group(1)!) ?? -1;
          final minute = int.tryParse(m.group(2) ?? '') ?? 0;
          if (hour < 0 || hour > 23 || minute > 59) continue;
          // 24小时制时钟图标误识别（如 "10:01 QOc"）过滤：时刻必须是纯数字行内
          if (!RegExp(r'^[\d\s:：点分]+$|[\u4e00-\u9fa5]').hasMatch(matched)) {
            continue;
          }
          var day = DateTime(now.year, now.month, now.day);
          if (hour < now.hour || (hour == now.hour && minute <= now.minute)) {
            day = DateTime(now.year, now.month, now.day + 1); // 已过 → 明天
          }
          dueTime = DateTime(day.year, day.month, day.day, hour, minute);
          break outer;
        case r'(\d+)天后':
          dueTime = DateTime(now.year, now.month,
              now.day + (int.tryParse(m.group(1)!) ?? 1), 18, 0);
          break outer;
        case r'(\d+)小时后':
          dueTime = now.add(Duration(hours: int.tryParse(m.group(1)!) ?? 1));
          break outer;
      }
    }

    // ===== 2. 提取标题 =====
    // 优先：含"事由/关于/标题:"的行（公文/表单常见）
    final keywordIdx = lines.indexWhere((l) =>
        RegExp(r'(事由|关于[^，。]{4,}|标题\s*[:：])').hasMatch(l) && l.length >= 6);
    String title;
    int titleIdx;
    if (keywordIdx >= 0) {
      titleIdx = keywordIdx;
      var t = lines[keywordIdx];
      // 去掉前缀关键词
      t = t.replaceFirst(RegExp(r'^(事由|标题)\s*[:：]?\s*'), '');
      // "关于...的请示/报告/通知" 通常是最完整的标题
      final aboutMatch = RegExp(r'关于[^，。]{4,30}').firstMatch(t);
      if (aboutMatch != null) t = aboutMatch.group(0)!;
      title = t.length > 40 ? '${t.substring(0, 40)}…' : t;
    } else {
      // 否则取第一个长度 >= 6 的行（跳过短的状态栏/页眉，如时间 "10:01"、页码）
      titleIdx = lines.indexWhere((l) =>
          l.length >= 6 &&
          !RegExp(r'^\d{1,2}[:：]\d{2}$').hasMatch(l) && // 纯时刻行
          !RegExp(r'^\d+[/\-\.]\d+([/\-\.]\d+)?$').hasMatch(l) && // 纯日期行
          !RegExp(r'^第?\d+页').hasMatch(l)); // 页码
      if (titleIdx < 0) titleIdx = 0;
      var t = lines[titleIdx];
      title = t.length > 40 ? '${t.substring(0, 40)}…' : t;
    }

    // ===== 3. 其余行作为详情 =====
    final contentLines = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (i == titleIdx) continue;
      contentLines.add(lines[i]);
    }
    final content = contentLines.join('\n');

    return (title: title, content: content, dueTime: dueTime);
  }

  /// 给日期附加时刻：从文本中找 HH:mm / X点，找不到用默认值。
  DateTime _withTimeOfDay(DateTime date, String text, DateTime now) {
    final m = RegExp(r'(\d{1,2})[:：点](\d{0,2})分?').firstMatch(text);
    if (m != null) {
      var hour = int.tryParse(m.group(1)!) ?? -1;
      final minute = int.tryParse(m.group(2) ?? '') ?? 0;
      if (hour >= 0 && hour <= 23 && minute <= 59) {
        // 下午/晚上标记
        if (RegExp(r'(下午|晚上)').hasMatch(text) && hour >= 1 && hour <= 11) {
          hour += 12;
        }
        return DateTime(date.year, date.month, date.day, hour, minute);
      }
    }
    // 无明确时刻：工作场景默认 9:00
    return DateTime(date.year, date.month, date.day, 9, 0);
  }
}
