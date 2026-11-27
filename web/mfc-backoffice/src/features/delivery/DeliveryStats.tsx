// 배송 통계 — 우리 센터(2026-11-23 사용자 "기능 넣은 거 백오피스 화면에도 나오게", PC 5 라이더 백엔드 알림).
// 원천(센터 직원은 mfcId 필수 — 그 센터 권한, 다른 센터 403, 최대 31일):
// - delivery-execution 0.38.0 `GET /delivery-metrics?from&to&mfcId` — (배정일 × 라이더) 묶음: 배정·완료·실패·지연(약속 뒤 전달 ÷ 판정)·
//   픽업 대기(가게 도착 → 픽업, MFC 에 중요)·배송 소요(픽업 → 전달), 도움요청 종류별.
// - delivery-dispatch 0.16.0 `GET /metrics/dispatch?from&to&mfcId` — 생성일별 배차 요청·배정·평균 배차 소요·재배차·제안·자동 취소, 실패 사유.
// 평균은 서버가 준 건수(*Count·assigned)로 가중해 다시 낸다(참고 web/rider-backoffice StatsPage). 조회 실패는 0 이 아니라 안내. 개인정보 없음(라이더는 번호만).
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router";

import { request } from "@pmart/web-core";
import { QueryState, toUiState } from "@pmart/web-ui";
import { useApi } from "../../app/ApiContext";
import { RiderLabel } from "../../shared/displayNumber";
import { messages } from "../../shared/messages";
import { useNow } from "../../shared/motion";
import { addDays } from "../dashboard/dashboardRules";
import { seoulToday } from "../ops/opsRules";
import { CountBar, RatioBar } from "./RatioBar";

const s = messages.deliveryStats;

type Range = "today" | "d7" | "d30";
const RANGES: readonly Range[] = ["today", "d7", "d30"];
const DAYS: Readonly<Record<Range, number>> = { today: 1, d7: 7, d30: 30 };

export interface ExecRow {
  readonly date: string;
  readonly riderId: string;
  readonly assigned: number;
  readonly completed: number;
  readonly failed: number;
  readonly late: number;
  readonly judged: number;
  readonly pickupWaitSeconds?: number | null;
  readonly pickupWaitCount: number;
  readonly deliverySeconds?: number | null;
  readonly deliveryCount: number;
}

export const pct = (num: number, den: number) =>
  den > 0 ? `${Math.round((num / den) * 1000) / 10}%` : "—";

/** 초 → "45초"·"12분"·"1시간 5분", 없으면 "—" */
export function dur(sec: number | null | undefined): string {
  if (sec === null || sec === undefined) return "—";
  const v = Math.round(sec);
  if (v < 60) return `${v}초`;
  const min = Math.round(v / 60);
  return min < 60
    ? `${min}분`
    : `${Math.floor(min / 60)}시간${min % 60 ? ` ${min % 60}분` : ""}`;
}

/** 가중 평균 — 값이 없는 묶음은 건너뛴다 */
export function wavg<T>(
  rows: readonly T[],
  value: (r: T) => number | null | undefined,
  weight: (r: T) => number,
): number | null {
  let sum = 0;
  let w = 0;
  for (const r of rows) {
    const v = value(r);
    const k = weight(r);
    if (v === null || v === undefined || k <= 0) continue;
    sum += v * k;
    w += k;
  }
  return w > 0 ? sum / w : null;
}
const total = <T,>(rows: readonly T[], f: (r: T) => number) =>
  rows.reduce((a, r) => a + f(r), 0);

export function agg(rows: readonly ExecRow[]) {
  return {
    assigned: total(rows, (r) => r.assigned),
    completed: total(rows, (r) => r.completed),
    failed: total(rows, (r) => r.failed),
    late: total(rows, (r) => r.late),
    judged: total(rows, (r) => r.judged),
    pickupWait: wavg(
      rows,
      (r) => r.pickupWaitSeconds,
      (r) => r.pickupWaitCount,
    ),
    pickupWaitCount: total(rows, (r) => r.pickupWaitCount),
    delivery: wavg(
      rows,
      (r) => r.deliverySeconds,
      (r) => r.deliveryCount,
    ),
    deliveryCount: total(rows, (r) => r.deliveryCount),
    riders: new Set(rows.map((r) => r.riderId)).size,
  };
}

