import { useState } from 'react';
import type { Task, TaskFormData, User } from '../../types';
import { pushTasks, taskToPushPayload } from '../../api';

const TAGS = [
  { id: 'default_work', label: '工作', color: '#3B82F6' },
  { id: 'default_personal', label: '个人', color: '#10B981' },
  { id: 'default_urgent', label: '紧急', color: '#EF4444' },
  { id: 'default_study', label: '学习', color: '#8B5CF6' },
];

const REMINDER_OPTIONS = [
  { value: '', label: '无' },
  { value: '10', label: '10 分钟前' },
  { value: '30', label: '30 分钟前' },
  { value: '60', label: '1 小时前' },
  { value: '1440', label: '1 天前' },
];

interface TaskCreateFormProps {
  token: string;
  users: User[];
  onSuccess: () => void;
  onCancel: () => void;
}

function makeDefaultForm(): TaskFormData {
  return {
    id: crypto.randomUUID(),
    title: '',
    content: '',
    status: 'pending',
    priority: 'medium',
    startTime: '',
    dueTime: '',
    assignee: '',
    assigneeUserId: '',
    isRecurring: false,
    recurringRule: '',
    tagIds: [],
    reminderMinutes: null,
    reminderVoiceEnabled: false,
    reminderVoiceType: 'female',
    reminderVoiceStyle: 'lively',
    reminderVoiceSpeed: 'normal',
  };
}

