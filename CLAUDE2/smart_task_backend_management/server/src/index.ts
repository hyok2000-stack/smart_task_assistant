import bcrypt from "bcryptjs";
import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import jwt, { type SignOptions } from "jsonwebtoken";
import morgan from "morgan";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { mutateDb, now, publicUser, readDb } from "./db";
import type { Task, TaskComment, TaskDistribution, User } from "./types";

// === 错误码定义 ===
const ErrorCode = {
  AUTH_REQUIRED: "AUTH_REQUIRED",
  AUTH_EXPIRED: "AUTH_EXPIRED",
  AUTH_INVALID_CREDENTIALS: "AUTH_INVALID_CREDENTIALS",
  FORBIDDEN: "FORBIDDEN",
  INVALID_APP_KEY: "INVALID_APP_KEY",
  NOT_FOUND: "NOT_FOUND",
  VALIDATION_ERROR: "VALIDATION_ERROR",
  CONFLICT: "CONFLICT",
  INVITE_CODE_INVALID: "INVITE_CODE_INVALID",
  INVITE_CODE_EXPIRED: "INVITE_CODE_EXPIRED",
  INVITE_CODE_EXHAUSTED: "INVITE_CODE_EXHAUSTED",
  SERVER_ERROR: "SERVER_ERROR",
} as const;

class AppError extends Error {
  constructor(public code: string, message: string, public details?: unknown) {
    super(message);
  }
}

function sendError(res: Response, status: number, code: string, message: string, details?: unknown) {
  return res.status(status).json({ code, message, ...(details ? { details } : {}) });
}

const app = express();
const port = Number(process.env.PORT ?? 4100);
const jwtSecret = process.env.JWT_SECRET ?? "dev-smart-task-secret";
const APP_KEY = process.env.APP_KEY ?? "smart-task-app-2025";
const tokenExpiresIn = (process.env.JWT_EXPIRES_IN ?? "7d") as SignOptions["expiresIn"];
const deviceOnlineTimeoutMs = Number(process.env.DEVICE_ONLINE_TIMEOUT_MS ?? 5 * 60_000);

if (process.env.NODE_ENV === "production") {
  if (!process.env.JWT_SECRET) throw new Error("生产环境必须配置 JWT_SECRET");
  if (!process.env.APP_KEY) throw new Error("生产环境必须配置 APP_KEY");
}

app.use(cors());
app.use(express.json({ limit: "2mb" }));
app.use(morgan("dev"));

interface AuthedRequest extends Request {
  user?: User;
}

function signToken(user: User) {
  return jwt.sign({ sub: user.id }, jwtSecret, { expiresIn: tokenExpiresIn });
}

function auth(req: AuthedRequest, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    return sendError(res, 401, ErrorCode.AUTH_REQUIRED, "请先登录");
  }

  try {
    const payload = jwt.verify(header.slice(7), jwtSecret) as { sub: string };
    const user = readDb().users.find((item) => item.id === payload.sub && item.status === "active");
    if (!user) return sendError(res, 401, ErrorCode.AUTH_EXPIRED, "账号不存在或已停用");
    req.user = user;
    next();
  } catch {
    return sendError(res, 401, ErrorCode.AUTH_EXPIRED, "登录已失效");
  }
}

function logOperation(action: string, operatorUserId?: string, targetType = "system", targetId?: string | string[], detail?: unknown) {
  mutateDb((db) => {
    db.operationLogs.unshift({
      id: randomUUID(),
      operatorUserId,
      action,
      targetType,
      targetId,
      detail,
      createdAt: now(),
    });
  });
}

function requireTeamMember(userId: string, teamId: string) {
  return readDb().teamMembers.some(
    (member) => member.userId === userId && member.teamId === teamId && member.status === "active",
  );
}

function canSeeTask(user: User, task: Task) {
  if (task.ownerUserId === user.id) return true;
  if (user.role === "system_admin") return true;
  if (user.role === "team_admin" && task.teamId && requireTeamMember(user.id, task.teamId)) return true;
  // Distribution: sender/recipient can see each other's related tasks
  const db = readDb();
  const dist = db.distributions.find(
    (d) => d.sourceTaskId === task.id || d.recipientTaskId === task.id,
  );
  if (dist && (dist.senderUserId === user.id || dist.recipientUserId === user.id)) return true;
  return false;
}

function requireAppKey(req: Request, res: Response, next: NextFunction) {
  const key = req.headers["x-app-key"];
  if (key !== APP_KEY) {
    return sendError(res, 403, ErrorCode.INVALID_APP_KEY, "无效的客户端标识");
  }
  next();
}

function generateInviteCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "TEAM-";
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

const STATUS_ORDER: Record<string, number> = { pending: 0, in_progress: 1, completed: 2, cancelled: 3 };

function refreshDevicePresence() {
  const cutoff = Date.now() - deviceOnlineTimeoutMs;
  mutateDb((db) => {
    for (const device of db.devices) {
      if (!device.lastHeartbeatAt) continue;
      if (device.onlineStatus === "online" && new Date(device.lastHeartbeatAt).getTime() < cutoff) {
        device.onlineStatus = "offline";
        device.updatedAt = now();
      }
    }
  });
}

function parsePageQuery(req: Request) {
  const page = Math.max(1, Number(req.query.page ?? 1) || 1);
  const pageSizeRaw = Number(req.query.pageSize ?? 20) || 20;
  const pageSize = Math.min(100, Math.max(1, pageSizeRaw));
  return { page, pageSize };
}

function taskMatchesAdminQuery(task: Task, req: Request) {
  if (task.deletedAt) return false;

  const status = typeof req.query.status === "string" ? req.query.status : "";
  const priority = typeof req.query.priority === "string" ? req.query.priority : "";
  const source = typeof req.query.source === "string" ? req.query.source : "";
  const ownerUserId = typeof req.query.ownerUserId === "string" ? req.query.ownerUserId : "";
  const teamId = typeof req.query.teamId === "string" ? req.query.teamId : "";
  const search = typeof req.query.search === "string" ? req.query.search.trim().toLowerCase() : "";

  if (status && task.status !== status) return false;
  if (priority && task.priority !== priority) return false;
  if (source && task.sourceType !== source) return false;
  if (ownerUserId && task.ownerUserId !== ownerUserId) return false;
  if (teamId && task.teamId !== teamId) return false;
  if (search) {
    const haystack = `${task.title} ${task.content ?? ""} ${task.assignee ?? ""}`.toLowerCase();
    if (!haystack.includes(search)) return false;
  }

  return true;
}

function recordStatusChange(
  db: ReturnType<typeof readDb>,
  taskId: string,
  opts: { previousStatus: string; newStatus: string; changedByUserId: string; distributionId?: string; source: "sender" | "recipient" | "admin" },
) {
  db.statusChangeLogs.unshift({
    id: randomUUID(),
    taskId,
    distributionId: opts.distributionId,
    changedByUserId: opts.changedByUserId,
    previousStatus: opts.previousStatus,
    newStatus: opts.newStatus,
    source: opts.source,
    createdAt: now(),
  });
}

function propagateSenderStatusToRecipient(db: ReturnType<typeof readDb>, sourceTaskId: string, newStatus: string, senderUserId: string) {
  const distributions = db.distributions.filter((d) => d.sourceTaskId === sourceTaskId);
  for (const dist of distributions) {
    const recipientTask = dist.recipientTaskId ? db.tasks.find((t) => t.id === dist.recipientTaskId) : undefined;
    if (!recipientTask || recipientTask.status === newStatus) continue;
    // Protect recipient's completed/cancelled status from being overwritten
    if (recipientTask.status === "completed" || recipientTask.status === "cancelled") continue;
    const shouldPropagate = (STATUS_ORDER[newStatus] ?? 0) > (STATUS_ORDER[recipientTask.status] ?? 0);
    if (!shouldPropagate) continue;
    const prev = recipientTask.status;
    recipientTask.status = newStatus as any;
    if (newStatus === "completed") recipientTask.completedAt = now();
    else recipientTask.completedAt = undefined;
    recipientTask.version++;
    recipientTask.updatedAt = now();
    recordStatusChange(db, recipientTask.id, {
      previousStatus: prev,
      newStatus,
      changedByUserId: senderUserId,
      distributionId: dist.id,
      source: "sender",
    });
  }
}

