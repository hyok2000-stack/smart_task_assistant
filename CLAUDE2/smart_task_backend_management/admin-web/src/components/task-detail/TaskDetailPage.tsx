import { useEffect, useState } from 'react';
import type { Task } from '../../types';
import * as api from '../../api';

const STATUS_MAP: Record<string, { label: string; cls: string }> = {
  pending: { label: '待处理', cls: 'status-pending' },
  in_progress: { label: '进行中', cls: 'status-in_progress' },
  completed: { label: '已完成', cls: 'status-completed' },
  cancelled: { label: '已取消', cls: 'status-cancelled' },
};

const PRIORITY_MAP: Record<string, { label: string; color: string }> = {
  high: { label: '高', color: '#ef4444' },
  medium: { label: '中', color: '#f59e0b' },
  low: { label: '低', color: '#22c55e' },
};

const DIST_STATUS_MAP: Record<string, { label: string; cls: string }> = {
  sent: { label: '已发送', cls: 'status-sent' },
  received: { label: '已接收', cls: 'status-received' },
  generated: { label: '已生成', cls: 'status-generated' },
  viewed: { label: '已查看', cls: 'status-viewed' },
  completed: { label: '已完成', cls: 'status-completed' },
  failed: { label: '失败', cls: 'status-failed' },
};

interface Props {
  taskId: string;
  token: string;
  onBack: () => void;
}

type TabKey = 'info' | 'comments' | 'distributions' | 'logs' | 'sync';