export default function TaskCreateForm({ token, users, onSuccess, onCancel }: TaskCreateFormProps) {
  const [form, setForm] = useState<TaskFormData>(makeDefaultForm);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const update = <K extends keyof TaskFormData>(key: K, value: TaskFormData[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const toggleTag = (tagId: string) => {
    setForm((prev) => ({
      ...prev,
      tagIds: prev.tagIds.includes(tagId)
        ? prev.tagIds.filter((t) => t !== tagId)
        : [...prev.tagIds, tagId],
    }));
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.title.trim()) {
      setError('请输入任务标题');
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      await pushTasks(token, [taskToPushPayload(form)]);
      onSuccess();
    } catch (err: any) {
      setError(err.message ?? '创建失败');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="task-form" onSubmit={handleSubmit}>
      <div className="form-section">
        <h3 className="form-section-title">基本信息</h3>
        <div className="form-grid">
          <div className="form-field full-width">
            <label>标题 *</label>
            <input
              value={form.title}
              onChange={(e) => update('title', e.target.value)}
              placeholder="输入任务标题"
            />
          </div>
          <div className="form-field full-width">
            <label>内容</label>
            <textarea
              value={form.content}
              onChange={(e) => update('content', e.target.value)}
              placeholder="任务描述（可选）"
              rows={3}
            />
          </div>
          <div className="form-field">
            <label>状态</label>
            <select value={form.status} onChange={(e) => update('status', e.target.value as Task['status'])}>
              <option value="pending">待处理</option>
              <option value="in_progress">进行中</option>
              <option value="completed">已完成</option>
              <option value="cancelled">已取消</option>
            </select>
          </div>
          <div className="form-field">
            <label>优先级</label>
            <div className="priority-group">
              {(['low', 'medium', 'high'] as const).map((p) => (
                <button
                  key={p}
                  type="button"
                  className={`priority-option ${form.priority === p ? 'active' : ''} priority-${p}`}
                  onClick={() => update('priority', p)}
                >
                  {p === 'low' ? '低' : p === 'medium' ? '中' : '高'}
                </button>
              ))}
            </div>
          </div>
          <div className="form-field">
            <label>指派人</label>
            <select
              value={form.assigneeUserId ?? ''}
              onChange={(e) => update('assigneeUserId', e.target.value)}
            >
              <option value="">未指派</option>
              {users.map((u) => <option key={u.id} value={u.id}>{u.nickname || u.email || u.id}</option>)}
            </select>
          </div>
        </div>
      </div>

      <div className="form-section">
        <h3 className="form-section-title">时间设置</h3>
        <div className="form-grid">
          <div className="form-field">
            <label>开始时间</label>
            <input
              type="datetime-local"
              value={form.startTime}
              onChange={(e) => update('startTime', e.target.value)}
            />
          </div>
          <div className="form-field">
            <label>截止时间</label>
            <input
              type="datetime-local"
              value={form.dueTime}
              onChange={(e) => update('dueTime', e.target.value)}
            />
          </div>
        </div>
      </div>

      <div className="form-section">
        <h3 className="form-section-title">提醒设置</h3>
        <div className="form-grid">
          <div className="form-field">
            <label>提前提醒</label>
            <select
              value={form.reminderMinutes ?? ''}
              onChange={(e) => update('reminderMinutes', e.target.value ? Number(e.target.value) : null)}
            >
              {REMINDER_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
          <div className="form-field">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={form.reminderVoiceEnabled}
                onChange={(e) => update('reminderVoiceEnabled', e.target.checked)}
              />
              启用语音提醒
            </label>
          </div>
          {form.reminderVoiceEnabled && (
            <>
              <div className="form-field">
                <label>语音类型</label>
                <select value={form.reminderVoiceType} onChange={(e) => update('reminderVoiceType', e.target.value)}>
                  <option value="female">女声</option>
                  <option value="male">男声</option>
                  <option value="neutral">中性</option>
                </select>
              </div>
              <div className="form-field">
                <label>语音风格</label>
                <select value={form.reminderVoiceStyle} onChange={(e) => update('reminderVoiceStyle', e.target.value)}>
                  <option value="lively">活泼</option>
                  <option value="gentle">温柔</option>
                  <option value="standard">标准</option>
                </select>
              </div>
              <div className="form-field">
                <label>语速</label>
                <select value={form.reminderVoiceSpeed} onChange={(e) => update('reminderVoiceSpeed', e.target.value)}>
                  <option value="slow">慢速</option>
                  <option value="normal">正常</option>
                  <option value="fast">快速</option>
                </select>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="form-section">
        <h3 className="form-section-title">标签</h3>
        <div className="tag-group">
          {TAGS.map((tag) => (
            <button
              key={tag.id}
              type="button"
              className={`tag-toggle ${form.tagIds.includes(tag.id) ? 'active' : ''}`}
              style={{
                borderColor: form.tagIds.includes(tag.id) ? tag.color : '#cbd5e1',
                color: form.tagIds.includes(tag.id) ? '#fff' : tag.color,
                background: form.tagIds.includes(tag.id) ? tag.color : 'transparent',
              }}
              onClick={() => toggleTag(tag.id)}
            >
              {tag.label}
            </button>
          ))}
        </div>
      </div>

      <div className="form-section">
        <h3 className="form-section-title">周期任务</h3>
        <div className="form-grid">
          <div className="form-field">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={form.isRecurring}
                onChange={(e) => update('isRecurring', e.target.checked)}
              />
              设为周期任务
            </label>
          </div>
          {form.isRecurring && (
            <div className="form-field">
              <label>重复频率</label>
              <select value={form.recurringRule} onChange={(e) => update('recurringRule', e.target.value)}>
                <option value="">选择频率</option>
                <option value='{"freq":"daily","interval":1}'>每天</option>
                <option value='{"freq":"weekly","interval":1}'>每周</option>
                <option value='{"freq":"monthly","interval":1}'>每月</option>
              </select>
            </div>
          )}
        </div>
      </div>

      {error && <div className="form-error">{error}</div>}

      <div className="form-actions">
        <button type="submit" className="primary-btn" disabled={submitting}>
          {submitting ? '创建中...' : '创建任务'}
        </button>
        <button type="button" className="ghost-button" onClick={onCancel}>
          取消
        </button>
      </div>
    </form>
  );
}
