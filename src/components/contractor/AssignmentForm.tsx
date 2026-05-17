import { useMemo, useState } from 'react'
import { useAppDispatch, useAppState } from '../../store/AppStore'
import { blockLockedCategory, canAssign } from '../../store/logic'
import {
  SHIFTS,
  WORKER_CATEGORIES,
  type ShiftId,
  type WorkerCategory,
} from '../../store/types'

export function AssignmentForm() {
  const { blocks } = useAppState()
  const dispatch = useAppDispatch()

  const [blockId, setBlockId] = useState(blocks[0]?.id ?? 'A')
  const [roomId, setRoomId] = useState(blocks[0]?.rooms[0]?.id ?? '')
  const [category, setCategory] = useState<WorkerCategory>('technical')
  const [count, setCount] = useState(2)
  const [shift, setShift] = useState<ShiftId>('morning')

  const block = blocks.find((b) => b.id === blockId)!
  const room = block.rooms.find((r) => r.id === roomId) ?? block.rooms[0]
  const locked = blockLockedCategory(block)

  // عند قفل المربع على فئة، تُفرض الفئة المقفل عليها هندسياً
  const effectiveCategory = locked ?? category

  const check = useMemo(
    () => canAssign(block, room, effectiveCategory),
    [block, room, effectiveCategory],
  )

  function onBlockChange(id: string) {
    setBlockId(id)
    const b = blocks.find((x) => x.id === id)!
    setRoomId(b.rooms[0]?.id ?? '')
  }

  function submit() {
    if (!check.ok) return
    dispatch({
      type: 'ASSIGN_WORKERS',
      blockId,
      roomId: room.id,
      category: effectiveCategory,
      count,
      shift,
    })
  }

  return (
    <section className="panel" style={{ padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 4 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>نموذج إسناد العمالة</h2>
        <span className="eyebrow">DYNAMIC INTAKE</span>
      </div>
      <p style={{ color: 'var(--ink-dim)', fontSize: 12, marginBottom: 18 }}>
        يفرض النموذج القيد الهندسي تلقائياً: لا يمكن دمج فئتين عماليتين مختلفتين داخل نفس المربع السكني.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
        <div>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
            المربع السكني
          </label>
          <select value={blockId} onChange={(e) => onBlockChange(e.target.value)}>
            {blocks.map((b) => (
              <option key={b.id} value={b.id}>
                {b.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
            الغرفة
          </label>
          <select value={room.id} onChange={(e) => setRoomId(e.target.value)}>
            {block.rooms.map((r) => (
              <option key={r.id} value={r.id} disabled={r.status === 'maintenance'}>
                {r.id} — {r.occupants}/{r.capacity}
                {r.status === 'maintenance' ? ' (صيانة)' : ''}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
            الفئة العمالية
          </label>
          <select
            value={effectiveCategory}
            onChange={(e) => setCategory(e.target.value as WorkerCategory)}
            disabled={locked !== null}
            title={locked ? 'المربع مقفل هندسياً على فئة واحدة' : undefined}
          >
            {Object.entries(WORKER_CATEGORIES).map(([k, v]) => (
              <option key={k} value={k}>
                {v.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
            الوردية الزمنية
          </label>
          <select value={shift} onChange={(e) => setShift(e.target.value as ShiftId)}>
            {Object.entries(SHIFTS).map(([k, v]) => (
              <option key={k} value={k}>
                {v.label} · {v.window}
              </option>
            ))}
          </select>
        </div>

        <div style={{ gridColumn: '1 / -1' }}>
          <label style={{ display: 'block', fontSize: 12, color: 'var(--ink-dim)', marginBottom: 6 }}>
            عدد العمال المُسنَدين — متاح {Math.max(room.capacity - room.occupants, 0)} مقعد
          </label>
          <input
            type="range"
            min={1}
            max={Math.max(room.capacity - room.occupants, 1)}
            value={Math.min(count, Math.max(room.capacity - room.occupants, 1))}
            onChange={(e) => setCount(Number(e.target.value))}
            style={{ accentColor: 'var(--neon-cyan)', padding: 0 }}
          />
          <div className="mono" style={{ fontSize: 13, color: 'var(--neon-cyan)', marginTop: 6 }}>
            {Math.min(count, Math.max(room.capacity - room.occupants, 1))} عامل
          </div>
        </div>
      </div>

      {locked && (
        <div
          className="tag"
          style={{
            color: WORKER_CATEGORIES[locked].neon,
            marginTop: 16,
            fontSize: 12,
          }}
        >
          <span className="glow-dot" />
          القيد الهندسي مُفعّل — المربع {block.id} مقفل على فئة «{WORKER_CATEGORIES[locked].label}»
        </div>
      )}

      <div
        style={{
          marginTop: 16,
          padding: '12px 14px',
          borderRadius: 8,
          border: `1px solid ${check.ok ? 'var(--panel-edge)' : 'var(--neon-rose)'}`,
          background: check.ok ? 'rgba(163,230,53,0.05)' : 'rgba(244,63,94,0.07)',
          fontSize: 13,
          color: check.ok ? 'var(--neon-lime)' : 'var(--neon-rose)',
          display: 'flex',
          alignItems: 'center',
          gap: 10,
        }}
      >
        <span style={{ fontSize: 15 }}>{check.ok ? '✓' : '⚠'}</span>
        {check.ok ? 'الإسناد متوافق مع القيود الهندسية.' : check.reason}
      </div>

      <button
        onClick={submit}
        disabled={!check.ok}
        style={{
          marginTop: 16,
          width: '100%',
          padding: '13px',
          fontSize: 14,
          fontWeight: 700,
          borderColor: check.ok ? 'var(--neon-cyan)' : 'var(--panel-edge)',
          color: check.ok ? 'var(--neon-cyan)' : 'var(--ink-faint)',
        }}
      >
        تأكيد الإسناد
      </button>
    </section>
  )
}
