// 사진 권장 규격 경고(2026-11-24 사용자 "1번으로" — 규격이 다르면 화면에서 경고만, 올리기는 막지 않는다. 서버는 형식·용량만 막는다).
// 권장 값은 고객 앱이 실제로 그리는 모양에서(1080px = 360dp): 배너 2.8:1(가운데 잘라 채움)·팝업 4:5·로딩 화면 9:16(다 보이게)·상품 대표 1:1, 가로 1080.
// 비율은 ±10% 안이면 맞는 것으로 본다. 가로가 1080 보다 작으면 흐려 보일 수 있다고 알린다.

export interface ImageSpec {
  /** 가로 ÷ 세로(없으면 비율은 보지 않는다 — 상세설명처럼 세로 자유) */
  readonly ratio?: number;
  /** 화면에 쓰는 비율 이름(2.8:1, 4:5 …) */
  readonly ratioLabel?: string;
  /** cover = 칸을 채우고 넘치는 쪽을 잘라 냄, contain = 그림을 다 보이고 남는 곳을 채움 */
  readonly fit?: 'cover' | 'contain';
  readonly minWidth: number;
}

const BANNER: ImageSpec = { ratio: 2.8, ratioLabel: '2.8:1', fit: 'cover', minWidth: 1080 };
/** 배너 자리별(storefront placement) */
export const BANNER_SPEC: Readonly<Record<string, ImageSpec>> = {
  HOME_TOP: BANNER,
  HOME_MIDDLE: BANNER,
  HOME_INLINE: BANNER,
  CATEGORY: BANNER,
  POPUP: { ratio: 4 / 5, ratioLabel: '4:5', fit: 'cover', minWidth: 1080 },
  SPLASH: { ratio: 9 / 16, ratioLabel: '9:16', fit: 'contain', minWidth: 1080 },
};
/** 상품 콘텐츠 사진 역할별 */
export const CONTENT_SPEC: Readonly<Record<string, ImageSpec>> = {
  MAIN: { ratio: 1, ratioLabel: '1:1', fit: 'cover', minWidth: 1080 },
  DESCRIPTION: { minWidth: 1080 },
  DETAIL: { minWidth: 1080 },
};

const TOLERANCE = 0.1;

/** 권장과 다른 점(없으면 null). w·h 는 그림의 실제 픽셀 */
export function fitWarning(w: number, h: number, spec: ImageSpec | undefined): string | null {
  if (!spec || !(w > 0) || !(h > 0)) return null;
  const parts: string[] = [];
  if (spec.ratio !== undefined) {
    const r = w / h;
    if (Math.abs(r - spec.ratio) / spec.ratio > TOLERANCE) {
      const how = spec.fit === 'contain' ? '남는 곳은 색으로 채워요' : r > spec.ratio ? '양옆이 잘려요' : '위아래가 잘려요';
      parts.push(`${spec.ratioLabel ?? ''}과 달라 ${how}`);
    }
  }
  if (w < spec.minWidth) parts.push(`${spec.minWidth}px보다 작아 흐릴 수 있어요`);
  return parts.length ? `${w}×${h} — ${parts.join(' · ')}` : null;
}
