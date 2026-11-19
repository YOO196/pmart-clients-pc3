// 번호 또는 ID 입력 칸(2026-11-19 사용자 "주문·라이더·배달 ID 같은 난수를 일일이 확인 안 하고 불러올 방법").
// 화면에 보이는 번호(배송 74939255-1 · 주문 74939255 · 라이더 123456)를 넣으면 서버에서 찾아 칸 아래에 바로 알린다.
// 예전처럼 시스템 ID 를 넣어도 된다. 찾지 못했거나 조회가 실패하면 그렇다고 보이고 다른 값으로 바꾸지 않는다.
import type { useResolvedRef } from './numberLookups';
import { messages } from './messages';

const m = messages.refField;

export function RefStatus({ r, kind }: { readonly r: ReturnType<typeof useResolvedRef>; readonly kind: 'delivery' | 'rider' | 'order' | 'case' }) {
  if (r.state === 'empty' || r.state === 'id') return null;
  const tone = r.state === 'found' ? 'text-success' : r.state === 'loading' ? 'text-base-content/50' : 'text-warning';
  const text = r.state === 'found' ? m.found(m.kind[kind], r.value) : r.state === 'loading' ? m.loading : r.state === 'notFound' ? m.notFound(m.kind[kind], r.value) : m.failed;
  return (
    <span className={`text-xs ${tone}`} role="status" data-testid={`ref-status-${kind}`} data-state={r.state}>
      {text}
    </span>
  );
}
