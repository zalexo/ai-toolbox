import { expect, mock, test } from 'claude-code/testing'

import { formatStatus, formatTime, pickLimits } from './register'

test('formatTime renders HH:MM without seconds', () => {
  const morning = new Date(2026, 9, 7, 9, 5, 42).getTime()
  expect(formatTime(morning)).toBe('09:05')
})

test('formatStatus shows bare percentages once any window is read, no labels or slashes', () => {
  const noon = new Date(2026, 9, 7, 12, 0, 0).getTime()
  expect(formatStatus(noon, {})).toBe('12:00')
  expect(formatStatus(noon, { fiveHour: 23.5 })).toBe('12:00  24%  0%')
  // A window the engine left out while the other has a reading is 0%, not a gap.
  expect(formatStatus(noon, { sevenDay: 16 })).toBe('12:00  0%  16%')
  expect(formatStatus(noon, { fiveHour: 0, sevenDay: 16 })).toBe('12:00  0%  16%')
  expect(formatStatus(noon, { fiveHour: 7, sevenDay: 41.2 })).toBe('12:00  7%  41%')
  expect(formatStatus(noon, { fiveHour: 7, sevenDay: 41.2 })).not.toContain('/')
})

test('pickLimits ignores windows it does not show', () => {
  expect(
    pickLimits([
      { kind: 'spend_limit', percentUsed: 99 },
      { kind: 'seven_day', percentUsed: 41 },
    ]),
  ).toEqual({ sevenDay: 41 })
})

test('the status line carries time and limits and follows the clock and measurements', async ($, on) => {
  const start = new Date(2026, 9, 7, 14, 30, 20).getTime()
  const clock = mock.clock(on, { now: start })
  const statuses: Array<string | undefined> = []
  on('ui.panes', () => ({ value: [] }))
  on('ui.status', (_$, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  let reported: Array<{ kind: string; percentUsed: number }> = []
  on('session.usage', () => ({
    value: { startedAt: start, context: {}, rateLimits: reported },
  }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))

  await $.session.start({ cwd: '/tmp', surface: 'desktop', isInteractive: true })
  expect(statuses).toEqual(['14:30'])

  // A reading that arrives after load is picked up by the next minute tick.
  reported = [
    { kind: 'five_hour', percentUsed: 23 },
    { kind: 'seven_day', percentUsed: 41 },
  ]
  await clock.advance(40_000)
  expect(statuses.at(-1)).toBe('14:31  23%  41%')

  await $.session.measure({
    context: {},
    rateLimits: [
      { kind: 'five_hour', percentUsed: 25 },
      { kind: 'seven_day', percentUsed: 41 },
    ],
    changed: ['rateLimits'],
  })
  expect(statuses.at(-1)).toBe('14:31  25%  41%')
})
