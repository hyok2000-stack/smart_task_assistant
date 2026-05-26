import { Fragment, useState } from 'react';
import type { Overview, TeamMemberInfo } from '../../types';
import { addTeamMember, createTeam, getTeamMembers, removeTeamMember } from '../../api';

interface TeamTabProps {
  overview: Overview;
  token: string;
  onRefresh: () => void;
}

export default function TeamTab({ overview, token, onRefresh }: TeamTabProps) {
  const [newTeamName, setNewTeamName] = useState('');
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState('');
  const [expandedTeamId, setExpandedTeamId] = useState<string | null>(null);
  const [teamMembers, setTeamMembers] = useState<TeamMemberInfo[]>([]);
  const [showAddMember, setShowAddMember] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState('');
  const [addingMember, setAddingMember] = useState(false);

  const userName = (id: string) => overview.users.find((u) => u.id === id)?.nickname ?? id;

  async function handleCreateTeam(e: React.FormEvent) {
    e.preventDefault();
    if (!newTeamName.trim()) return;
    setCreating(true);
    setError('');
    try {
      await createTeam(token, newTeamName.trim());
      setNewTeamName('');
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '创建失败');
    } finally {
      setCreating(false);
    }
  }

  async function toggleTeamMembers(teamId: string) {
    if (expandedTeamId === teamId) {
      setExpandedTeamId(null);
      setTeamMembers([]);
      setShowAddMember(false);
      return;
    }
    setExpandedTeamId(teamId);
    setShowAddMember(false);
    try {
      const data = await getTeamMembers(token, teamId);
      setTeamMembers(data.members);
    } catch {
      setTeamMembers([]);
    }
  }

  async function handleAddMember(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedUserId || !expandedTeamId) return;
    setAddingMember(true);
    setError('');
    try {
      await addTeamMember(token, expandedTeamId, selectedUserId);
      setSelectedUserId('');
      setShowAddMember(false);
      const data = await getTeamMembers(token, expandedTeamId);
      setTeamMembers(data.members);
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '添加失败');
    } finally {
      setAddingMember(false);
    }
  }

  async function handleRemoveMember(userId: string) {
    if (!expandedTeamId) return;
    setError('');
    try {
      await removeTeamMember(token, expandedTeamId, userId);
      const data = await getTeamMembers(token, expandedTeamId);
      setTeamMembers(data.members);
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '移除失败');
    }
  }

  const getMemberCount = (teamId: string) =>
    overview.members.filter((m) => m.teamId === teamId && m.status === 'active').length;

  const nonMembers = expandedTeamId
    ? overview.users.filter(
        (u) =>
          u.status === 'active' &&
          !overview.members.some(
            (m) => m.teamId === expandedTeamId && m.userId === u.id && m.status === 'active',
          ),
      )
    : [];

  return (
    <div className="tab-content">
      <div className="panel">
        <h2>创建团队</h2>
        <form className="form-grid" onSubmit={handleCreateTeam} style={{ maxWidth: 500 }}>
          <div className="form-field">
            <label>团队名称</label>
            <input
              value={newTeamName}
              onChange={(e) => setNewTeamName(e.target.value)}
              placeholder="输入团队名称"
            />
          </div>
          <div className="form-field" style={{ alignSelf: 'end' }}>
            <button type="submit" className="primary-btn" disabled={creating}>
              {creating ? '创建中...' : '创建团队'}
            </button>
          </div>
        </form>
        {error && <div className="form-error">{error}</div>}
      </div>

      <div className="panel">
        <h2>团队列表</h2>
        {overview.teams.length === 0 ? (
          <div className="empty-state">暂无团队</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>团队名称</th>
                <th>创建者</th>
                <th>成员数</th>
                <th>状态</th>
                <th>创建时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {overview.teams.map((team) => (
                <Fragment key={team.id}>
                  <tr>
                    <td className="task-title-cell">{team.name}</td>
                    <td>{userName(team.ownerUserId)}</td>
                    <td>{getMemberCount(team.id)} 人</td>
                    <td>
                      <span className={`status-badge ${team.status === 'active' ? 'status-completed' : 'status-cancelled'}`}>
                        {team.status === 'active' ? '活跃' : team.status}
                      </span>
                    </td>
                    <td>{new Date(team.createdAt).toLocaleDateString('zh-CN')}</td>
                    <td>
                      <button
                        type="button"
                        className="expand-btn"
                        onClick={() => toggleTeamMembers(team.id)}
                      >
                        {expandedTeamId === team.id ? '收起' : '管理成员'}
                      </button>
                    </td>
                  </tr>
                  {expandedTeamId === team.id && (
                    <tr>
                      <td colSpan={6} className="task-expanded-cell">
                        <div className="task-expanded">
                          <div className="section-header-row">
                            <h3 className="form-section-title">团队成员 ({teamMembers.length} 人)</h3>
                            <button
                              type="button"
                              className="select-all-btn"
                              onClick={() => setShowAddMember((prev) => !prev)}
                            >
                              {showAddMember ? '取消' : '添加成员'}
                            </button>
                          </div>

                          {showAddMember && (
                            <form className="form-grid member-add-form" onSubmit={handleAddMember}>
                              <div className="form-field">
                                <label>选择用户</label>
                                <select value={selectedUserId} onChange={(e) => setSelectedUserId(e.target.value)}>
                                  <option value="">-- 选择用户 --</option>
                                  {nonMembers.map((u) => (
                                    <option key={u.id} value={u.id}>
                                      {u.nickname}{u.phone ? ` (${u.phone})` : ''}{u.email ? ` (${u.email})` : ''}
                                    </option>
                                  ))}
                                </select>
                              </div>
                              <div className="form-field" style={{ alignSelf: 'end' }}>
                                <button type="submit" className="primary-btn" disabled={addingMember || !selectedUserId}>
                                  {addingMember ? '添加中...' : '添加'}
                                </button>
                              </div>
                            </form>
                          )}

                          <div className="member-list">
                            {teamMembers.length === 0 ? (
                              <span className="detail-label">加载中...</span>
                            ) : teamMembers.length === 0 ? (
                              <span className="detail-label">暂无成员</span>
                            ) : (
                              teamMembers.map((m) => (
                                <div key={m.userId} className="member-item">
                                  {m.online && <span className="online-dot" />}
                                  <span className="user-name">{m.displayName}</span>
                                  <span className="user-role">{m.role === 'team_admin' ? '管理员' : '成员'}</span>
                                  {m.phoneMasked && <span className="detail-label">{m.phoneMasked}</span>}
                                  <button
                                    type="button"
                                    className="remove-member-btn"
                                    onClick={() => handleRemoveMember(m.userId)}
                                  >
                                    移除
                                  </button>
                                </div>
                              ))
                            )}
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
