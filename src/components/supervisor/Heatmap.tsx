import { useState } from 'react'
import { useAppState } from '../../store/AppStore'
import { ROOM_STATUS, WORKER_CATEGORIES, type Room } from '../../store/types'

// لون الخلية يعكس كثافة الحشد (نسبة الإشغال)، والوهج يعكس استهلاك الطاقة اللحظي.
function densityColor(ratio: number): string {
  if (ratio === 0) return 'rgba(40, 56, 70, 0.45)'
  const stops: [number, string][] = [
    [0.25, 'rgba(34, 211, 238, '],
    [0.5, 'rgba(163, 230, 53, '],
    [0.75, 'rgba(245, 158, 11, '],
    [1.01, 'rgba(244, 63, 94, '],
  ]
  const base = stops.find(([t]) => ratio <= t)?.[1] ?? 'rgba(244, 63, 94, '
  return `${base}${(0.28 + ratio * 0.6).toFixed(2)})`
}

function RoomCell({ room }: { room: Room }) {
  const ratio = room.capacity === 0 ? 0 : room.occupants / room.capacity
  const isMaint = room.status === 'maintenance'
  const energyGlow = Math.min(room.energyKw / 4, 1)

  return (
    <div
      title={`${room.id} · ${ROOM_STATUS[room.status].label} · ${room.occupants}/${room.capacity} نزيل · ${room.energyKw.toFixed(2)} ك.و`}
      style={{
        position: 'relative',
        aspectRatio: '1 / 1',
        borderRadius: 6,
        border: '1px solid var(--panel-edge)',
        background: isMaint
          ? 'repeating-linear-gradient(45deg, rgba(245,158,11,0.12) 0 6px, transparent 6px 12px)'
          : densityColor(ratio),
        boxShadow:
          room.occupants > 0
            ? `inset 0 0 12px rgba(0,0,0,0.5), 0 0 ${4 + energyGlow * 14}px rgba(34,211,238,${0.1 +
                energyGlow * 0.35})`
            : 'inset 0 0 8px rgba(0,0,0,0.4)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 10,
        fontFamily: 'var(--mono)',
        color: ratio > 0.5 ? '#05070a' : 'var(--ink-dim)',
        cursor: 'default',
      }}
    >
      {isMaint ? '⚠' : room.occupants > 0 ? room.occupants : ''}
    </div>
  )
}

export function Heatmap() {
  const { blocks } = useAppState()
  const [hoverBlock, setHoverBlock] = useState<string | null>(null)

  return (
    <section className="panel" style={{ padding: 20 }}>
      <div className="scanline" />
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 4 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>الخريطة الحرارية — كثافة الحشود</h2>
        <span className="eyebrow">DENSITY · LIVE</span>
      </div>
      <p style={{ color: 'var(--ink-dim)', fontSize: 12, marginBottom: 18 }}>
        كل خلية تمثّل غرفة؛ تدرّج اللون يعكس كثافة الإشغال ووهج النيون يعكس استهلاك الطاقة اللحظي.
      </p>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: `repeat(${blocks.length}, 1fr)`,
          gap: 16,
        }}
      >
        {blocks.map((b) => {
          const occ = b.rooms.reduce((s, r) => s + r.occupants, 0)
          const cap = b.rooms.reduce((s, r) => s + r.capacity, 0)
          const lockedCat = b.rooms.find((r) => r.occupants > 0 && r.category)?.category ?? null
          return (
            <div
              key={b.id}
              onMouseEnter={() => setHoverBlock(b.id)}
              onMouseLeave={() => setHoverBlock(null)}
              style={{
                border: '1px solid var(--panel-edge)',
                borderRadius: 8,
                padding: 12,
                background:
                  hoverBlock === b.id ? 'rgba(34,211,238,0.04)' : 'rgba(255,255,255,0.012)',
                transition: 'background 0.15s ease',
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
                <strong style={{ fontSize: 13 }}>{b.name}</strong>
                <span className="mono" style={{ fontSize: 11, color: 'var(--ink-dim)' }}>
                  {occ}/{cap}
                </span>
              </div>
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(3, 1fr)',
                  gap: 6,
                }}
              >
                {b.rooms.map((r) => (
                  <RoomCell key={r.id} room={r} />
                ))}
              </div>
              <div style={{ marginTop: 10, fontSize: 11 }}>
                {lockedCat ? (
                  <span
                    className="tag"
                    style={{ color: WORKER_CATEGORIES[lockedCat].neon, fontSize: 10 }}
                  >
                    <span className="glow-dot" />
                    {WORKER_CATEGORIES[lockedCat].label}
                  </span>
                ) : (
                  <span className="mono" style={{ color: 'var(--ink-faint)', fontSize: 10 }}>
                    مربع غير مُسند
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>

      <div style={{ display: 'flex', gap: 16, marginTop: 18, flexWrap: 'wrap' }}>
        {[
          ['منخفضة', 'rgba(34,211,238,0.6)'],
          ['متوسطة', 'rgba(163,230,53,0.7)'],
          ['مرتفعة', 'rgba(245,158,11,0.8)'],
          ['حرجة', 'rgba(244,63,94,0.85)'],
        ].map(([label, c]) => (
          <span
            key={label}
            className="mono"
            style={{ fontSize: 11, color: 'var(--ink-dim)', display: 'flex', gap: 6, alignItems: 'center' }}
          >
            <span
              style={{ width: 14, height: 10, borderRadius: 3, background: c, display: 'inline-block' }}
            />
            {label}
          </span>
        ))}
      </div>
    </section>
  )
}
