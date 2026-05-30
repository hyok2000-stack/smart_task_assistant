import { useState } from 'react';
import type { Comment, Task, User } from '../../types';
import { updateTask, adminAddComment, adminDeleteComment } from '../../api';

const TAG_OPTIONS = [
  { id: 'default_work', label: '工作' },
  { id: 'default_personal', label: '个人' },
  { id: 'default_urgent', label: '紧急' },
  { id: 'default_study', label: '学习' },
];

const RECURRENCE_OPTIONS = [
  { value: '', label: '无' },
  { value: 'daily', label: '每天' },
  { value: 'weekly', label: '每周' },
  { value: 'monthly', label: '每月' },
];

interface TaskEditFormProps {
  task: Task;
  users: User[];
  comments: Comment[];
  distributions: Array<{ sourceTaskId: string; recipientTaskId?: string }>;
  token: string;
  onSave: () => void;
  onCancel: () => void;
}

function datetimeLocal(v?: string) {
  if (!v) return '';
  try {
    const d = new Date(v);
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } catch {
    return '';
  }
}

export default function TaskEditForm({ task, users, comments, distributions, token, onSave, onCancel }: TaskEditFormProps) {
  const [title, setTitle] = useState(task.title);
  const [content, setContent] = useState(task.content ?? '');
  const [status, setStatus] = useState(task.status);
  function handleStatusChange(newStatus: string) {
    setStatus(newStatus as Task['status']);
    if (newStatus === 'completed' && !completedAt) {
      setCompletedAt(datetimeLocal(new Date().toISOString()));
    }
  }
  const [priority, setPriority] = useState(task.priority);
  const [startTime, setStartTime] = useState(datetimeLocal(task.startTime));
  const [dueTime, setDueTime] = useState(datetimeLocal(task.dueTime));
  const [completedAt, setCompletedAt] = useState(datetimeLocal(task.completedAt));
  const [assigneeUserId, setAssigneeUserId] = useState(task.assigneeUserId ?? '');
  const [ownerUserId, setOwnerUserId] = useState(task.ownerUserId);
  const [teamId, setTeamId] = useState(task.teamId ?? '');
  const [parentId, setParentId] = useState(task.parentId ?? '');
  const [isRecurring, setIsRecurring] = useState(task.isRecurring ?? false);
  const [recurringFreq, setRecurringFreq] = useState(() => {
    if (!task.recurringRule) return '';
    try { return JSON.parse(task.recurringRule).freq ?? ''; } catch { return ''; }
  });
  const [tagIds, setTagIds] = useState<string[]>(task.tagIds ?? []);
  const [reminderMinutes, setReminderMinutes] = useState(task.reminderMinutes != null ? String(task.reminderMinutes) : '');
  const [reminderDismissed, setReminderDismissed] = useState(task.reminderDismissed ?? false);
  const [reminderVoiceEnabled, setReminderVoiceEnabled] = useState(task.reminderVoiceEnabled ?? false);
  const [reminderVoiceType, setReminderVoiceType] = useState(task.reminderVoiceType ?? '');
  const [reminderVoiceStyle, setReminderVoiceStyle] = useState(task.reminderVoiceStyle ?? '');
  const [reminderVoiceSpeed, setReminderVoiceSpeed] = useState(task.reminderVoiceSpeed ?? '');
  const [reminderCustomVoicePath, setReminderCustomVoicePath] = useState(task.reminderCustomVoicePath ?? '');

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  // Comment state
  const [newComment, setNewComment] = useState('');
  const [commentAsUserId, setCommentAsUserId] = useState<string>(task.ownerUserId ?? '');
  const [commentSubmitting, setCommentSubmitting] = useState(false);

  // Collect related task IDs (source + recipient for distributed tasks)
  const relatedTaskIds = (() => {
    const ids = new Set<string>([task.id]);
    for (const d of distributions) {
      if (d.sourceTaskId === task.id && d.recipientTaskId) ids.add(d.recipientTaskId);
      if (d.recipientTaskId === task.id) ids.add(d.sourceTaskId);
    }
    return ids;
  })();

  const [localComments, setLocalComments] = useState(() =>
    comments
      .filter((c) => relatedTaskIds.has(c.taskId) && c.status === 'active')
      .sort((a, b) => b.serverCreatedAt.localeCompare(a.serverCreatedAt))
  );

  const userName = (id: string) => users.find((u) => u.id === id)?.nickname ?? id;

  const toggleTag = (id: string) => {
    setTagIds((prev) => prev.includes(id) ? prev.filter((t) => t !== id) : [...prev, id]);
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) { setError('请输入任务标题'); return; }
    setSubmitting(true);
    setError('');
    try {
      await updateTask(token, task.id, {
        title: title.trim(),
        content: content.trim() || undefined,
        status,
        priority,
        startTime: startTime || undefined,
        dueTime: dueTime || undefined,
        completedAt: completedAt || undefined,
        assigneeUserId: assigneeUserId || undefined,
        ownerUserId: ownerUserId || undefined,
        teamId: teamId || undefined,
        parentId: parentId.trim() || undefined,
        isRecurring,
        recurringRule: isRecurring && recurringFreq ? JSON.stringify({ freq: recurringFreq }) : undefined,
        tagIds,
        reminderMinutes: reminderMinutes ? (isNaN(Number(reminderMinutes)) ? undefined : Number(reminderMinutes)) : undefined,
        reminderDismissed,
        reminderVoiceEnabled,
        reminderVoiceType: reminderVoiceType || undefined,
        reminderVoiceStyle: reminderVoiceStyle || undefined,
        reminderVoiceSpeed: reminderVoiceSpeed || undefined,
        reminderCustomVoicePath: reminderCustomVoicePath || undefined,
      });
      onSave();
    } catch (err: any) {
      setError(err.message ?? '保存失败');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleAddComment() {
    const text = newComment.trim();
    if (!text) return;
    setCommentSubmitting(true);
    try {
      const authorId = commentAsUserId || undefined;
      const data = await adminAddComment(token, task.id, text, authorId);
      if (data?.comment) setLocalComments((prev) => [data.comment, ...prev]);
      setNewComment('');
    } catch (err: any) {
      alert(err.message ?? '评论失败');
    } finally {
      setCommentSubmitting(false);
    }
  }

  async function handleDeleteComment(commentId: string) {
    if (!confirm('确定删除该评论？')) return;
    try {
      await adminDeleteComment(token, commentId);
      setLocalComments((prev) => prev.filter((c) => c.id !== commentId));
    } catch (err: any) {
      alert(err.message ?? '删除失败');
    }
  }

  const field = (label: string, node: React.ReactNode, span?: boolean) => (
    <div className="form-field" key={label} style={span ? { gridColumn: '1 / -1' } : undefined}>
      <label>{label}</label>
      {node}
    </div>
  );

  return (
    <tr>
      <td colSpan={8} className="task-expanded-cell">
        <form className="dist-form" onSubmit={handleSubmit} style={{ margin: 0 }}>
          <div className="form-grid">
            {/* === 基本信息 === */}
            {field('标题 *', <input value={title} onChange={(e) => setTitle(e.target.value)} />, true)}
            {field('内容', <textarea value={content} onChange={(e) => setContent(e.target.value)} rows={3} />, true)}
            {field('状态', (
              <select value={status} onChange={(e) => handleStatusChange(e.target.value)}>
                <option value="pending">待处理</option>
                <option value="in_progress">进行中</option>
                <option value="completed">已完成</option>
                <option value="cancelled">已取消</option>
              </select>
            ))}
            {field('优先级', (
              <select value={priority} onChange={(e) => setPriority(e.target.value as Task['priority'])}>
                <option value="low">低</option>
                <option value="medium">中</option>
                <option value="high">高</option>
              </select>
            ))}
            {field('负责人', (
              <select value={ownerUserId} onChange={(e) => setOwnerUserId(e.target.value)}>
                {users.map((u) => <option key={u.id} value={u.id}>{u.nickname}</option>)}
              </select>
            ))}
            {field('指派人', (
              <select value={assigneeUserId} onChange={(e) => setAssigneeUserId(e.target.value)}>
                <option value="">未指派</option>
                {users.map((u) => <option key={u.id} value={u.id}>{u.nickname || u.email || u.id}</option>)}
              </select>
            ))}
            {field('开始时间', <input type="datetime-local" value={startTime} onChange={(e) => setStartTime(e.target.value)} />)}
            {field('截止时间', <input type="datetime-local" value={dueTime} onChange={(e) => setDueTime(e.target.value)} />)}
            {field('完成时间', <input type="datetime-local" value={completedAt} onChange={(e) => setCompletedAt(e.target.value)} />)}

            {/* === 组织关系 === */}
            {field('团队ID', <input value={teamId} onChange={(e) => setTeamId(e.target.value)} placeholder="留空表示不属于团队" />)}
            {field('父任务ID', <input value={parentId} onChange={(e) => setParentId(e.target.value)} placeholder="留空表示顶层任务" />)}

            {/* === 标签 === */}
            {field('标签', (
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {TAG_OPTIONS.map((tag) => (
                  <label key={tag.id} style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer', fontSize: 13 }}>
                    <input type="checkbox" checked={tagIds.includes(tag.id)} onChange={() => toggleTag(tag.id)} />
                    {tag.label}
                  </label>
                ))}
              </div>
            ))}

            {/* === 周期任务 === */}
            {field('周期任务', (
              <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <input type="checkbox" checked={isRecurring} onChange={(e) => setIsRecurring(e.target.checked)} />
                启用周期
              </label>
            ))}
            {isRecurring && field('重复频率', (
              <select value={recurringFreq} onChange={(e) => setRecurringFreq(e.target.value)}>
                {RECURRENCE_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            ))}

            {/* === 提醒设置 === */}
            {field('提醒时间(分钟)', <input type="number" value={reminderMinutes} onChange={(e) => setReminderMinutes(e.target.value)} placeholder="留空不提醒" />)}
            {field('提醒已关闭', (
              <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <input type="checkbox" checked={reminderDismissed} onChange={(e) => setReminderDismissed(e.target.checked)} />
                已关闭
              </label>
            ))}
            {field('语音提醒', (
              <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <input type="checkbox" checked={reminderVoiceEnabled} onChange={(e) => setReminderVoiceEnabled(e.target.checked)} />
                启用语音
              </label>
            ))}
            {reminderVoiceEnabled && (
              <>
                {field('语音类型', <input value={reminderVoiceType} onChange={(e) => setReminderVoiceType(e.target.value)} placeholder="如 alloy, echo" />)}
                {field('语音风格', <input value={reminderVoiceStyle} onChange={(e) => setReminderVoiceStyle(e.target.value)} />)}
                {field('语音速度', <input value={reminderVoiceSpeed} onChange={(e) => setReminderVoiceSpeed(e.target.value)} />)}
                {field('自定义语音路径', <input value={reminderCustomVoicePath} onChange={(e) => setReminderCustomVoicePath(e.target.value)} />, true)}
              </>
            )}
          </div>

          {error && <div className="form-error">{error}</div>}
          <div className="form-actions">
            <button type="submit" className="primary-btn" disabled={submitting}>
              {submitting ? '保存中...' : '保存'}
            </button>
            <button type="button" className="ghost-button" onClick={onCancel}>取消</button>
          </div>
        </form>

        {/* === 评论区域 === */}
        <div style={{ marginTop: 16, borderTop: '1px solid #e2e8f0', paddingTop: 16 }}>
          <h4 style={{ margin: '0 0 12px', fontSize: 14, color: '#334155' }}>
            评论记录 ({localComments.length})
          </h4>
          <div style={{ display: 'flex', gap: 8, marginBottom: 8, alignItems: 'center' }}>
            <label style={{ fontSize: 12, color: '#64748b', whiteSpace: 'nowrap' }}>以谁的名义：</label>
            <select
              value={commentAsUserId}
              onChange={(e) => setCommentAsUserId(e.target.value)}
              style={{ padding: '4px 8px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 12, minWidth: 120 }}
            >
              <option value="">管理员</option>
              {users.map((u) => (
                <option key={u.id} value={u.id}>{u.nickname || u.email || u.id}</option>
              ))}
            </select>
          </div>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <input
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder="添加评论..."
              style={{ flex: 1, padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleAddComment(); } }}
            />
            <button
              type="button"
              className="primary-btn"
              style={{ padding: '6px 14px', fontSize: 13 }}
              disabled={commentSubmitting || !newComment.trim()}
              onClick={handleAddComment}
            >
              {commentSubmitting ? '发送中...' : '发送'}
            </button>
          </div>
          {localComments.length === 0 ? (
            <div style={{ fontSize: 13, color: '#94a3b8', textAlign: 'center', padding: 12 }}>暂无评论</div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {localComments.map((c) => (
                <div key={c.id} style={{ background: '#f8fafc', padding: '8px 12px', borderRadius: 8, border: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                      <span style={{ fontWeight: 600, fontSize: 12, color: '#334155' }}>{userName(c.authorUserId)}</span>
                      <span style={{ fontSize: 11, color: '#94a3b8' }}>{new Date(c.serverCreatedAt).toLocaleString('zh-CN')}</span>
                    </div>
                    <div style={{ fontSize: 13, color: '#475569' }}>{c.content}</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => handleDeleteComment(c.id)}
                    style={{ marginLeft: 8, background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: 12, padding: '2px 4px', flexShrink: 0 }}
                    title="删除评论"
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* === 只读信息 === */}
        <div style={{ marginTop: 16, padding: '10px 12px', background: '#f8fafc', borderRadius: 6, border: '1px solid #e2e8f0' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 6, fontSize: 12, color: '#64748b' }}>
            <span>ID: <code>{task.id}</code></span>
            <span>来源: {task.sourceType === 'team_distribution' ? '团队分发' : '本地创建'}</span>
            {task.sourceTaskId && <span>原任务ID: <code>{task.sourceTaskId}</code></span>}
            {task.sourceDistributionId && <span>分发ID: <code>{task.sourceDistributionId}</code></span>}
            <span>版本: v{task.version}</span>
            <span>创建: {task.createdAt ? new Date(task.createdAt).toLocaleString('zh-CN') : '-'}</span>
            <span>更新: {task.updatedAt ? new Date(task.updatedAt).toLocaleString('zh-CN') : '-'}</span>
          </div>
        </div>
      </td>
    </tr>
  );
}
