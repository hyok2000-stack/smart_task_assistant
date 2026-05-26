import { Fragment, useState } from 'react';
import type { Task, TaskQuery, Team, User } from '../../types';
import TaskRowExpanded from './TaskRowExpanded';
import TaskEditForm from './TaskEditForm';

const STATUS_MAP: Record<string, { label: string; cls: string }> = {
  pending: { label: '待处理', cls: 'status-pending' },
  in_progress: { label: '进行中', cls: 'status-in-progress' },
  completed: { label: '已完成', cls: 'status-completed' },
  cancelled: { label: '已取消', cls: 'status-cancelled' },
};

const PRIORITY_MAP: Record<string, { label: string; cls: string }> = {
  low: { label: '低', cls: 'priority-low' },
  medium: { label: '中', cls: 'priority-medium' },
  high: { label: '高', cls: 'priority-high' },
};

interface Comment {
  id: string;
  taskId: string;
  authorUserId: string;
  content: string;
  status: string;
  serverCreatedAt: string;
}

interface TaskTableProps {
  tasks: Task[];
  users: User[];
  teams: Team[];
  comments: Comment[];
  distributions: Array<{ sourceTaskId: string; recipientTaskId?: string }>;
  expandedTaskId: string | null;
  onToggleExpand: (taskId: string) => void;
  token: string;
  onRefresh: () => void;
  query: TaskQuery;
  pageInfo: { total: number; totalPages: number };
  loading: boolean;
  onQueryChange: (patch: TaskQuery) => void;
  onViewDetail?: (taskId: string) => void;
}

