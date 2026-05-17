import type { HousingBlock, Room, RoomStatus, WorkerCategory } from './types'

const BLOCK_DEFS = [
  { id: 'A', name: 'المربع السكني أ', cat: 'technical' as WorkerCategory },
  { id: 'B', name: 'المربع السكني ب', cat: 'general' as WorkerCategory },
  { id: 'C', name: 'المربع السكني ج', cat: 'logistics' as WorkerCategory },
  { id: 'D', name: 'المربع السكني د', cat: null },
]

const ROOMS_PER_BLOCK = 12
const ROOM_CAPACITY = 6

function seededStatus(blockIdx: number, roomIdx: number): { status: RoomStatus; occupants: number } {
  const h = (blockIdx * 7 + roomIdx * 13) % 10
  if (h === 0) return { status: 'maintenance', occupants: 0 }
  if (h === 1) return { status: 'reserved', occupants: 0 }
  if (h <= 4) return { status: 'vacant', occupants: 0 }
  return { status: 'occupied', occupants: 2 + (h % 5) }
}

export function createSeedBlocks(): HousingBlock[] {
  return BLOCK_DEFS.map((def, blockIdx) => {
    const rooms: Room[] = Array.from({ length: ROOMS_PER_BLOCK }, (_, i) => {
      const { status, occupants } = seededStatus(blockIdx, i)
      const filled = status === 'occupied'
      return {
        id: `${def.id}-${String(i + 1).padStart(2, '0')}`,
        blockId: def.id,
        index: i + 1,
        status,
        capacity: ROOM_CAPACITY,
        occupants: filled ? Math.min(occupants, ROOM_CAPACITY) : 0,
        category: filled ? def.cat : null,
        shift: filled ? 'morning' : null,
        energyKw: filled ? 1.4 + occupants * 0.35 : 0.2,
      }
    })
    return { id: def.id, name: def.name, rooms }
  })
}
