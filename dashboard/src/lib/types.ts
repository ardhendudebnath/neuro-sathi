export type Role = "user" | "caregiver" | "health_worker" | "admin";

export interface User {
  id: string;
  phone: string;
  name: string | null;
  role: Role;
  language: string;
  region: string | null;
}

export interface LinkedUserSummary {
  user: User;
  relationship: string | null;
  last_active: string | null;
  sessions_7d: number;
  open_alerts: number;
}

export interface DailyTrend {
  day: string;
  sessions: number;
  completion_rate: number | null;
  accuracy: number | null;
  avg_response_ms: number | null;
  reminders_done: number;
  reminders_missed: number;
}

export interface Alert {
  id: string;
  user_id: string;
  kind: string;
  severity: "info" | "watch" | "check_in";
  message: string;
  metrics: Record<string, { recent: number; baseline: number }>;
  created_at: string;
  acknowledged_at: string | null;
}

export interface MemoryEntry {
  id: string;
  user_id: string;
  kind: "person" | "place" | "date" | "memory";
  title: string;
  person_name: string | null;
  relationship: string | null;
  event_date: string | null;
  place: string | null;
  description: string | null;
  photo_key: string | null;
  updated_by_role: Role;
  updated_at: string;
}

export type ReminderKind = "medication" | "hydration" | "meal" | "activity" | "appointment" | "custom";

export interface Reminder {
  id: string;
  user_id: string;
  kind: ReminderKind;
  title: string;
  time_of_day: string;
  days_of_week: number[];
  note: string | null;
  active: boolean;
}

export interface Recommendation {
  game_slug: string;
  level: number;
  rank: number;
  reason: string;
}
