import type { Comment, Task } from '../../types';

const TAG_MAP: Record<string, { label: string; color: string }> = {
  default_work: { label: '工作', color: '#3B82F6' },
  default_personal: { label: '个人', color: '#10B981' },
  default_urgent: { label: '紧急', color: '#EF4444' },
  default_study: { label: '学习', color: '#8B5CF6' },
};

interface TaskRowExpandedProps {
  task: Task;
  userName: (id: string) => string;
  comments: Comment[];
  distributions: Array<{ sourceTaskId: string; recipientTaskId?: string }>;
}

export default function TaskRowExpanded({ task, userName, comments, distributions }: TaskRowExpandedProps) {
  const fmtDate = (v?: string) => (v ? new Date(v).toLocaleString('zh-CN') : '-');
  const recurringLabel = (rule?: string) => {
    if (!rule) return '是';
    if (rule === 'daily') return '每天';
    if (rule === 'weekly') return '每周';
    if (rule === 'monthly') return '每月';
    try {
      const parsed = JSON.parse(rule);
      if (parsed.freq === 'daily') return '每天';
      if (parsed.freq === 'weekly') return '每周';
      if (parsed.freq === 'monthly') return '每月';
    } catch {
      return rule;
    }
    return rule;
  };
  const relatedIds = new Set<string>([task.id]);
  for (const d of distributions) {
    if (d.sourceTaskId === task.id && d.recipientTaskId) relatedIds.add(d.recipientTaskId);
    if (d.recipientTaskId === task.id) relatedIds.add(d.sourceTaskId);
  }
  const taskComments = comments
    .filter((c) => relatedIds.has(c.taskId) && c.status === 'active')
    .sort((a, b) => b.serverCreatedAt.localeCompare(a.serverCreatedAt));

  return (
    <tr>
      <td colSpan={8} className="task-expanded-cell">
        <div className="task-expanded">
          <div className="detail-grid">
            <div className="detail-item">
              <span className="detail-label">ID</span>
              <span className="detail-value mono">{task.id}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">内容</span>
              <span className="detail-value">{task.content || '-'}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">负责人</span>
              <span className="detail-value">{userName(task.ownerUserId)}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">指派人</span>
              <span className="detail-value">{task.assignee || '-'}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">开始时间</span>
              <span className="detail-value">{fmtDate(task.startTime)}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">截止时间</span>
              <span className="detail-value">{fmtDate(task.dueTime)}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">完成时间</span>
              <span className="detail-value">{fmtDate(task.completedAt)}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">来源类型</span>
              <span className="detail-value">
                {task.sourceType === 'team_distribution' ? '团队分发' : '本地创建'}
              </span>
            </div>
            {task.sourceTaskId && (
              <div className="detail-item">
                <span className="detail-label">原任务ID</span>
                <span className="detail-value mono">{task.sourceTaskId}</span>
              </div>
            )}
            <div className="detail-item">
              <span className="detail-label">标签</span>
              <span className="detail-value">
                {task.tagIds && task.tagIds.length > 0
                  ? task.tagIds.map((tagId) => {
                      const tag = TAG_MAP[tagId];
                      return tag ? (
                        <span key={tagId} className="tag-chip" style={{ background: tag.color + '18', color: tag.color, border: `1px solid ${tag.color}40` }}>
                          {tag.label}
                        </span>
                      ) : (
                        <span key={tagId} className="tag-chip">{tagId}</span>
                      );
                    })
                  : '-'}
              </span>
            </div>
            <div className="detail-item">
              <span className="detail-label">提醒</span>
              <span className="detail-value">
                {task.reminderMinutes != null ? `提前 ${task.reminderMinutes} 分钟` : '-'}
                {task.reminderVoiceEnabled ? ' (语音)' : ''}
              </span>
            </div>
            <div className="detail-item">
              <span className="detail-label">周期任务</span>
              <span className="detail-value">
                {task.isRecurring ? recurringLabel(task.recurringRule) : '否'}
              </span>
            </div>
            <div className="detail-item">
              <span className="detail-label">团队ID</span>
              <span className="detail-value mono">{task.teamId || '-'}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">版本</span>
              <span className="detail-value">v{task.version}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">创建时间</span>
              <span className="detail-value">{fmtDate(task.createdAt)}</span>
            </div>
            <div className="detail-item">
              <span className="detail-label">更新时间</span>
              <span className="detail-value">{fmtDate(task.updatedAt)}</span>
            </div>
          </div>

          {taskComments.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <h4 style={{ margin: '0 0 8px', fontSize: 13, color: '#64748b' }}>
                评论记录 ({taskComments.length})
              </h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {taskComments.map((c) => (
                  <div key={c.id} style={{ background: '#f8fafc', padding: '8px 12px', borderRadius: 8, border: '1px solid #e2e8f0' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                      <span style={{ fontWeight: 600, fontSize: 12, color: '#334155' }}>{userName(c.authorUserId)}</span>
                      <span style={{ fontSize: 11, color: '#94a3b8' }}>{new Date(c.serverCreatedAt).toLocaleString('zh-CN')}</span>
                    </div>
                    <div style={{ fontSize: 13, color: '#475569' }}>{c.content}</div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </td>
    </tr>
  );
}