export default function TaskTable({
  tasks,
  users,
  teams,
  comments,
  distributions,
  expandedTaskId,
  onToggleExpand,
  token,
  onRefresh,
  query,
  pageInfo,
  loading,
  onQueryChange,
  onViewDetail,
}: TaskTableProps) {
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);

  const userName = (id: string) => users.find((u) => u.id === id)?.nickname ?? id;
  const hasFilter = query.status || query.priority || query.source || query.ownerUserId || query.teamId || query.search;

  const clearFilters = () => {
    onQueryChange({
      page: 1,
      status: '',
      priority: '',
      source: '',
      ownerUserId: '',
      teamId: '',
      search: '',
    });
  };

  return (
    <>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center', marginBottom: 12 }}>
        <select value={query.status ?? ''} onChange={(e) => onQueryChange({ status: e.target.value })} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}>
          <option value="">全部状态</option>
          <option value="pending">待处理</option>
          <option value="in_progress">进行中</option>
          <option value="completed">已完成</option>
          <option value="cancelled">已取消</option>
        </select>
        <select value={query.priority ?? ''} onChange={(e) => onQueryChange({ priority: e.target.value })} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}>
          <option value="">全部优先级</option>
          <option value="high">高</option>
          <option value="medium">中</option>
          <option value="low">低</option>
        </select>
        <select value={query.source ?? ''} onChange={(e) => onQueryChange({ source: e.target.value })} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}>
          <option value="">全部来源</option>
          <option value="local">本地创建</option>
          <option value="team_distribution">团队分发</option>
        </select>
        <select value={query.ownerUserId ?? ''} onChange={(e) => onQueryChange({ ownerUserId: e.target.value })} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}>
          <option value="">全部负责人</option>
          {users.map((u) => (
            <option key={u.id} value={u.id}>{u.nickname}</option>
          ))}
        </select>
        <select value={query.teamId ?? ''} onChange={(e) => onQueryChange({ teamId: e.target.value })} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}>
          <option value="">全部团队</option>
          {teams.map((team) => (
            <option key={team.id} value={team.id}>{team.name}</option>
          ))}
        </select>
        <input
          value={query.search ?? ''}
          onChange={(e) => onQueryChange({ search: e.target.value })}
          placeholder="搜索标题/内容"
          style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13, width: 160 }}
        />
        {hasFilter && (
          <button type="button" onClick={clearFilters} style={{ padding: '6px 12px', borderRadius: 6, border: '1px solid #e2e8f0', background: '#f1f5f9', fontSize: 13, cursor: 'pointer' }}>
            清除筛选
          </button>
        )}
        <span style={{ marginLeft: 'auto', fontSize: 13, color: '#64748b' }}>
          {loading ? '加载中...' : `第 ${query.page ?? 1} / ${pageInfo.totalPages} 页，共 ${pageInfo.total} 条`}
        </span>
      </div>

      {tasks.length === 0 ? (
        <div className="empty-state">{loading ? '正在加载任务...' : '暂无匹配任务'}</div>
      ) : (
        <table className="task-table">
          <thead>
            <tr>
              <th>标题</th>
              <th>负责人</th>
              <th>指派给</th>
              <th>状态</th>
              <th>优先级</th>
              <th>截止时间</th>
              <th>来源</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {tasks.map((task) => {
              const status = STATUS_MAP[task.status] ?? { label: task.status, cls: '' };
              const priority = PRIORITY_MAP[task.priority] ?? { label: task.priority, cls: '' };
              const isExpanded = expandedTaskId === task.id;

              return (
                <Fragment key={task.id}>
                  <tr>
                    <td className="task-title-cell">{task.title}</td>
                    <td>{userName(task.ownerUserId)}</td>
                    <td>{task.assigneeUserId ? userName(task.assigneeUserId) : '-'}</td>
                    <td>
                      <span className={`status-badge ${status.cls}`}>{status.label}</span>
                    </td>
                    <td>
                      <span className={`priority-dot ${priority.cls}`} />
                      {priority.label}
                    </td>
                    <td>{task.dueTime ? new Date(task.dueTime).toLocaleDateString('zh-CN') : '-'}</td>
                    <td>
                      <span className={`source-badge ${task.sourceType === 'team_distribution' ? 'source-dist' : 'source-local'}`}>
                        {task.sourceType === 'team_distribution' ? '分发' : '本地'}
                      </span>
                    </td>
                    <td>
                      <div className="action-btns">
                        {onViewDetail && (
                          <button
                            type="button"
                            className="expand-btn"
                            onClick={() => onViewDetail(task.id)}
                          >
                            查看详情
                          </button>
                        )}
                        <button
                          type="button"
                          className="expand-btn"
                          onClick={() => onToggleExpand(task.id)}
                        >
                          {isExpanded ? '收起' : '详情'}
                        </button>
                        <button
                          type="button"
                          className="expand-btn"
                          onClick={() => setEditingTaskId(editingTaskId === task.id ? null : task.id)}
                        >
                          {editingTaskId === task.id ? '取消编辑' : '编辑'}
                        </button>
                      </div>
                    </td>
                  </tr>
                  {editingTaskId === task.id && (
                    <TaskEditForm
                      task={task}
                      users={users}
                      comments={comments}
                      distributions={distributions}
                      token={token}
                      onSave={() => { setEditingTaskId(null); onRefresh(); }}
                      onCancel={() => setEditingTaskId(null)}
                    />
                  )}
                  {isExpanded && editingTaskId !== task.id && (
                    <TaskRowExpanded task={task} userName={userName} comments={comments} distributions={distributions} />
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      )}
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 12, alignItems: 'center' }}>
        <button
          type="button"
          className="ghost-button"
          disabled={(query.page ?? 1) <= 1 || loading}
          onClick={() => onQueryChange({ page: Math.max(1, (query.page ?? 1) - 1) })}
        >
          上一页
        </button>
        <select
          value={query.pageSize ?? 20}
          onChange={(e) => onQueryChange({ page: 1, pageSize: Number(e.target.value) })}
          style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid #cbd5e1', fontSize: 13 }}
        >
          <option value={10}>10 条/页</option>
          <option value={20}>20 条/页</option>
          <option value={50}>50 条/页</option>
          <option value={100}>100 条/页</option>
        </select>
        <button
          type="button"
          className="ghost-button"
          disabled={(query.page ?? 1) >= pageInfo.totalPages || loading}
          onClick={() => onQueryChange({ page: (query.page ?? 1) + 1 })}
        >
          下一页
        </button>
      </div>
    </>
  );
}
