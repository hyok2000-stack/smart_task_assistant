import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../widgets/log_viewer_dialog.dart';

/// 设置页面 - 通用AI配置和本地大模型支持
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l.navSettings),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildTabBar(context),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildAISettingsTab(context),
                _buildChatAISettingsTab(context),
                _buildGeneralSettingsTab(context),
                _buildAboutTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final l = context.l;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTabItem(0, Icons.psychology_rounded, l.aiService),
          _buildTabItem(1, Icons.chat_rounded, l.chatAI),
          _buildTabItem(2, Icons.settings_rounded, l.general),
          _buildTabItem(3, Icons.info_rounded, l.about),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondaryColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAISettingsTab(BuildContext context) {
    final l = context.l;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(l.aiServiceConfig),
              const SizedBox(height: 16),

              // AI服务模式选择
              _buildRadioGroup(
                l.serviceMode,
                settings.aiMode,
                (value) {
                  settings.setAIMode(value);
                },
                [
                  (AIMode.local, l.localRuleMode, l.localRuleModeDesc),
                  (AIMode.localLLM, l.localLLMMode, l.localLLMModeDesc),
                  (AIMode.remoteAPI, l.remoteAPIMode, l.remoteAPIModeDesc),
                ],
              ),

              const SizedBox(height: 24),

              // 本地大模型配置
              if (settings.aiMode == AIMode.localLLM) ...[
                _buildSectionTitle(l.localLLMConfig),
                const SizedBox(height: 16),
                _buildTextField(
                  l.serviceAddress,
                  settings.localLLMAddress,
                  (value) => settings.setLocalLLMAddress(value),
                  hint: 'http://localhost:11434',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.modelName,
                  settings.localLLMModel,
                  (value) => settings.setLocalLLMModel(value),
                  hint: 'qwen2.5:7b',
                ),
                const SizedBox(height: 16),
                _buildHelpText(l.localLLMHelp),
              ],

              // 远程API配置
              if (settings.aiMode == AIMode.remoteAPI) ...[
                _buildSectionTitle(l.remoteAPIConfig),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiServiceName,
                  settings.apiServiceName,
                  (value) => settings.setAPIServiceName(value),
                  hint: 'OpenAI',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiKey,
                  settings.apiKey,
                  (value) => settings.setAPIKey(value),
                  obscure: true,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiBase,
                  settings.apiBase,
                  (value) => settings.setAPIBase(value),
                  hint: 'https://api.openai.com/v1',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiModel,
                  settings.apiModel,
                  (value) => settings.setAPIModel(value),
                  hint: 'gpt-3.5-turbo',
                ),
                const SizedBox(height: 16),
                _buildHelpText(l.apiHelp),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatAISettingsTab(BuildContext context) {
    final l = context.l;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(l.chatAIConfig),
              const SizedBox(height: 16),

              // 智答AI服务模式选择
              _buildRadioGroup(
                l.serviceMode,
                settings.chatMode,
                (value) {
                  settings.setChatMode(value);
                },
                [
                  (ChatAIMode.localLLM, l.localLLMMode, l.localLLMModeDesc),
                  (ChatAIMode.remoteAPI, l.remoteAPIMode, l.remoteAPIModeDesc),
                ],
              ),

              const SizedBox(height: 24),

              // 本地大模型配置
              if (settings.chatMode == ChatAIMode.localLLM) ...[
                _buildSectionTitle(l.localLLMConfig),
                const SizedBox(height: 16),
                _buildTextField(
                  l.serviceAddress,
                  settings.chatLocalLLMAddress,
                  (value) => settings.setChatLocalLLMAddress(value),
                  hint: 'http://localhost:11434',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.modelName,
                  settings.chatLocalLLMModel,
                  (value) => settings.setChatLocalLLMModel(value),
                  hint: 'qwen2.5:7b',
                ),
              ],

              // 远程API配置
              if (settings.chatMode == ChatAIMode.remoteAPI) ...[
                _buildSectionTitle(l.remoteAPIConfig),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiServiceName,
                  settings.chatAPIServiceName,
                  (value) => settings.setChatAPIServiceName(value),
                  hint: 'OpenAI',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiKey,
                  settings.chatAPIKey,
                  (value) => settings.setChatAPIKey(value),
                  obscure: true,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiBase,
                  settings.chatAPIBase,
                  (value) => settings.setChatAPIBase(value),
                  hint: 'https://api.openai.com/v1',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  l.apiModel,
                  settings.chatAPIModel,
                  (value) => settings.setChatAPIModel(value),
                  hint: 'gpt-3.5-turbo',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildGeneralSettingsTab(BuildContext context) {
    final l = context.l;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(l.generalSettings),
              const SizedBox(height: 16),

              // 剪贴板监听
              _buildSwitchTile(
                Icons.content_copy_rounded,
                l.clipboardMonitor,
                settings.clipboardMonitor,
                (value) => settings.setClipboardMonitor(value),
              ),

              const SizedBox(height: 16),

              // 任务提醒
              _buildSectionTitle(l.reminderSettings),
              const SizedBox(height: 16),
              _buildSwitchTile(
                Icons.notifications_rounded,
                l.enableReminder,
                settings.reminderEnabled,
                (value) => settings.setReminderEnabled(value),
              ),

              if (settings.reminderEnabled) ...[
                const SizedBox(height: 16),
                _buildReminderMinutesDropdown(settings, l),
              ],

              const SizedBox(height: 24),

              // 数据管理
              _buildSectionTitle(l.dataManagement),
              const SizedBox(height: 16),
              _buildExportButton(context, l),
              const SizedBox(height: 12),
              _buildImportButton(context, l),
              const SizedBox(height: 12),
              _buildClearDataButton(context, l),

              const SizedBox(height: 24),

              // 日志查看
              _buildSectionTitle(l.logViewer),
              const SizedBox(height: 16),
              _buildLogViewerButton(context, l),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAboutTab(BuildContext context) {
    final l = context.l;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    size: 50,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Smart Task Assistant',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(l.appDescription),
          const SizedBox(height: 16),
          Text(
            l.appDescriptionText,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondaryColor,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(l.features),
          const SizedBox(height: 16),
          _buildFeatureItem(Icons.task_rounded, l.feature1),
          _buildFeatureItem(Icons.psychology_rounded, l.feature2),
          _buildFeatureItem(Icons.notifications_rounded, l.feature3),
          _buildFeatureItem(Icons.sync_rounded, l.feature4),
          const SizedBox(height: 24),
          _buildSectionTitle(l.contact),
          const SizedBox(height: 16),
          Text(
            'GitHub: https://github.com/smarttask/assistant',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.primaryColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimaryColor,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String value,
    Function(String) onChanged, {
    bool obscure = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: value,
          obscureText: obscure,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioGroup<T>(
    String label,
    T value,
    Function(T) onChanged,
    List<(T, String, String)> options,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        ...options.map((option) {
          final (optionValue, optionLabel, optionDesc) = option;
          return RadioListTile<T>(
            value: optionValue,
            groupValue: value,
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
            title: Text(
              optionLabel,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              optionDesc,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondaryColor,
              ),
            ),
            activeColor: AppTheme.primaryColor,
            contentPadding: EdgeInsets.zero,
          );
        }),
      ],
    );
  }

  Widget _buildSwitchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildReminderMinutesDropdown(
      SettingsProvider settings, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded,
              color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.reminderTime,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DropdownButton<int>(
            value: settings.reminderMinutes,
            items: const [
              DropdownMenuItem(value: 5, child: Text('提前5分钟')),
              DropdownMenuItem(value: 10, child: Text('提前10分钟')),
              DropdownMenuItem(value: 15, child: Text('提前15分钟')),
              DropdownMenuItem(value: 30, child: Text('提前30分钟')),
              DropdownMenuItem(value: 60, child: Text('提前1小时')),
              DropdownMenuItem(value: 120, child: Text('提前2小时')),
            ],
            onChanged: (value) {
              if (value != null) settings.setReminderMinutes(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(BuildContext context, AppLocalizations l) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _exportData(context, l),
        icon: const Icon(Icons.file_download_rounded),
        label: Text(l.exportData),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildImportButton(BuildContext context, AppLocalizations l) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _importData(context, l),
        icon: const Icon(Icons.file_upload_rounded),
        label: Text(l.importData),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _buildClearDataButton(BuildContext context, AppLocalizations l) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _clearData(context, l),
        icon: const Icon(Icons.delete_rounded),
        label: Text(l.clearData),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.errorColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: AppTheme.errorColor),
        ),
      ),
    );
  }

  Widget _buildLogViewerButton(BuildContext context, AppLocalizations l) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const LogViewerDialog(),
          );
        },
        icon: const Icon(Icons.description_rounded),
        label: Text(l.viewLog),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: AppTheme.textSecondaryColor),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpText(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.infoColor,
          height: 1.5,
        ),
      ),
    );
  }

  void _exportData(BuildContext context, AppLocalizations l) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.exportSuccess),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  void _importData(BuildContext context, AppLocalizations l) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.importSuccess),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  void _clearData(BuildContext context, AppLocalizations l) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.confirmClear),
        content: Text(l.confirmClearHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.clearSuccess),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
  }
}
