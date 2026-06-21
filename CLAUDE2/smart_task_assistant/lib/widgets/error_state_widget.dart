import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';

/// 统一错误状态组件（加载失败 + 可重试）
///
/// 用于 FutureBuilder 的 snapshot.hasError 分支，与 [EmptyStateWidget] 配套，
/// 构成「加载中 / 加载失败可重试 / 空 / 数据」四态。
class ErrorStateWidget extends StatelessWidget {
  /// 错误描述文案，默认走 i18n（loadFailed）
  final String? message;

  /// 重试按钮文案，默认走 i18n（retry）
  final String? retryLabel;

  /// 重试回调；为 null 时不显示重试按钮
  final VoidCallback? onRetry;

  /// 紧凑模式：true 为行内（适合嵌入 section 内部），false 为居中（适合列表区域）
  final bool compact;

  const ErrorStateWidget({
    super.key,
    this.message,
    this.retryLabel,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final msg = message ?? (l?.loadFailed ?? '加载失败');
    final retry = retryLabel ?? (l?.retry ?? '重试');

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 16, color: AppTheme.errorColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                msg,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondaryColor),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(retry),
              ),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: AppTheme.errorColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              msg,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