export default function TaskDetailPage({ taskId, token, onBack }: Props) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState<TabKey>('info');
  const [newComment, setNewComment] = useState('');

  useEffect(() => {
    load();
  }, [taskId, token]);

  async function load() {
    setLoading(true);
    setError('');
    try {
      const result = await api.loadAdminTaskDetail(token, taskId);
      setData(result);
    } catch (e: any) {
      setError(e.message ?? '加载失败');
    } finally {
      setLoading(false);
    }
  }

  async function handleAddComment() {
    if (!newComment.trim()) return;
    try {
      await api.adminAddComment(token, taskId, newComment.trim());
      setNewComment('');
      load();
    } catch (e: any) {
      alert('评论失败: ' + e.message);
    }
  }

  async function handleDeleteComment(commentId: string) {
    try {
      await api.adminDeleteComment(token, commentId);
      load();
    } catch (e: any) {
      alert('删除失败: ' + e.message);
    }
  }

  if (loading) return <div className="detail-loading">加载中...</div>;
  if (error) return <div className="detail-error">{error}</div>;
  if (!data) return null;

  const task: Task = data.task;

  const tabs: { key: TabKey; label: string }[] = [
    { key: 'info', label: `任务信息` },
    { key: 'comments', label: `评论 (${data.comments.length})` },
    { key: 'distributions', label: `分发链路 (${data.distributions.length})` },
    { key: 'logs', label: `状态日志 (${data.statusLogs.length})` },
    { key: 'sync', label: `同步日志 (${data.syncLogs.length})` },
  ];

  return (
    <div className="detail-page">
      <div className="detail-header">
        <button className="back-btn" onClick={onBack}>← 返回</button>
        <div className="detail-title-row">
          <h2>{task.title}</h2>
          <span className={`status-badge ${STATUS_MAP[task.status]?.cls ?? ''}`}>
            {STATUS_MAP[task.status]?.label ?? task.status}
          </span>
          <span className="priority-dot" style={{ background: PRIORITY_MAP[task.priority]?.color ?? '#94a3b8' }}>
            {PRIORITY_MAP[task.priority]?.label ?? task.priority}
          </span>
          <span className="version-badge">v{task.version ?? 1}</span>
        </div>
      </div>

      <div className="detail-tabs">
        {tabs.map((t) => (
          <button
            key={t.key}
            className={`detail-tab ${activeTab === t.key ? 'active' : ''}`}
            onClick={() => setActiveTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="detail-body">
        {activeTab === 'info' && <InfoSection task={task} />}
        {activeTab === 'comments' && (
          <CommentsSection
            comments={data.comments}
            newComment={newComment}
            onNewCommentChange={setNewComment}
            onSubmit={handleAddComment}
            onDelete={handleDeleteComment}
          />
        )}
        {activeTab === 'distributions' && <DistributionsSection distributions={data.distributions} />}
        {activeTab === 'logs' && <StatusLogsSection logs={data.statusLogs} />}
        {activeTab === 'sync' && <SyncLogsSection logs={data.syncLogs} />}
      </div>
    </div>
  );
}

function InfoSection({ task }: { task: Task }) {
  const fields: [string, string | undefined][] = [
    ['ID', task.id],
    ['内容', task.content],
    ['指派人', (task as any).assigneeName ?? (task as any).assigneeUserId ?? '-'],
    ['来源', task.sourceType === 'team_distribution' ? '团队分发' : '本地'],
    ['优先级', task.priority],
    ['开始时间', task.startTime ? new Date(task.startTime).toLocaleString('zh-CN') : undefined],
    ['截止时间', task.dueTime ? new Date(task.dueTime).toLocaleString('zh-CN') : undefined],
    ['完成时间', task.completedAt ? new Date(task.completedAt).toLocaleString('zh-CN') : undefined],
    ['标签', (task as any).tagIds?.length ? (task as any).tagIds.join(', ') : undefined],
    ['提醒(分钟)', (task as any).reminderMinutes != null ? String((task as any).reminderMinutes) : undefined],
    ['重复', (task as any).isRecurring ? (task as any).recurringRule ?? '是' : '否'],
    ['团队ID', (task as any).teamId],
    ['创建时间', task.createdAt ? new Date(task.createdAt).toLocaleString('zh-CN') : undefined],
    ['更新时间', task.updatedAt ? new Date(task.updatedAt).toLocaleString('zh-CN') : undefined],
  ];
  return (
    <div className="info-grid">
      {fields.map(([label, value]) => (
        <div key={label} className="info-item">
          <span className="info-label">{label}</span>
          <span className="info-value">{value ?? '-'}</span>
        </div>
      ))}
    </div>
  );
}

function CommentsSection({ comments, newComment, onNewCommentChange, onSubmit, onDelete }: any) {
  return (
    <div>
      <div className="comment-input-row">
        <input
          value={newComment}
          onChange={(e) => onNewCommentChange(e.target.value)}
          placeholder="输入评论..."
          onKeyDown={(e) => e.key === 'Enter' && onSubmit()}
        />
        <button onClick={onSubmit} disabled={!newComment.trim()}>发送</button>
      </div>
      {comments.length === 0 ? (
        <div className="empty-state">暂无评论</div>
      ) : (
        <div className="comment-timeline">
          {[...comments].reverse().map((c: any) => (
            <div key={c.id} className="comment-item">
              <div className="comment-meta">
                <span className="comment-author">{c.authorName ?? '未知'}</span>
                <span className="comment-time">{new Date(c.serverCreatedAt ?? c.createdAt).toLocaleString('zh-CN')}</span>
                <button className="comment-delete-btn" onClick={() => onDelete(c.id)}>删除</button>
              </div>
              <div className="comment-content">{c.content}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function DistributionsSection({ distributions }: { distributions: any[] }) {
  if (distributions.length === 0) return <div className="empty-state">暂无分发记录</div>;
  return (
    <table className="dist-table">
      <thead>
        <tr>
          <th>方向</th>
          <th>原任务</th>
          <th>接收方任务</th>
          <th>发送方</th>
          <th>接收方</th>
          <th>状态</th>
          <th>评论</th>
          <th>创建时间</th>
        </tr>
      </thead>
      <tbody>
        {distributions.map((d: any) => {
          const s = DIST_STATUS_MAP[d.status] ?? { label: d.status, cls: '' };
          return (
            <tr key={d.id}>
              <td>{d.sourceTaskTitle ? '发出' : '接收'}</td>
              <td>{d.sourceTaskTitle ?? d.sourceTaskId}</td>
              <td>{d.recipientTaskTitle ?? '-'}</td>
              <td>{d.senderName}</td>
              <td>{d.recipientName}</td>
              <td><span className={`status-badge ${s.cls}`}>{s.label}</span></td>
              <td>{d.commentCount} 条</td>
              <td>{new Date(d.createdAt).toLocaleString('zh-CN')}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function StatusLogsSection({ logs }: { logs: any[] }) {
  if (logs.length === 0) return <div className="empty-state">暂无状态变更记录</div>;
  return (
    <div className="log-timeline">
      {logs.map((l: any) => (
        <div key={l.id} className="log-item">
          <span className={`status-badge ${STATUS_MAP[l.newStatus]?.cls ?? ''}`}>
            {STATUS_MAP[l.previousStatus]?.label ?? l.previousStatus}
          </span>
          <span className="log-arrow">→</span>
          <span className={`status-badge ${STATUS_MAP[l.newStatus]?.cls ?? ''}`}>
            {STATUS_MAP[l.newStatus]?.label ?? l.newStatus}
          </span>
          <span className="log-detail">
            由 {l.changedByName}（{l.source}）于 {new Date(l.createdAt).toLocaleString('zh-CN')}
          </span>
        </div>
      ))}
    </div>
  );
}

function SyncLogsSection({ logs }: { logs: any[] }) {
  if (logs.length === 0) return <div className="empty-state">暂无同步记录</div>;
  return (
    <table>
      <thead>
        <tr>
          <th>操作类型</th>
          <th>状态</th>
          <th>设备ID</th>
          <th>时间</th>
        </tr>
      </thead>
      <tbody>
        {logs.map((l: any) => (
          <tr key={l.id}>
            <td>{l.operationType}</td>
            <td>{l.status}</td>
            <td className="id-cell">{l.deviceId ?? '-'}</td>
            <td>{new Date(l.createdAt).toLocaleString('zh-CN')}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
