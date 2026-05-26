import 'package:flutter/material.dart';

class DistributionStatusWidget extends StatelessWidget {
  final String status;
  final bool compact;

  const DistributionStatusWidget({
    super.key,
    required this.status,
    this.compact = false,
  });

  static const _steps = [
    ('generated', '已生成', Icons.inventory_2_outlined),
    ('sent', '已发送', Icons.send_outlined),
    ('received', '已接收', Icons.mark_email_read_outlined),
    ('viewed', '已查看', Icons.visibility_outlined),
    ('in_progress', '进行中', Icons.play_circle_outline),
    ('completed', '已完成', Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final info = _statusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: info.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 14, color: info.color),
          const SizedBox(width: 4),
          Text(
            info.label,
            style: TextStyle(fontSize: 12, color: info.color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final isFailed = status == 'failed';
    final isCancelled = status == 'cancelled';
    final currentIndex = _steps.indexWhere((s) => s.$1 == status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isFailed) ...[
          _buildStep(context, Icons.error_outline, '失败', Colors.red, isActive: true),
        ] else if (isCancelled) ...[
          _buildStep(context, Icons.cancel_outlined, '已取消', Colors.grey, isActive: true),
        ] else ...[
          for (int i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i * 0.0),
              child: _buildStep(
                context,
                _steps[i].$3,
                _steps[i].$2,
                i <= currentIndex ? _statusColor(_steps[i].$1) : Colors.grey[300]!,
                isActive: i == currentIndex,
                isCompleted: i < currentIndex,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildStep(
    BuildContext context,
    IconData icon,
    String label,
    Color color, {
    bool isActive = false,
    bool isCompleted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? color : (isActive ? color.withValues(alpha: 0.2) : Colors.grey[200]),
              border: isActive ? Border.all(color: color, width: 2) : null,
            ),
            child: Icon(
              isCompleted ? Icons.check : icon,
              size: 14,
              color: isCompleted ? Colors.white : (isActive ? color : Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isActive ? color : (isCompleted ? Colors.black87 : Colors.grey),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  ({String label, IconData icon, Color color}) _statusInfo(String s) {
    switch (s) {
      case 'generated':
        return (label: '已生成', icon: Icons.inventory_2_outlined, color: Colors.grey);
      case 'sent':
        return (label: '已发送', icon: Icons.send_outlined, color: Colors.blue);
      case 'received':
        return (label: '已接收', icon: Icons.mark_email_read_outlined, color: Colors.indigo);
      case 'viewed':
        return (label: '已查看', icon: Icons.visibility_outlined, color: Colors.teal);
      case 'in_progress':
        return (label: '进行中', icon: Icons.play_circle_outline, color: Colors.orange);
      case 'completed':
        return (label: '已完成', icon: Icons.check_circle_outline, color: Colors.green);
      case 'cancelled':
        return (label: '已取消', icon: Icons.cancel_outlined, color: Colors.grey);
      case 'failed':
        return (label: '失败', icon: Icons.error_outline, color: Colors.red);
      default:
        return (label: s, icon: Icons.help_outline, color: Colors.grey);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'generated':
        return Colors.grey;
      case 'sent':
        return Colors.blue;
      case 'received':
        return Colors.indigo;
      case 'viewed':
        return Colors.teal;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
