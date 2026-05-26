import type { TaskDistribution, User } from '../../types';

const STATUS_MAP: Record<string, { label: string; cls: string }> = {
  sent: { label: '已发送', cls: 'status-sent' },
  received: { label: '已接收', cls: 'status-received' },
  generated: { label: '已生成', cls: 'status-generated' },
  viewed: { label: '已查看', cls: 'status-viewed' },
  in_progress: { label: '进行中', cls: 'status-in-progress' },
  completed: { label: '已完成', cls: 'status-completed' },
  cancelled: { label: '已取消', cls: 'status-cancelled' },
  failed: { label: '失败', cls: 'status-failed' },
};

interface DistributionTableProps {
  distributions: TaskDistribution[];
  users: User[];
  page: number;
  totalPages: number;
  total: number;
  onPageChange: (page: number) => void;
}

export default function DistributionTable({ distributions, users, page, totalPages, total, onPageChange }: DistributionTableProps) {
  const userName = (id: string) => users.find((u) => u.id === id)?.nickname ?? id;
  const distributionTitle = (dist: TaskDistribution) => dist.sourceTaskTitle ?? dist.sourceTaskId;
  const recipientTaskTitle = (dist: TaskDistribution) => dist.recipientTaskTitle ?? '-';

  if (distributions.length === 0) {
    return <div className="empty-state">暂无分发记录</div>;
  }

  return (
    <>
      <table className="dist-table">
        <thead>
          <tr>
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
          {distributions.map((dist) => {
            const status = STATUS_MAP[dist.status] ?? { label: dist.status, cls: '' };
            return (
              <tr key={dist.id}>
                <td className="task-title-cell">{distributionTitle(dist)}</td>
                <td className="task-title-cell">{recipientTaskTitle(dist)}</td>
                <td>{userName(dist.senderUserId)}</td>
                <td>{userName(dist.recipientUserId)}</td>
                <td>
                  <span className={`status-badge ${status.cls}`}>{status.label}</span>
                </td>
                <td>
                  {dist.commentCount} 条
                  {dist.lastCommentSummary ? `：${dist.lastCommentSummary}` : ''}
                  {dist.lastCommentAt && (Date.now() - new Date(dist.lastCommentAt).getTime() < 24 * 3600 * 1000) && (
                    <span className="new-badge" style={{ marginLeft: 6, background: '#ff4d4f', color: '#fff', padding: '1px 6px', borderRadius: 8, fontSize: 11 }}>新</span>
                  )}
                </td>
                <td>{new Date(dist.createdAt).toLocaleString('zh-CN')}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {totalPages > 1 && (
        <div className="pagination">
          <button disabled={page <= 1} onClick={() => onPageChange(page - 1)}>
            上一页
          </button>
          <span className="pagination-info">
            第 {page} / {totalPages} 页（共 {total} 条）
          </span>
          <button disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}>
            下一页
          </button>
        </div>
      )}
    </>
  );
}