function groupBy<T>(
  rows: readonly T[],
  key: (r: T) => string,
): [string, T[]][] {
  const m = new Map<string, T[]>();
  for (const r of rows) {
    const k = key(r);
    const list = m.get(k);
    if (list) list.push(r);
    else m.set(k, [r]);
  }
  return [...m.entries()];
}

function Tile({
  label,
  value,
  hint,
  testId,
  warn = false,
}: {
  readonly label: string;
  readonly value: string;
  readonly hint?: string | undefined;
  readonly testId: string;
  readonly warn?: boolean;
}) {
  return (
    <div
      className="rounded-box border border-base-300 bg-base-100 px-3 py-2.5"
      data-testid={testId}
    >
      <dt className="text-xs text-base-content/60">{label}</dt>
      <dd className={`pm-mono text-xl font-bold ${warn ? "text-warning" : ""}`}>
        {value}
      </dd>
      {hint && <dd className="text-xs text-base-content/55">{hint}</dd>}
    </div>
  );
}

function DailyChart({
  daily,
}: {
  readonly daily: readonly (readonly [string, readonly ExecRow[]])[];
}) {
  const xs = daily.map(([day, rs]) => [day, agg(rs)] as const);
  const max = Math.max(...xs.map(([, x]) => x.assigned));
  const w = (v: number) => `${max > 0 ? (v / max) * 100 : 0}%`;
  return (
    <div
      className="space-y-1.5 rounded-box border border-base-300 bg-base-100 p-4"
      data-testid="stats-daily-chart"
    >
      {xs.map(([day, x]) => {
        const rest = Math.max(0, x.assigned - x.completed - x.failed);
        return (
          <div
            key={day}
            className="grid grid-cols-[4rem_1fr_3rem] items-center gap-3 text-sm"
            title={`${day} — ${s.part.completed} ${x.completed} · ${s.part.failed} ${x.failed} · ${s.part.other} ${rest}`}
          >
            <span className="pm-mono text-base-content/70">{day.slice(5)}</span>
            <div className="flex h-4 gap-0.5">
              {x.completed > 0 && (
                <div
                  className="rounded-l bg-success"
                  style={{ width: w(x.completed) }}
                />
              )}
              {x.failed > 0 && (
                <div className="bg-error" style={{ width: w(x.failed) }} />
              )}
              {rest > 0 && (
                <div
                  className="rounded-r bg-base-300"
                  style={{ width: w(rest) }}
                />
              )}
            </div>
            <span className="pm-mono text-right font-semibold">
              {x.assigned}
            </span>
          </div>
        );
      })}
      <ul className="flex gap-3 pt-1 text-xs text-base-content/65">
        {(
          [
            [s.part.completed, "bg-success"],
            [s.part.failed, "bg-error"],
            [s.part.other, "bg-base-300"],
          ] as const
        ).map(([l, c]) => (
          <li key={l} className="flex items-center gap-1">
            <span
              className={`inline-block size-2 rounded-sm ${c}`}
              aria-hidden="true"
            />
            {l}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function DeliveryStats({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const range: Range = (RANGES as readonly string[]).includes(
    params.get("range") ?? "",
  )
    ? (params.get("range") as Range)
    : "d7";
  // 날짜는 1분마다 다시 본다(자정을 넘기면 기간이 밀린다) — 렌더 중 시계를 직접 읽지 않는다
  const to = seoulToday(useNow(60_000));
  const from = addDays(to, -(DAYS[range] - 1));
  const q = { from, to, mfcId };
  const exec = useQuery({
    queryKey: ["delivery-stats", "exec", mfcId, from, to],
    queryFn: () =>
      request(
        "GET",
        api.execution.GET("/delivery-metrics", { params: { query: q } }),
      ),
  });
  const disp = useQuery({
    queryKey: ["delivery-stats", "dispatch", mfcId, from, to],
    queryFn: () =>
      request(
        "GET",
        api.dispatch.GET("/metrics/dispatch", { params: { query: q } }),
      ),
  });
  // 다른 센터 줄은 쓰지 않는다(서버가 이 센터만 주지만 한 번 더)
  const rows: readonly ExecRow[] = (exec.data?.rows ?? []).filter(
    (r) => r.mfcId === mfcId,
  );
  const drows = (disp.data?.rows ?? []).filter((r) => r.mfcId === mfcId);
  const a = agg(rows);
  const dCreated = total(drows, (r) => r.created);
  const dAssigned = total(drows, (r) => r.assigned);
  const dAvgAssign = wavg(
    drows,
    (r) => r.avgAssignSeconds,
    (r) => r.assigned,
  );
  const dReassigned = total(drows, (r) => r.reassigned);
  const dSent = total(drows, (r) => r.offersSent);
  const dAccepted = total(drows, (r) => r.offersAccepted);
  const daily = groupBy(rows, (r) => r.date).sort(([x], [y]) =>
    y.localeCompare(x),
  );
  const dispByDay = new Map(groupBy(drows, (r) => r.date));
  const byRider = groupBy(rows, (r) => r.riderId).sort(
    ([, x], [, y]) => total(y, (r) => r.assigned) - total(x, (r) => r.assigned),
  );
  const incidents = exec.data?.incidents ?? [];

  return (
    <section className="space-y-4" data-testid="delivery-stats">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-base-content/65">{s.intro}</p>
        <div
          className="pm-seg"
          role="group"
          aria-label={s.rangeLabel}
          data-testid="stats-range"
        >
          {RANGES.map((k) => (
            <button
              key={k}
              type="button"
              aria-pressed={range === k}
              onClick={() =>
                setParams(
                  (p) => {
                    const n = new URLSearchParams(p);
                    n.set("range", k);
                    return n;
                  },
                  { replace: true },
                )
              }
            >
              {s.range[k]}
            </button>
          ))}
        </div>
      </div>
      {/* 배송 통계(execution)를 못 읽으면 숫자 0 대신 안내 — 조회 실패 ≠ 0 */}
      <QueryState state={toUiState(exec)} onRetry={() => void exec.refetch()}>
        {() => (
          <>
            {/* 배송 품질 — 비율 세 가지를 한 차트에, 막대 안에 % (사용자 2026-11-27) */}
            <section
              className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
              aria-label={s.quality}
              data-testid="stats-quality"
            >
              <h2 className="text-base font-bold">{s.quality}</h2>
              <RatioBar
                title={s.tile.completion}
                headline={pct(a.completed, a.completed + a.failed)}
                parts={[
                  {
                    label: s.part.completed,
                    value: a.completed,
                    tone: "success",
                  },
                  { label: s.part.failed, value: a.failed, tone: "error" },
                ]}
                testId="tile-completion"
              />
              <RatioBar
                title={s.tile.late}
                headline={pct(a.late, a.judged)}
                parts={[
                  {
                    label: s.part.onTime,
                    value: Math.max(0, a.judged - a.late),
                    tone: "primary",
                  },
                  { label: s.part.late, value: a.late, tone: "warning" },
                ]}
                testId="tile-late"
              />
              <RatioBar
                title={s.tile.failure}
                headline={pct(a.failed, a.assigned)}
                parts={[
                  {
                    label: s.part.completed,
                    value: a.completed,
                    tone: "success",
                  },
                  { label: s.part.failed, value: a.failed, tone: "error" },
                  {
                    label: s.part.other,
                    value: Math.max(0, a.assigned - a.completed - a.failed),
                    tone: "rest",
                  },
                ]}
                testId="tile-failure"
              />
            </section>
            <dl
              className="grid grid-cols-2 gap-2 md:grid-cols-4"
              aria-label={s.efficiency}
              data-testid="stats-efficiency"
            >
              <Tile
                label={s.tile.riders}
                value={s.count(a.riders, "명")}
                hint={s.hint.deliveries(a.assigned)}
                testId="tile-riders"
              />
              <Tile
                label={s.tile.pickupWait}
                value={dur(a.pickupWait)}
                hint={s.hint.avgOf(a.pickupWaitCount)}
                warn={(a.pickupWait ?? 0) > 600}
                testId="tile-pickup-wait"
              />
              <Tile
                label={s.tile.delivery}
                value={dur(a.delivery)}
                hint={s.hint.avgOf(a.deliveryCount)}
                testId="tile-delivery"
              />
              <Tile
                label={s.tile.assign}
                value={disp.isError ? s.failed : dur(dAvgAssign)}
                hint={disp.isError ? undefined : s.hint.avgOf(dAssigned)}
                testId="tile-assign"
              />
            </dl>
          </>
        )}
      </QueryState>

      <section
        className="space-y-2 rounded-box border border-base-300 bg-base-100 p-4"
        aria-label={s.dispatch}
        data-testid="stats-dispatch"
      >
        <h2 className="text-base font-bold">{s.dispatch}</h2>
        {disp.isError ? (
          <p role="alert" className="text-sm font-semibold text-error">
            {s.dispatchFailed}
          </p>
        ) : disp.isPending ? (
          <p className="text-sm text-base-content/40">…</p>
        ) : (
          <>
            <div className="space-y-3">
              <RatioBar
                title={s.tile.assignRate}
                headline={pct(dAssigned, dCreated)}
                parts={[
                  { label: s.part.assigned, value: dAssigned, tone: "primary" },
                  {
                    label: s.part.notAssigned,
                    value: Math.max(0, dCreated - dAssigned),
                    tone: "rest",
                  },
                ]}
                testId="tile-assign-rate"
              />
              <RatioBar
                title={s.tile.reassign}
                headline={pct(dReassigned, dCreated)}
                parts={[
                  {
                    label: s.part.firstTry,
                    value: Math.max(0, dCreated - dReassigned),
                    tone: "rest",
                  },
                  {
                    label: s.part.reassigned,
                    value: dReassigned,
                    tone: "warning",
                  },
                ]}
                testId="tile-reassign"
              />
              <RatioBar
                title={s.tile.accept}
                headline={pct(dAccepted, dSent)}
                parts={[
                  { label: s.part.accepted, value: dAccepted, tone: "primary" },
                  {
                    label: s.part.notAccepted,
                    value: Math.max(0, dSent - dAccepted),
                    tone: "rest",
                  },
                ]}
                testId="tile-accept"
              />
            </div>
            <dl className="grid grid-cols-2 gap-2 md:grid-cols-4">
              <Tile
                label={s.tile.autoCancel}
                value={s.count(
                  total(drows, (r) => r.autoCancelled),
                  "건",
                )}
                testId="tile-auto-cancel"
              />
            </dl>
            <p
              className="text-xs text-base-content/60"
              data-testid="stats-source"
            >
              {s.source(
                total(drows, (r) => r.assignedByAi),
                total(drows, (r) => r.assignedByList),
                total(drows, (r) => r.assignedByFailedReturn),
              )}
            </p>
            {(disp.data?.failureReasons ?? []).length > 0 && (
              <div
                className="space-y-1.5"
                aria-label={s.failureReasons}
                data-testid="stats-failure-reasons"
              >
                <h3 className="text-xs text-base-content/60">
                  {s.failureReasons}
                </h3>
                {(disp.data?.failureReasons ?? []).map((x, _, all) => (
                  <CountBar
                    key={x.reason}
                    label={s.reason[x.reason] ?? x.reason}
                    value={x.rounds}
                    max={Math.max(...all.map((y) => y.rounds))}
                    tone="error"
                  />
                ))}
              </div>
            )}
          </>
        )}
      </section>

      {exec.isSuccess &&
        (rows.length === 0 ? (
          <p className="text-sm text-base-content/60" data-testid="stats-empty">
            {s.empty}
          </p>
        ) : (
          <>
            <section className="space-y-2" aria-label={s.daily}>
              <h2 className="text-base font-bold">{s.daily}</h2>
              {/* 날짜별 배송 수 — 막대 길이는 가장 많은 날 대비, 안은 완료·실패·그 밖 */}
              {daily.length > 1 && <DailyChart daily={daily} />}
              <div className="overflow-x-auto">
                <table
                  className="table table-sm rounded-box bg-base-100"
                  data-testid="stats-daily-table"
                >
                  <thead>
                    <tr>
                      <th>{s.col.date}</th>
                      <th>{s.col.requests}</th>
                      <th>{s.col.assign}</th>
                      <th>{s.col.deliveries}</th>
                      <th>{s.col.completed}</th>
                      <th>{s.col.failed}</th>
                      <th>{s.col.late}</th>
                      <th>{s.col.pickupWait}</th>
                      <th>{s.col.delivery}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {daily.map(([day, rs]) => {
                      const x = agg(rs);
                      const dd = dispByDay.get(day) ?? [];
                      return (
                        <tr key={day} data-testid="stats-day-row">
                          <td className="whitespace-nowrap">{day}</td>
                          <td>
                            {disp.isError
                              ? s.failed
                              : total(dd, (r) => r.created)}
                          </td>
                          <td>
                            {disp.isError
                              ? s.failed
                              : dur(
                                  wavg(
                                    dd,
                                    (r) => r.avgAssignSeconds,
                                    (r) => r.assigned,
                                  ),
                                )}
                          </td>
                          <td>{x.assigned}</td>
                          <td>{x.completed}</td>
                          <td>{x.failed}</td>
                          <td>{pct(x.late, x.judged)}</td>
                          <td>{dur(x.pickupWait)}</td>
                          <td>{dur(x.delivery)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
            <section className="space-y-2" aria-label={s.byRider}>
              <h2 className="text-base font-bold">{s.byRider}</h2>
              <div className="overflow-x-auto">
                <table
                  className="table table-sm rounded-box bg-base-100"
                  data-testid="stats-rider-table"
                >
                  <thead>
                    <tr>
                      <th>{s.col.rider}</th>
                      <th>{s.col.deliveries}</th>
                      <th>{s.col.completed}</th>
                      <th>{s.col.failed}</th>
                      <th>{s.col.completion}</th>
                      <th>{s.col.late}</th>
                      <th>{s.col.pickupWait}</th>
                      <th>{s.col.delivery}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {byRider.map(([rider, rs]) => {
                      const x = agg(rs);
                      return (
                        <tr key={rider} data-testid="stats-rider-row">
                          <td>
                            <RiderLabel riderId={rider} />
                          </td>
                          <td>{x.assigned}</td>
                          <td>{x.completed}</td>
                          <td>{x.failed}</td>
                          <td>
                            {/* 완료율 — 숫자 옆 짧은 막대 */}
                            <span className="flex items-center gap-2">
                              <span className="pm-mono w-12">
                                {pct(x.completed, x.completed + x.failed)}
                              </span>
                              <span className="h-2 w-16 rounded-full bg-base-200">
                                <span
                                  className="block h-2 rounded-full bg-success"
                                  style={{
                                    width: `${x.completed + x.failed > 0 ? (x.completed / (x.completed + x.failed)) * 100 : 0}%`,
                                  }}
                                />
                              </span>
                            </span>
                          </td>
                          <td>{pct(x.late, x.judged)}</td>
                          <td>{dur(x.pickupWait)}</td>
                          <td>{dur(x.delivery)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        ))}

      {exec.isSuccess && (
        <section className="space-y-2" aria-label={s.incidents}>
          <h2 className="text-base font-bold">{s.incidents}</h2>
          {incidents.length === 0 ? (
            <p className="text-sm text-base-content/60">{s.noIncidents}</p>
          ) : (
            <table
              className="table table-sm rounded-box bg-base-100"
              data-testid="stats-incident-table"
            >
              <thead>
                <tr>
                  <th>{s.col.category}</th>
                  <th>{s.col.count}</th>
                  <th>{s.col.resolved}</th>
                  <th>{s.col.resolve}</th>
                </tr>
              </thead>
              <tbody>
                {incidents.map((x) => (
                  <tr key={x.category} data-testid="stats-incident-row">
                    <td>{s.helpCategory[x.category] ?? x.category}</td>
                    <td>{x.count}</td>
                    <td>{x.resolved}</td>
                    <td>{dur(x.resolveSeconds)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}
      <p className="text-xs text-base-content/50">{s.definitions}</p>
    </section>
  );
}
