// 관련 칸 한 개의 화면 표기(ADR-0070 덧붙임 2026-11-19) — 배송은 배송 번호, 주문은 주문번호, 라이더는 가린 이름 · 번호.
// 응답에 번호가 없는 화면(접수 건 상세의 refs 등)에서 시스템 ID 를 글자로 보이지 않게 그 원천에서 번호를 받아 붙인다.
import { DisplayNumber, RiderLabel } from './displayNumber';
import { useDeliveryNumber, useOrderNumbers, useRiderLabels } from './numberLookups';

export function DeliveryNo({ id }: { readonly id: string }) {
  const d = useDeliveryNumber(id);
  return <DisplayNumber number={d.number} systemId={id} failed={d.failed} />;
}

export function OrderNo({ id }: { readonly id: string }) {
  const o = useOrderNumbers([id]);
  return <DisplayNumber number={o.get(id)} systemId={id} failed={o.failed(id)} />;
}

export function RiderNo({ id }: { readonly id: string }) {
  const r = useRiderLabels([id]);
  return <RiderLabel rider={r.get(id)} riderId={id} failed={r.failed} />;
}
