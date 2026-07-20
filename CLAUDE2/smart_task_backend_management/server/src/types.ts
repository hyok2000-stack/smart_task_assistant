export type UserRole = "system_admin" | "team_admin" | "member";
export type EntityStatus = "active" | "disabled" | "deleted";
export type TeamMemberStatus = "pending" | "active" | "disabled" | "left";
export type DeviceOnlineStatus = "online" | "offline";
export type TaskStatus = "pending" | "in_progress" | "completed" | "cancelled";
export type TaskPriority = "low" | "medium" | "high";
export type TaskSourceType = "local" | "team_distribution";
export type DistributionStatus =
  | "sent"
  | "received"
  | "generated"
  | "viewed"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "failed";
export type SyncStatus = "success" | "failed" | "pending";
export type OperationType =
  | "create"
  | "update"
  | "status_update"
  | "complete"
  | "delete"
  | "comment_create"
  | "comment_delete";

export interface User {
  id: string;
  nickname: string;
  phone?: string;
  email?: string;
  passwordHash: string;
  avatar?: string;
  role: UserRole;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface Team {
  id: string;
  name: string;
  ownerUserId: string;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface TeamMember {
  id: string;
  teamId: string;
  userId: string;
  role: "team_admin" | "member";
  status: TeamMemberStatus;
  joinedAt: string;
  updatedAt: string;
}

export interface Device {
  id: string;
  userId: string;
  deviceName: string;
  platform: string;
  deviceToken?: string;
  onlineStatus: DeviceOnlineStatus;
  lastHeartbeatAt?: string;
  lastSyncAt?: string;
  createdAt: string;
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
  archivedAt?: string | null;
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
  senderLastReadCommentAt?: string;
  recipientLastReadCommentAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface TaskComment {
  id: string;
  clientCommentId: string;
  taskId: string;
  teamId?: string;
  authorUserId: string;
  content: string;
  sourceDeviceId?: string;
  operationId: string;
  status: "active" | "deleted";
  serverCreatedAt: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
  readByUserIds?: string[]; // 已读该评论的用户ID（已读回执）
}

export interface SyncLog {
  id: string;
  userId: string;
  deviceId?: string;
  taskId?: string;
  operationType: OperationType;
  status: SyncStatus;
  errorMessage?: string;
  createdAt: string;
}

export interface OperationLog {
  id: string;
  operatorUserId?: string;
  action: string;
  targetType: string;
  targetId?: string | string[];
  detail?: unknown;
  createdAt: string;
}

export interface InviteCode {
  id: string;
  code: string;
  teamId: string;
  createdByUserId: string;
  maxUses: number;
  usedCount: number;
  expiresAt?: string;
  status: "active" | "disabled" | "expired";
  createdAt: string;
  updatedAt: string;
}

export interface TaskStatusChangeLog {
  id: string;
  taskId: string;
  distributionId?: string;
  changedByUserId: string;
  previousStatus: string;
  newStatus: string;
  source: "sender" | "recipient" | "admin";
  createdAt: string;
}

export interface DatabaseShape {
  users: User[];
  teams: Team[];
  teamMembers: TeamMember[];
  devices: Device[];
  tasks: Task[];
  distributions: TaskDistribution[];
  comments: TaskComment[];
  syncLogs: SyncLog[];
  operationLogs: OperationLog[];
  inviteCodes: InviteCode[];
  statusChangeLogs: TaskStatusChangeLog[];
  notifications: AppNotification[];
}

export interface AppNotification {
  id: string;
  userId: string;
  type: "mention" | "assignment" | "distribution" | "status_change";
  taskId: string;
  commentId?: string;
  fromUserId: string;
  title: string;
  body: string;
  read: boolean;
  createdAt: string;
}