function updateDistributionStatusOnTaskChange(db: ReturnType<typeof readDb>, taskId: string, newStatus: string) {
  const distribution = db.distributions.find((d) => d.recipientTaskId === taskId);
  if (!distribution) return;
  if (distribution.status === "completed" || distribution.status === "cancelled" || distribution.status === "failed") return;

  if (newStatus === "completed") {
    distribution.status = "completed";
  } else if (newStatus === "cancelled") {
    distribution.status = "cancelled";
  } else if (newStatus === "in_progress" && (distribution.status === "generated" || distribution.status === "sent" || distribution.status === "received")) {
    distribution.status = "in_progress";
  }
  distribution.updatedAt = now();

  // Propagate status back to source task
  const sourceTask = db.tasks.find((t) => t.id === distribution.sourceTaskId);
  if (sourceTask && sourceTask.status !== newStatus) {
    // Protect sender's completed/cancelled status from being overwritten
    const shouldPropagate =
      sourceTask.status !== "completed" &&
      sourceTask.status !== "cancelled" &&
      (STATUS_ORDER[newStatus] ?? 0) > (STATUS_ORDER[sourceTask.status] ?? 0);
    if (shouldPropagate) {
      const prev = sourceTask.status;
      sourceTask.status = newStatus as any;
      if (newStatus === "completed") sourceTask.completedAt = now();
      else sourceTask.completedAt = undefined;
      sourceTask.version++;
      sourceTask.updatedAt = now();
      recordStatusChange(db, sourceTask.id, {
        previousStatus: prev,
        newStatus,
        changedByUserId: distribution.recipientUserId,
        distributionId: distribution.id,
        source: "recipient",
      });
    }
  }
}

function updateDistributionCommentSummary(db: ReturnType<typeof readDb>, taskId: string) {
  const related = db.distributions.find((item) => item.recipientTaskId === taskId);
  if (!related) return;

  const activeComments = db.comments
    .filter((comment) => comment.taskId === taskId && comment.status === "active")
    .sort((a, b) => a.serverCreatedAt.localeCompare(b.serverCreatedAt));
  const last = activeComments.at(-1);
  related.commentCount = activeComments.length;
  related.lastCommentAt = last?.serverCreatedAt;
  related.lastCommentSummary = last ? last.content.slice(0, 80) : undefined;
  related.updatedAt = now();
}

function enrichDistribution(db: ReturnType<typeof readDb>, distribution: TaskDistribution, userId?: string) {
  let unreadCommentCount = 0;
  if (userId && distribution.commentCount > 0 && distribution.lastCommentAt) {
    const isSender = userId === distribution.senderUserId;
    const lastRead = isSender ? distribution.senderLastReadCommentAt : distribution.recipientLastReadCommentAt;
    if (!lastRead || distribution.lastCommentAt > lastRead) {
      unreadCommentCount = distribution.commentCount;
    }
  }
  return {
    ...distribution,
    sourceTaskTitle: db.tasks.find((task) => task.id === distribution.sourceTaskId)?.title,
    recipientTaskTitle: distribution.recipientTaskId
      ? db.tasks.find((task) => task.id === distribution.recipientTaskId)?.title
      : undefined,
    senderName: db.users.find((u) => u.id === distribution.senderUserId)?.nickname ?? "未知",
    recipientName: db.users.find((u) => u.id === distribution.recipientUserId)?.nickname ?? "未知",
    unreadCommentCount,
  };
}

app.get("/api/health", (_req, res) => {
  refreshDevicePresence();
  res.json({ ok: true, time: now(), deviceOnlineTimeoutMs });
});

app.get("/", (_req, res) => {
  res.type("html").send(`<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>智能任务后台服务</title>
    <style>
      body {
        margin: 0;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #f5f7fb;
        color: #172033;
      }
      main {
        max-width: 720px;
        margin: 72px auto;
        padding: 0 24px;
      }
      section {
        background: #fff;
        border: 1px solid #dbe3ef;
        border-radius: 8px;
        padding: 28px;
      }
      h1 {
        margin: 0 0 10px;
        font-size: 28px;
      }
      p {
        color: #475569;
        line-height: 1.7;
      }
      a {
        display: inline-flex;
        margin: 8px 12px 0 0;
        padding: 10px 14px;
        border-radius: 6px;
        color: #fff;
        background: #2563eb;
        text-decoration: none;
        font-weight: 600;
      }
      a.secondary {
        color: #1e293b;
        background: #e2e8f0;
      }
      code {
        background: #eef2f7;
        padding: 2px 6px;
        border-radius: 4px;
      }
    </style>
  </head>
  <body>
    <main>
      <section>
        <h1>智能任务后台服务已运行</h1>
        <p>这里是 API 服务入口，不是后台管理页面。后台管理页面由前端开发服务提供。</p>
        <p>如果要打开管理页面，请访问 <code>http://127.0.0.1:5173</code>。</p>
        <a href="http://127.0.0.1:5173">打开后台管理页面</a>
        <a class="secondary" href="/api/health">查看接口健康状态</a>
      </section>
    </main>
  </body>
</html>`);
});

app.post("/api/auth/register", requireAppKey, (req, res) => {
  const body = z
    .object({
      nickname: z.string().min(1),
      email: z.string().email().optional(),
      phone: z.string().min(6).optional(),
      password: z.string().min(6),
      inviteCode: z.string().min(1),
    })
    .parse(req.body);

  if (!body.email && !body.phone) throw new AppError(ErrorCode.VALIDATION_ERROR, "邮箱和手机号至少填写一项");

  // Pre-validate invite code and persist expired status if needed
  const inviteCheck = readDb().inviteCodes.find((item) => item.code === body.inviteCode);
  if (!inviteCheck) throw new AppError(ErrorCode.INVITE_CODE_INVALID, "邀请码不存在");
  if (inviteCheck.status !== "active") throw new AppError(ErrorCode.INVITE_CODE_INVALID, "邀请码已失效");
  if (inviteCheck.expiresAt && new Date(inviteCheck.expiresAt) < new Date()) {
    mutateDb((db) => {
      const inv = db.inviteCodes.find((i) => i.id === inviteCheck.id);
      if (inv) { inv.status = "expired"; inv.updatedAt = now(); }
    });
    throw new AppError(ErrorCode.INVITE_CODE_EXPIRED, "邀请码已过期");
  }
  if (inviteCheck.maxUses !== -1 && inviteCheck.usedCount >= inviteCheck.maxUses) throw new AppError(ErrorCode.INVITE_CODE_EXHAUSTED, "邀请码已用完");

  const user = mutateDb((db) => {
    const exists = db.users.some((item) =>
      (body.email && item.email === body.email) || (body.phone && item.phone === body.phone),
    );
    if (exists) throw new AppError(ErrorCode.CONFLICT, "账号已存在");

    const invite = db.inviteCodes.find((item) => item.code === body.inviteCode);
    if (!invite || invite.status !== "active") throw new AppError(ErrorCode.INVITE_CODE_INVALID, "邀请码无效");
    if (invite.maxUses !== -1 && invite.usedCount >= invite.maxUses) throw new AppError(ErrorCode.INVITE_CODE_EXHAUSTED, "邀请码已用完");

    const team = db.teams.find((t) => t.id === invite.teamId && t.status === "active");
    if (!team) throw new AppError(ErrorCode.NOT_FOUND, "关联团队不存在");

    const createdAt = now();
    const nextUser: User = {
      id: randomUUID(),
      nickname: body.nickname,
      email: body.email,
      phone: body.phone,
      passwordHash: bcrypt.hashSync(body.password, 10),
      role: "member",
      status: "active",
      createdAt,
      updatedAt: createdAt,
    };
    db.users.push(nextUser);

    db.teamMembers.push({
      id: randomUUID(),
      teamId: team.id,
      userId: nextUser.id,
      role: "member",
      status: "active",
      joinedAt: createdAt,
      updatedAt: createdAt,
    });

    invite.usedCount++;
    invite.updatedAt = createdAt;

    return nextUser;
  });

  logOperation("user.register", user.id, "user", user.id);
  res.json({ token: signToken(user), user: publicUser(user) });
});

