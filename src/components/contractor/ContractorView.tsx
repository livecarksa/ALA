import { AssignmentForm } from './AssignmentForm'
import { BlockRoster } from './BlockRoster'
import { SecurityPermits } from '../security/SecurityPermits'

export function ContractorView() {
  return (
    <div style={{ display: 'grid', gap: 20, maxWidth: 1280, margin: '0 auto' }}>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1.15fr) minmax(0, 0.85fr)',
          gap: 20,
        }}
      >
        <AssignmentForm />
        <BlockRoster />
      </div>
      <SecurityPermits />
    </div>
  )
}
