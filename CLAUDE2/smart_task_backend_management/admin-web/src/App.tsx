import { useEffect, useMemo, useState } from 'react';
import './App.css';
import type { Overview } from './types';
import { login, loadOverview } from './api';
import LoginPanel from './components/LoginPanel';
import MetricGrid from './components/MetricGrid';
import TabBar from './components/TabBar';
import type { TabKey } from './components/TabBar';
import TaskListTab from './components/task-list/TaskListTab';
import TaskDistributionTab from './components/task-distribution/TaskDistributionTab';
import InviteCodeTab from './components/invite-code/InviteCodeTab';
import TeamTab from './components/team/TeamTab';
import UserTab from './components/user/UserTab';

function isTokenExpired(token: string): boolean {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.exp * 1000 < Date.now();
  } catch {
    return true;
  }
}

function App() {
  const [account, setAccount] = useState('');
  const [password, setPassword] = useState('');
  const [token, setToken] = useState(() => {
    const stored = localStorage.getItem('smart-task-token');
    return stored && !isTokenExpired(stored) ? stored : '';
  });
  const [overview, setOverview] = useState<Overview | null>(null);
  const [message, setMessage] = useState('');
  const [activeTab, setActiveTab] = useState<TabKey>('list');
  const [drillFilter, setDrillFilter] = useState<{ status?: string; priority?: string; source?: string } | undefined>(undefined);

  async function handleLogin() {
    setMessage('登录中...');
    try {
      const data = await login(account, password);
      localStorage.setItem('smart-task-token', data.token);
      setToken(data.token);
      setMessage('登录成功');
    } catch (err: any) {
      setMessage(err.message ?? '登录失败');
    }
  }

  async function handleRefresh() {
    if (!token) return;
    try {
      const data = await loadOverview(token);
      setOverview(data);
    } catch (err: any) {
      const status = err?.status;
      if (status === 401 || status === 403) {
        localStorage.removeItem('smart-task-token');
        setToken('');
        setOverview(null);
        setMessage('登录已过期，请重新登录');
      } else {
        setMessage(err.message ?? '读取失败');
      }
    }
  }

  useEffect(() => {
    if (token) handleRefresh();
  }, [token]);

  const adminUserId = useMemo(() => {
    if (!token) return '';
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      return payload.sub ?? '';
    } catch {
      return '';
    }
  }, [token]);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Smart Task Backend</p>
          <h1>任务后台管理系统</h1>
        </div>
        <div className="topbar-actions">
          {token && (
            <button className="ghost-button" type="button" onClick={handleRefresh}>
              刷新
            </button>
          )}
          {token && (
            <button
              className="ghost-button"
              type="button"
              onClick={() => {
                localStorage.removeItem('smart-task-token');
                setToken('');
                setOverview(null);
                setMessage('');
              }}
            >
              退出
            </button>
          )}
        </div>
      </header>

      {!token && (
        <LoginPanel
          account={account}
          password={password}
          message={message}
          onAccountChange={setAccount}
          onPasswordChange={setPassword}
          onLogin={handleLogin}
        />
      )}

      {token && !overview && (
        <div style={{ textAlign: 'center', padding: '48px 16px', color: '#666' }}>
          <p>{message || '加载中...'}</p>
          {message && (
            <button className="ghost-button" type="button" onClick={handleRefresh} style={{ marginTop: 12 }}>
              重试
            </button>
          )}
        </div>
      )}

      {overview && token && (
        <>
          <MetricGrid stats={overview.stats} onMetricClick={(key) => {
            if (key === 'tasks') {
              setDrillFilter(undefined);
              setActiveTab('list');
            } else if (key === 'distributions') {
              setActiveTab('distribution');
            } else if (key === 'users') {
              setActiveTab('user');
            } else if (key === 'teams') {
              setActiveTab('team');
            }
          }} />

          <TabBar activeTab={activeTab} onTabChange={(tab) => { setActiveTab(tab); setDrillFilter(undefined); }} />

          {activeTab === 'list' && (
            <TaskListTab overview={overview} token={token} onRefresh={handleRefresh} initialFilter={drillFilter} />
          )}

          {activeTab === 'distribution' && (
            <TaskDistributionTab
              overview={overview}
              adminUserId={adminUserId}
              token={token}
              onRefresh={handleRefresh}
            />
          )}

          {activeTab === 'invite' && (
            <InviteCodeTab overview={overview} token={token} onRefresh={handleRefresh} />
          )}

          {activeTab === 'team' && (
            <TeamTab overview={overview} token={token} onRefresh={handleRefresh} />
          )}

          {activeTab === 'user' && (
            <UserTab overview={overview} token={token} onRefresh={handleRefresh} />
          )}
        </>
      )}
    </main>
  );
}

export default App;
