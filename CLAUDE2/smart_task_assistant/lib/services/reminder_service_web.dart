/// Web 平台提醒声音实现
library;
import 'dart:html' as html;
import 'dart:js' as js;

/// Web 平台播放提醒声音
void playReminderSoundWeb() {
  try {
    // 调用 JavaScript 播放声音
    js.context.callMethod('playReminderSound', []);
  } catch (e) {
    // 如果 JavaScript 方法不存在，尝试使用 Audio 元素
    try {
      final audioElement = html.AudioElement();
      audioElement.src = 'data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleQgAOImm0eWpYhAJSqnL5rhoDgAktMTkqWQcBwCO1OOxah4HAIHU4bJqHQcAgdPhsmoZBgCB0+GyahkGAIDT4bNrGQYAgNPhs2sbBQCA0OGzbhsFAIDQ4bNtGwUAgM/hsm8cBQCAz+GzbhwFAIDL4bNwHQUAgcvhs3AeBQCB0+GzcB8FAIHT4bNxIAUAgdPhs3EgBQCB0+GzcSEFAIHT4bNxIQUAgdPhs3IiBQCB0+GzciMFAIHT4bNyIwUAgdPhs3IkBQCB0+GzciQFAIHT4bNyJQUAgdPhs3ImBQCB0+GzciYFAIHT4bNyJgUAgdPhs3InBQCB0+GzcicFAIHT4bNyJwUAgdPhs3IoBQCB0+GzcigFAIHT4bNyKQUAgdPhs3IpBQCB0+GzcioFAIHT4bNyKgUAgdPhs3IqBQCB0+GzciwFAIHT4bNyLQUAgdPhs3ItBQCB0+Gzci4FAIHT4bNyLgUAgdPhs3IvBQCB0+Gzci8FAIHT4bNyMAUAgdPhs3IwBQCB0+GzcjEFAIHT4bNyMQUAgdPhs3IyBQCB0+Gzcv//';
      audioElement.volume = 1.0;
      audioElement.currentTime = 0;
      audioElement.play();
    } catch (e2) {
      print('音频播放失败: $e2');
    }
  }
}