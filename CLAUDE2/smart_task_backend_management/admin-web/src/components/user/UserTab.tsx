import { useState } from 'react';
import type { Overview, User } from '../../types';
import { createUser, updateUser } from '../../api';

interface UserTabProps {
  overview: Overview;
  token: string;
  onRefresh: () => void;
}

const ROLE_LABELS: Record<string, { label: string; cls: string }> = {
  system_admin: { label: '系统管理员', cls: 'status-viewed' },
  team_admin: { label: '团队管理员', cls: 'status-in-progress' },
  member: { label: '成员', cls: 'status-completed' },
};

export default function UserTab({ overview, token, onRefresh }: UserTabProps) {
  const [showForm, setShowForm] = useState(false);
  const [nickname, setNickname] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('member');
  const [teamId, setTeamId] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  // Edit state
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [editNickname, setEditNickname] = useState('');
  const [editPhone, setEditPhone] = useState('');
  const [editEmail, setEditEmail] = useState('');
  const [editRole, setEditRole] = useState('');
  const [editPassword, setEditPassword] = useState('');
  const [editSubmitting, setEditSubmitting] = useState(false);
  const [editError, setEditError] = useState('');

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!nickname.trim()) { setError('请输入昵称'); return; }
    if (password.length < 6) { setError('密码至少6位'); return; }
    setSubmitting(true);
    setError('');
    try {
      await createUser(token, {
        nickname: nickname.trim(),
        phone: phone.trim() || undefined,
        email: email.trim() || undefined,
        password,
        role: role as 'member' | 'team_admin',
        teamId: teamId || undefined,
      });
      setNickname(''); setPhone(''); setEmail(''); setPassword('');
      setRole('member'); setTeamId('');
      setShowForm(false);
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '创建失败');
    } finally {
      setSubmitting(false);
    }
  }

  function openEdit(user: User) {
    setEditingUser(user);
    setEditNickname(user.nickname);
    setEditPhone(user.phone ?? '');
    setEditEmail(user.email ?? '');
    setEditRole(user.role === 'system_admin' ? 'team_admin' : user.role);
    setEditPassword('');
    setEditError('');
  }

  async function handleEditSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!editingUser) return;
    setEditSubmitting(true);
    setEditError('');
    try {
      const body: Record<string, string> = {
        nickname: editNickname.trim(),
        role: editRole,
      };
      if (editPhone.trim()) body.phone = editPhone.trim();
      if (editEmail.trim()) body.email = editEmail.trim();
      if (editPassword) body.password = editPassword;
      await updateUser(token, editingUser.id, body);
      setEditingUser(null);
      onRefresh();
    } catch (err: any) {
      setEditError(err.message ?? '更新失败');
    } finally {
      setEditSubmitting(false);
    }
  }

  async function handleResetPassword(user: User) {
    const defaultPwd = '123456';
    if (!confirm(`确认将 ${user.nickname} 的密码重置为 ${defaultPwd}？`)) return;
    try {
      await updateUser(token, user.id, { password: defaultPwd });
      alert(`${user.nickname} 的密码已重置为 ${defaultPwd}`);
    } catch (err: any) {
      alert(err.message ?? '重置失败');
    }
  }

  async function handleToggleStatus(user: User) {
    const newStatus = user.status === 'active' ? 'disabled' : 'active';
    const label = newStatus === 'disabled' ? '停用' : '启用';
    if (!confirm(`确认${label}用户 ${user.nickname}？`)) return;
    try {
      await updateUser(token, user.id, { status: newStatus });
      onRefresh();
    } catch (err: any) {
      alert(err.message ?? '操作失败');
    }
  }

  const getUserDevice = (userId: string) => {
    return overview.devices.find((d) => d.userId === userId);
  };

  return (
    <div className="tab-content">
      <div className="tab-header">
        <button
          type="button"
          className="primary-btn"
          onClick={() => setShowForm((prev) => !prev)}
        >
          {showForm ? '取消' : '新建用户'}
        </button>
      </div>

      {showForm && (
        <form className="panel dist-form" onSubmit={handleCreate}>
          <div className="form-section">
            <h3 className="form-section-title">创建用户</h3>
            <div className="form-grid">
              <div className="form-field">
                <label>昵称 *</label>
                <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="输入昵称" />
              </div>
              <div className="form-field">
                <label>密码 *</label>
                <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="至少6位" />
              </div>
              <div className="form-field">
                <label>手机号（可选）</label>
                <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="13800000000" />
              </div>
              <div className="form-field">
                <label>邮箱（可选）</label>
                <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="user@example.com" />
              </div>
              <div className="form-field">
                <label>角色</label>
                <select value={role} onChange={(e) => setRole(e.target.value)}>
                  <option value="member">成员</option>
                  <option value="team_admin">团队管理员</option>
                </select>
              </div>
              <div className="form-field">
                <label>加入团队（可选）</label>
                <select value={teamId} onChange={(e) => setTeamId(e.target.value)}>
                  <option value="">不加入团队</option>
                  {overview.teams.map((t) => (
                    <option key={t.id} value={t.id}>{t.name}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>
          {error && <div className="form-error">{error}</div>}
          <div className="form-actions">
            <button type="submit" className="primary-btn" disabled={submitting}>
              {submitting ? '创建中...' : '创建用户'}
            </button>
          </div>
        </form>
      )}

      {/* Edit dialog */}
      {editingUser && (
        <div className="panel">
          <div className="section-header-row">
            <h3 className="form-section-title">编辑用户：{editingUser.nickname}</h3>
            <button type="button" className="select-all-btn" onClick={() => setEditingUser(null)}>关闭</button>
          </div>
          <form onSubmit={handleEditSubmit}>
            <div className="form-grid">
              <div className="form-field">
                <label>昵称</label>
                <input value={editNickname} onChange={(e) => setEditNickname(e.target.value)} />
              </div>
              <div className="form-field">
                <label>手机号</label>
                <input value={editPhone} onChange={(e) => setEditPhone(e.target.value)} />
              </div>
              <div className="form-field">
                <label>邮箱</label>
                <input value={editEmail} onChange={(e) => setEditEmail(e.target.value)} />
              </div>
              <div className="form-field">
                <label>角色</label>
                <select value={editRole} onChange={(e) => setEditRole(e.target.value)}>
                  <option value="member">成员</option>
                  <option value="team_admin">团队管理员</option>
                </select>
              </div>
              <div className="form-field">
                <label>新密码（留空不修改）</label>
                <input type="password" value={editPassword} onChange={(e) => setEditPassword(e.target.value)} placeholder="输入新密码" />
              </div>
            </div>
            {editError && <div className="form-error">{editError}</div>}
            <div className="form-actions">
              <button type="submit" className="primary-btn" disabled={editSubmitting}>
                {editSubmitting ? '保存中...' : '保存'}
              </button>
            </div>
          </form>
        </div>
      )}

      <div className="panel">
        <h2>用户列表</h2>
        {overview.users.length === 0 ? (
          <div className="empty-state">暂无用户</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>昵称</th>
                <th>手机号</th>
                <th>邮箱</th>
                <th>角色</th>
                <th>状态</th>
                <th>设备</th>
                <th>注册时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {overview.users.map((user) => {
                const r = ROLE_LABELS[user.role] ?? { label: user.role, cls: '' };
                const device = getUserDevice(user.id);
                return (
                  <tr key={user.id}>
                    <td className="task-title-cell">{user.nickname}</td>
                    <td>{user.phone ?? '-'}</td>
                    <td>{user.email ?? '-'}</td>
                    <td><span className={`status-badge ${r.cls}`}>{r.label}</span></td>
                    <td>
                      <span className={`status-badge ${user.status === 'active' ? 'status-completed' : 'status-cancelled'}`}>
                        {user.status === 'active' ? '正常' : '停用'}
                      </span>
                    </td>
                    <td>
                      {device ? (
                        <span className="device-info">
                          <span className={`online-status ${device.onlineStatus === 'online' ? 'is-online' : ''}`}>
                            {device.onlineStatus === 'online' ? '在线' : '离线'}
                          </span>
                          <span className="detail-label">{device.platform}</span>
                        </span>
                      ) : (
                        <span className="detail-label">未绑定</span>
                      )}
                    </td>
                    <td>{new Date(user.createdAt).toLocaleDateString('zh-CN')}</td>
                    <td>
                      <div className="action-btns">
                        <button type="button" className="expand-btn" onClick={() => openEdit(user)}>
                          编辑
                        </button>
                        <button type="button" className="expand-btn" onClick={() => handleResetPassword(user)}>
                          重置密码
                        </button>
                        {user.role !== 'system_admin' && (
                          <button
                            type="button"
                            className={`expand-btn ${user.status === 'active' ? 'danger-btn' : ''}`}
                            onClick={() => handleToggleStatus(user)}
                          >
                            {user.status === 'active' ? '停用' : '启用'}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
