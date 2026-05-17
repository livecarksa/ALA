import { useAppState } from '../../store/AppStore'
import { blockOccupancy } from '../../store/logic'
import { Heatmap } from './Heatmap'
import { EnergyMonitor } from './EnergyMonitor'
import { IotControlUnit } from '../iot/IotControlUnit'

function Kpi({ label, value, unit, neon }: { label: string; value: string; unit?: string; neon: string }) {
  return (
    <div className="panel" style={{ padding: 16 }}>
      <div className="eyebrow" style={{ fontSize: 10, marginBottom: 8 }}>
        {label}
      </div>
      <div className="mono" style={{ fontSize: 24, color: neon, textShadow: `0 0 12px ${neon}` }}>
        {value}
        {unit && <span style={{ fontSize: 12, color: 'var(--ink-dim)' }}> {unit}</span>}
      </div>
    </div>
  )
}

export function SupervisorView() {
  const { blocks, gridLoadKw, permits } = useAppState()

  const totals = blocks.reduce(
    (acc, b) => {
      const { occupants, capacity } = blockOccupancy(b)
      acc.occ += occupants
      acc.cap += capacity
      return acc
    },
    { occ: 0, cap: 0 },
  )
  const fill = totals.cap === 0 ? 0 : Math.round((totals.occ / totals.cap) * 100)

  return (
    <div style={{ display: 'grid', gap: 20, maxWidth: 1280, margin: '0 auto' }}>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 14,
        }}
      >
        <Kpi label="إجمالي النزلاء" value={String(totals.occ)} neon="var(--neon-cyan)" />
        <Kpi label="نسبة الإشغال" value={`${fill}٪`} neon="var(--neon-lime)" />
        <Kpi label="الحمل اللحظي" value={gridLoadKw.toFixed(1)} unit="ك.و" neon="var(--neon-amber)" />
        <Kpi label="تصاريح مؤقتة" value={String(permits.length)} neon="var(--neon-violet)" />
      </div>

      <Heatmap />

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1.1fr) minmax(0, 0.9fr)',
          gap: 20,
        }}
      >
        <EnergyMonitor />
        <IotControlUnit />
      </div>
    </div>
  )
}
