import { createContext, useContext, useReducer, type Dispatch, type ReactNode } from 'react'
import type { AppAction, AppState, HousingBlock } from './types'
import { createSeedBlocks } from './seed'
import { blockEnergyKw, canAssign } from './logic'

function initState(): AppState {
  const blocks = createSeedBlocks()
  return {
    role: null,
    blocks,
    fieldShiftActive: false,
    activeShift: 'morning',
    permits: [],
    gridLoadKw: blocks.reduce((s, b) => s + blockEnergyKw(b), 0),
  }
}

function mapRoom(
  blocks: HousingBlock[],
  blockId: string,
  roomId: string,
  fn: (r: HousingBlock['rooms'][number]) => HousingBlock['rooms'][number],
): HousingBlock[] {
  return blocks.map((b) =>
    b.id !== blockId ? b : { ...b, rooms: b.rooms.map((r) => (r.id === roomId ? fn(r) : r)) },
  )
}

function recomputeGrid(blocks: HousingBlock[]): number {
  return blocks.reduce((s, b) => s + blockEnergyKw(b), 0)
}

function reducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'SET_ROLE':
      return { ...state, role: action.role }

    case 'ASSIGN_WORKERS': {
      const block = state.blocks.find((b) => b.id === action.blockId)
      const room = block?.rooms.find((r) => r.id === action.roomId)
      if (!block || !room) return state
      // حارس القيد الهندسي على مستوى الحالة المركزية
      const check = canAssign(block, room, action.category)
      if (!check.ok) return state
      const nextCount = Math.min(room.occupants + action.count, room.capacity)
      const blocks = mapRoom(state.blocks, action.blockId, action.roomId, (r) => ({
        ...r,
        occupants: nextCount,
        category: action.category,
        shift: action.shift,
        status: 'occupied',
        energyKw: 1.4 + nextCount * 0.35,
      }))
      return { ...state, blocks, gridLoadKw: recomputeGrid(blocks) }
    }

    case 'SET_ROOM_STATUS': {
      const target = state.blocks.find((b) => b.rooms.some((r) => r.id === action.roomId))
      if (!target) return state
      const blocks = mapRoom(state.blocks, target.id, action.roomId, (r) => ({
        ...r,
        status: action.status,
        occupants: action.status === 'occupied' ? r.occupants : 0,
        category: action.status === 'occupied' ? r.category : null,
        energyKw: action.status === 'occupied' ? r.energyKw : 0.2,
      }))
      return { ...state, blocks, gridLoadKw: recomputeGrid(blocks) }
    }

    case 'TOGGLE_FIELD_SHIFT':
      return { ...state, fieldShiftActive: !state.fieldShiftActive }

    case 'SET_ACTIVE_SHIFT':
      return { ...state, activeShift: action.shift }

    case 'ISSUE_PERMIT':
      return { ...state, permits: [action.permit, ...state.permits] }

    case 'REVOKE_PERMIT':
      return { ...state, permits: state.permits.filter((p) => p.id !== action.permitId) }

    case 'EXPIRE_PERMITS':
      return {
        ...state,
        permits: state.permits.filter((p) => p.expiresAt === null || p.expiresAt > action.now),
      }

    case 'TICK_ENERGY': {
      // محاكاة استهلاك طاقة لحظي متذبذب حول الحمل الأساسي لكل غرفة مشغولة
      const blocks = state.blocks.map((b) => ({
        ...b,
        rooms: b.rooms.map((r) => {
          if (r.occupants === 0) return r
          const base = 1.4 + r.occupants * 0.35
          const jitter = (Math.sin(Date.now() / 900 + r.index) + 1) * 0.45
          return { ...r, energyKw: +(base + jitter).toFixed(2) }
        }),
      }))
      return { ...state, blocks, gridLoadKw: +recomputeGrid(blocks).toFixed(1) }
    }

    default:
      return state
  }
}

const StateCtx = createContext<AppState | null>(null)
const DispatchCtx = createContext<Dispatch<AppAction> | null>(null)

export function AppStoreProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, undefined, initState)
  return (
    <StateCtx.Provider value={state}>
      <DispatchCtx.Provider value={dispatch}>{children}</DispatchCtx.Provider>
    </StateCtx.Provider>
  )
}

export function useAppState(): AppState {
  const ctx = useContext(StateCtx)
  if (!ctx) throw new Error('useAppState يجب أن يُستخدم داخل AppStoreProvider')
  return ctx
}

export function useAppDispatch(): Dispatch<AppAction> {
  const ctx = useContext(DispatchCtx)
  if (!ctx) throw new Error('useAppDispatch يجب أن يُستخدم داخل AppStoreProvider')
  return ctx
}
