import { useEffect, useRef } from 'react'

/**
 * Tracks which async load is the most recent one. `begin()` starts a load and returns `isStale()`:
 * true once a newer load has begun (or the tracker was cancelled). Loads must check `isStale()` after
 * every await and before writing state, so a slow earlier load (e.g. the previous account's) never
 * overwrites a newer one.
 */
export function createLatestRequest() {
  let latest = 0
  return {
    begin(): () => boolean {
      const id = ++latest
      return () => id !== latest
    },
    /** Makes every load started so far stale (used on unmount). */
    cancel(): void {
      latest++
    },
  }
}

/** React hook form of createLatestRequest: `const begin = useLatestRequest()`; loads in flight become stale on unmount. */
export function useLatestRequest(): () => () => boolean {
  const tracker = useRef<ReturnType<typeof createLatestRequest>>()
  if (!tracker.current) tracker.current = createLatestRequest()
  useEffect(() => {
    const t = tracker.current!
    return () => t.cancel()
  }, [])
  return tracker.current.begin
}
