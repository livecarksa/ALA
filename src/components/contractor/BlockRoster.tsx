import { useAppState } from '../../store/AppStore'
import { blockLockedCategory, blockOccupancy } from '../../store/logic'
import { ROOM_STATUS, WORKER_CATEGORIES } from '../../store/types'

export function BlockRoster() {
  const { blocks } = useAppState()

  return (
    <section className="panel" style={{ padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 16 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>كشف المربعات السكنية</h2>
        <span className="eyebrow">BLOCK ROSTER</span>
      </div>

      <div style={{ display: 'grid', gap: 12 }}>
        {blocks.map((b) => {
          const { occupants, capacity, ratio } = blockOccupancy(b)
          const locked = blockLockedCategory(b)
          return (
            <div
              key={b.id}
              style={{
                border: '1px solid var(--panel-edge)',
                borderRadius: 8,
                padding: 14,
              }}
            >
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  marginBottom: 10,
                }}
              >
                <strong style={{ fontSize: 14 }}>{b.name}</strong>
                {locked ? (
                  <span
                    className="tag"
                    style={{ color: WORKER_CATEGORIES[locked].neon, fontSize: 10 }}
                  >
                    <span className="glow-dot" />
                    {WORKER_CATEGORIES[locked].label}
                  </span>
                ) : (
                  <span className="mono" style={{ fontSize: 10, color: 'var(--ink-faint)' }}>
                    غير مُسند
                  </span>
                )}
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--ink-dim)' }}>الإشغال</span>
                <span className="mono">
                  {occupants}/{capacity} ({Math.round(ratio * 100)}٪)
                </span>
              </div>
              <div style={{ height: 6, borderRadius: 3, background: 'var(--bg-2)', overflow: 'hidden' }}>
                <div
                  style={{
                    width: `${ratio * 100}%`,
                    height: '100%',
                    background: 'linear-gradient(90deg, var(--neon-cyan), var(--neon-violet))',
                    boxShadow: '0 0 6px var(--neon-cyan)',
                  }}
                />
              </div>

              <div style={{ display: 'flex', gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
                {(['occupied', 'vacant', 'reserved', 'maintenance'] as const).map((s) => {
                  const n = b.rooms.filter((r) => r.status === s).length
                  return (
                    <span
                      key={s}
                      className="mono"
                      style={{ fontSize: 10, color: ROOM_STATUS[s].neon }}
                    >
                      {ROOM_STATUS[s].label}: {n}
                    </span>
                  )
                })}
              </div>
            </div>
          )
        })}
      </div>
    </section>
  )
}
