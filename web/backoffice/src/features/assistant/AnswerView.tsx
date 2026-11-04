// 답변 표시. 모델 응답·문서 제목은 신뢰할 수 없는 텍스트 — React 텍스트 노드로만 그린다(HTML·마크다운 해석, 링크 생성 없음).
import { Link } from 'react-router';

import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { type AssistantAnswer, type Citation, isDisplayableDocRef } from './model';

function GroundingBadge({ grounding }: { readonly grounding: Citation['grounding'] }) {
  if (!grounding) return <span className="badge badge-ghost badge-sm">{m.assistant.groundingUnknown}</span>;
  const tone = grounding === 'CONFIRMED_POLICY' ? 'badge-success' : grounding === 'DESIGN_PROPOSAL' ? 'badge-warning' : 'badge-error';
  return (
    <span className={`badge badge-sm ${tone}`} data-grounding={grounding}>
      {m.assistant.grounding[grounding]}
    </span>
  );
}

function CitationItem({ c }: { readonly c: Citation }) {
  const shown = isDisplayableDocRef(c.docRef);
  return (
    <li className="rounded-box bg-base-200 p-3 text-sm" data-testid="citation">
      <div className="flex flex-wrap items-center gap-2">
        <GroundingBadge grounding={c.grounding} />
        {c.title && <span className="font-bold">{c.title}</span>}
        {shown ? (
          <code className="text-xs break-all">{c.docRef}</code>
        ) : (
          <span className="text-xs text-warning">{m.assistant.hiddenDocRef}</span>
        )}
      </div>
      <dl className="mt-1 grid grid-cols-[6rem_1fr] gap-x-2 text-xs opacity-80">
        <dt>{m.assistant.section}</dt>
        <dd>{c.section ?? m.none}</dd>
        <dt>{m.assistant.docVersion}</dt>
        <dd>{c.docVersion ?? m.none}</dd>
        <dt>{m.assistant.policyVersion}</dt>
        <dd>{c.policyVersion === null ? m.none : `v${c.policyVersion}`}</dd>
        <dt>{m.assistant.asOf}</dt>
        <dd>{c.asOf ? `${formatSeoul(c.asOf)}${c.freshness ? ` · ${c.freshness}` : ''}` : m.none}</dd>
      </dl>
    </li>
  );
}

export function AnswerView({ answer, linkToDetail = false }: { readonly answer: AssistantAnswer; readonly linkToDetail?: boolean }) {
  const idLine = linkToDetail ? (
    <Link className="link text-xs" to={`/assistant/answers/${encodeURIComponent(answer.answerId)}`}>
      {m.assistant.answerId(answer.answerId)}
    </Link>
  ) : (
    <span className="text-xs opacity-70 select-all">{m.assistant.answerId(answer.answerId)}</span>
  );

  if (answer.state === 'NO_GROUNDING') {
    return (
      <div role="status" data-state="no-grounding" className="alert alert-warning flex-col items-start">
        <span className="font-bold">{m.assistant.noGroundingTitle}</span>
        <span>{m.assistant.noGroundingBody}</span>
        {idLine}
      </div>
    );
  }
  if (answer.state === 'FORBIDDEN_SCOPE') {
    return (
      <div role="status" data-state="forbidden-scope" className="alert flex-col items-start">
        <span className="font-bold">{m.assistant.forbiddenScopeTitle}</span>
        <span>{m.assistant.forbiddenScopeBody}</span>
        {idLine}
      </div>
    );
  }

  return (
    <article data-state="answered" className="space-y-3 rounded-box bg-base-100 p-4">
      {answer.question && <p className="text-sm opacity-70 whitespace-pre-wrap">{`Q. ${answer.question}`}</p>}
      <p className="whitespace-pre-wrap break-words" data-testid="answer-text">
        {answer.answer}
      </p>
      <div className="flex flex-wrap gap-3 text-xs opacity-70">
        {idLine}
        {answer.answeredAt && <span>{formatSeoul(answer.answeredAt)}</span>}
      </div>
      <h2 className="font-bold">{m.assistant.citations}</h2>
      {answer.citations === null ? (
        <p className="text-sm text-warning">{m.assistant.citationsMissing}</p>
      ) : answer.citations.length === 0 ? (
        <p role="alert" className="alert alert-warning text-sm">
          {m.assistant.ungroundedAnswer}
        </p>
      ) : (
        <ul className="space-y-2">
          {answer.citations.map((c, i) => (
            <CitationItem key={`${c.docRef}-${i}`} c={c} />
          ))}
        </ul>
      )}
    </article>
  );
}
