// 아직 만들지 않은 메뉴 — 들어가면 "준비 중". 메뉴 화면은 delivery 영역(PC 5)이 채운다(2026-11-17 사용자 결정).
// 어떤 기능이 서버에 있고 없는지는 nav.ts 의 apiReady·apiMissing 으로 보인다.
import type { MenuItem } from '../../app/nav';
import { messages as m } from '../../shared/messages';

export function PreparingPage({ menu }: { readonly menu: MenuItem }) {
  return (
    <section className="max-w-2xl space-y-4">
      <h1 className="text-xl font-bold">{m.menus[menu.key]}</h1>
      <div role="status" className="alert">
        <div>
          <p className="font-semibold">{m.preparing.title}</p>
          <p className="text-sm">{m.preparing.body}</p>
        </div>
      </div>
      {menu.apiReady.length > 0 && (
        <div className="rounded-box bg-base-100 p-4 text-sm">
          <h2 className="mb-1 font-semibold">{m.preparing.apiReady}</h2>
          <ul className="list-disc pl-5">
            {menu.apiReady.map((f) => (
              <li key={f}>{f}</li>
            ))}
          </ul>
        </div>
      )}
      {menu.apiMissing.length > 0 && (
        <div className="rounded-box bg-base-100 p-4 text-sm" data-testid="api-missing">
          <h2 className="mb-1 font-semibold">{m.preparing.apiMissing}</h2>
          <ul className="list-disc pl-5">
            {menu.apiMissing.map((f) => (
              <li key={f}>{f}</li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
