import { useState } from 'react'
import { useAppState } from '../../store/AppStore'
import { StationCredential } from './StationCredential'
import { TempPermitCard } from './TempPermitCard'
import { TempPermitModal } from './TempPermitModal'

export function SecurityPermits() {
  const { permits } = useAppState()
  const [modalOpen, setModalOpen] = useState(false)

  return (
    <section className="panel" style={{ padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 16 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700 }}>وحدة التصاريح الأمنية</h2>
        <span className="eyebrow">SECURITY CLEARANCE</span>
        <div style={{ flex: 1 }} />
        <button
          onClick={() => setModalOpen(true)}
          style={{
            padding: '9px 16px',
            fontSize: 13,
            fontWeight: 600,
            borderColor: 'var(--neon-violet)',
            color: 'var(--neon-violet)',
          }}
        >
          + إصدار تصريح مؤقت
        </button>
      </div>

      <StationCredential />

      <div style={{ marginTop: 18 }}>
        <div className="eyebrow" style={{ marginBottom: 10 }}>
          التصاريح المؤقتة النشطة ({permits.length})
        </div>
        {permits.length === 0 ? (
          <div
            className="mono"
            style={{
              fontSize: 12,
              color: 'var(--ink-faint)',
              border: '1px dashed var(--panel-edge)',
              borderRadius: 8,
              padding: '22px',
              textAlign: 'center',
            }}
          >
            لا توجد تصاريح مؤقتة سارية
          </div>
        ) : (
          <div style={{ display: 'grid', gap: 12 }}>
            {permits.map((p) => (
              <TempPermitCard key={p.id} permit={p} />
            ))}
          </div>
        )}
      </div>

      {modalOpen && <TempPermitModal onClose={() => setModalOpen(false)} />}
    </section>
  )
}
