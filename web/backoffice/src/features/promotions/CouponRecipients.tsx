// 쿠폰 받을 고객 고르기(2026-11-24 사용자 "직원 지정 발급을 눌러도 고객 id 를 넣는다던가 찾는 칸 자체가 없는데") —
// 고객 ID 를 손으로 붙여 넣던 칸 대신, 고객번호·전화·주문번호로 찾아(bff /views/customer-search — 고객 메뉴와 같은 완전 일치) 목록에 더한다.
// 찾은 고객은 가린 이름·번호만 보인다. 고객 찾기 권한이 없는 역할(마케팅 — 계약상 CS_AGENT·OPERATOR_ADMIN 만)은 403 → ID 직접 넣기로.
import { ProblemFailure, request } from '@pmart/web-core';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';

import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { isCustomerNumber, isOrderNumber } from '../../shared/numberLookups';

const m = messages.promotions.grant.pick;
const BY = ['customerNumber', 'phone', 'orderNumber'] as const;
type By = (typeof BY)[number];

export interface Recipient {
  readonly id: string;
  /** 화면 표시(가린 이름 · 고객번호) — ID 로 직접 넣었으면 없음 */
  readonly label?: string;
}

export function CouponRecipients({ value, onChange, disabled, max }: { readonly value: readonly Recipient[]; readonly onChange: (next: Recipient[]) => void; readonly disabled: boolean; readonly max: number }) {
  const api = useApi();
  const [by, setBy] = useState<By>('customerNumber');
  const [text, setText] = useState('');
  const [asked, setAsked] = useState<{ by: By; value: string } | null>(null);
  const bad = text.trim() !== '' && (by === 'customerNumber' ? !isCustomerNumber(text) : by === 'orderNumber' ? !isOrderNumber(text) : false);
  const q = useQuery({
    queryKey: ['customers', 'search', asked?.by, asked?.value],
    enabled: asked !== null,
    retry: false,
    queryFn: () => request('GET', api.bff.GET('/views/customer-search', { params: { query: asked ? { [asked.by]: asked.by === 'customerNumber' ? asked.value : asked.value.replace(/[\s-]/g, '') } : {} } })),
  });
  const has = (id: string) => value.some((r) => r.id === id);
  const add = (r: Recipient) => {
    if (!has(r.id) && value.length < max) onChange([...value, r]);
  };
  const forbidden = q.error instanceof ProblemFailure && q.error.problem.status === 403;
  return (
    <div className="space-y-2" data-testid="grant-recipients">
      <form
        className="flex flex-wrap items-end gap-2"
        aria-label={m.title}
        onSubmit={(e) => {
          e.preventDefault();
          if (text.trim() && !bad) setAsked({ by, value: text.trim() });
        }}
      >
        <label className="flex flex-col gap-1 text-xs font-medium text-base-content/60">
          {m.by}
          <select className="select select-sm w-32" value={by} disabled={disabled} onChange={(e) => setBy(BY.find((x) => x === e.target.value) ?? 'customerNumber')}>
            {BY.map((x) => (
              <option key={x} value={x}>
                {m.byName[x]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-base-content/60">
          {m.value}
          <input className={`input input-sm w-52 ${bad ? 'input-error' : ''}`} inputMode="numeric" maxLength={by === 'phone' ? 20 : 16} placeholder={m.placeholder[by]} value={text} disabled={disabled} onChange={(e) => setText(e.target.value)} />
        </label>
        <button type="submit" className="btn btn-sm" disabled={disabled || !text.trim() || bad}>
          {m.find}
        </button>
        {bad && <p className="w-full text-xs text-error">{m.badFormat[by]}</p>}
      </form>
      {asked && (
        <div className="rounded-box border border-base-300 bg-base-100 px-3 py-2 text-sm" data-testid="grant-search-result" aria-live="polite">
          {q.isPending ? (
            <p className="text-base-content/60">{m.searching}</p>
          ) : forbidden ? (
            <p className="text-warning">{m.forbidden}</p>
          ) : q.isError ? (
            <p className="text-error">{m.failed}</p>
          ) : q.data.items.length === 0 ? (
            <p className="text-base-content/60">{(q.data.unavailableSources?.length ?? 0) > 0 ? m.unavailable : m.none}</p>
          ) : (
            <ul className="divide-y divide-base-200">
              {q.data.items.map((c) => {
                const label = [c.nameMasked, c.customerNumber].filter(Boolean).join(' · ') || c.customerId;
                return (
                  <li key={c.customerId} className="flex items-center justify-between gap-3 py-1.5" data-testid="grant-search-item">
                    <span>
                      <span className="font-medium">{label}</span>
                      {c.phoneMasked && <span className="ml-2 text-xs text-base-content/55">{c.phoneMasked}</span>}
                    </span>
                    <button type="button" className="btn btn-xs" disabled={disabled || has(c.customerId) || value.length >= max} onClick={() => add({ id: c.customerId, label })}>
                      {has(c.customerId) ? m.added : m.add}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
      {/* 고른 고객 */}
      <div className="flex flex-wrap items-center gap-1.5" data-testid="grant-picked">
        <span className="text-xs text-base-content/60">{m.picked(value.length, max)}</span>
        {value.map((r) => (
          <span key={r.id} className="inline-flex items-center gap-1 rounded-full border border-base-300 bg-base-100 py-0.5 pl-2.5 pr-1 text-xs" data-testid="grant-picked-item">
            <span className={r.label ? '' : 'font-mono'}>{r.label ?? r.id}</span>
            <button type="button" className="btn btn-ghost btn-xs h-5 min-h-0 w-5 p-0" aria-label={m.remove(r.label ?? r.id)} disabled={disabled} onClick={() => onChange(value.filter((x) => x.id !== r.id))}>
              ✕
            </button>
          </span>
        ))}
      </div>
    </div>
  );
}
