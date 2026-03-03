import { writeText } from "./fs"
import { resolvePath } from "./path"

const HEALTH_CHECK_INTERVAL = 5 * 60 * 1000 // 5 minutes

/**
 * Starts a health check writer that periodically updates a timestamp file.
 * This allows the CLI wrapper to check if the service is running properly.
 */
export function startHealthCheck(dataDir: string): () => void {
  const healthFile = resolvePath(dataDir, "health.check")
  
  const writeHealthCheck = async () => {
    try {
      const timestamp = new Date().toISOString()
      await writeText(healthFile, timestamp)
    } catch (error) {
      // Silently fail - health check is non-critical
    }
  }
  
  // Write initial health check
  void writeHealthCheck()
  
  // Set up interval
  const intervalId = setInterval(() => {
    void writeHealthCheck()
  }, HEALTH_CHECK_INTERVAL)
  
  // Return cleanup function
  return () => {
    clearInterval(intervalId)
  }
}
