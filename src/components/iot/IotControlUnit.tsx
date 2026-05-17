import { useAppDispatch, useAppState } from '../../store/AppStore'

const CHANNELS = ['تيار الإنارة', 'تكييف المربعات', 'مضخات المياه', 'بوابات الدخول']

export function IotControlUnit() {
  const { fieldShiftActive } = useAppState()
  const dispatch = useAppDispatch()
  const asleep = fieldShiftActive

  return (
    <section
      className="panel"
      style={{
        padding: 20,
        opacity: asleep ? 0.92 : 1,
        transition: 'opacity 0.4s ease',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 4 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>وحدة تحكم إنترنت الأشياء</h2>
        <span className="eyebrow">IOT EDGE NODE</span>
      </div>
      <p style={{ color: 'var(--ink-dim)', fontSize: 12, marginBottom: 18 }}>
        تتحوّل الوحدة إلى وضع السكون الطاقي تلقائياً بمجرد تنشيط دالة بدء الوردية الميدانية.
      </p>

      <div
        style={{
          position: 'relative',
          border: '1px solid var(--panel-edge)',
          borderRadius: 10,
          padding: 18,
          background:
            'linear-gradient(180deg, rgba(8,11,16,0.9), rgba(5,7,10,0.95))',
          overflow: 'hidden',
        }}
      >
        {/* شاشة الذبذبات — تنطفئ في وضع السكون */}
        <div
          style={{
            height: 76,
            borderRadius: 8,
            border: '1px solid var(--panel-edge)',
            background: '#06090d',
            position: 'relative',
            overflow: 'hidden',
            marginBottom: 16,
          }}
        >
          {asleep ? (
            <div
              style={{
                position: 'absolute',
                inset: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: 'var(--mono)',
                fontSize: 12,
                color: 'var(--neon-violet)',
                letterSpacing: '0.3em',
              }}
            >
              <span style={{ animation: 'pulse 2.4s ease-in-out infinite' }}>· · · STANDBY · · ·</span>
            </div>
          ) : (
            <svg viewBox="0 0 400 76" preserveAspectRatio="none" style={{ width: '100%', height: '100%' }}>
              <polyline
                fill="none"
                stroke="var(--neon-cyan)"
                strokeWidth="1.6"
                style={{ filter: 'drop-shadow(0 0 5px var(--neon-cyan))' }}
                points={Array.from({ length: 80 }, (_, i) => {
                  const x = (i / 79) * 400
                  const y = 38 + Math.sin(i / 3) * 14 * Math.sin(i / 11) - Math.cos(i / 5) * 6
                  return `${x},${y}`
                }).join(' ')}
              />
              <rect x="0" y="0" width="120" height="76" fill="url(#sweepGrad)">
                <animate attributeName="x" from="-120" to="400" dur="2.4s" repeatCount="indefinite" />
              </rect>
              <defs>
                <linearGradient id="sweepGrad" x1="0" x2="1">
                  <stop offset="0%" stopColor="rgba(34,211,238,0)" />
                  <stop offset="50%" stopColor="rgba(34,211,238,0.18)" />
                  <stop offset="100%" stopColor="rgba(34,211,238,0)" />
                </linearGradient>
              </defs>
            </svg>
          )}
        </div>

        {/* مؤشرات القنوات */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(2, 1fr)',
            gap: 10,
            marginBottom: 16,
          }}
        >
          {CHANNELS.map((c, i) => (
            <div
              key={c}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 9,
                fontSize: 12,
                color: asleep ? 'var(--ink-faint)' : 'var(--ink)',
                fontFamily: 'var(--mono)',
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: asleep ? 'var(--ink-faint)' : 'var(--neon-lime)',
                  boxShadow: asleep ? 'none' : '0 0 8px var(--neon-lime)',
                  animation: asleep ? 'none' : `pulse ${1.6 + i * 0.3}s ease-in-out infinite`,
                }}
              />
              {c}
              <span style={{ marginInlineStart: 'auto', color: 'var(--ink-faint)' }}>
                {asleep ? 'SLEEP' : 'ON'}
              </span>
            </div>
          ))}
        </div>

        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 12,
          }}
        >
          <div
            className="tag mono"
            style={{
              color: asleep ? 'var(--neon-violet)' : 'var(--neon-lime)',
              fontSize: 11,
            }}
          >
            <span className="glow-dot" />
            {asleep ? 'وضع السكون الطاقي' : 'تشغيل كامل'}
          </div>
          <button
            onClick={() => dispatch({ type: 'TOGGLE_FIELD_SHIFT' })}
            style={{
              padding: '10px 18px',
              fontSize: 13,
              fontWeight: 600,
              borderColor: asleep ? 'var(--neon-violet)' : 'var(--panel-edge)',
              color: asleep ? 'var(--neon-violet)' : 'var(--ink)',
            }}
          >
            {asleep ? 'إنهاء الوردية الميدانية' : 'بدء الوردية الميدانية'}
          </button>
        </div>

        {asleep && (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background:
                'radial-gradient(600px 200px at 50% 0%, rgba(167,139,250,0.05), transparent 70%)',
              pointerEvents: 'none',
            }}
          />
        )}
      </div>
    </section>
  )
}
