---
paths:
  - "web/**"
  - "package.json"
---

# React(관리자 웹) 규칙

## 스택
- Vite 8 + TypeScript(strict), React Router, TanStack Query, openapi-typescript + openapi-fetch, MSW, Vitest + Testing Library, Playwright.
- 스타일: Tailwind CSS 4(`@tailwindcss/vite` 플러그인, CSS 우선 설정 — `tailwind.config.js` 를 만들지 않는다) + daisyUI 5(`@plugin "daisyui";`). 테마는 daisyUI 테마 변수로 정의하고 색을 하드코딩하지 않는다.
- 요청 없이 상태관리·HTTP·UI 라이브러리를 추가하지 않는다. UI 컴포넌트는 daisyUI 하나만(다른 컴포넌트 라이브러리 병행 금지).
- 루트 `package.json` 이 npm workspaces. 패키지 매니저는 npm(lockfile 커밋).

## 구조
- `src/api`(클라이언트·명령 헬퍼·ResultResolver), `src/features/<동선>`, `src/mocks`(MSW 핸들러·픽스처), `src/shared`.
- 생성 타입(`src/api/generated`)은 수정하지 않는다.
- 서버 상태는 TanStack Query만. 서버 데이터를 전역 클라이언트 상태에 복제하지 않는다. 표 필터·정렬·페이지는 URL 쿼리에.

## 화면 규칙 (docs/apps/backoffice-web.md §1)
- `ComposedView`·`SourceStamp`·`AsOf` 를 공통 컴포넌트로 표시(원천·기준시각·신선도·미제공).
- 금지 기능 버튼을 만들지 않는다. 명령은 bff 명령 프록시 또는 계약된 도메인 명령으로만.
- 개인정보는 기본 마스킹 컴포넌트로 렌더링. 원문 열람은 사유 입력 흐름을 거친다.
- 토큰은 localStorage에 저장하지 않는다(access token은 메모리). 방식 확정은 BR-03.

## 검증
- `npm run typecheck`, `npm run lint`, `npm run test` 를 실행한 뒤 보고한다(스크립트명은 스캐폴딩 후 확정).
