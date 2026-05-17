import { useState } from 'react'
import { QrCanvas } from './QrCanvas'
import { useInterval } from '../../hooks/useInterval'

const ROTATE_SECONDS = 30

function freshToken(): string {
  return Array.from({ length: 4 }, () =>
    Math.random().toString(36).slice(2, 6).toUpperCase(),
  ).join('-')
}

interface Credential {
  token: string
  issuedAt: number
  secondsLeft: number
}

function rotated(): Credential {
  return { token: freshToken(), issuedAt: Date.now(), secondsLeft: ROTATE_SECONDS }
}

// بطاقة الاعتماد الثابتة — يتحدّث رمز الاستجابة السريعة برمجياً كل 30 ثانية.
export function StationCredential() {
  const [cred, setCred] = useState<Credential>(rotated)
  const { token, issuedAt, secondsLeft } = cred

  // تحديث ذرّي واحد: نُنقص العدّاد، وعند بلوغه الصفر يُولَّد رمز جديد.
  useInterval(() => {
    setCred((c) =>
      c.secondsLeft <= 1 ? rotated() : { ...c, secondsLeft: c.secondsLeft - 1 },
    )
  }, 1000)

  const payload = `ALA|CRED|STATION-01|${token}|t=${issuedAt}`

  const progress = secondsLeft / ROTATE_SECONDS
  const C = 2 * Math.PI * 22

  return (
    <div
      className="panel"
      style={{
        padding: 18,
        display: 'flex',
        gap: 18,
        alignItems: 'center',
        background:
          'linear-gradient(135deg, rgba(15,20,28,0.95), rgba(8,11,16,0.95))',
      }}
    >
      <div style={{ position: 'relative' }}>
        <QrCanvas value={payload} size={132} />
        <svg
          width="46"
          height="46"
          viewBox="0 0 50 50"
          style={{ position: 'absolute', top: -10, insetInlineStart: -10 }}
        >
          <circle cx="25" cy="25" r="22" fill="#06090d" stroke="var(--panel-edge)" strokeWidth="3" />
          <circle
            cx="25"
            cy="25"
            r="22"
            fill="none"
            stroke="var(--neon-cyan)"
            strokeWidth="3"
            strokeLinecap="round"
            strokeDasharray={C}
            strokeDashoffset={C * (1 - progress)}
            transform="rotate(-90 25 25)"
            style={{ filter: 'drop-shadow(0 0 4px var(--neon-cyan))', transition: 'stroke-dashoffset 1s linear' }}
          />
          <text
            x="25"
            y="29"
            textAnchor="middle"
            fontSize="14"
            fill="var(--neon-cyan)"
            fontFamily="var(--mono)"
          >
            {secondsLeft}
          </text>
        </svg>
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="eyebrow" style={{ marginBottom: 6 }}>
          بطاقة الاعتماد الرقمية
        </div>
        <div style={{ fontSize: 17, fontWeight: 700, marginBottom: 4 }}>
          محطة التحكم المركزية
        </div>
        <div className="mono" style={{ fontSize: 12, color: 'var(--ink-dim)', marginBottom: 10 }}>
          STATION-01 · معتمدة
        </div>
        <div
          className="mono"
          style={{
            fontSize: 13,
            color: 'var(--neon-cyan)',
            background: 'rgba(34,211,238,0.06)',
            border: '1px solid var(--panel-edge)',
            borderRadius: 6,
            padding: '6px 10px',
            wordBreak: 'break-all',
          }}
        >
          {token}
        </div>
        <div style={{ fontSize: 11, color: 'var(--ink-faint)', marginTop: 8 }}>
          يتجدّد الرمز تلقائياً كل {ROTATE_SECONDS} ثانية لمنع إعادة الاستخدام.
        </div>
      </div>
    </div>
  )
}
