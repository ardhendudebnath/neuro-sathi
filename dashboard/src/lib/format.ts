const IST = "Asia/Kolkata";

export function dateTime(iso: string | null): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: IST }).format(new Date(iso));
}

export function relative(iso: string | null): string {
  if (!iso) return "No activity yet";
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 2) return "Just now";
  if (mins < 60) return `${mins} minutes ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

export function clock(t: string): string {
  const [h, m] = t.split(":").map(Number);
  const suffix = h >= 12 ? "PM" : "AM";
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, "0")} ${suffix}`;
}

export const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export function days(list: number[]): string {
  if (list.length === 7) return "Every day";
  if (list.join() === "0,1,2,3,4") return "Weekdays";
  if (list.join() === "5,6") return "Weekends";
  return list.map((d) => DAY_NAMES[d]).join(", ");
}

export const GAME_NAMES: Record<string, string> = {
  photo_recall: "Who Is This?",
  market_list: "Market List",
  odd_one_out: "Odd One Out",
  gamosa_patterns: "Weaving Patterns",
  name_it: "Name It",
  quick_tap: "Quick Tap",
  my_day: "My Day in Order",
};
