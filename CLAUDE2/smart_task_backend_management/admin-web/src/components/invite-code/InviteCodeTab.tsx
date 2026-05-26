import { useState } from 'react';
import type { Overview, InviteCode } from '../../types';
import { createInviteCode, disableInviteCode } from '../../api';

interface InviteCodeTabProps {
  overview: Overview;
  token: string;
  onRefresh: () => void;
}

const STATUS_LABELS: Record<string, { label: string; cls: string }> = {
  active: { label: '有效', cls: 'status-completed' },
  disabled: { label: '已禁用', cls: 'status-cancelled' },
  expired: { label: '已过期', cls: 'status-pending' },
};

export default function InviteCodeTab({ overview, token, onRefresh }: InviteCodeTabProps) {
  const [showForm, setShowForm] = useState(false);
  const [teamId, setTeamId] = useState('');
  const [maxUses, setMaxUses] = useState(-1);
  const [expiresAt, setExpiresAt] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [error, setError] = useState('');

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!teamId) { setError('请选择团队'); return; }
    setSubmitting(true);
    setError('');
    try {
      await createInviteCode(token, {
        teamId,
        maxUses,
        expiresAt: expiresAt || undefined,
      });
      setShowForm(false);
      setTeamId('');
      setMaxUses(-1);
      setExpiresAt('');
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '创建失败');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDisable(code: InviteCode) {
    try {
      await disableInviteCode(token, code.id);
      onRefresh();
    } catch (err: any) {
      setError(err.message ?? '操作失败');
    }
  }

  function copyCode(code: InviteCode) {
    navigator.clipboard.writeText(code.code);
    setCopiedId(code.id);
    setTimeout(() => setCopiedId(null), 1500);
  }

  const codes = overview.inviteCodes ?? [];

  return (
    <div className="tab-content">
      <div className="tab-header">
        <button
          type="button"
          className="primary-btn"
          onClick={() => setShowForm((prev) => !prev)}
        >
          {showForm ? '取消' : '生成邀请码'}
        </button>
      </div>

      {showForm && (
        <form className="panel dist-form" onSubmit={handleCreate}>
          <div className="form-section">
            <h3 className="form-section-title">生成邀请码</h3>
            <div className="form-grid">
              <div className="form-field">
                <label>关联团队</label>
                <select value={teamId} onChange={(e) => setTeamId(e.target.value)}>
                  <option value="">-- 选择团队 --</option>
                  {overview.teams.map((team) => (
                    <option key={team.id} value={team.id}>{team.name}</option>
                  ))}
                </select>
              </div>
              <div className="form-field">
                <label>最大使用次数</label>
                <select value={maxUses} onChange={(e) => setMaxUses(Number(e.target.value))}>
                  <option value={-1}>不限</option>
                  <option value={1}>1 次</option>
                  <option value={5}>5 次</option>
                  <option value={10}>10 次</option>
                  <option value={50}>50 次</option>
                </select>
              </div>
              <div className="form-field">
                <label>过期时间（可选）</label>
                <input
                  type="datetime-local"
                  value={expiresAt}
                  onChange={(e) => setExpiresAt(e.target.value)}
                />
              </div>
            </div>
          </div>
          {error && <div className="form-error">{error}</div>}
          <div className="form-actions">
            <button type="submit" className="primary-btn" disabled={submitting}>
              {submitting ? '生成中...' : '生成'}
            </button>
          </div>
        </form>
      )}

      <div className="panel">
        {codes.length === 0 ? (
          <div className="empty-state">暂无邀请码</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>邀请码</th>
                <th>关联团队</th>
                <th>使用次数</th>
                <th>过期时间</th>
                <th>状态</th>
                <th>创建时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {codes.map((code) => {
                const status = STATUS_LABELS[code.status] ?? { label: code.status, cls: '' };
                return (
                  <tr key={code.id}>
                    <td>
                      <code className="invite-code-text">{code.code}</code>
                    </td>
                    <td>{code.teamName ?? overview.teams.find((t) => t.id === code.teamId)?.name ?? '-'}</td>
                    <td>{code.usedCount}{code.maxUses === -1 ? ' / 不限' : ` / ${code.maxUses}`}</td>
                    <td>{code.expiresAt ? new Date(code.expiresAt).toLocaleString('zh-CN') : '永不过期'}</td>
                    <td>
                      <span className={`status-badge ${status.cls}`}>{status.label}</span>
                    </td>
                    <td>{new Date(code.createdAt).toLocaleString('zh-CN')}</td>
                    <td>
                      <div className="action-btns">
                        <button
                          type="button"
                          className="expand-btn"
                          onClick={() => copyCode(code)}
                        >
                          {copiedId === code.id ? '已复制' : '复制'}
                        </button>
                        {code.status === 'active' && (
                          <button
                            type="button"
                            className="expand-btn danger-btn"
                            onClick={() => handleDisable(code)}
                          >
                            禁用
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