app.post("/api/users", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    nickname: z.string().min(1),
    phone: z.string().min(6).optional(),
    email: z.string().email().optional(),
    password: z.string().min(6),
    role: z.enum(["member", "team_admin"]).default("member"),
    teamId: z.string().optional(),
  }).parse(req.body);

  const user = mutateDb((db) => {
    const exists = db.users.some((item) =>
      (body.email && item.email === body.email) || (body.phone && item.phone === body.phone),
    );
    if (exists) throw new AppError(ErrorCode.CONFLICT, "账号已存在");

    const createdAt = now();
    const nextUser: User = {
      id: randomUUID(),
      nickname: body.nickname,
      email: body.email,
      phone: body.phone,
      passwordHash: bcrypt.hashSync(body.password, 10),
      role: body.role,
      status: "active",
      createdAt,
      updatedAt: createdAt,
    };
    db.users.push(nextUser);

    const teamId = body.teamId;
    if (teamId) {
      const team = db.teams.find((t) => t.id === teamId && t.status === "active");
      if (team) {
        db.teamMembers.push({
          id: randomUUID(),
          teamId: team.id,
          userId: nextUser.id,
          role: body.role === "team_admin" ? "team_admin" : "member",
          status: "active",
          joinedAt: createdAt,
          updatedAt: createdAt,
        });
      }
    }

    return nextUser;
  });

  logOperation("user.create", req.user!.id, "user", user.id);
  res.json({ user: publicUser(user) });
});

app.post("/api/auth/login", requireAppKey, (req, res) => {
  const body = z.object({ account: z.string().min(1), password: z.string().min(1) }).parse(req.body);
  const user = readDb().users.find((item) => item.email === body.account || item.phone === body.account);
  if (!user || !bcrypt.compareSync(body.password, user.passwordHash)) {
    return sendError(res, 401, ErrorCode.AUTH_INVALID_CREDENTIALS, "账号或密码错误");
  }
  res.json({ token: signToken(user), user: publicUser(user) });
});

app.get("/api/me", auth, (req: AuthedRequest, res) => {
  res.json({ user: publicUser(req.user!) });
});

app.patch("/api/users/:userId", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    nickname: z.string().min(1).optional(),
    phone: z.string().min(6).optional(),
    email: z.string().email().optional(),
    role: z.enum(["member", "team_admin"]).optional(),
    status: z.enum(["active", "disabled"]).optional(),
    password: z.string().min(6).optional(),
  }).parse(req.body);

  const user = mutateDb((db) => {
    const found = db.users.find((u) => u.id === req.params.userId);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "用户不存在");

    if (body.nickname !== undefined) found.nickname = body.nickname;
    if (body.phone !== undefined) found.phone = body.phone;
    if (body.email !== undefined) found.email = body.email;
    if (body.role !== undefined) found.role = body.role;
    if (body.status !== undefined) found.status = body.status;
    if (body.password) found.passwordHash = bcrypt.hashSync(body.password, 10);
    found.updatedAt = now();

    return found;
  });

  logOperation("user.update", req.user!.id, "user", req.params.userId);
  res.json({ user: publicUser(user) });
});

app.patch("/api/admin/tasks/:taskId", auth, (req: AuthedRequest, res) => {
  if (req.user!.role !== "system_admin" && req.user!.role !== "team_admin") {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权操作");
  }
  const body = z.object({
    title: z.string().min(1).optional(),
    content: z.string().optional(),
    status: z.enum(["pending", "in_progress", "completed", "cancelled"]).optional(),
    priority: z.enum(["low", "medium", "high"]).optional(),
    startTime: z.string().optional(),
    dueTime: z.string().optional(),
    completedAt: z.string().optional(),
    assignee: z.string().optional(),
    ownerUserId: z.string().optional(),
    teamId: z.string().optional(),
    parentId: z.string().optional(),
    isRecurring: z.boolean().optional(),
    recurringRule: z.string().optional(),
    tagIds: z.array(z.string()).optional(),
    reminderMinutes: z.number().nullable().optional(),
    reminderDismissed: z.boolean().optional(),
    reminderVoiceEnabled: z.boolean().optional(),
    reminderVoiceType: z.string().optional(),
    reminderVoiceStyle: z.string().optional(),
    reminderVoiceSpeed: z.string().optional(),
    reminderCustomVoicePath: z.string().optional(),
    sortOrder: z.number().int().optional(),
    assigneeUserId: z.string().optional(),
  }).parse(req.body);

  const task = mutateDb((db) => {
    const found = db.tasks.find((t) => t.id === req.params.taskId);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "任务不存在");
    if (body.title !== undefined) found.title = body.title;
    if (body.content !== undefined) found.content = body.content;
    if (body.status !== undefined) {
      const prev = found.status;
      found.status = body.status;
      if (body.status === "completed") found.completedAt = now();
      if (prev !== body.status) {
        recordStatusChange(db, found.id, {
          previousStatus: prev,
          newStatus: body.status,
          changedByUserId: req.user!.id,
          source: "admin",
        });
        // Propagate to distributed copies or source task
        if (found.sourceType === "team_distribution") {
          updateDistributionStatusOnTaskChange(db, found.id, body.status);
        } else {
          propagateSenderStatusToRecipient(db, found.id, body.status, req.user!.id);
        }
      }
    }
    if (body.priority !== undefined) found.priority = body.priority;
    if (body.startTime !== undefined) found.startTime = body.startTime || undefined;
    if (body.dueTime !== undefined) found.dueTime = body.dueTime || undefined;
    if (body.assignee !== undefined) found.assignee = body.assignee || undefined;
    if (body.ownerUserId !== undefined) found.ownerUserId = body.ownerUserId;
    if (body.teamId !== undefined) found.teamId = body.teamId || undefined;
    if (body.parentId !== undefined) found.parentId = body.parentId || undefined;
    if (body.completedAt !== undefined) found.completedAt = body.completedAt || undefined;
    if (body.isRecurring !== undefined) found.isRecurring = body.isRecurring;
    if (body.recurringRule !== undefined) found.recurringRule = body.recurringRule || undefined;
    if (body.tagIds !== undefined) found.tagIds = body.tagIds;
    if (body.reminderMinutes !== undefined) found.reminderMinutes = body.reminderMinutes ?? undefined;
    if (body.reminderDismissed !== undefined) found.reminderDismissed = body.reminderDismissed;
    if (body.reminderVoiceEnabled !== undefined) found.reminderVoiceEnabled = body.reminderVoiceEnabled;
    if (body.reminderVoiceType !== undefined) found.reminderVoiceType = body.reminderVoiceType || undefined;
    if (body.reminderVoiceStyle !== undefined) found.reminderVoiceStyle = body.reminderVoiceStyle || undefined;
    if (body.reminderVoiceSpeed !== undefined) found.reminderVoiceSpeed = body.reminderVoiceSpeed || undefined;
    if (body.reminderCustomVoicePath !== undefined) found.reminderCustomVoicePath = body.reminderCustomVoicePath || undefined;
    if (body.sortOrder !== undefined) found.sortOrder = body.sortOrder;
    if (body.assigneeUserId !== undefined) found.assigneeUserId = body.assigneeUserId || undefined;
    found.version++;
    found.updatedAt = now();
    return found;
  });

  logOperation("task.update", req.user!.id, "task", req.params.taskId);
  res.json({ task });
});

app.get("/api/admin/overview", auth, (req: AuthedRequest, res) => {
  refreshDevicePresence();
  const db = readDb();
  const today = new Date().toISOString().slice(0, 10);
  res.json({
    stats: {
      users: db.users.length,
      teams: db.teams.length,
      onlineDevices: db.devices.filter((device) => device.onlineStatus === "online").length,
      tasks: db.tasks.filter((task) => !task.deletedAt).length,
      pendingSync: db.syncLogs.filter((log) => log.status === "pending").length,
      distributions: db.distributions.length,
      failedDistributions: db.distributions.filter((item) => item.status === "failed").length,
      todayComments: db.comments.filter((comment) => comment.createdAt.startsWith(today)).length,
    },
    users: db.users.map(publicUser),
    teams: db.teams,
    members: db.teamMembers,
    devices: db.devices,
    tasks: db.tasks.filter((task) => canSeeTask(req.user!, task) && !task.deletedAt).slice(0, 200),
    distributions: db.distributions.map((distribution) => enrichDistribution(db, distribution, req.user!.id)),
    comments: db.comments,
    syncLogs: db.syncLogs.slice(0, 50),
    operationLogs: db.operationLogs.slice(0, 50),
    inviteCodes: db.inviteCodes,
  });
});

