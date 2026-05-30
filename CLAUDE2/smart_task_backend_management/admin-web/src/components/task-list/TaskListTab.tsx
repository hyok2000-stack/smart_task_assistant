import { useEffect, useRef, useState } from 'react';
import { loadAdminTasks, apiFetch } from '../../api';
import type { Overview, Task, TaskQuery } from '../../types';
import TaskDetailPage from '../task-detail/TaskDetailPage';
import TaskTable from './TaskTable';
import TaskCreateForm from './TaskCreateForm';

interface TaskListTabProps {
  overview: Overview;
  token: string;
  onRefresh: () => void;
  initialFilter?: { status?: string; priority?: string; source?: string };
}

export default function TaskListTab({ overview, token, onRefresh, initialFilter }: TaskListTabProps) {
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [expandedTaskId, setExpandedTaskId] = useState<string | null>(null);
  const [detailTaskId, setDetailTaskId] = useState<string | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [query, setQuery] = useState<TaskQuery>({
    page: 1,
    pageSize: 20,
    status: initialFilter?.status ?? '',
    priority: initialFilter?.priority ?? '',
    source: initialFilter?.source ?? '',
  });
  const [pageInfo, setPageInfo] = useState({ total: 0, totalPages: 1 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const fetchSeq = useRef(0);

  const toggleExpand = (taskId: string) => {
    setExpandedTaskId((prev) => (prev === taskId ? null : taskId));
  };

  const handleCreateSuccess = () => {
    setShowCreateForm(false);
    onRefresh();
    void fetchTasks(query);
  };

  async function fetchTasks(nextQuery = query) {
    const seq = ++fetchSeq.current;
    setLoading(true);
    setError('');
    try {
      const data = await loadAdminTasks(token, nextQuery);
      if (seq !== fetchSeq.current) return;
      setTasks(data.tasks);
      setPageInfo({ total: data.total, totalPages: data.totalPages });
      setQuery((prev) => ({ ...prev, page: data.page, pageSize: data.pageSize }));
    } catch (err: any) {
      if (seq !== fetchSeq.current) return;
      setError(err.message ?? '任务加载失败');
    } finally {
      if (seq === fetchSeq.current) setLoading(false);
    }
  }

  function handleQueryChange(patch: TaskQuery) {
    const next = { ...query, ...patch, page: patch.page ?? 1 };
    setQuery(next);
    void fetchTasks(next);
  }

  useEffect(() => {
    const next = {
      ...query,
      page: 1,
      status: initialFilter?.status ?? '',
      priority: initialFilter?.priority ?? '',
      source: initialFilter?.source ?? '',
    };
    setQuery(next);
    void fetchTasks(next);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialFilter?.status, initialFilter?.priority, initialFilter?.source, token]);

  return (
    <div className="tab-content">
      {detailTaskId ? (
        <TaskDetailPage
          taskId={detailTaskId}
          token={token}
          onBack={() => setDetailTaskId(null)}
        />
      ) : (
        <>
          <div className="tab-header">
            <button
              type="button"
              className="primary-btn"
              onClick={() => setShowCreateForm((prev) => !prev)}
            >
              {showCreateForm ? '取消新建' : '新建任务'}
            </button>
            <button
              type="button"
              className="ghost-button"
              style={{ marginLeft: 8 }}
              onClick={async () => {
                try {
                  const API_BASE = import.meta.env.VITE_API_BASE ?? 'http://localhost:4100/api';
                  const res = await fetch(`${API_BASE}/admin/tasks/export`, {
                    headers: { Authorization: `Bearer ${token}` },
                  });
                  if (!res.ok) {
                    const ct = res.headers.get('content-type') ?? '';
                    if (ct.includes('application/json')) {
                      const err = await res.json();
                      throw new Error(err.message ?? `导出失败: ${res.status}`);
                    }
                    throw new Error(`导出失败: ${res.status}`);
                  }
                  const csv = await res.text();
                  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
                  const url = URL.createObjectURL(blob);
                  const a = document.createElement('a');
                  a.href = url;
                  a.download = `tasks_export_${new Date().toISOString().slice(0, 10)}.csv`;
                  a.click();
                  URL.revokeObjectURL(url);
                } catch { alert('导出失败'); }
              }}
            >
              导出 CSV
            </button>
            <button
              type="button"
              className="ghost-button"
              style={{ marginLeft: 8, color: '#ef4444', borderColor: '#fca5a5' }}
              onClick={async () => {
                const msg = pageInfo.total > tasks.length
                  ? `确定删除当前筛选条件下的全部 ${pageInfo.total} 条任务？此操作不可撤销。`
                  : `确定删除当前显示的 ${tasks.length} 条任务？此操作不可撤销。`;
                if (!confirm(msg)) return;
                try {
                  const filterQuery = {
                    status: query.status || undefined,
                    priority: query.priority || undefined,
                    source: query.source || undefined,
                    ownerUserId: query.ownerUserId || undefined,
                    teamId: query.teamId || undefined,
                    search: query.search || undefined,
                  };
                  const res = await apiFetch('/admin/tasks/batch-delete', {
                    method: 'POST',
                    body: JSON.stringify({ query: filterQuery }),
                  }, token);
                  alert(`已删除 ${res.deleted} 条任务`);
                  onRefresh();
                  void fetchTasks(query);
                } catch (err: any) {
                  alert('批量删除失败: ' + (err.message ?? '未知错误'));
                }
              }}
            >
              批量删除 ({pageInfo.total})
            </button>
          </div>

          {showCreateForm && (
            <div className="panel">
              <TaskCreateForm
                token={token}
                users={overview.users}
                onSuccess={handleCreateSuccess}
                onCancel={() => setShowCreateForm(false)}
              />
            </div>
          )}

          <div className="panel">
            {error && <div className="form-error">{error}</div>}
            <TaskTable
              tasks={tasks}
              users={overview.users}
              teams={overview.teams}
              comments={overview.comments ?? []}
              distributions={overview.distributions ?? []}
              expandedTaskId={expandedTaskId}
              onToggleExpand={toggleExpand}
              token={token}
              onRefresh={() => {
                onRefresh();
                void fetchTasks(query);
              }}
              query={query}
              pageInfo={pageInfo}
              loading={loading}
              onQueryChange={handleQueryChange}
              onViewDetail={setDetailTaskId}
            />
          </div>
        </>
      )}
    </div>
  );
}
