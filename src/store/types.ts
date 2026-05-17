// نموذج البيانات المركزي لمحطة التحكم في التسكين اللامركزي

export type Role = 'supervisor' | 'contractor'

// الفئات العمالية — لا يجوز دمج فئتين مختلفتين داخل نفس المربع السكني
export type WorkerCategory =
  | 'technical' // عمالة فنية
  | 'general' // عمالة عامة
  | 'logistics' // إمداد ولوجستيات
  | 'security' // أمن وحراسة

export const WORKER_CATEGORIES: Record<WorkerCategory, { label: string; neon: string }> = {
  technical: { label: 'عمالة فنية', neon: '#22d3ee' },
  general: { label: 'عمالة عامة', neon: '#a3e635' },
  logistics: { label: 'إمداد ولوجستيات', neon: '#f59e0b' },
  security: { label: 'أمن وحراسة', neon: '#f43f5e' },
}

// الوردية الزمنية
export type ShiftId = 'morning' | 'evening' | 'night'

export const SHIFTS: Record<ShiftId, { label: string; window: string }> = {
  morning: { label: 'وردية صباحية', window: '06:00 — 14:00' },
  evening: { label: 'وردية مسائية', window: '14:00 — 22:00' },
  night: { label: 'وردية ليلية', window: '22:00 — 06:00' },
}

export type RoomStatus = 'vacant' | 'occupied' | 'maintenance' | 'reserved'

export const ROOM_STATUS: Record<RoomStatus, { label: string; neon: string }> = {
  vacant: { label: 'شاغرة', neon: '#3f6d7a' },
  occupied: { label: 'مشغولة', neon: '#22d3ee' },
  maintenance: { label: 'صيانة', neon: '#f59e0b' },
  reserved: { label: 'محجوزة', neon: '#a78bfa' },
}

export interface Room {
  id: string
  blockId: string
  index: number
  status: RoomStatus
  capacity: number
  occupants: number
  // فئة العامل المسموح بها داخل هذه الغرفة (مشتقة من المربع السكني)
  category: WorkerCategory | null
  shift: ShiftId | null
  energyKw: number // استهلاك الطاقة اللحظي للغرفة
}

export interface HousingBlock {
  id: string
  name: string
  rooms: Room[]
}

export interface Permit {
  id: string
  holder: string
  category: WorkerCategory
  blockId: string
  issuedAt: number
  // التصاريح المؤقتة فقط لها تاريخ انتهاء (زمن يونكس بالملي ثانية)
  expiresAt: number | null
}

export interface AppState {
  role: Role | null
  blocks: HousingBlock[]
  // هل تم تنشيط دالة بدء الوردية الميدانية (تحوّل وحدة إنترنت الأشياء لوضع السكون)
  fieldShiftActive: boolean
  activeShift: ShiftId
  permits: Permit[]
  // إجمالي استهلاك الطاقة اللحظي للمنظومة
  gridLoadKw: number
}

export type AppAction =
  | { type: 'SET_ROLE'; role: Role | null }
  | { type: 'ASSIGN_WORKERS'; blockId: string; roomId: string; category: WorkerCategory; count: number; shift: ShiftId }
  | { type: 'SET_ROOM_STATUS'; roomId: string; status: RoomStatus }
  | { type: 'TOGGLE_FIELD_SHIFT' }
  | { type: 'SET_ACTIVE_SHIFT'; shift: ShiftId }
  | { type: 'ISSUE_PERMIT'; permit: Permit }
  | { type: 'REVOKE_PERMIT'; permitId: string }
  | { type: 'EXPIRE_PERMITS'; now: number }
  | { type: 'TICK_ENERGY' }
