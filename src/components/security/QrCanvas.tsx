import { useEffect, useRef } from 'react'
import QRCode from 'qrcode'

export function QrCanvas({
  value,
  size = 148,
  active = true,
}: {
  value: string
  size?: number
  active?: boolean
}) {
  const ref = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    QRCode.toCanvas(canvas, value, {
      width: size,
      margin: 1,
      errorCorrectionLevel: 'M',
      color: {
        dark: active ? '#0a0e14' : '#33414f',
        light: active ? '#22d3ee' : '#1b2430',
      },
    }).catch(() => {})
  }, [value, size, active])

  return (
    <canvas
      ref={ref}
      width={size}
      height={size}
      style={{
        borderRadius: 8,
        opacity: active ? 1 : 0.35,
        filter: active ? 'drop-shadow(0 0 10px rgba(34,211,238,0.45))' : 'grayscale(1)',
        transition: 'opacity 0.3s ease, filter 0.3s ease',
      }}
    />
  )
}
