import { useState } from 'react'
import { useAppDispatch, useAppState } from '../../store/AppStore'
import { WORKER_CATEGORIES, type Permit, type WorkerCategory } from '../../store/types'

const DURATIONS = [
  { label: '٣٠ ثانية', sec: 30 },
  { label: 'دقيقتان', sec: 120 },
  { label: '٥ دقائق', sec: 300 },
  { label: '١٥ دقيقة', sec: 900 },
]

export function TempPermitModal({ onClose }: { onClose: () => void }) {
  const { blocks } = useAppState()
  const dispatch = useAppDispatch()

  const [holder, setHolder] = useState('')
  const [category, setCategory] = useState<WorkerCategory>('technical')
  const [blockId, setBlockId] = useState(blocks[0]?.id ?? 'A')
  const [durationSec, setDurationSec] = useState(120)

  const valid = holder.trim().length >= 2

  function issue() {
    if (!valid) return
    const now = Date.now()
    const permit: Permit = {
      id: `TMP-${now.toString(36).toUpperCase().slice(-6)}`,
      holder: holder.trim(),
      category,
      blockId,
      issuedAt: now,
      expiresAt: now + durationSec * 1000,
    }
    dispatch({ type: 'ISSUE_PERMIT', permit })
    onClose()
  }

  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(3,5,8,0.78)',
        backdropFilter: 'blur(4px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 50,
        padding: 20,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="panel"
        style={{
          width: 'min(440px, 100%)',
          padding: 24,
          background: 'linear-gradient(180deg, var(--panel), var(--bg-0))',
        }}
      >
        <div className="scanline" />
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 4 }}>
          <h3 style={{ fontSize: 17, fontWeight: 700 }}>إصدار تصريح مؤقت</h3>
          <span className="eyebrow">TEMP ACCESS</span>
        </div>
        <p style={{ color: 'var(--ink-dim)', fontSize: 12, marginBottom: 18 }}>
          يُربط التصريح بمؤقت تنازلي حقيقي يُعطّل بطاقة العرض فور وصوله إلى الصفر.
        </p>

        <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
          اسم حامل التصريح
        </label>
        <input
          value={holder}
          onChange={(e) => setHolder(e.target.value)}
          placeholder="الاسم الكامل"
          style={{ marginBottom: 14 }}
          autoFocus
        />

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 14 }}>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
              الفئة العمالية
            </label>
            <select value={category} onChange={(e) => setCategory(e.target.value as WorkerCategory)}>
              {Object.entries(WORKER_CATEGORIES).map(([k, v]) => (
                <option key={k} value={k}>
                  {v.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
              المربع السكني
            </label>
            <select value={blockId} onChange={(e) => setBlockId(e.target.value)}>
              {blocks.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 8 }}>
          مدة الصلاحية
        </label>
        <div style={{ display: 'flex', gap: 8, marginBottom: 22, flexWrap: 'wrap' }}>
          {DURATIONS.map((d) => (
            <button
              key={d.sec}
              onClick={() => setDurationSec(d.sec)}
              style={{
                padding: '8px 12px',
                fontSize: 12,
                borderColor: durationSec === d.sec ? 'var(--neon-cyan)' : 'var(--panel-edge)',
                color: durationSec === d.sec ? 'var(--neon-cyan)' : 'var(--ink)',
                background: durationSec === d.sec ? 'rgba(34,211,238,0.06)' : 'transparent',
              }}
            >
              {d.label}
            </button>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 10 }}>
          <button
            onClick={issue}
            disabled={!valid}
            style={{
              flex: 1,
              padding: '12px',
              fontWeight: 700,
              borderColor: 'var(--neon-cyan)',
              color: 'var(--neon-cyan)',
            }}
          >
            إصدار التصريح
          </button>
          <button onClick={onClose} style={{ padding: '12px 18px' }}>
            إلغاء
          </button>
        </div>
      </div>
    </div>
  )
}