app.get("/api/admin/tasks/export", auth, (req: AuthedRequest, res) => {
  if (req.user!.role !== "system_admin" && req.user!.role !== "team_admin") {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权操作");
  }
  const db = readDb();
  const tasks = db.tasks.filter((t) => !t.deletedAt);
  const header = "ID,标题,状态,优先级,负责人,截止时间,创建时间,更新时间";
  const rows = tasks.map((t) => {
    const statusMap: Record<string, string> = { pending: "待处理", in_progress: "进行中", completed: "已完成", cancelled: "已取消" };
    const prioMap: Record<string, string> = { low: "低", medium: "中", high: "高" };
    const assignee = t.assigneeUserId ? db.users.find((u) => u.id === t.assigneeUserId)?.nickname ?? "" : t.assignee ?? "";
    return [t.id, `"${t.title.replace(/"/g, '""')}"`, statusMap[t.status] ?? t.status, prioMap[t.priority] ?? t.priority, assignee, t.dueTime ?? "", t.createdAt, t.updatedAt].join(",");
  });
  const csv = [header, ...rows].join("\n");
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", "attachment; filename=tasks-export.csv");
  res.send("﻿" + csv);
});

app.post("/api/admin/tasks/batch-delete", auth, (req: AuthedRequest, res) => {
  if (req.user!.role !== "system_admin" && req.user!.role !== "team_admin") {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权操作");
  }
  const body = z.object({
    taskIds: z.array(z.string().min(1)).optional(),
    query: z.object({
      status: z.string().optional(),
      priority: z.string().optional(),
      source: z.string().optional(),
      ownerUserId: z.string().optional(),
      teamId: z.string().optional(),
      search: z.string().optional(),
    }).optional(),
  }).parse(req.body);

  const deleted = mutateDb((db) => {
    let count = 0;
    const timestamp = now();
    let targets: Task[];

    if (body.taskIds?.length) {
      targets = db.tasks.filter((t) => body.taskIds!.includes(t.id) && !t.deletedAt);
    } else {
      targets = db.tasks.filter((t) => !t.deletedAt && canSeeTask(req.user!, t) && taskMatchesAdminQuery(t, { query: body.query ?? {} } as any));
    }

    for (const task of targets) {
      task.deletedAt = timestamp;
      task.updatedAt = timestamp;
      task.version = (task.version ?? 0) + 1;
      count++;
    }
    return count;
  });
  logOperation("task.batch_delete", req.user!.id, "task", `${deleted} tasks`);
  res.json({ deleted });
});

app.get("/api/admin/tasks", auth, (req: AuthedRequest, res) => {
  refreshDevicePresence();
  const db = readDb();
  const { page, pageSize } = parsePageQuery(req);
  const matched = db.tasks
    .filter((task) => canSeeTask(req.user!, task) && taskMatchesAdminQuery(task, req))
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  const total = matched.length;
  const start = (page - 1) * pageSize;
  const tasks = matched.slice(start, start + pageSize);

  res.json({
    tasks,
    page,
    pageSize,
    total,
    totalPages: Math.max(1, Math.ceil(total / pageSize)),
  });
});

app.get("/api/admin/tasks/:taskId", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const task = db.tasks.find((t) => t.id === req.params.taskId);
  if (!task || task.deletedAt) throw new AppError(ErrorCode.NOT_FOUND, "任务不存在");
  if (!canSeeTask(req.user!, task)) throw new AppError(ErrorCode.FORBIDDEN, "无权查看此任务");

  const comments = db.comments
    .filter((c) => c.taskId === task.id && c.status === "active")
    .sort((a, b) => a.serverCreatedAt.localeCompare(b.serverCreatedAt))
    .map((c) => ({ ...c, authorName: db.users.find((u) => u.id === c.authorUserId)?.nickname ?? "未知" }));

  const distributions = db.distributions
    .filter((d) => d.sourceTaskId === task.id || d.recipientTaskId === task.id)
    .map((d) => enrichDistribution(db, d, req.user!.id));

  const statusLogs = db.statusChangeLogs
    .filter((l) => l.taskId === task.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map((l) => ({ ...l, changedByName: db.users.find((u) => u.id === l.changedByUserId)?.nickname ?? "未知" }));

  const syncLogs = db.syncLogs
    .filter((l) => l.taskId === task.id)
    .slice(0, 50);

  const taskWithAssignee = {
    ...task,
    assigneeName: task.assigneeUserId ? (db.users.find((u) => u.id === task.assigneeUserId)?.nickname ?? null) : null,
  };
  res.json({ task: taskWithAssignee, comments, distributions, statusLogs, syncLogs });
});

app.get("/api/admin/distributions", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const { page, pageSize } = parsePageQuery(req);
  let matched = db.distributions;

  const status = typeof req.query.status === "string" ? req.query.status : "";
  const teamId = typeof req.query.teamId === "string" ? req.query.teamId : "";
  if (status) matched = matched.filter((d) => d.status === status);
  if (teamId) matched = matched.filter((d) => d.teamId === teamId);

  matched = [...matched].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  const total = matched.length;
  const start = (page - 1) * pageSize;
  const distributions = matched.slice(start, start + pageSize).map((d) => enrichDistribution(db, d, req.user!.id));

  res.json({
    distributions,
    page,
    pageSize,
    total,
    totalPages: Math.max(1, Math.ceil(total / pageSize)),
  });
});

// ==================== Invite Codes ====================

app.get("/api/invite-codes", auth, (_req: AuthedRequest, res) => {
  const db = readDb();
  const codes = db.inviteCodes.map((code) => ({
    ...code,
    teamName: db.teams.find((t) => t.id === code.teamId)?.name ?? "未知团队",
    createdByName: db.users.find((u) => u.id === code.createdByUserId)?.nickname ?? "未知用户",
  }));
  res.json({ inviteCodes: codes });
});

app.post("/api/invite-codes", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    teamId: z.string().min(1),
    maxUses: z.number().int().default(-1),
    expiresAt: z.string().optional(),
  }).parse(req.body);

  const inviteCode = mutateDb((db) => {
    const team = db.teams.find((t) => t.id === body.teamId && t.status === "active");
    if (!team) throw new AppError(ErrorCode.NOT_FOUND, "团队不存在");

    const timestamp = now();
    const code = generateInviteCode();
    const next = {
      id: randomUUID(),
      code,
      teamId: body.teamId,
      createdByUserId: req.user!.id,
      maxUses: body.maxUses,
      usedCount: 0,
      expiresAt: body.expiresAt,
      status: "active" as const,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.inviteCodes.push(next);
    return next;
  });

  logOperation("invite_code.create", req.user!.id, "invite_code", inviteCode.id);
  res.json({ inviteCode });
});

app.post("/api/invite-codes/:id/disable", auth, (req: AuthedRequest, res) => {
  const inviteCode = mutateDb((db) => {
    const found = db.inviteCodes.find((item) => item.id === req.params.id);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "邀请码不存在");
    found.status = "disabled";
    found.updatedAt = now();
    return found;
  });
  res.json({ inviteCode });
});

// ==================== Teams ====================

app.get("/api/teams/mine", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const myTeamIds = db.teamMembers
    .filter((m) => m.userId === req.user!.id && m.status === "active")
    .map((m) => m.teamId);
  const teams = db.teams.filter((t) => myTeamIds.includes(t.id) && t.status === "active");
  res.json({ teams });
});

app.post("/api/teams", auth, (req: AuthedRequest, res) => {
  const body = z.object({ name: z.string().min(1) }).parse(req.body);
  const team = mutateDb((db) => {
    const createdAt = now();
    const nextTeam = {
      id: randomUUID(),
      name: body.name,
      ownerUserId: req.user!.id,
      status: "active" as const,
      createdAt,
      updatedAt: createdAt,
    };
    db.teams.push(nextTeam);
    db.teamMembers.push({
      id: randomUUID(),
      teamId: nextTeam.id,
      userId: req.user!.id,
      role: "team_admin",
      status: "active",
      joinedAt: createdAt,
      updatedAt: createdAt,
    });
    return nextTeam;
  });
  logOperation("team.create", req.user!.id, "team", team.id);
  res.json({ team });
});

