import bcrypt from "bcryptjs";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import type { DatabaseShape } from "./types";

const dbPath = join(process.cwd(), "data", "db.json");

function now() {
  return new Date().toISOString();
}

function createSeedData(): DatabaseShape {
  const createdAt = now();
  const adminId = "user_admin";
  const memberId = "user_member";
  const teamId = "team_default";
  const taskId = "task_seed";
  const recipientTaskId = "task_seed_copy";
  const distributionId = "dist_seed";

  return {
    users: [
      {
        id: adminId,
        nickname: "团队管理员",
        phone: "13800000001",
        email: "admin@example.com",
        passwordHash: bcrypt.hashSync("admin123", 10),
        role: "team_admin",
        status: "active",
        createdAt,
        updatedAt: createdAt,
      },
      {
        id: memberId,
        nickname: "团队成员",
        phone: "13800000002",
        email: "member@example.com",
        passwordHash: bcrypt.hashSync("member123", 10),
        role: "member",
        status: "active",
        createdAt,
        updatedAt: createdAt,
      },
    ],
    teams: [
      {
        id: teamId,
        name: "默认任务团队",
        ownerUserId: adminId,
        status: "active",
        createdAt,
        updatedAt: createdAt,
      },
    ],
    teamMembers: [
      {
        id: randomUUID(),
        teamId,
        userId: adminId,
        role: "team_admin",
        status: "active",
        joinedAt: createdAt,
        updatedAt: createdAt,
      },
      {
        id: randomUUID(),
        teamId,
        userId: memberId,
        role: "member",
        status: "active",
        joinedAt: createdAt,
        updatedAt: createdAt,
      },
    ],
    devices: [],
    tasks: [
      {
        id: taskId,
        ownerUserId: adminId,
        teamId,
        title: "整理第一版任务同步方案",
        content: "验证本地优先、登录同步、团队内分发和评论同步主流程。",
        status: "in_progress",
        priority: "high",
        dueTime: new Date(Date.now() + 86400000).toISOString(),
        sourceType: "local",
        version: 1,
        createdAt,
        updatedAt: createdAt,
      },
      {
        id: recipientTaskId,
        ownerUserId: memberId,
        teamId,
        title: "整理第一版任务同步方案",
        content: "来自团队管理员的任务分发副本。",
        status: "pending",
        priority: "high",
        sourceType: "team_distribution",
        sourceTaskId: taskId,
        sourceDistributionId: distributionId,
        version: 1,
        createdAt,
        updatedAt: createdAt,
      },
    ],
    distributions: [
      {
        id: distributionId,
        senderUserId: adminId,
        recipientUserId: memberId,
        sourceTaskId: taskId,
        recipientTaskId,
        teamId,
        status: "generated",
        remark: "请先验证 APP 内任务卡片自动生成。",
        commentCount: 0,
        createdAt,
        updatedAt: createdAt,
      },
    ],
    comments: [],
    syncLogs: [],
    operationLogs: [],
    inviteCodes: [],
    statusChangeLogs: [],
    notifications: [],
  };
}

function ensureDb() {
  if (!existsSync(dbPath)) {
    mkdirSync(dirname(dbPath), { recursive: true });
    writeFileSync(dbPath, JSON.stringify(createSeedData(), null, 2), "utf8");
  }
}

export function readDb(): DatabaseShape {
  ensureDb();
  const db = JSON.parse(readFileSync(dbPath, "utf8")) as DatabaseShape;
  if (!db.inviteCodes) db.inviteCodes = [];
  if (!db.statusChangeLogs) db.statusChangeLogs = [];
  if (!db.notifications) db.notifications = [];
  return db;
}

export function writeDb(db: DatabaseShape) {
  mkdirSync(dirname(dbPath), { recursive: true });
  writeFileSync(dbPath, JSON.stringify(db, null, 2), "utf8");
}

export function mutateDb<T>(fn: (db: DatabaseShape) => T): T {
  const db = readDb();
  const result = fn(db);
  writeDb(db);
  return result;
}

export function publicUser(user: DatabaseShape["users"][number]) {
  const { passwordHash, ...safe } = user;
  return safe;
}

export { now };
