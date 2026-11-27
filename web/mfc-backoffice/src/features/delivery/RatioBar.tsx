// 비율 막대 — 한 줄이 100%, 칸마다 몫과 % 를 막대 안에(사용자 2026-11-27 "앞 항목은 한 바에, 바 안에 % 비율이 보이도록").
// 색은 상태 뜻(완료=success·실패=error·늦음=warning·나머지=회색)만 쓰고, 칸 이름·수는 아래 범례 글자로도 낸다(색만으로 구분하지 않음).
export type Tone = "success" | "error" | "warning" | "primary" | "rest";

export interface Part {
  readonly label: string;
  readonly value: number;
  readonly tone: Tone;
}

const FILL: Readonly<Record<Tone, string>> = {
  success: "bg-success text-success-content",
  error: "bg-error text-error-content",
  warning: "bg-warning text-warning-content",
  primary: "bg-primary text-primary-content",
  rest: "bg-base-300 text-base-content/75",
};
const DOT: Readonly<Record<Tone, string>> = {
  success: "bg-success",
  error: "bg-error",
  warning: "bg-warning",
  primary: "bg-primary",
  rest: "bg-base-300",
};

const share = (v: number, sum: number) => Math.round((v / sum) * 1000) / 10;

/** 비율 막대 한 줄 — 이름·대표 비율(왼쪽), 막대(가운데), 범례(아래). 합이 0 이면 빈 막대에 "—". */
export function RatioBar({
  title,
  headline,
  parts,
  testId,
}: {
  readonly title: string;
  readonly headline: string;
  readonly parts: readonly Part[];
  readonly testId: string;
}) {
  const sum = parts.reduce((a, p) => a + Math.max(0, p.value), 0);
  return (
    <div
      className="grid grid-cols-[8.5rem_1fr] items-center gap-x-3 gap-y-1"
      data-testid={testId}
    >
      <div className="leading-tight">
        <div className="text-xs text-base-content/60">{title}</div>
        <div className="pm-mono text-lg font-bold">{headline}</div>
      </div>
      <div
        className="flex h-7 w-full gap-0.5 overflow-hidden rounded-md bg-base-200"
        role="img"
        aria-label={`${title} ${headline} — ${parts.map((p) => `${p.label} ${p.value}`).join(", ")}`}
      >
        {sum > 0 &&
          parts
            .filter((p) => p.value > 0)
            .map((p) => {
              const w = share(p.value, sum);
              return (
                <div
                  key={p.label}
                  className={`flex min-w-0 items-center justify-center first:rounded-l-md last:rounded-r-md ${FILL[p.tone]}`}
                  style={{ width: `${w}%` }}
                  title={`${p.label} ${p.value.toLocaleString("ko-KR")} · ${w}%`}
                >
                  {/* 좁은 칸은 글자를 빼고(겹침 방지) 범례·마우스 올림으로 */}
                  {w >= 9 && (
                    <span className="truncate px-1.5 text-xs font-semibold">
                      {w}%
                    </span>
                  )}
                </div>
              );
            })}
      </div>
      <ul className="col-start-2 flex flex-wrap gap-x-3 text-xs text-base-content/65">
        {parts.map((p) => (
          <li key={p.label} className="flex items-center gap-1">
            <span
              className={`inline-block size-2 rounded-sm ${DOT[p.tone]}`}
              aria-hidden="true"
            />
            {p.label}{" "}
            <span className="pm-mono font-semibold text-base-content/85">
              {p.value.toLocaleString("ko-KR")}
            </span>
            {sum > 0 && <span>({share(p.value, sum)}%)</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}

/** 가로 막대 한 개(최댓값 대비 길이) — 실패 사유·날짜별 같은 수 비교 */
export function CountBar({
  label,
  value,
  max,
  tone = "primary",
  testId,
}: {
  readonly label: string;
  readonly value: number;
  readonly max: number;
  readonly tone?: Tone;
  readonly testId?: string;
}) {
  const w = max > 0 ? Math.max(2, (value / max) * 100) : 0;
  return (
    <div
      className="grid grid-cols-[8.5rem_1fr_3rem] items-center gap-3 text-sm"
      data-testid={testId}
    >
      <span className="truncate text-base-content/75">{label}</span>
      <div className="h-3 rounded-r bg-base-200">
        <div
          className={`h-3 rounded-r ${DOT[tone]}`}
          style={{ width: `${w}%` }}
        />
      </div>
      <span className="pm-mono text-right font-semibold">
        {value.toLocaleString("ko-KR")}
      </span>
    </div>
  );
}