app.get("/api/teams/:teamId/members", auth, (req, res) => {
  refreshDevicePresence();
  const db = readDb();
  const members = db.teamMembers
    .filter((member) => member.teamId === req.params.teamId && member.status === "active")
    .map((member) => {
      const user = db.users.find((item) => item.id === member.userId)!;
      const online = db.devices.some((device) => device.userId === user.id && device.onlineStatus === "online");
      return {
        userId: user.id,
        displayName: user.nickname,
        phoneMasked: user.phone ? `${user.phone.slice(0, 3)}****${user.phone.slice(-4)}` : undefined,
        role: member.role,
        online,
      };
    });
  res.json({ members });
});

app.post("/api/teams/:teamId/members", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    userId: z.string().min(1),
    role: z.enum(["member", "team_admin"]).default("member"),
  }).parse(req.body);

  const member = mutateDb((db) => {
    const team = db.teams.find((t) => t.id === req.params.teamId && t.status === "active");
    if (!team) throw new AppError(ErrorCode.NOT_FOUND, "团队不存在");
    const user = db.users.find((u) => u.id === body.userId && u.status === "active");
    if (!user) throw new AppError(ErrorCode.NOT_FOUND, "用户不存在");
    const existing = db.teamMembers.find(
      (m) => m.teamId === req.params.teamId && m.userId === body.userId,
    );
    if (existing) {
      if (existing.status === "active") throw new AppError(ErrorCode.CONFLICT, "该用户已是团队成员");
      existing.status = "active";
      existing.role = body.role;
      existing.updatedAt = now();
      return existing;
    }
    const timestamp = now();
    const teamId = req.params.teamId as string;
    const next = {
      id: randomUUID(),
      teamId,
      userId: body.userId,
      role: body.role as "team_admin" | "member",
      status: "active" as const,
      joinedAt: timestamp,
      updatedAt: timestamp,
    };
    db.teamMembers.push(next);
    return next;
  });
  logOperation("team.add_member", req.user!.id, "team", req.params.teamId as string);
  res.json({ member });
});

app.delete("/api/teams/:teamId/members/:userId", auth, (req: AuthedRequest, res) => {
  const member = mutateDb((db) => {
    const found = db.teamMembers.find(
      (m) => m.teamId === req.params.teamId && m.userId === req.params.userId && m.status === "active",
    );
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "成员不存在");
    found.status = "left";
    found.updatedAt = now();
    return found;
  });
  res.json({ member });
});

app.post("/api/devices/bind", auth, (req: AuthedRequest, res) => {
  const body = z
    .object({
      deviceId: z.string().nullish(),
      deviceName: z.string().nullish(),
      platform: z.string().nullish(),
      deviceToken: z.string().optional(),
    })
    .parse(req.body);

  const device = mutateDb((db) => {
    const timestamp = now();
    const existing = body.deviceId ? db.devices.find((item) => item.id === body.deviceId) : undefined;
    if (existing) {
      existing.userId = req.user!.id;
      existing.deviceName = body.deviceName?.trim() || "APP设备";
      existing.platform = body.platform?.trim() || "unknown";
      existing.deviceToken = body.deviceToken;
      existing.onlineStatus = "online";
      existing.lastHeartbeatAt = timestamp;
      existing.updatedAt = timestamp;
      return existing;
    }

    const nextDevice = {
      id: body.deviceId ?? randomUUID(),
      userId: req.user!.id,
      deviceName: body.deviceName?.trim() || "APP设备",
      platform: body.platform?.trim() || "unknown",
      deviceToken: body.deviceToken,
      onlineStatus: "online" as const,
      lastHeartbeatAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.devices.push(nextDevice);
    return nextDevice;
  });

  logOperation("device.bind", req.user!.id, "device", device.id);
  res.json({ device });
});

app.post("/api/devices/heartbeat", auth, (req: AuthedRequest, res) => {
  const body = z.object({ deviceId: z.string().min(1) }).parse(req.body);
  const heartbeatAt = now();
  const device = mutateDb((db) => {
    const found = db.devices.find((item) => item.id === body.deviceId && item.userId === req.user!.id);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "设备不存在");
    found.onlineStatus = "online";
    found.lastHeartbeatAt = heartbeatAt;
    found.updatedAt = heartbeatAt;
    return found;
  });
  res.json({ device });
});

app.get("/api/tasks", auth, (req: AuthedRequest, res) => {
  const tasks = readDb().tasks.filter((task) => canSeeTask(req.user!, task) && !task.deletedAt);
  res.json({ tasks });
});

app.get("/api/tasks/:taskId", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const task = db.tasks.find((t) => t.id === req.params.taskId && !t.deletedAt);
  if (!task || !canSeeTask(req.user!, task)) throw new AppError(ErrorCode.NOT_FOUND, "任务不存在");
  res.json({ task });
});

app.post("/api/tasks/sync/push", auth, (req: AuthedRequest, res) => {
  const body = z
    .object({
      deviceId: z.string().optional(),
      force: z.boolean().optional(),
      tasks: z.array(
        z.object({
          id: z.string().min(1),
          title: z.string().min(1),
          content: z.string().optional(),
          status: z.enum(["pending", "in_progress", "completed", "cancelled"]).default("pending"),
          priority: z.enum(["low", "medium", "high"]).default("medium"),
          startTime: z.string().optional(),
          dueTime: z.string().optional(),
          completedAt: z.string().optional(),
          reminderTime: z.string().optional(),
          assignee: z.string().optional(),
          parentId: z.string().optional(),
          isRecurring: z.boolean().optional(),
          recurringRule: z.string().optional(),
          tagIds: z.array(z.string()).optional(),
          attachmentPaths: z.array(z.string()).optional(),
          reminderMinutes: z.number().int().optional(),
          reminderDismissed: z.boolean().optional(),
          reminderVoiceEnabled: z.boolean().optional(),
          reminderVoiceType: z.string().optional(),
          reminderVoiceStyle: z.string().optional(),
          reminderVoiceSpeed: z.string().optional(),
          reminderCustomVoicePath: z.string().optional(),
          sourceType: z.enum(["local", "team_distribution"]).optional(),
          sourceTaskId: z.string().optional(),
          sourceDistributionId: z.string().optional(),
          teamId: z.string().optional(),
          version: z.number().int().nonnegative().default(1),
          sortOrder: z.number().int().optional(),
          assigneeUserId: z.string().optional(),
          updatedAt: z.string().optional(),
          deletedAt: z.string().optional(),
        }),
      ),
    })
    .parse(req.body);

  const conflicts: Array<{ taskId: string; serverVersion: Task; clientVersion: Task }> = [];
  const saved = mutateDb((db) => {
    const result: Task[] = [];
    for (const incoming of body.tasks) {
      const timestamp = incoming.updatedAt ?? now();
      const existing = db.tasks.find((task) => task.id === incoming.id && task.ownerUserId === req.user!.id);
      if (!existing) {
        const nextTask: Task = {
          ...incoming,
          ownerUserId: req.user!.id,
          sourceType: incoming.sourceType ?? "local",
          createdAt: timestamp,
          updatedAt: timestamp,
          version: incoming.version ?? 1,
        };
        db.tasks.push(nextTask);
        result.push(nextTask);
      } else if (incoming.version != null && incoming.version < existing.version) {
        // 检查数据是否完全一致，一致则跳过冲突
        const merged = { ...existing, ...incoming };
        const fieldsToCompare = ["title", "content", "status", "priority", "startTime", "dueTime", "completedAt", "assignee", "parentId", "isRecurring", "recurringRule", "tagIds", "reminderMinutes", "reminderDismissed", "assigneeUserId", "sortOrder"] as const;
        const isIdentical = fieldsToCompare.every((f) => JSON.stringify(existing[f]) === JSON.stringify(merged[f]));
        if (isIdentical) {
          // 数据一致，静默接受服务器版本（同步 version 号）
          result.push(existing);
        } else if (body.force) {
          // Force push: overwrite server version
          const prevStatus = existing.status;
          Object.assign(existing, incoming, { updatedAt: timestamp, version: existing.version + 1 });
          if (incoming.status && prevStatus !== incoming.status) {
            recordStatusChange(db, existing.id, {
              previousStatus: prevStatus,
              newStatus: incoming.status,
              changedByUserId: req.user!.id,
              source: existing.sourceType === "team_distribution" ? "recipient" : "sender",
            });
          }
          result.push(existing);
        } else {
          // Report conflict
          conflicts.push({
            taskId: existing.id,
            serverVersion: { ...existing },
            clientVersion: { ...existing, ...incoming },
          });
          result.push(existing);
        }
      } else if (timestamp >= existing.updatedAt) {
        const prevStatus = existing.status;
        Object.assign(existing, incoming, { updatedAt: timestamp, version: Math.max(existing.version + 1, incoming.version) });
        if (incoming.status && prevStatus !== incoming.status) {
          recordStatusChange(db, existing.id, {
            previousStatus: prevStatus,
            newStatus: incoming.status,
            changedByUserId: req.user!.id,
            source: existing.sourceType === "team_distribution" ? "recipient" : "sender",
          });
        }
        if (existing.sourceType === "team_distribution" && incoming.status) {
          updateDistributionStatusOnTaskChange(db, existing.id, incoming.status);
        }
        // Sender's status change → propagate to recipient task copies
        if (existing.sourceType !== "team_distribution" && incoming.status && prevStatus !== incoming.status) {
          propagateSenderStatusToRecipient(db, existing.id, incoming.status, req.user!.id);
        }
        result.push(existing);
      } else {
        result.push(existing);
      }
      db.syncLogs.unshift({
        id: randomUUID(),
        userId: req.user!.id,
        deviceId: body.deviceId,
        taskId: incoming.id,
        operationType: incoming.deletedAt ? "delete" : "update",
        status: "success",
        createdAt: now(),
      });
    }
    return result;
  });
  res.json({ tasks: saved, conflicts });
});

