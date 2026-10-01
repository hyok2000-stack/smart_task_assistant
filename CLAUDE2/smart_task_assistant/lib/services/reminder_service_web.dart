/// Web 平台提醒声音实现
library;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Web 平台播放提醒声音
void playReminderSoundWeb() {
  try {
    // 调用页面上可能存在的 JS 播放函数（未定义则走 Audio 兜底）
    final fn = web.window.getProperty('playReminderSound'.toJS);
    if (fn != null && fn.typeofEquals('function')) {
      web.window.callMethod('playReminderSound'.toJS);
      return;
    }
  } catch (_) {
    // 忽略，走 Audio 元素兜底
  }
  try {
    final audioElement = web.HTMLAudioElement();
    audioElement.src =
        'data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleQgAOImm0eWpYhAJSqnL5rhoDgAktMTkqWQcBwCO1OOxah4HAIHU4bJqHQcAgdPhsmoZBgCB0+GyahkGAIDT4bNrGQYAgNPhs2sbBQCA0OGzbhsFAIDQ4bNtGwUAgM/hsm8cBQCAz+GzbhwFAIDL4bNwHQUAgcvhs3AeBQCB0+GzcB8FAIHT4bNxIAUAgdPhs3EgBQCB0+GzcSEFAIHT4bNxIQUAgdPhs3IiBQCB0+GzciMFAIHT4bNyIwUAgdPhs3IkBQCB0+GzciQFAIHT4bNyJQUAgdPhs3ImBQCB0+GzciYFAIHT4bNyJgUAgdPhs3InBQCB0+GzcicFAIHT4bNyJwUAgdPhs3IoBQCB0+GzcigFAIHT4bNyKQUAgdPhs3IpBQCB0+GzcioFAIHT4bNyKgUAgdPhs3IqBQCB0+GzciwFAIHT4bNyLQUAgdPhs3ItBQCB0+Gzci4FAIHT4bNyLgUAgdPhs3IvBQCB0+Gzci8FAIHT4bNyMAUAgdPhs3IwBQCB0+GzcjEFAIHT4bNyMQUAgdPhs3IyBQCB0+Gzcv//';
    audioElement.volume = 1.0;
    audioElement.currentTime = 0;
    audioElement.play();
  } catch (_) {
    // Web 端音频兜底失败时静默（提醒弹窗仍然可见）
  }
}
