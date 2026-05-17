import { useEffect, useState } from 'react'

// مؤقت تنازلي حقيقي يعتمد على الزمن الفعلي (لا يتأثر بتجمّد الخيط).
// يُرجع المتبقي بالثواني وعلمَ الانتهاء.
export function useCountdown(expiresAt: number | null): { remaining: number; expired: boolean } {
  const compute = () =>
    expiresAt === null ? Infinity : Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000))

  const [remaining, setRemaining] = useState<number>(compute)

  useEffect(() => {
    setRemaining(compute())
    if (expiresAt === null) return
    const id = window.setInterval(() => {
      const left = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000))
      setRemaining(left)
      if (left <= 0) window.clearInterval(id)
    }, 250)
    return () => window.clearInterval(id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expiresAt])

  return { remaining, expired: expiresAt !== null && remaining <= 0 }
}