app.get("/api/tasks/sync/pull", auth, (req: AuthedRequest, res) => {
  const since = typeof req.query.since === "string" ? req.query.since : "1970-01-01T00:00:00.000Z";
  const db = readDb();
  const allVisible = db.tasks.filter((task) => canSeeTask(req.user!, task));
  const visibleTaskIds = new Set(allVisible.map((t) => t.id));
  // Tasks: only return those updated since last sync
  const tasks = allVisible
    .filter((task) => task.updatedAt >= since)
    .map((task) => ({ ...task, deleted: !!task.deletedAt }));
  // Comments: return all active comments for visible tasks (no since filter, client deduplicates)
  const comments = db.comments.filter((comment) => {
    return visibleTaskIds.has(comment.taskId) && comment.status === "active";
  }).map((c) => ({
    ...c,
    authorName: db.users.find((u) => u.id === c.authorUserId)?.nickname ?? "未知",
  }));
  res.json({ tasks, comments, serverTime: now() });
});

app.patch("/api/tasks/batch", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    taskIds: z.array(z.string().min(1)).min(1),
    status: z.enum(["pending", "in_progress", "completed", "cancelled"]).optional(),
    priority: z.enum(["low", "medium", "high"]).optional(),
    tagIds: z.array(z.string()).optional(),
    assigneeUserId: z.string().optional(),
  }).parse(req.body);

  const updated = mutateDb((db) => {
    const result: Task[] = [];
    const timestamp = now();
    for (const id of body.taskIds) {
      const task = db.tasks.find((t) => t.id === id && t.ownerUserId === req.user!.id);
      if (!task) continue;
      if (body.status) {
        const prev = task.status;
        task.status = body.status;
        if (prev !== body.status) {
          recordStatusChange(db, task.id, {
            previousStatus: prev,
            newStatus: body.status,
            changedByUserId: req.user!.id,
            source: task.sourceType === "team_distribution" ? "recipient" : "sender",
          });
          updateDistributionStatusOnTaskChange(db, task.id, body.status);
          propagateSenderStatusToRecipient(db, task.id, body.status, req.user!.id);
        }
      }
      if (body.priority) task.priority = body.priority;
      if (body.tagIds) task.tagIds = body.tagIds;
      if (body.assigneeUserId !== undefined) task.assigneeUserId = body.assigneeUserId;
      task.updatedAt = timestamp;
      task.version = (task.version ?? 0) + 1;
      result.push(task);
    }
    return result;
  });
  res.json({ updated: updated.length });
});

app.delete("/api/tasks/batch", auth, (req: AuthedRequest, res) => {
  const body = z.object({
    taskIds: z.array(z.string().min(1)).min(1),
  }).parse(req.body);

  const deleted = mutateDb((db) => {
    let count = 0;
    const timestamp = now();
    for (const id of body.taskIds) {
      const task = db.tasks.find((t) => t.id === id && t.ownerUserId === req.user!.id);
      if (!task) continue;
      task.deletedAt = timestamp;
      task.updatedAt = timestamp;
      task.version = (task.version ?? 0) + 1;
      db.syncLogs.unshift({
        id: randomUUID(),
        userId: req.user!.id,
        taskId: id,
        operationType: "delete",
        status: "success",
        createdAt: timestamp,
      });
      count++;
    }
    return count;
  });
  res.json({ deleted });
});

app.post("/api/distributions", auth, (req: AuthedRequest, res) => {
  const body = z
    .object({
      sourceTaskId: z.string().min(1),
      recipientUserId: z.string().min(1),
      teamId: z.string().min(1),
      remark: z.string().optional(),
    })
    .parse(req.body);

  const distribution = mutateDb((db) => {
    const sourceTask = db.tasks.find((task) => task.id === body.sourceTaskId && task.ownerUserId === req.user!.id);
    if (!sourceTask) throw new AppError(ErrorCode.NOT_FOUND, "原任务不存在或无权分发");
    const senderInTeam = db.teamMembers.some((item) => item.teamId === body.teamId && item.userId === req.user!.id && item.status === "active");
    const recipientInTeam = db.teamMembers.some((item) => item.teamId === body.teamId && item.userId === body.recipientUserId && item.status === "active");
    if (!senderInTeam || !recipientInTeam) throw new AppError(ErrorCode.FORBIDDEN, "只能向同一团队成员分发任务");

    const timestamp = now();
    const distributionId = randomUUID();
    const recipientTask: Task = {
      id: randomUUID(),
      ownerUserId: body.recipientUserId,
      teamId: body.teamId,
      title: sourceTask.title,
      content: sourceTask.content,
      status: "pending",
      priority: sourceTask.priority,
      startTime: sourceTask.startTime,
      dueTime: sourceTask.dueTime,
      completedAt: undefined,
      assignee: sourceTask.assignee,
      parentId: sourceTask.parentId,
      attachmentPaths: sourceTask.attachmentPaths ? [...sourceTask.attachmentPaths] : undefined,
      sourceType: "team_distribution",
      sourceTaskId: sourceTask.id,
      sourceDistributionId: distributionId,
      version: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.tasks.push(recipientTask);

    const nextDistribution: TaskDistribution = {
      id: distributionId,
      senderUserId: req.user!.id,
      recipientUserId: body.recipientUserId,
      sourceTaskId: body.sourceTaskId,
      recipientTaskId: recipientTask.id,
      teamId: body.teamId,
      status: "generated",
      remark: body.remark,
      commentCount: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.distributions.unshift(nextDistribution);
    return nextDistribution;
  });

  logOperation("distribution.create", req.user!.id, "distribution", distribution.id);
  res.json({ distribution });
});

app.post("/api/distributions/:id/ack", auth, (req: AuthedRequest, res) => {
  const body = z.object({ status: z.enum(["received", "viewed", "in_progress", "completed", "cancelled", "failed"]) }).parse(req.body);
  const distribution = mutateDb((db) => {
    const found = db.distributions.find((item) => item.id === req.params.id);
    if (!found || found.recipientUserId !== req.user!.id) throw new AppError(ErrorCode.NOT_FOUND, "分发记录不存在或无权操作");
    found.status = body.status;
    found.updatedAt = now();
    return found;
  });
  res.json({ distribution });
});

app.get("/api/distributions", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const filtered = db.distributions.filter(
    (item) =>
      item.senderUserId === req.user!.id ||
      item.recipientUserId === req.user!.id ||
      (req.user!.role === "team_admin" && requireTeamMember(req.user!.id, item.teamId)),
  );
  const distributions = filtered.map((d) => enrichDistribution(db, d, req.user!.id));
  res.json({ distributions });
});

app.get("/api/distributions/by-task/:taskId", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const filtered = db.distributions.filter((d) => d.sourceTaskId === req.params.taskId || d.recipientTaskId === req.params.taskId);
  if (filtered.length === 0) return res.json({ distributions: [] });
  const isAuthorized = filtered.some(
    (d) => d.senderUserId === req.user!.id || d.recipientUserId === req.user!.id ||
      (req.user!.role === "system_admin") ||
      (req.user!.role === "team_admin" && requireTeamMember(req.user!.id, d.teamId)),
  );
  if (!isAuthorized) return sendError(res, 403, ErrorCode.FORBIDDEN, "无权查看此任务的分发记录");
  const distributions = filtered.map((d) => {
    const recipientTask = d.recipientTaskId ? db.tasks.find((t) => t.id === d.recipientTaskId) : undefined;
    return {
      ...enrichDistribution(db, d, req.user!.id),
      recipientTaskStatus: recipientTask?.status,
    };
  });
  res.json({ distributions });
});

