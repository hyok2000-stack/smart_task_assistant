import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/ai_service.dart';
import '../models/task_suggestion.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';

/// AI聊天对话框
class AIChatDialog extends StatefulWidget {
  const AIChatDialog({super.key});

  @override
  State<AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<AIChatDialog>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _aiService = AIService();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  String _currentModelName = '本地规则引擎';
  final _focusNode = FocusNode();
  late AnimationController _typingAnimationController;
  final List<int> _dotIndices = [0, 1, 2];

  @override
  void initState() {
    super.initState();
    _loadAIConfig();
    _checkUrgentTasks(); // 自动检测紧急任务
    _addWelcomeMessage();

    // 初始化打字动画控制器
    _typingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _typingAnimationController.repeat();

    // 监听焦点变化，自动滚动到底部
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
      }
    });
  }

  Future<void> _loadAIConfig() async {
    await _aiService.loadConfig();
    setState(() {
      _currentModelName = _aiService.currentModelDisplayName;
    });
  }

  /// 自动检测紧急任务
  Future<void> _checkUrgentTasks() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final tasks = taskProvider.tasks;

    // 检查是否有逾期任务或即将到期的任务
    final now = DateTime.now();
    final overdueTasks =
        tasks.where((t) => !t.isCompleted && t.isOverdue).toList();
    final urgentTasks = tasks.where((t) {
      if (t.isCompleted || t.isOverdue) return false;
      if (t.dueTime == null) return false;
      final hoursUntilDue = t.dueTime!.difference(now).inHours;
      return hoursUntilDue <= 24; // 24小时内到期
    }).toList();

    if (overdueTasks.isNotEmpty || urgentTasks.isNotEmpty) {
      setState(() {
        _messages.add(_ChatMessage(
          content: _buildUrgentTaskMessage(overdueTasks, urgentTasks),
          isUser: false,
          type: ChatMessageType.urgent,
        ));
      });
      _scrollToBottom();
    }
  }

  String _buildUrgentTaskMessage(
      List<dynamic> overdueTasks, List<dynamic> urgentTasks) {
    String message = '⚠️ 检测到紧急任务：\n\n';

    if (overdueTasks.isNotEmpty) {
      message += '🔴 逾期任务 (${overdueTasks.length}个)\n';
      for (var i = 0; i < overdueTasks.length && i < 3; i++) {
        message += '  • ${overdueTasks[i].title}\n';
      }
      if (overdueTasks.length > 3) {
        message += '  • 还有 ${overdueTasks.length - 3} 个逾期任务...\n';
      }
      message += '\n';
    }

    if (urgentTasks.isNotEmpty) {
      message += '🟡 即将到期 (${urgentTasks.length}个)\n';
      for (var i = 0; i < urgentTasks.length && i < 3; i++) {
        message += '  • ${urgentTasks[i].title}\n';
      }
      if (urgentTasks.length > 3) {
        message += '  • 还有 ${urgentTasks.length - 3} 个即将到期任务...\n';
      }
    }

    message += '\n点击下方"📊 分析任务优先级"获取处理建议';
    return message;
  }

  void _addWelcomeMessage() {
    _messages.add(_ChatMessage(
      content:
          '你好！我是智能任务助手 🤖\n\n我可以帮助你：\n• 创建和管理任务\n• 分析任务优先级\n• 提供工作效率建议\n• 解答任务管理相关问题\n\n请问有什么可以帮助你的？',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingAnimationController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    await _sendQuickMessage(text);
    _controller.clear();
  }

  /// 发送快捷消息（用于快捷按钮）
  Future<void> _sendQuickMessage(String message) async {
    if (_isLoading) return;

    setState(() {
      _messages.add(_ChatMessage(content: message, isUser: true));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // 加载AI配置
      await _aiService.loadConfig();

      // C8: 检测任务创建意图
      final taskKeywords = ['创建任务', '添加任务', '新建任务', '提醒我', '帮我记', '安排', '待办'];
      final isTaskIntent = taskKeywords.any((k) => message.contains(k));
      if (isTaskIntent) {
        final parsed = await _aiService.parseTask(message);
        if (parsed != null) {
          setState(() {
            _messages.add(_ChatMessage(
              content: '',
              isUser: false,
              type: ChatMessageType.taskSuggestion,
              parsedTask: parsed,
              engineType: _aiService.currentModelDisplayName,
            ));
            _isLoading = false;
          });
          _scrollToBottom();
          return;
        }
      }

      // 获取任务列表
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      final tasks = taskProvider.tasks;

      // 构建历史消息
      final history = _messages
          .take(_messages.length - 1)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      // 使用新的API获取响应和引擎信息，传递任务列表
      final result = await _aiService.chatWithEngineInfo(
        message,
        history: history,
        tasks: tasks,
      );

      setState(() {
        _messages.add(_ChatMessage(
          content: result.content,
          isUser: false,
          engineType: result.engineType,
        ));
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(
          content: '抱歉，处理您的请求时出现错误。请稍后重试。',
          isUser: false,
          engineType: '本地规则引擎',
        ));
        _isLoading = false;
      });
    }
  }

  /// 分析任务优先级
  Future<void> _analyzeTaskPriority() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      final tasks = taskProvider.tasks;

      // 显示用户消息
      setState(() {
        _messages.add(_ChatMessage(
          content: '帮我分析任务优先级',
          isUser: true,
        ));
      });
      _scrollToBottom();

      // 获取优先级建议
      final suggestion = await _aiService.generatePrioritySuggestion(tasks);

      // 显示AI建议
      setState(() {
        _messages.add(_ChatMessage(
          content: '',
          isUser: false,
          type: ChatMessageType.prioritySuggestion,
          suggestion: suggestion,
        ));
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(
          content: '抱歉，分析任务优先级时出现错误：$e',
          isUser: false,
        ));
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 获取键盘高度
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1),
                  const Color(0xFF8B5CF6),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI 智能助手',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _aiService.config.enabled
                                      ? Icons.cloud
                                      : Icons.computer,
                                  color: Colors.white70,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _currentModelName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // 消息列表
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 80,
                    ),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isLoading) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          // 快捷操作区域
          _buildQuickActions(),
          // 输入区域
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              keyboardHeight + 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: const Color(0xFF6366F1),
                          width: 2,
                        ),
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    onTap: () {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _scrollToBottom();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildQuickActionButton(
            icon: Icons.analytics,
            label: '分析任务优先级',
            onTap: _analyzeTaskPriority,
          ),
          _buildQuickActionButton(
            icon: Icons.tips_and_updates,
            label: '效率建议',
            onTap: () async {
              await _sendQuickMessage('请给我一些提高工作效率的建议');
            },
          ),
          _buildQuickActionButton(
            icon: Icons.help_outline,
            label: '使用帮助',
            onTap: () async {
              await _sendQuickMessage('如何使用这个应用？');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: _isLoading ? Colors.grey : const Color(0xFF6366F1),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _isLoading ? Colors.grey : AppTheme.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 48,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '开始与 AI 对话',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '输入任何问题，AI 将为你解答',
            style: TextStyle(
              color: AppTheme.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    // 处理优先级建议消息
    if (message.type == ChatMessageType.prioritySuggestion &&
        message.suggestion != null) {
      return _buildPrioritySuggestionCard(message.suggestion!);
    }

    // C8: 处理任务建议消息
    if (message.type == ChatMessageType.taskSuggestion &&
        message.parsedTask != null) {
      return _buildTaskSuggestionCard(message.parsedTask!);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                message.type == ChatMessageType.urgent
                    ? Icons.warning
                    : Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: message.type == ChatMessageType.urgent
                        ? Colors.red.shade50
                        : (message.isUser
                            ? const Color(0xFF6366F1)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight:
                          message.isUser ? const Radius.circular(4) : null,
                      bottomLeft:
                          !message.isUser ? const Radius.circular(4) : null,
                    ),
                    border: message.type == ChatMessageType.urgent
                        ? Border.all(color: Colors.red.shade200)
                        : null,
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: message.type == ChatMessageType.urgent
                          ? Colors.red.shade900
                          : (message.isUser
                              ? Colors.white
                              : AppTheme.textPrimaryColor),
                      height: 1.5,
                    ),
                  ),
                ),
                if (!message.isUser && message.engineType != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        message.engineType == '本地规则引擎'
                            ? Icons.computer
                            : Icons.cloud,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        message.engineType!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.person,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrioritySuggestionCard(TaskPrioritySuggestion suggestion) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.analytics,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 总体建议
                  Row(
                    children: [
                      Icon(
                        suggestion.isFromAI
                            ? Icons.auto_awesome
                            : Icons.lightbulb,
                        size: 16,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        suggestion.isFromAI ? 'AI 智能分析' : '智能建议',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    suggestion.summary,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  if (suggestion.items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      '推荐处理顺序：',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...suggestion.items
                        .take(5)
                        .map((item) => _buildSuggestionItem(item)),
                    if (suggestion.items.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '...还有 ${suggestion.items.length - 5} 个任务',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondaryColor,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(TaskSuggestionItem item) {
    Color priorityColor;
    switch (item.priorityLevel) {
      case '高':
        priorityColor = Colors.red;
        break;
      case '中':
        priorityColor = Colors.orange;
        break;
      default:
        priorityColor = Colors.green;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${item.recommendedOrder}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: priorityColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.priorityLevel,
                          style: TextStyle(
                            fontSize: 12,
                            color: priorityColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: AppTheme.textSecondaryColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.reason,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 12,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.suggestion,
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF6366F1),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // C8: Task suggestion card
  Widget _buildTaskSuggestionCard(ParsedTask parsed) {
    final priorityText = {
      TaskPriority.high: '高优先级',
      TaskPriority.medium: '中优先级',
      TaskPriority.low: '低优先级',
    }[parsed.priority] ?? '中优先级';
    final priorityColor = {
      TaskPriority.high: AppTheme.highPriorityColor,
      TaskPriority.medium: AppTheme.mediumPriorityColor,
      TaskPriority.low: AppTheme.lowPriorityColor,
    }[parsed.priority] ?? AppTheme.mediumPriorityColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                const Text('AI 任务建议', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parsed.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (parsed.content != null && parsed.content!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(parsed.content!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(priorityText, style: TextStyle(fontSize: 12, color: priorityColor, fontWeight: FontWeight.w500)),
                      ),
                      if (parsed.dueTime != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text('截止: ${parsed.dueTime!.month}/${parsed.dueTime!.day} ${parsed.dueTime!.hour}:${parsed.dueTime!.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final provider = Provider.of<TaskProvider>(context, listen: false);
                  final task = Task(
                    id: const Uuid().v4(),
                    title: parsed.title,
                    content: parsed.content,
                    priority: parsed.priority,
                    dueTime: parsed.dueTime,
                    tagIds: parsed.tags,
                    reminderMinutes: parsed.recommendedReminderMinutes ?? 10,
                    sourceType: 'local',
                  );
                  provider.addTask(task);
                  setState(() {
                    _messages.add(_ChatMessage(
                      content: '任务已创建！',
                      isUser: false,
                    ));
                  });
                  _scrollToBottom();
                },
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('创建此任务'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _typingAnimationController,
      builder: (context, child) {
        // 创建延迟效果：每个点延迟 200ms
        final delay = index * 0.2;
        final value = _typingAnimationController.value;

        // 计算动画值，考虑延迟
        double animatedValue = (value - delay) % 1.0;
        if (animatedValue < 0) animatedValue += 1.0;

        // 使用正弦波创建平滑的淡入淡出效果
        final opacity = 0.4 + (0.6 * (1 - (animatedValue - 0.5).abs() * 2));

        return Opacity(
          opacity: opacity.clamp(0.4, 1.0),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.textSecondaryColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

enum ChatMessageType {
  normal,
  urgent,
  prioritySuggestion,
  taskSuggestion,
}

class _ChatMessage {
  final String content;
  final bool isUser;
  final ChatMessageType type;
  final TaskPrioritySuggestion? suggestion;
  final ParsedTask? parsedTask;
  final String? engineType;

  _ChatMessage({
    required this.content,
    required this.isUser,
    this.type = ChatMessageType.normal,
    this.suggestion,
    this.parsedTask,
    this.engineType,
  });
}

/// 显示AI聊天对话框
void showAIChatDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: const AIChatDialog(),
    ),
  );
}
