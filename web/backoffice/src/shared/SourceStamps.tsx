// ComposedView 의 원천·기준시각·신선도·확인 등급·미제공 원천을 숨기지 않고 보여 준다.
import type { components } from '../api/generated/backoffice-bff';
import { formatSeoul } from './format';
import { messages as m } from './messages';

type SourceStamp = components['schemas']['SourceStamp'];

interface Props {
  readonly sources: readonly SourceStamp[];
  readonly unavailableSources?: readonly string[] | undefined;
}

export function SourceStamps({ sources, unavailableSources }: Props) {
  return (
    <section aria-label={m.sources} className="flex flex-wrap items-center gap-2 text-sm">
      {sources.map((s) => {
        const freshness = s.asOf.freshness;
        return (
          <span
            key={s.system}
            data-freshness={freshness ?? 'UNAVAILABLE'}
            className={`badge ${freshness === 'CURRENT' ? 'badge-success' : 'badge-warning'}`}
          >
            {`${s.system} · ${m.confidence[s.confidence]} · ${
              freshness ? m.freshness[freshness] : m.freshness.UNAVAILABLE
            }${s.asOf.asOf ? ` · ${formatSeoul(s.asOf.asOf)}` : ''}`}
          </span>
        );
      })}
      {unavailableSources && unavailableSources.length > 0 && (
        <span className="badge badge-error">{`${m.unavailableSources}: ${unavailableSources.join(', ')}`}</span>
      )}
    </section>
  );
}
