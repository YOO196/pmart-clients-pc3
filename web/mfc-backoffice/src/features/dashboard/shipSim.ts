// 출하 약속 준수율 — ⚠ 목 모드(env.isMock)에서만 쓰는 시뮬레이션(2026-11-24 사용자 "정시율 대신 센터가 움직일 수 있는 지표, 목으로 먼저").
// 뜻: 출하 약속 시각이 지난 작업(포장·인계) 중 약속 안에 인계까지 끝낸 비율. 날짜 = 출하 약속 날짜(한국).
// 계약에 이 지표 API 가 없다 — 요청 handoff mfc-backoffice/2026-11-24-backend-ship-promise-metrics. 실서버에서는 부르지 않고 "API 없음"을 보인다.
// API 가 생기면 이 파일은 mocks/ 로 옮기고 화면은 서버 값만 쓴다.

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
