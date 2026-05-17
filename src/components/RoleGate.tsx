import { useAppDispatch } from '../store/AppStore'
import type { Role } from '../store/types'

const ROLES: { id: Role; title: string; desc: string; neon: string; sigil: string }[] = [
  {
    id: 'supervisor',
    title: 'المشرف المركزي',
    desc: 'مراقبة لحظية للخريطة الحرارية، كثافة الحشود، واستهلاك الطاقة عبر كامل المنظومة.',
    neon: 'var(--neon-cyan)',
    sigil: '◎',
  },
  {
    id: 'contractor',
    title: 'المقاول الميداني',
    desc: 'إسناد العمالة للمربعات السكنية وفق القيود الهندسية، وإدارة التصاريح الأمنية.',
    neon: 'var(--neon-violet)',
    sigil: '◈',
  },
]

export function RoleGate() {
  const dispatch = useAppDispatch()

  return (
    <div
      style={{
        minHeight: '100%',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '40px 20px',
        gap: 36,
      }}
    >
      <div style={{ textAlign: 'center' }}>
        <div className="eyebrow" style={{ marginBottom: 10 }}>
          منظومة التحكم اللحظي · ALA-CTRL
        </div>
        <h1 style={{ fontSize: 30, fontWeight: 700, letterSpacing: '0.02em' }}>
          محطة التسكين اللامركزي وإدارة الحشود
        </h1>
        <p style={{ color: 'var(--ink-dim)', marginTop: 10, fontSize: 14 }}>
          اختر واجهة التشغيل للدخول إلى بيئة التحكم
        </p>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 340px))',
          gap: 20,
          width: '100%',
          maxWidth: 760,
        }}
      >
        {ROLES.map((r) => (
          <button
            key={r.id}
            className="panel"
            onClick={() => dispatch({ type: 'SET_ROLE', role: r.id })}
            style={{
              textAlign: 'right',
              padding: 26,
              display: 'flex',
              flexDirection: 'column',
              gap: 14,
              borderRadius: 'var(--radius)',
            }}
          >
            <div
              style={{
                fontSize: 30,
                color: r.neon,
                textShadow: `0 0 18px ${r.neon}`,
              }}
            >
              {r.sigil}
            </div>
            <div style={{ fontSize: 19, fontWeight: 700 }}>{r.title}</div>
            <div style={{ fontSize: 13, color: 'var(--ink-dim)', lineHeight: 1.7 }}>{r.desc}</div>
            <div
              className="mono"
              style={{ marginTop: 'auto', fontSize: 12, color: r.neon, paddingTop: 8 }}
            >
              دخول ←
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
