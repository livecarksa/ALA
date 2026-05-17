import { QrCanvas } from './QrCanvas'
import { useCountdown } from '../../hooks/useCountdown'
import { useAppDispatch } from '../../store/AppStore'
import { WORKER_CATEGORIES, type Permit } from '../../store/types'

function fmt(sec: number): string {
  if (!isFinite(sec)) return '∞'
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

export function TempPermitCard({ permit }: { permit: Permit }) {
  const dispatch = useAppDispatch()
  const { remaining, expired } = useCountdown(permit.expiresAt)
  const cat = WORKER_CATEGORIES[permit.category]

  const total = permit.expiresAt ? (permit.expiresAt - permit.issuedAt) / 1000 : 1
  const ratio = expired ? 0 : Math.min(remaining / total, 1)
  const critical = !expired && remaining <= 10

  const payload = `ALA|TEMP|${permit.id}|${permit.holder}|${permit.category}|blk:${permit.blockId}|exp:${permit.expiresAt}`

  return (
    <div
      className="panel"
      style={{
        padding: 14,
        display: 'flex',
        gap: 14,
        alignItems: 'center',
        // فور وصول المؤقت للصفر تُعطّل واجهة العرض بصرياً
        opacity: expired ? 0.45 : 1,
        borderColor: expired
          ? 'var(--panel-edge)'
          : critical
            ? 'var(--neon-rose)'
            : 'var(--panel-edge)',
        boxShadow: critical ? '0 0 0 1px rgba(244,63,94,0.3)' : 'none',
        transition: 'opacity 0.3s ease, border-color 0.3s ease',
      }}
    >
      <QrCanvas value={payload} size={92} active={!expired} />

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <strong style={{ fontSize: 14 }}>{permit.holder}</strong>
          <span className="tag" style={{ color: cat.neon, fontSize: 10 }}>
            <span className="glow-dot" />
            {cat.label}
          </span>
        </div>
        <div className="mono" style={{ fontSize: 11, color: 'var(--ink-dim)' }}>
          {permit.id} · مربع {permit.blockId}
        </div>

        <div style={{ marginTop: 10 }}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              fontSize: 12,
              marginBottom: 5,
            }}
          >
            <span style={{ color: expired ? 'var(--neon-rose)' : 'var(--ink-dim)' }}>
              {expired ? 'انتهى التصريح — العرض مُعطّل' : 'الوقت المتبقي'}
            </span>
            <span
              className="mono"
              style={{
                color: expired
                  ? 'var(--neon-rose)'
                  : critical
                    ? 'var(--neon-rose)'
                    : 'var(--neon-cyan)',
                fontWeight: 700,
              }}
            >
              {expired ? 'EXPIRED' : fmt(remaining)}
            </span>
          </div>
          <div
            style={{
              height: 5,
              borderRadius: 3,
              background: 'var(--bg-2)',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                width: `${ratio * 100}%`,
                height: '100%',
                background: critical
                  ? 'var(--neon-rose)'
                  : 'linear-gradient(90deg, var(--neon-cyan), var(--neon-violet))',
                boxShadow: critical ? '0 0 8px var(--neon-rose)' : '0 0 6px var(--neon-cyan)',
                transition: 'width 0.5s linear',
              }}
            />
          </div>
        </div>
      </div>

      <button
        onClick={() => dispatch({ type: 'REVOKE_PERMIT', permitId: permit.id })}
        title="إلغاء التصريح"
        style={{ padding: '7px 10px', fontSize: 12, alignSelf: 'flex-start' }}
      >
        ✕
      </button>
    </div>
  )
}
