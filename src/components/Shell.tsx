import type { ReactNode } from 'react'
import { useAppDispatch, useAppState } from '../store/AppStore'
import { SHIFTS } from '../store/types'
import { useInterval } from '../hooks/useInterval'

export function Shell({ children }: { children: ReactNode }) {
  const { role, activeShift, gridLoadKw, fieldShiftActive } = useAppState()
  const dispatch = useAppDispatch()

  // نبض الطاقة اللحظي على مستوى المنظومة
  useInterval(() => dispatch({ type: 'TICK_ENERGY' }), 1500)
  // كنس التصاريح المنتهية من الحالة المركزية
  useInterval(() => dispatch({ type: 'EXPIRE_PERMITS', now: Date.now() }), 1000)

  const roleLabel = role === 'supervisor' ? 'المشرف المركزي' : 'المقاول الميداني'

  return (
    <div style={{ minHeight: '100%', display: 'flex', flexDirection: 'column' }}>
      <header
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 18,
          padding: '14px 22px',
          borderBottom: '1px solid var(--panel-edge)',
          background: 'linear-gradient(180deg, rgba(12,17,24,0.9), rgba(10,14,20,0.6))',
          backdropFilter: 'blur(6px)',
          position: 'sticky',
          top: 0,
          zIndex: 20,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span
            style={{
              color: 'var(--neon-cyan)',
              fontSize: 20,
              textShadow: '0 0 14px var(--neon-cyan)',
            }}
          >
            ◎
          </span>
          <div>
            <div style={{ fontWeight: 700, fontSize: 15 }}>ALA · محطة التحكم</div>
            <div className="eyebrow" style={{ fontSize: 10 }}>
              {roleLabel}
            </div>
          </div>
        </div>

        <div style={{ flex: 1 }} />

        <div
          className="mono tag"
          style={{ color: 'var(--neon-amber)', border: '1px solid var(--panel-edge)' }}
        >
          <span className="glow-dot" />
          {SHIFTS[activeShift].label} · {SHIFTS[activeShift].window}
        </div>

        <div
          className="mono tag"
          style={{
            color: fieldShiftActive ? 'var(--neon-violet)' : 'var(--neon-lime)',
            border: '1px solid var(--panel-edge)',
          }}
        >
          <span className="glow-dot" />
          الحمل: {gridLoadKw.toFixed(1)} ك.و
        </div>

        <button
          onClick={() => dispatch({ type: 'SET_ROLE', role: null })}
          style={{ padding: '8px 14px', fontSize: 13 }}
        >
          خروج ⎋
        </button>
      </header>

      <main style={{ flex: 1, padding: 22 }}>{children}</main>
    </div>
  )
}
