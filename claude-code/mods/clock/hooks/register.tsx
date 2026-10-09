import type { EngineInterface, Register, SessionRateLimit } from 'claude-code'

const MINUTE_MS = 60_000
/** The pane an earlier version of this mod opened; closed on load so it does not linger. */
const LEGACY_PANE = 'clock'

export type Limits = { fiveHour?: number; sevenDay?: number }

/** Formats a timestamp as HH:MM in the local time zone, 24-hour, no seconds. */
export function formatTime(ms: number): string {
  const date = new Date(ms)
  const hh = String(date.getHours()).padStart(2, '0')
  const mm = String(date.getMinutes()).padStart(2, '0')

  return `${hh}:${mm}`
}

/** Picks the session (5h) and weekly (7d) windows out of the engine's rate-limit readings. */
export function pickLimits(rateLimits: readonly SessionRateLimit[]): Limits {
  const limits: Limits = {}
  for (const window of rateLimits) {
    if (window.kind === 'five_hour') limits.fiveHour = window.percentUsed
    if (window.kind === 'seven_day') limits.sevenDay = window.percentUsed
  }

  return limits
}

/**
 * The status line: time, then the used share of the 5-hour window, then of the 7-day window.
 * Before the first reading only the time shows. Once any window is reported, both show: the
 * engine leaves out a window that has no usage yet, and that is a 0%, not a gap.
 */
export function formatStatus(nowMs: number, limits: Limits): string {
  const parts = [formatTime(nowMs)]
  const hasReading = limits.fiveHour !== undefined || limits.sevenDay !== undefined
  if (hasReading) {
    parts.push(`${Math.round(limits.fiveHour ?? 0)}%`, `${Math.round(limits.sevenDay ?? 0)}%`)
  }

  return parts.join('  ')
}

/** The last readings seen; module state, so a reload starts it over. */
let limits: Limits = {}

/** Re-reads the windows and repaints the line; the plain usage call is free. */
async function refresh($: EngineInterface): Promise<void> {
  limits = pickLimits((await $.session.usage()).rateLimits)
  $.ui.status(formatStatus(await $.clock.now(), limits))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const isLegacyPaneUp = (await $.ui.panes()).some(pane => pane.id === LEGACY_PANE)
    if (isLegacyPaneUp) {
      await $.ui.close({ id: LEGACY_PANE })
    }

    // Every tick re-reads the windows: a reading that was missing at load shows up
    // on the next minute even without a measure event.
    const tick = () => refresh($)

    await tick()
    // Align the first repaint to the next minute boundary, then repaint once per minute.
    const now = await $.clock.now()
    const untilNextMinute = MINUTE_MS - (now % MINUTE_MS)
    $.clock.after(untilNextMinute, () => {
      void tick()
      $.clock.every(MINUTE_MS, () => void tick())
    })

    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('rateLimits')) {
      limits = pickLimits(e.rateLimits)
      $.ui.status(formatStatus(await $.clock.now(), limits))
    }

    return next(e)
  })

  // The first API response of a fresh session brings the first reading: show it at once.
  on('turn.complete', async ($, e, next) => {
    await refresh($)

    return next(e)
  })
}
