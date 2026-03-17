import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../widgets/tag_management_dialog.dart';
import '../services/ai_service.dart';
import '../database/storage_service.dart';

// 条件导入：文件操作（Web和移动端）
import '../utils/platform_file_stub.dart'
    if (dart.library.html) '../utils/platform_file_web.dart'
    if (dart.library.io) '../utils/platform_file_native.dart';

/// 设置页面 - 传统列表布局
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isTestingConnection = false;
  final TextEditingController _localLLMAddressController =
      TextEditingController();
  final TextEditingController _localLLMModelController =
      TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiBaseController = TextEditingController();
  final TextEditingController _apiModelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettingsToControllers();
  }

  @override
  void dispose() {
    _localLLMAddressController.dispose();
    _localLLMModelController.dispose();
    _apiKeyController.dispose();
    _apiBaseController.dispose();
    _apiModelController.dispose();
    super.dispose();
  }

  void _loadSettingsToControllers() {
    final settings = context.read<SettingsProvider>();
    _localLLMAddressController.text = settings.localLLMAddress;
    _localLLMModelController.text = settings.localLLMModel;
    _apiKeyController.text = settings.apiKey;
    _apiBaseController.text = settings.apiBase;
    _apiModelController.text = settings.apiModel;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l.navSettings),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimaryColor,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimaryColor,
        ),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('外观'),
          _buildAppearanceSettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('通知'),
          _buildNotificationSettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('AI服务'),
          _buildAISettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('标签管理'),
          _buildTagManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('数据'),
          _buildDataManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('设置管理'),
          _buildSettingsManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('关于'),
          _buildAboutSection(context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildAppearanceSettings(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.dark_mode_outlined,
            title: '深色模式',
            subtitle: '使用深色主题',
            trailing: Switch(
              value: settings.isDarkMode,
              onChanged: (value) {
                settings.toggleDarkMode(value);
              },
              activeColor: AppTheme.primaryColor,
            ),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.language_outlined,
            title: '语言',
            subtitle: settings.isZh ? '简体中文' : 'English',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              _showLanguageDialog(context, settings);
            },
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('选择语言'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption(context, settings, 'zh', '简体中文'),
            const SizedBox(height: 8),
            _buildLanguageOption(context, settings, 'en', 'English'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context,
    SettingsProvider settings,
    String languageCode,
    String languageName,
  ) {
    final isSelected = settings.locale.languageCode == languageCode;
    return InkWell(
      onTap: () {
        settings.setLocale(
          Locale(languageCode, languageCode == 'zh' ? 'CN' : 'US'),
        );
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primaryColor : Colors.grey,
            ),
            const SizedBox(width: 12),
            Text(
              languageName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettings(BuildContext context) {
    final l = context.l;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildListTile(
                icon: Icons.notifications_outlined,
                title: '推送通知',
                subtitle: '接收任务提醒通知',
                trailing: Switch(
                  value: settings.notificationsEnabled,
                  onChanged: (value) {
                    settings.setNotificationsEnabled(value);
                  },
                  activeColor: AppTheme.primaryColor,
                ),
              ),
              _buildDivider(),
              _buildListTile(
                icon: Icons.content_copy_outlined,
                title: '剪贴板监视',
                subtitle: '粘贴内容时自动弹出任务创建窗口',
                trailing: Switch(
                  value: settings.clipboardMonitor,
                  onChanged: (value) {
                    settings.setClipboardMonitor(value);
                  },
                  activeColor: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAISettings(BuildContext context) {
    final l = context.l;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          color: Colors.white,
          child: _buildListTile(
            icon: Icons.psychology_outlined,
            title: 'AI服务配置',
            subtitle: '配置本地大模型或远程API',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              _showAISettingsDialog(context, settings);
            },
          ),
        );
      },
    );
  }

  Widget _buildTagManagement(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildDefaultTagsSection(),
          _buildDivider(),
          _buildListTile(
            icon: Icons.add_circle_outline,
            title: '添加标签',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              showTagManagementDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultTagsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.label_outline,
                color: AppTheme.textSecondaryColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Text(
                '默认标签',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTagChip('工作', '#10B981'),
              _buildTagChip('个人', '#3B82F6'),
              _buildTagChip('紧急', '#EF4444'),
              _buildTagChip('学习', '#8B5CF6'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String label, String colorCode) {
    final color = Color(int.parse(colorCode.replaceFirst('#', '0xFF')));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDataManagement(BuildContext context) {
    final l = context.l;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.file_download_outlined,
            title: l.exportData,
            subtitle: '导出所有任务数据',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _exportData(context, l),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.file_upload_outlined,
            title: l.importData,
            subtitle: '导入任务数据',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _importData(context, l),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.delete_outline,
            title: l.clearData,
            subtitle: '清除所有数据',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _clearData(context, l),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsManagement(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.restore_outlined,
            title: '重置所有设置',
            subtitle: '恢复到默认配置',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _showResetSettingsDialog(context, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '版本 ${settings.appVersion}',
            trailing: Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              _showAboutDialog(context, settings);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showTrailing = true,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondaryColor),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimaryColor,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: AppTheme.textHintColor),
            )
          : null,
      trailing: trailing ??
          (showTrailing
              ? Icon(Icons.chevron_right, color: AppTheme.textHintColor)
              : null),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 0.5, indent: 68, endIndent: 0);
  }

  void _showAISettingsDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('AI服务配置'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 400
                  ? 400
                  : MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '选择服务模式',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.local,
                      '本地规则',
                      '使用本地规则引擎，无需网络连接',
                      setState,
                    ),
                    const SizedBox(height: 8),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.localLLM,
                      '本地大模型',
                      '连接本地部署的LLM（如Ollama）',
                      setState,
                    ),
                    const SizedBox(height: 8),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.remoteAPI,
                      '远程API',
                      '使用云端API服务（如OpenAI）',
                      setState,
                    ),
                    const SizedBox(height: 24),
                    if (settings.aiMode == AIMode.localLLM) ...[
                      _buildConfigSection('本地大模型配置', Icons.cloud_outlined, [
                        TextField(
                          decoration: InputDecoration(
                            labelText: '服务地址',
                            hintText: 'http://localhost:11434',
                            border: const OutlineInputBorder(),
                            errorText:
                                settings.isValidUrl(settings.localLLMAddress) ||
                                        settings.localLLMAddress.isEmpty
                                    ? null
                                    : '请输入有效的URL地址',
                          ),
                          controller: _localLLMAddressController,
                          onChanged: (value) {
                            settings.setLocalLLMAddress(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: InputDecoration(
                            labelText: '模型名称',
                            hintText: 'qwen2.5:7b',
                            border: const OutlineInputBorder(),
                            errorText: !settings.isValidModelName(
                              settings.localLLMModel,
                            )
                                ? '请输入模型名称'
                                : null,
                          ),
                          controller: _localLLMModelController,
                          onChanged: (value) {
                            settings.setLocalLLMModel(value);
                          },
                        ),
                      ]),
                    ],
                    if (settings.aiMode == AIMode.remoteAPI) ...[
                      _buildConfigSection(
                        '远程API配置',
                        Icons.cloud_queue_outlined,
                        [
                          _buildAPIKeyField(settings),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'API地址',
                              hintText: 'https://api.openai.com/v1',
                              border: const OutlineInputBorder(),
                              errorText:
                                  !settings.isValidUrl(settings.apiBase) &&
                                          settings.apiBase.isNotEmpty
                                      ? '请输入有效的URL地址'
                                      : null,
                            ),
                            controller: _apiBaseController,
                            onChanged: (value) {
                              settings.setAPIBase(value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: '模型名称',
                              hintText: 'gpt-3.5-turbo',
                              border: const OutlineInputBorder(),
                              errorText:
                                  !settings.isValidModelName(settings.apiModel)
                                      ? '请输入模型名称'
                                      : null,
                            ),
                            controller: _apiModelController,
                            onChanged: (value) {
                              settings.setAPIModel(value);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (settings.aiMode != AIMode.local)
                TextButton.icon(
                  onPressed: _isTestingConnection
                      ? null
                      : () => _testConnection(settings, settings.aiMode),
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi, size: 18),
                  label: Text(_isTestingConnection ? '测试中...' : '测试连接'),
                ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showConfigSavedMessage(context, settings.aiMode);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCompactAIModeOption(
    SettingsProvider settings,
    AIMode mode,
    String title,
    String subtitle,
    StateSetter setState,
  ) {
    final isSelected = settings.aiMode == mode;
    return InkWell(
      onTap: () {
        settings.setAIMode(mode);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primaryColor : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAPIKeyField(SettingsProvider settings) {
    bool _obscureText = true;

    return StatefulBuilder(
      builder: (context, setState) {
        return TextField(
          decoration: InputDecoration(
            labelText: 'API Key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
          ),
          controller: _apiKeyController,
          onChanged: (value) {
            settings.setAPIKey(value);
          },
          obscureText: _obscureText,
        );
      },
    );
  }

  Widget _buildAIModeOption(
    BuildContext context,
    SettingsProvider settings,
    AIMode mode,
    String title,
    String subtitle,
  ) {
    final isSelected = settings.aiMode == mode;
    return InkWell(
      onTap: () {
        settings.setAIMode(mode);
        Navigator.pop(context);
        _showAISettingsDialog(context, settings);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? AppTheme.primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _testConnection(settings, mode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.wifi, size: 18),
                label: const Text('测试连接', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _testConnection(SettingsProvider settings, AIMode mode) async {
    setState(() => _isTestingConnection = true);

    try {
      final aiService = AIService();
      bool isConnected;

      if (mode == AIMode.localLLM) {
        isConnected = await aiService.testLocalLLMConnection(
          settings.localLLMAddress,
          settings.localLLMModel,
        );
      } else if (mode == AIMode.remoteAPI) {
        isConnected = await aiService.testAPIConnection(
          settings.apiKey,
          settings.apiBase,
          settings.apiModel,
        );
      } else {
        isConnected = true;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isConnected ? '连接成功！' : '连接失败，请检查配置'),
            backgroundColor:
                isConnected ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接测试失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  void _exportData(BuildContext context, AppLocalizations l) async {
    try {
      // 获取存储服务
      final storageService = getStorageService();

      // 生成导出数据
      String exportData;
      if (kIsWeb && storageService is WebStorageService) {
        exportData = storageService.getExportData();
      } else {
        // 移动端或其他平台，从数据库获取数据
        final taskProvider = context.read<TaskProvider>();
        final tasks = taskProvider.tasks;
        final tags = taskProvider.tags;

        final data = {
          'tasks': tasks.map((t) => t.toJson()).toList(),
          'tags': tags.map((t) => t.toJson()).toList(),
          'exportTime': DateTime.now().toIso8601String(),
        };
        exportData = jsonEncode(data);
      }

      // 生成文件名：任务列表_YYYYMMDD_HHMMSS.json
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = '任务列表_$timestamp.json';

      // 生成文件大小
      final bytes = utf8.encode(exportData);
      final kbSize = (bytes.length / 1024).toStringAsFixed(2);

      if (kIsWeb) {
        // Web平台使用下载方式
        downloadFile(exportData, fileName, 'application/json');
      } else {
        // 移动端保存到程序目录
        final filePath = await exportDataToAppDir(
          data: exportData,
          fileName: fileName,
        );
      }

      // 显示成功对话框
      _showExportSuccessDialog(context, fileName, kbSize, exportData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.exportFailed}: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _showExportSuccessDialog(
    BuildContext context,
    String fileName,
    String size,
    String exportData,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.successColor,
                      AppTheme.successColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.file_download_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '导出数据',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 64,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '导出成功！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '数据已导出为以下文件',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.successColor.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file_rounded,
                                color: AppTheme.successColor,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'JSON格式',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondaryColor,
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
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importData(BuildContext context, AppLocalizations l) async {
    try {
      String? content;
      String? fileName;

      if (kIsWeb) {
        // Web平台使用文件选择器
        bool fileSelected = false;

        selectFile(
          accept: '.json',
          onFileSelected: (selectedContent, selectedFileName) async {
            content = selectedContent;
            fileName = selectedFileName;
            fileSelected = true;
          },
          onError: (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${l.importFailed}: $error'),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
          },
        );

        // 等待文件选择完成
        await Future.delayed(const Duration(milliseconds: 100));

        // 如果没有选择文件，直接返回
        if (!fileSelected) {
          return;
        }
      } else {
        // 移动端：直接从应用内部目录导入
        final filesList = await getExportFilesList();

        if (filesList.isEmpty) {
          // 如果没有文件，显示提示
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('应用目录中没有备份文件，请先导出数据'),
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
          return;
        }

        // 显示文件选择对话框
        final selectedFile = await _showImportFilesDialog(context, filesList);
        if (selectedFile == null) {
          // 用户取消选择
          return;
        }

        // 从选择的文件导入数据
        final result = await importDataFromPath(selectedFile['filePath']);
        if (result != null) {
          content = result['content'];
          fileName = result['fileName'];
        }
      }

      // 检查是否获取到内容
      if (content == null) {
        return;
      }

      try {
        final data = jsonDecode(content!) as Map<String, dynamic>;

        // 验证数据格式
        if (!data.containsKey('tasks') || !data.containsKey('tags')) {
          throw Exception('无效的数据格式');
        }

        // 导入数据
        final taskProvider = context.read<TaskProvider>();

        if (kIsWeb) {
          // Web平台使用存储服务
          final storageService = getStorageService();
          if (storageService is! WebStorageService) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.importFailed),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }

          final success = await (storageService as WebStorageService)
              .restoreFromBackup(data);

          if (!success) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.importFailed),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }
        } else {
          // 移动端直接导入数据
          await taskProvider.importData(data);
        }

        // 重新加载数据
        if (context.mounted) {
          await taskProvider.loadData();
          _showImportSuccessDialog(
            context,
            fileName!,
            data['tasks']?.length ?? 0,
            data['tags']?.length ?? 0,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l.importFailed}: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.importFailed}: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// 显示导入来源选择对话框
  Future<String?> _showImportSourceDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.file_upload_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '选择导入方式',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildImportSourceOption(
                      context,
                      'internal',
                      Icons.folder_rounded,
                      '从应用目录导入',
                      '选择应用内部保存的备份文件',
                    ),
                    const SizedBox(height: 12),
                    _buildImportSourceOption(
                      context,
                      'external',
                      Icons.sd_card_rounded,
                      '从外部导入',
                      '从手机存储或其他应用选择文件',
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建导入来源选项
  Widget _buildImportSourceOption(
    BuildContext context,
    String source,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(context, source),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.textHintColor,
            ),
          ],
        ),
      ),
    );
  }

  /// 从外部文件导入
  Future<Map<String, String>?> _importFromExternalFile(
      BuildContext context) async {
    try {
      // 使用文件选择器
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final fileName = result.files.single.name;
        return {
          'content': content,
          'fileName': fileName,
        };
      }

      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return null;
    }
  }

  /// 显示导入文件选择对话框
  Future<Map<String, dynamic>?> _showImportFilesDialog(
    BuildContext context,
    List<Map<String, dynamic>> filesList,
  ) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '选择备份文件',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 文件列表
              Expanded(
                child: filesList.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_rounded,
                              size: 64,
                              color: AppTheme.textHintColor,
                            ),
                            SizedBox(height: 16),
                            Text(
                              '暂无备份文件',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filesList.length,
                        itemBuilder: (context, index) {
                          final file = filesList[index];
                          final modifiedTime = file['modifiedTime'] as DateTime;
                          final fileSize = (file['fileSize'] as int) / 1024;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.pop(context, file);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.description_rounded,
                                        color: AppTheme.primaryColor,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file['fileName'] as String,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_formatDateTime(modifiedTime)} · ${fileSize.toStringAsFixed(1)} KB',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppTheme.textSecondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: AppTheme.textHintColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '今天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  void _showImportSuccessDialog(
    BuildContext context,
    String fileName,
    int taskCount,
    int tagCount,
  ) {
    final l = context.l;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.successColor,
                      AppTheme.successColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '导入成功！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.restoreSuccessCount('$taskCount', '$tagCount'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.successColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file_rounded,
                            color: AppTheme.successColor,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearData(BuildContext context, AppLocalizations l) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.errorColor,
                      AppTheme.errorColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '确认清除所有数据',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '此操作将永久删除所有任务和标签，无法恢复！',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);

                          try {
                            final taskProvider = context.read<TaskProvider>();
                            await taskProvider.clearAllData();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('所有数据已清除'),
                                  backgroundColor: AppTheme.successColor,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('清除失败: $e'),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认清除'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetSettingsDialog(
    BuildContext context,
    SettingsProvider settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.warningColor,
                      AppTheme.warningColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Icon(
                  Icons.restore_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '重置所有设置',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '此操作将恢复所有设置到默认值，您的任务数据不会受影响。',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await settings.resetToDefault();
                          _loadSettingsToControllers();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('设置已重置'),
                                backgroundColor: AppTheme.successColor,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.warningColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认重置'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.task_alt_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '智能任务助手',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '版本 ${settings.appVersion}',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAboutItem(
                      Icons.description_outlined,
                      '应用介绍',
                      '一款智能的任务管理应用，帮助您高效管理日常任务。支持AI智能识别、周期任务、提醒通知等功能。',
                    ),
                    const SizedBox(height: 20),
                    _buildAboutItem(
                      Icons.new_releases_outlined,
                      '新功能',
                      '• AI智能识别任务内容\n• 支持周期任务设置\n• 剪贴板监视功能\n• 数据导入导出\n• 设置重置功能',
                    ),
                    const SizedBox(height: 20),
                    _buildAboutItem(
                      Icons.update_outlined,
                      '更新日志',
                      'v${settings.appVersion} - 当前版本\n• 完善设置管理功能\n• 添加输入验证\n• 改进用户界面',
                    ),
                    const SizedBox(height: 20),
                    _buildAboutItem(
                      Icons.contact_support_outlined,
                      '联系我们',
                      '如有问题或建议，欢迎反馈',
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutItem(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondaryColor,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showConfigSavedMessage(BuildContext context, AIMode mode) {
    String modeText;
    IconData modeIcon;

    switch (mode) {
      case AIMode.local:
        modeText = '本地规则模式';
        modeIcon = Icons.check_circle_outlined;
        break;
      case AIMode.localLLM:
        modeText = '本地大模型';
        modeIcon = Icons.cloud_outlined;
        break;
      case AIMode.remoteAPI:
        modeText = '远程API服务';
        modeIcon = Icons.cloud_queue_outlined;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(modeIcon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '配置已保存：$modeText',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
