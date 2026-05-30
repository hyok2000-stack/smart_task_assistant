export type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'cancelled';
export type TaskPriority = 'low' | 'medium' | 'high';
export type TaskSourceType = 'local' | 'team_distribution';
export type DistributionStatus = 'sent' | 'received' | 'generated' | 'viewed' | 'in_progress' | 'completed' | 'cancelled' | 'failed';

export interface User {
  id: string;
  nickname: string;
  phone?: string;
  email?: string;
  role: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export interface Team {
  id: string;
  name: string;
  ownerUserId: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export interface TeamMember {
  id: string;
  teamId: string;
  userId: string;
  role: 'team_admin' | 'member';
  status: string;
  joinedAt: string;
  updatedAt: string;
}

export interface Task {
  id: string;
  ownerUserId: string;
  teamId?: string;
  title: string;
  content?: string;
  status: TaskStatus;
  priority: TaskPriority;
  startTime?: string;
  dueTime?: string;
  completedAt?: string;
  reminderTime?: string;
  assignee?: string;
  parentId?: string;
  isRecurring?: boolean;
  recurringRule?: string;
  tagIds?: string[];
  attachmentPaths?: string[];
  reminderMinutes?: number;
  reminderDismissed?: boolean;
  reminderVoiceEnabled?: boolean;
  reminderVoiceType?: string;
  reminderVoiceStyle?: string;
  reminderVoiceSpeed?: string;
  reminderCustomVoicePath?: string;
  sourceType: TaskSourceType;
  sourceTaskId?: string;
  sourceDistributionId?: string;
  version: number;
  sortOrder?: number;
  assigneeUserId?: string;
  deletedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface TaskDistribution {
  id: string;
  senderUserId: string;
  recipientUserId: string;
  sourceTaskId: string;
  recipientTaskId?: string;
  teamId: string;
  status: DistributionStatus;
  remark?: string;
  commentCount: number;
  lastCommentAt?: string;
  lastCommentSummary?: string;
  sourceTaskTitle?: string;
  recipientTaskTitle?: string;
  createdAt: string;
  updatedAt: string;
}

export interface TeamMemberInfo {
  userId: string;
  displayName: string;
  phoneMasked?: string;
  role: string;
  online: boolean;
}

export interface InviteCode {
  id: string;
  code: string;
  teamId: string;
  teamName?: string;
  createdByUserId: string;
  createdByName?: string;
  maxUses: number;
  usedCount: number;
  expiresAt?: string;
  status: 'active' | 'disabled' | 'expired';
  createdAt: string;
  updatedAt: string;
}

export interface Overview {
  stats: {
    users: number;
    teams: number;
    onlineDevices: number;
    tasks: number;
    pendingSync: number;
    distributions: number;
    failedDistributions: number;
    todayComments: number;
  };
  users: User[];
  teams: Team[];
  members: TeamMember[];
  devices: Array<{
    id: string;
    deviceName: string;
    platform: string;
    onlineStatus: string;
    lastHeartbeatAt?: string;
    userId?: string;
  }>;
  tasks: Task[];
  distributions: TaskDistribution[];
  comments: Array<{
    id: string;
    taskId: string;
    authorUserId: string;
    content: string;
    status: string;
    serverCreatedAt: string;
  }>;
  syncLogs: Array<{
    id: string;
    operationType: string;
    status: string;
    createdAt: string;
  }>;
  operationLogs: Array<{
    id: string;
    action: string;
    targetType: string;
    targetId?: string;
    createdAt: string;
  }>;
  inviteCodes: InviteCode[];
}

export interface TaskFormData {
  id: string;
  title: string;
  content: string;
  status: TaskStatus;
  priority: TaskPriority;
  startTime: string;
  dueTime: string;
  assignee: string;
  assigneeUserId?: string;
  isRecurring: boolean;
  recurringRule: string;
  tagIds: string[];
  reminderMinutes: number | null;
  reminderVoiceEnabled: boolean;
  reminderVoiceType: string;
  reminderVoiceStyle: string;
  reminderVoiceSpeed: string;
}

export interface Comment {
  id: string;
  taskId: string;
  content: string;
  authorUserId: string;
  authorName?: string;
  status: string;
  createdAt?: string;
  serverCreatedAt: string;
}

export interface TaskQuery {
  page?: number;
  pageSize?: number;
  status?: string;
  priority?: string;
  source?: string;
  ownerUserId?: string;
  teamId?: string;
  search?: string;
}
