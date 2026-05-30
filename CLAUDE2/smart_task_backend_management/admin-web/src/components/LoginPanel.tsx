interface LoginPanelProps {
  account: string;
  password: string;
  message: string;
  onAccountChange: (value: string) => void;
  onPasswordChange: (value: string) => void;
  onLogin: () => void;
}

export default function LoginPanel({ account, password, message, onAccountChange, onPasswordChange, onLogin }: LoginPanelProps) {
  return (
    <section className="login-panel">
      <form onSubmit={(e) => { e.preventDefault(); onLogin(); }}>
        <label>
          账号
          <input value={account} onChange={(e) => onAccountChange(e.target.value)} />
        </label>
        <label>
          密码
          <input type="password" value={password} onChange={(e) => onPasswordChange(e.target.value)} />
        </label>
        <button type="submit">
          登录后台
        </button>
      </form>
      <span>{message}</span>
    </section>
  );
}
