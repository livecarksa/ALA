import { useEffect, useRef } from 'react'
import { useAppState } from '../../store/AppStore'
import { blockEnergyKw, blockOccupancy } from '../../store/logic'

export function EnergyMonitor() {
  const { blocks, gridLoadKw, fieldShiftActive } = useAppState()
  const historyRef = useRef<number[]>([])

  // سجلّ متحرّك لآخر القراءات لرسم منحنى الحمل اللحظي
  useEffect(() => {
    const h = historyRef.current
    h.push(gridLoadKw)
    if (h.length > 48) h.shift()
  }, [gridLoadKw])

  const hist = historyRef.current
  const max = Math.max(...hist, 10)

  return (
    <section className="panel" style={{ padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 14 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>استهلاك الطاقة اللحظي</h2>
        <span className="eyebrow">GRID LOAD</span>
        <div style={{ flex: 1 }} />
        <span
          className="mono"
          style={{
            fontSize: 22,
            color: fieldShiftActive ? 'var(--neon-violet)' : 'var(--neon-cyan)',
            textShadow: '0 0 14px currentColor',
          }}
        >
          {gridLoadKw.toFixed(1)} <span style={{ fontSize: 12 }}>ك.و</span>
        </span>
      </div>

      <svg
        viewBox="0 0 480 110"
        preserveAspectRatio="none"
        style={{ width: '100%', height: 110, display: 'block' }}
      >
        <defs>
          <linearGradient id="loadFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="rgba(34,211,238,0.35)" />
            <stop offset="100%" stopColor="rgba(34,211,238,0)" />
          </linearGradient>
        </defs>
        {[0.25, 0.5, 0.75].map((g) => (
          <line
            key={g}
            x1="0"
            x2="480"
            y1={110 * g}
            y2={110 * g}
            stroke="rgba(120,160,200,0.08)"
            strokeWidth="1"
          />
        ))}
        {hist.length > 1 && (
          <>
            <polygon
              fill="url(#loadFill)"
              points={
                `0,110 ` +
                hist
                  .map((v, i) => `${(i / (hist.length - 1)) * 480},${110 - (v / max) * 100}`)
                  .join(' ') +
                ` 480,110`
              }
            />
            <polyline
              fill="none"
              stroke="var(--neon-cyan)"
              strokeWidth="1.6"
              style={{ filter: 'drop-shadow(0 0 4px var(--neon-cyan))' }}
              points={hist
                .map((v, i) => `${(i / (hist.length - 1)) * 480},${110 - (v / max) * 100}`)
                .join(' ')}
            />
          </>
        )}
      </svg>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: `repeat(${blocks.length}, 1fr)`,
          gap: 12,
          marginTop: 16,
        }}
      >
        {blocks.map((b) => {
          const e = blockEnergyKw(b)
          const { ratio } = blockOccupancy(b)
          return (
            <div key={b.id} style={{ fontSize: 12 }}>
              <div
                style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}
              >
                <span style={{ color: 'var(--ink-dim)' }}>{b.name}</span>
                <span className="mono">{e.toFixed(1)} ك.و</span>
              </div>
              <div
                style={{
                  height: 6,
                  borderRadius: 3,
                  background: 'var(--bg-2)',
                  overflow: 'hidden',
                }}
              >
                <div
                  style={{
                    width: `${Math.min(ratio * 100, 100)}%`,
                    height: '100%',
                    background:
                      'linear-gradient(90deg, var(--neon-cyan), var(--neon-violet))',
                    boxShadow: '0 0 8px var(--neon-cyan)',
                    transition: 'width 0.4s ease',
                  }}
                />
              </div>
            </div>
          )
        })}
      </div>
    </section>
  )
}
