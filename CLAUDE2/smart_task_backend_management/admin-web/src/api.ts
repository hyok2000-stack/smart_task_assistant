import type { Overview, Task, TeamMemberInfo, TaskFormData, TaskQuery } from './types';

const API_BASE = import.meta.env.VITE_API_BASE ?? 'http://localhost:4100/api';
const APP_KEY = import.meta.env.VITE_APP_KEY ?? 'smart-task-app-2025';

function authHeaders(token: string): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}

export async function apiFetch(path: string, options: RequestInit, token: string) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: { ...authHeaders(token), ...options.headers },
  });
  const data = await readJson(response, `${API_BASE}${path}`);
  if (!response.ok) {
    const err = new Error(data.message ?? '请求失败');
    (err as any).code = data.code;
    throw err;
  }
  return data;
}

export async function login(account: string, password: string): Promise<{ token: string }> {
  const response = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-App-Key': APP_KEY },
    body: JSON.stringify({ account, password }),
  });
  const data = await readJson(response, `${API_BASE}/auth/login`);
  if (!response.ok) {
    const err = new Error(data.message ?? '登录失败');
    (err as any).code = data.code;
    throw err;
  }
  return data;
}

async function readJson(response: Response, url: string) {
  const contentType = response.headers.get('content-type') ?? '';
  const text = await response.text();

  if (!contentType.includes('application/json')) {
    const preview = text.replace(/\s+/g, ' ').slice(0, 120);
    throw new Error(
      `接口没有返回 JSON：${response.status} ${url}。` +
      `请确认后端服务已启动且 API 地址正确。返回内容：${preview}`,
    );
  }

  try {
    return text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`接口返回 JSON 解析失败：${response.status} ${url}`);
  }
}

export async function loadOverview(token: string): Promise<Overview> {
  return apiFetch('/admin/overview', {}, token);
}

export async function loadAdminTasks(token: string, query: TaskQuery) {
  const params = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => {
    if (value !== undefined && value !== '') params.set(key, String(value));
  });
  const suffix = params.toString() ? `?${params.toString()}` : '';
  return apiFetch(`/admin/tasks${suffix}`, {}, token) as Promise<{
    tasks: Task[];
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  }>;
}

export async function loadAdminDistributions(token: string, query?: { page?: number; pageSize?: number; status?: string; teamId?: string }) {
  const params = new URLSearchParams();
  if (query) {
    Object.entries(query).forEach(([key, value]) => {
      if (value !== undefined && value !== '') params.set(key, String(value));
    });
  }
  const suffix = params.toString() ? `?${params.toString()}` : '';
  return apiFetch(`/admin/distributions${suffix}`, {}, token) as Promise<{
    distributions: any[];
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  }>;
}

export async function loadAdminTaskDetail(token: string, taskId: string) {
  return apiFetch(`/admin/tasks/${taskId}`, {}, token) as Promise<{
    task: Task;
    comments: any[];
    distributions: any[];
    statusLogs: any[];
    syncLogs: any[];
  }>;
}

export async function pushTasks(token: string, tasks: Task[]): Promise<{ tasks: Task[] }> {
  return apiFetch('/tasks/sync/push', {
    method: 'POST',
    body: JSON.stringify({ tasks }),
  }, token);
}

export async function updateTask(
  token: string,
  taskId: string,
  body: Record<string, unknown>,
) {
  return apiFetch(`/admin/tasks/${taskId}`, {
    method: 'PATCH',
    body: JSON.stringify(body),
  }, token);
}

export async function adminAddComment(token: string, taskId: string, content: string, authorUserId?: string) {
  return apiFetch(`/admin/tasks/${taskId}/comments`, {
    method: 'POST',
    body: JSON.stringify({ content, authorUserId }),
  }, token);
}

export async function adminDeleteComment(token: string, commentId: string) {
  return apiFetch(`/admin/comments/${commentId}`, {
    method: 'DELETE',
  }, token);
}

export function taskToPushPayload(form: TaskFormData): Partial<Task> {
  return {
    id: form.id,
    title: form.title,
    content: form.content || undefined,
    status: form.status,
    priority: form.priority,
    startTime: form.startTime || undefined,
    dueTime: form.dueTime || undefined,
    assignee: form.assignee || undefined,
    assigneeUserId: (form as any).assigneeUserId || undefined,
    isRecurring: form.isRecurring || undefined,
    recurringRule: form.isRecurring ? form.recurringRule : undefined,
    tagIds: form.tagIds.length > 0 ? form.tagIds : undefined,
    reminderMinutes: form.reminderMinutes ?? undefined,
    reminderVoiceEnabled: form.reminderVoiceEnabled || undefined,
    reminderVoiceType: form.reminderVoiceEnabled ? form.reminderVoiceType : undefined,
    reminderVoiceStyle: form.reminderVoiceEnabled ? form.reminderVoiceStyle : undefined,
    reminderVoiceSpeed: form.reminderVoiceEnabled ? form.reminderVoiceSpeed : undefined,
    sourceType: 'local',
    version: 1,
  };
}

export async function getTeamMembers(token: string, teamId: string): Promise<{ members: TeamMemberInfo[] }> {
  return apiFetch(`/teams/${teamId}/members`, {}, token);
}

export async function createDistribution(
  token: string,
  body: { sourceTaskId: string; recipientUserId: string; teamId: string; remark?: string },
) {
  return apiFetch('/distributions', {
    method: 'POST',
    body: JSON.stringify(body),
  }, token);
}

export async function createInviteCode(
  token: string,
  body: { teamId: string; maxUses: number; expiresAt?: string },
) {
  return apiFetch('/invite-codes', {
    method: 'POST',
    body: JSON.stringify(body),
  }, token);
}

export async function disableInviteCode(token: string, id: string) {
  return apiFetch(`/invite-codes/${id}/disable`, {
    method: 'POST',
  }, token);
}

export async function createTeam(token: string, name: string) {
  return apiFetch('/teams', {
    method: 'POST',
    body: JSON.stringify({ name }),
  }, token);
}

export async function addTeamMember(token: string, teamId: string, userId: string, role: string = 'member') {
  return apiFetch(`/teams/${teamId}/members`, {
    method: 'POST',
    body: JSON.stringify({ userId, role }),
  }, token);
}

export async function removeTeamMember(token: string, teamId: string, userId: string) {
  return apiFetch(`/teams/${teamId}/members/${userId}`, {
    method: 'DELETE',
  }, token);
}

export async function createUser(
  token: string,
  body: { nickname: string; phone?: string; email?: string; password: string; role?: string; teamId?: string },
) {
  return apiFetch('/users', {
    method: 'POST',
    body: JSON.stringify(body),
  }, token);
}

export async function updateUser(
  token: string,
  userId: string,
  body: { nickname?: string; phone?: string; email?: string; role?: string; status?: string; password?: string },
) {
  return apiFetch(`/users/${userId}`, {
    method: 'PATCH',
    body: JSON.stringify(body),
  }, token);
}