app.get("/api/distributions/:distributionId/recipient-comments", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const distribution = db.distributions.find((d) => d.id === req.params.distributionId);
  if (!distribution) return sendError(res, 404, ErrorCode.NOT_FOUND, "分发记录不存在");
  if (distribution.senderUserId !== req.user!.id && distribution.recipientUserId !== req.user!.id && req.user!.role !== "system_admin" && !(req.user!.role === "team_admin" && requireTeamMember(req.user!.id, distribution.teamId))) {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权查看");
  }
  const relatedTaskIds = [distribution.sourceTaskId, distribution.recipientTaskId].filter(Boolean) as string[];
  const comments = db.comments
    .filter((c) => relatedTaskIds.includes(c.taskId) && c.status === "active")
    .sort((a, b) => a.serverCreatedAt.localeCompare(b.serverCreatedAt))
    .map((c) => ({
      ...c,
      authorName: db.users.find((u) => u.id === c.authorUserId)?.nickname ?? "未知",
    }));
  res.json({ comments });
});

app.get("/api/distributions/:distributionId/status-logs", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const distribution = db.distributions.find((d) => d.id === req.params.distributionId);
  if (!distribution) return sendError(res, 404, ErrorCode.NOT_FOUND, "分发记录不存在");
  if (distribution.senderUserId !== req.user!.id && distribution.recipientUserId !== req.user!.id && req.user!.role !== "system_admin" && !(req.user!.role === "team_admin" && requireTeamMember(req.user!.id, distribution.teamId))) {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权查看");
  }
  const taskIds = new Set([distribution.sourceTaskId, distribution.recipientTaskId].filter(Boolean) as string[]);
  const logs = db.statusChangeLogs
    .filter((l) => taskIds.has(l.taskId))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map((l) => ({
      ...l,
      changedByName: db.users.find((u) => u.id === l.changedByUserId)?.nickname ?? "未知",
    }));
  res.json({ logs });
});

app.post("/api/distributions/:id/mark-comments-read", auth, (req: AuthedRequest, res) => {
  const distribution = mutateDb((db) => {
    const found = db.distributions.find((d) => d.id === req.params.id);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "分发记录不存在");
    if (found.senderUserId !== req.user!.id && found.recipientUserId !== req.user!.id) {
      throw new AppError(ErrorCode.FORBIDDEN, "无权操作");
    }
    const timestamp = now();
    if (found.senderUserId === req.user!.id) {
      found.senderLastReadCommentAt = timestamp;
    } else {
      found.recipientLastReadCommentAt = timestamp;
    }
    found.updatedAt = timestamp;
    return found;
  });
  res.json({ ok: true });
});

// Notifications
app.get("/api/notifications", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const notifications = (db.notifications ?? [])
    .filter((n) => n.userId === req.user!.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, 50)
    .map((n) => ({
      ...n,
      fromUserName: db.users.find((u) => u.id === n.fromUserId)?.nickname ?? "未知",
      taskTitle: db.tasks.find((t) => t.id === n.taskId)?.title ?? "未知任务",
    }));
  res.json({ notifications });
});

app.get("/api/notifications/unread-count", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const count = (db.notifications ?? []).filter((n) => n.userId === req.user!.id && !n.read).length;
  res.json({ count });
});

app.post("/api/notifications/:id/read", auth, (req: AuthedRequest, res) => {
  mutateDb((db) => {
    const found = (db.notifications ?? []).find((n) => n.id === req.params.id && n.userId === req.user!.id);
    if (found) found.read = true;
    return found;
  });
  res.json({ ok: true });
});

app.post("/api/notifications/read-all", auth, (req: AuthedRequest, res) => {
  mutateDb((db) => {
    for (const n of db.notifications ?? []) {
      if (n.userId === req.user!.id) n.read = true;
    }
    return null;
  });
  res.json({ ok: true });
});

// Activity feed
app.get("/api/activity", auth, (req: AuthedRequest, res) => {
  const db = readDb();
  const logs = db.operationLogs
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, 100)
    .map((l) => ({
      ...l,
      nickname: l.operatorUserId ? db.users.find((u) => u.id === l.operatorUserId)?.nickname ?? "系统" : "系统",
      taskTitle: l.targetType === "task" && l.targetId
        ? (Array.isArray(l.targetId) ? l.targetId.map((id: string) => db.tasks.find((t) => t.id === id)?.title ?? id).join(", ") : db.tasks.find((t) => t.id === l.targetId)?.title ?? String(l.targetId))
        : undefined,
    }));
  res.json({ logs });
});

// Reports
app.get("/api/reports/summary", auth, (req: AuthedRequest, res) => {
  const period = typeof req.query.period === "string" ? req.query.period : "weekly";
  const db = readDb();
  const now_ = now();
  let since: string;
  if (period === "daily") {
    since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  } else if (period === "monthly") {
    since = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
  } else {
    since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
  }

  const tasks = db.tasks.filter((t) => t.ownerUserId === req.user!.id && !t.deletedAt);
  const recent = tasks.filter((t) => t.createdAt >= since || (t.updatedAt >= since));

  const totalTasks = tasks.length;
  const completedTasks = tasks.filter((t) => t.status === "completed").length;
  const inProgressTasks = tasks.filter((t) => t.status === "in_progress").length;
  const overdueTasks = tasks.filter((t) => t.status !== "completed" && t.dueTime && t.dueTime < now_).length;
  const recentlyCompleted = recent.filter((t) => t.status === "completed" && t.completedAt && t.completedAt >= since).length;
  const completionRate = totalTasks > 0 ? Math.round((completedTasks / totalTasks) * 100) : 0;

  const tasksByPriority = {
    high: tasks.filter((t) => t.priority === "high").length,
    medium: tasks.filter((t) => t.priority === "medium").length,
    low: tasks.filter((t) => t.priority === "low").length,
  };

  res.json({
    period,
    totalTasks,
    completedTasks,
    inProgressTasks,
    overdueTasks,
    recentlyCompleted,
    completionRate,
    tasksByPriority,
  });
});

