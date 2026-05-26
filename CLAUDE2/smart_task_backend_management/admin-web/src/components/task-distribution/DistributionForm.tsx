import { useEffect, useState } from 'react';
import type { Task, Team, TeamMemberInfo } from '../../types';
import { getTeamMembers, createDistribution, loadAdminTasks } from '../../api';

interface DistributionFormProps {
  initialTasks: Task[];
  teams: Team[];
  adminUserId: string;
  token: string;
  onSuccess: () => void;
}

export default function DistributionForm({ initialTasks, teams, adminUserId, token, onSuccess }: DistributionFormProps) {
  const [tasks, setTasks] = useState<Task[]>(initialTasks);
  const [selectedTaskId, setSelectedTaskId] = useState('');
  const [selectedTeamId, setSelectedTeamId] = useState('');
  const [teamMembers, setTeamMembers] = useState<TeamMemberInfo[]>([]);
  const [selectedUserIds, setSelectedUserIds] = useState<Set<string>>(new Set());
  const [remark, setRemark] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const myTasks = tasks.filter((t) => t.ownerUserId === adminUserId && !t.deletedAt);

  useEffect(() => {
    async function fetchOwnedTasks() {
      try {
        const data = await loadAdminTasks(token, {
          ownerUserId: adminUserId,
          page: 1,
          pageSize: 100,
        });
        setTasks(data.tasks);
      } catch {
        setTasks(initialTasks);
      }
    }
    if (adminUserId) void fetchOwnedTasks();
  }, [adminUserId, initialTasks, token]);

  async function handleTeamChange(teamId: string) {
    setSelectedTeamId(teamId);
    setSelectedUserIds(new Set());
    setTeamMembers([]);
    if (!teamId) return;

    try {
      const data = await getTeamMembers(token, teamId);
      setTeamMembers(data.members.filter((m) => m.userId !== adminUserId));
    } catch {
      setError('加载团队成员失败');
    }
  }

  const toggleUser = (userId: string) => {
    setSelectedUserIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const selectAll = () => {
    if (selectedUserIds.size === teamMembers.length) {
      setSelectedUserIds(new Set());
    } else {
      setSelectedUserIds(new Set(teamMembers.map((m) => m.userId)));
    }
  };

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedTaskId) { setError('请选择任务'); return; }
    if (!selectedTeamId) { setError('请选择团队'); return; }
    if (selectedUserIds.size === 0) { setError('请选择接收用户'); return; }

    setLoading(true);
    setError('');
    setSuccess('');

    try {
      for (const userId of selectedUserIds) {
        await createDistribution(token, {
          sourceTaskId: selectedTaskId,
          recipientUserId: userId,
          teamId: selectedTeamId,
          remark: remark || undefined,
        });
      }
      setSuccess(`成功分发给 ${selectedUserIds.size} 个用户`);
      setSelectedTaskId('');
      setSelectedTeamId('');
      setSelectedUserIds(new Set());
      setTeamMembers([]);
      setRemark('');
      onSuccess();
    } catch (err: any) {
      setError(err.message ?? '分发失败');
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="dist-form" onSubmit={handleSubmit}>
      <div className="form-section">
        <h3 className="form-section-title">分发任务</h3>
        <div className="form-grid">
          <div className="form-field">
            <label>选择任务</label>
            <select value={selectedTaskId} onChange={(e) => setSelectedTaskId(e.target.value)}>
              <option value="">-- 选择任务 --</option>
              {myTasks.map((task) => (
                <option key={task.id} value={task.id}>
                  {task.title}
                </option>
              ))}
            </select>
          </div>
          <div className="form-field">
            <label>选择团队</label>
            <select value={selectedTeamId} onChange={(e) => handleTeamChange(e.target.value)}>
              <option value="">-- 选择团队 --</option>
              {teams.map((team) => (
                <option key={team.id} value={team.id}>
                  {team.name}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {teamMembers.length > 0 && (
        <div className="form-section">
          <div className="section-header-row">
            <h3 className="form-section-title">选择接收用户</h3>
            <button type="button" className="select-all-btn" onClick={selectAll}>
              {selectedUserIds.size === teamMembers.length ? '取消全选' : '全选'}
            </button>
          </div>
          <div className="user-checkbox-grid">
            {teamMembers.map((member) => (
              <label key={member.userId} className="user-checkbox">
                <input
                  type="checkbox"
                  checked={selectedUserIds.has(member.userId)}
                  onChange={() => toggleUser(member.userId)}
                />
                <span className="user-name">{member.displayName}</span>
                {member.online && <span className="online-dot" />}
                <span className="user-role">{member.role === 'team_admin' ? '管理员' : '成员'}</span>
              </label>
            ))}
          </div>
        </div>
      )}

      <div className="form-section">
        <div className="form-grid">
          <div className="form-field full-width">
            <label>备注（可选）</label>
            <textarea
              value={remark}
              onChange={(e) => setRemark(e.target.value)}
              placeholder="添加分发备注..."
              rows={2}
            />
          </div>
        </div>
      </div>

      {error && <div className="form-error">{error}</div>}
      {success && <div className="form-success">{success}</div>}

      <div className="form-actions">
        <button type="submit" className="primary-btn" disabled={loading}>
          {loading ? '分发中...' : `分发 (${selectedUserIds.size} 人)`}
        </button>
      </div>
    </form>
  );
}
