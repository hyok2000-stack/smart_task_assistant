export type TabKey = 'list' | 'distribution' | 'invite' | 'team' | 'user';

const TABS: { key: TabKey; label: string }[] = [
  { key: 'list', label: '任务列表' },
  { key: 'distribution', label: '任务分发' },
  { key: 'invite', label: '邀请码' },
  { key: 'team', label: '团队管理' },
  { key: 'user', label: '用户管理' },
];

interface TabBarProps {
  activeTab: TabKey;
  onTabChange: (tab: TabKey) => void;
}

export default function TabBar({ activeTab, onTabChange }: TabBarProps) {
  return (
    <nav className="tab-bar">
      {TABS.map((tab) => (
        <button
          key={tab.key}
          type="button"
          className={`tab-button ${activeTab === tab.key ? 'active' : ''}`}
          onClick={() => onTabChange(tab.key)}
        >
          {tab.label}
        </button>
      ))}
    </nav>
  );
}