app.post("/api/tasks/:taskId/comments", auth, (req: AuthedRequest, res) => {
  const body = z
    .object({
      content: z.string().min(1).max(1000),
      clientCommentId: z.string().optional(),
      operationId: z.string().optional(),
      sourceDeviceId: z.string().optional(),
    })
    .parse(req.body);

  const comment = mutateDb((db) => {
    const task = db.tasks.find((item) => item.id === req.params.taskId && !item.deletedAt);
    if (!task) throw new AppError(ErrorCode.NOT_FOUND, "任务尚未同步到后台，请先同步任务后再评论");
    if (!canSeeTask(req.user!, task)) throw new AppError(ErrorCode.FORBIDDEN, "无权评论该任务");
    const operationId = body.operationId ?? randomUUID();
    const existingByOperation = db.comments.find((item) => item.operationId === operationId);
    if (existingByOperation) return existingByOperation;
    const timestamp = now();
    const nextComment: TaskComment = {
      id: randomUUID(),
      clientCommentId: body.clientCommentId ?? randomUUID(),
      taskId: task.id,
      teamId: task.teamId,
      authorUserId: req.user!.id,
      content: body.content,
      sourceDeviceId: body.sourceDeviceId,
      operationId,
      status: "active",
      serverCreatedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.comments.push(nextComment);
    updateDistributionCommentSummary(db, task.id);
    // Mirror sender's comment to all recipient task copies
    const relatedDists = db.distributions.filter((d) => d.sourceTaskId === task.id && d.recipientTaskId);
    for (const dist of relatedDists) {
      const mirrorComment: TaskComment = {
        id: randomUUID(),
        clientCommentId: randomUUID(),
        taskId: dist.recipientTaskId!,
        teamId: task.teamId,
        authorUserId: req.user!.id,
        content: body.content,
        sourceDeviceId: body.sourceDeviceId,
        operationId: `${operationId}-mirror-${dist.id}`,
        status: "active",
        serverCreatedAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      };
      db.comments.push(mirrorComment);
      updateDistributionCommentSummary(db, dist.recipientTaskId!);
    }
    db.syncLogs.unshift({
      id: randomUUID(),
      userId: req.user!.id,
      deviceId: body.sourceDeviceId,
      taskId: task.id,
      operationType: "comment_create",
      status: "success",
      createdAt: timestamp,
    });
    // Generate @mention notifications
    const mentionRegex = /@(\S+)/g;
    let match: RegExpExecArray | null;
    const mentionedNames = new Set<string>();
    while ((match = mentionRegex.exec(body.content)) !== null) {
      mentionedNames.add(match[1]);
    }
    for (const name of mentionedNames) {
      const mentionedUser = db.users.find((u) => u.nickname === name);
      if (mentionedUser && mentionedUser.id !== req.user!.id) {
        if (!db.notifications) (db as any).notifications = [];
        db.notifications.push({
          id: randomUUID(),
          userId: mentionedUser.id,
          type: "mention",
          taskId: task.id,
          commentId: nextComment.id,
          fromUserId: req.user!.id,
          title: `${req.user!.nickname} 在任务中@了你`,
          body: body.content.substring(0, 100),
          read: false,
          createdAt: timestamp,
        });
      }
    }
    return nextComment;
  });

  res.json({ comment });
});

app.delete("/api/tasks/:taskId/comments/:commentId", auth, (req: AuthedRequest, res) => {
  const body = z.object({ operationId: z.string().optional() }).parse(req.body ?? {});
  const comment = mutateDb((db) => {
    const found = db.comments.find((item) => item.id === req.params.commentId && item.taskId === req.params.taskId);
    if (!found || found.authorUserId !== req.user!.id) throw new AppError(ErrorCode.NOT_FOUND, "评论不存在或无权删除");
    found.status = "deleted";
    found.deletedAt = now();
    found.updatedAt = found.deletedAt;
    found.operationId = body.operationId ?? found.operationId;
    updateDistributionCommentSummary(db, found.taskId);
    return found;
  });
  res.json({ comment });
});

// Admin: add comment to any task
app.post("/api/admin/tasks/:taskId/comments", auth, (req: AuthedRequest, res) => {
  if (req.user!.role !== "system_admin" && req.user!.role !== "team_admin") {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权操作");
  }
  const body = z.object({
    content: z.string().min(1).max(1000),
    authorUserId: z.string().min(1).optional(),
  }).parse(req.body);
  const comment = mutateDb((db) => {
    const task = db.tasks.find((t) => t.id === req.params.taskId);
    if (!task) throw new AppError(ErrorCode.NOT_FOUND, "任务不存在");
    // If authorUserId specified, verify it exists
    const effectiveAuthorId = body.authorUserId ?? req.user!.id;
    if (body.authorUserId && !db.users.find((u) => u.id === body.authorUserId)) {
      throw new AppError(ErrorCode.NOT_FOUND, "指定用户不存在");
    }
    const timestamp = now();
    const c: TaskComment = {
      id: randomUUID(),
      clientCommentId: randomUUID(),
      taskId: task.id,
      teamId: task.teamId,
      authorUserId: effectiveAuthorId,
      content: body.content,
      operationId: randomUUID(),
      status: "active",
      serverCreatedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    db.comments.push(c);
    updateDistributionCommentSummary(db, task.id);
    return c;
  });
  logOperation("comment_create", req.user!.id, "task", req.params.taskId);
  res.json({ comment });
});

// Admin: delete any comment
app.delete("/api/admin/comments/:commentId", auth, (req: AuthedRequest, res) => {
  if (req.user!.role !== "system_admin" && req.user!.role !== "team_admin") {
    return sendError(res, 403, ErrorCode.FORBIDDEN, "无权操作");
  }
  const comment = mutateDb((db) => {
    const found = db.comments.find((c) => c.id === req.params.commentId);
    if (!found) throw new AppError(ErrorCode.NOT_FOUND, "评论不存在");
    found.status = "deleted";
    found.deletedAt = now();
    found.updatedAt = found.deletedAt;
    updateDistributionCommentSummary(db, found.taskId);
    return found;
  });
  logOperation("comment_delete", req.user!.id, "comment", req.params.commentId);
  res.json({ comment });
});

app.post("/api/comments/sync/push", auth, (req: AuthedRequest, res) => {
  const body = z
    .object({
      comments: z.array(
        z.object({
          taskId: z.string().min(1),
          content: z.string().min(1).max(1000),
          clientCommentId: z.string().min(1),
          operationId: z.string().min(1),
          sourceDeviceId: z.string().optional(),
        }),
      ),
    })
    .parse(req.body);

  const comments = mutateDb((db) => {
    const saved: TaskComment[] = [];
    for (const incoming of body.comments) {
      const existing = db.comments.find((item) => item.operationId === incoming.operationId || item.clientCommentId === incoming.clientCommentId);
      if (existing) {
        saved.push(existing);
        continue;
      }
      const task = db.tasks.find((item) => item.id === incoming.taskId && !item.deletedAt);
      if (!task || !canSeeTask(req.user!, task)) continue;
      const timestamp = now();
      const nextComment: TaskComment = {
        id: randomUUID(),
        ...incoming,
        teamId: task.teamId,
        authorUserId: req.user!.id,
        status: "active",
        serverCreatedAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      };
      db.comments.push(nextComment);
      updateDistributionCommentSummary(db, incoming.taskId);
      saved.push(nextComment);
      db.syncLogs.unshift({
        id: randomUUID(),
        userId: req.user!.id,
        deviceId: incoming.sourceDeviceId,
        taskId: incoming.taskId,
        operationType: "comment_create",
        status: "success",
        createdAt: timestamp,
      });
    }
    return saved;
  });
  res.json({ comments });
});

app.get("/api/comments/sync/pull", auth, (req: AuthedRequest, res) => {
  const since = typeof req.query.since === "string" ? req.query.since : "1970-01-01T00:00:00.000Z";
  const db = readDb();
  const comments = db.comments
    .filter((comment) => {
      const task = db.tasks.find((item) => item.id === comment.taskId);
      return task && canSeeTask(req.user!, task) && comment.status === "active" && comment.updatedAt >= since;
    })
    .sort((a, b) => a.serverCreatedAt.localeCompare(b.serverCreatedAt))
    .map((c) => ({
      ...c,
      authorName: db.users.find((u) => u.id === c.authorUserId)?.nickname ?? "未知",
    }));
  res.json({ comments, serverTime: now() });
});

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof AppError) {
    const statusMap: Record<string, number> = {
      AUTH_REQUIRED: 401, AUTH_EXPIRED: 401, AUTH_INVALID_CREDENTIALS: 401,
      FORBIDDEN: 403, INVALID_APP_KEY: 403,
      NOT_FOUND: 404,
      VALIDATION_ERROR: 400, CONFLICT: 409,
      INVITE_CODE_INVALID: 400, INVITE_CODE_EXPIRED: 400, INVITE_CODE_EXHAUSTED: 400,
    };
    const status = statusMap[err.code] ?? 500;
    return sendError(res, status, err.code, err.message, err.details);
  }
  if (err instanceof z.ZodError) {
    return sendError(res, 400, ErrorCode.VALIDATION_ERROR, "参数校验失败", err.issues);
  }
  const message = err instanceof Error ? err.message : "服务器异常";
  sendError(res, 500, ErrorCode.SERVER_ERROR, message);
});

app.listen(port, () => {
  console.log(`Smart task backend is running at http://localhost:${port}`);
});
