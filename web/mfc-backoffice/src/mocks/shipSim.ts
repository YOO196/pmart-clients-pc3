// 출하 약속 준수율 목 — mfc-fulfillment 0.35.0 `GET /metrics/ship-promises` 의 날짜 값을 만드는 시뮬레이션(2026-11-25 화면은 서버 값으로 바꿈, 이 파일은 목 서버 전용).
// 뜻(회신 2026-11-24-reply-ship-promise-metrics): 약속 = 배차 요청 때 알린 예상 준비 시각, 끝 = 포장 끝. due = onTime + late.

export interface ShipDay {
  readonly date: string;
  /** 출하 약속이 지난 작업 */
  readonly due: number;
  /** 약속 안에 인계 끝 */
  readonly onTime: number;
  /** 약속을 넘김(아직 인계 전 포함) */
  readonly late: number;
}

const hash = (s: string) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);

/** 그날 값 — 일요일은 출하 없음(null), 오늘은 지금까지 지난 약속만(대략 절반) */
export function shipDay(mfcId: string, date: string, today: string): ShipDay | null {
  if (date > today) return null;
  if (date !== today && new Date(`${date}T00:00:00Z`).getUTCDay() === 0) return null;
  const h = hash(`${mfcId}/${date}`);
  const size = 0.6 + (hash(mfcId) % 70) / 100; // 센터마다 규모 0.6~1.3
  const full = Math.round((70 + (h % 45)) * size);
  const due = date === today ? Math.round(full * 0.45) : full;
  // 늦음 1~8% — 주 중반에 조금 많게
  const wd = new Date(`${date}T00:00:00Z`).getUTCDay();
  const late = Math.min(due, Math.round(due * (0.01 + ((h >>> 7) % 6) / 100 + (wd === 5 || wd === 6 ? 0.02 : 0))));
  return { date, due, onTime: due - late, late };
}
