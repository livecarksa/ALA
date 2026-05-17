import { useAppState } from './store/AppStore'
import { RoleGate } from './components/RoleGate'
import { Shell } from './components/Shell'
import { SupervisorView } from './components/supervisor/SupervisorView'
import { ContractorView } from './components/contractor/ContractorView'

// التوجيه مبني على حالة المستخدم (role) لا على عنوان URL.
export function App() {
  const { role } = useAppState()

  if (role === null) return <RoleGate />

  return (
    <Shell>
      {role === 'supervisor' ? <SupervisorView /> : <ContractorView />}
    </Shell>
  )
}
