import type { HousingBlock, Room, WorkerCategory } from './types'

// القيد الهندسي: المربع السكني يُقفل على فئة عمالية واحدة بمجرد إشغاله.
// تُرجع الفئة المقفل عليها المربع، أو null إذا كان المربع فارغاً تماماً.
export function blockLockedCategory(block: HousingBlock): WorkerCategory | null {
  for (const room of block.rooms) {
    if (room.occupants > 0 && room.category) return room.category
  }
  return null
}

export function blockOccupancy(block: HousingBlock): { occupants: number; capacity: number; ratio: number } {
  let occupants = 0
  let capacity = 0
  for (const room of block.rooms) {
    occupants += room.occupants
    capacity += room.capacity
  }
  return { occupants, capacity, ratio: capacity === 0 ? 0 : occupants / capacity }
}

export function blockEnergyKw(block: HousingBlock): number {
  return block.rooms.reduce((sum, r) => sum + r.energyKw, 0)
}

// هل يُسمح بإسناد هذه الفئة لهذه الغرفة دون كسر القيد الهندسي؟
export function canAssign(
  block: HousingBlock,
  room: Room,
  category: WorkerCategory,
): { ok: true } | { ok: false; reason: string } {
  if (room.status === 'maintenance') {
    return { ok: false, reason: 'الغرفة تحت الصيانة ولا يمكن إسناد عمالة إليها.' }
  }
  if (room.occupants >= room.capacity) {
    return { ok: false, reason: 'الغرفة بلغت سعتها القصوى.' }
  }
  const locked = blockLockedCategory(block)
  if (locked && locked !== category) {
    return {
      ok: false,
      reason: 'القيد الهندسي: لا يجوز دمج فئتين عماليتين مختلفتين داخل نفس المربع السكني.',
    }
  }
  if (room.category && room.category !== category) {
    return { ok: false, reason: 'الغرفة مخصّصة لفئة عمالية أخرى.' }
  }
  return { ok: true }
}
