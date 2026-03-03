import { ensureDir, readJson, writeJson } from "../utils/fs"
import { basename, dirname, relativePath, resolvePath } from "../utils/path"

type WhitelistData = {
  telegram: string[]
}

const DEFAULT_DATA: WhitelistData = {
  telegram: [],
}

export class WhitelistStore {
  private data: WhitelistData = { ...DEFAULT_DATA }

  constructor(private readonly filePath = resolvePath(Bun.cwd, ".data/whitelist.json")) {}

  async init(): Promise<void> {
    await ensureDir(dirname(this.filePath))
    try {
      const parsed = await readJson<Partial<WhitelistData>>(this.filePath)
      this.data = {
        telegram: Array.isArray(parsed.telegram) ? parsed.telegram.map(String) : [],
      }
      await this.persist()
    } catch {
      this.data = { ...DEFAULT_DATA }
      await this.persist()
    }
  }

  isWhitelisted(userID: string): boolean {
    return this.data.telegram.includes(String(userID))
  }

  async add(userID: string): Promise<boolean> {
    const id = String(userID)
    if (this.data.telegram.includes(id)) return false
    this.data.telegram.push(id)
    await this.persist()
    return true
  }

  file(): string {
    return this.filePath
  }

  displayFile(): string {
    const rel = relativePath(Bun.cwd, this.filePath)
    return rel.length > 0 ? rel : basename(this.filePath)
  }

  private async persist(): Promise<void> {
    await writeJson(this.filePath, this.data)
  }
}
