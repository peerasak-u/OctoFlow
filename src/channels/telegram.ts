import { Bot } from "grammy"
import type { Logger } from "pino"
import { AssistantCore, type ProgressUpdate } from "../core/assistant"
import { WhitelistStore } from "../core/whitelist-store"
import { splitTextChunks } from "../utils/format-message"
import { ackOutbox, listOutbox } from "../utils/outbox"

type TelegramAdapterOptions = {
  token: string
  logger: Logger
  assistant: AssistantCore
  whitelist: WhitelistStore
  pairToken?: string
}

function whitelistInstruction(userID: string, filePath: string): string {
  return [
    "Access restricted.",
    `Your Telegram ID: ${userID}`,
    "Send /pair <token> to whitelist yourself.",
    `If you don't have a token, ask admin to add you in ${filePath}.`,
  ].join("\n")
}

const THIRTY_MINUTES_MS = 30 * 60 * 1000

function formatStatusMessage(update: ProgressUpdate): string {
  switch (update.type) {
    case "start":
      return "⏳ Processing your request..."
    case "thinking":
      return "🤔 Thinking about your question..."
    case "tool":
      return `🔧 Running tool: ${update.name}...`
    case "skill":
      return `📚 Loading skill: ${update.name}...`
    case "generating":
      return "📝 Preparing your answer..."
    default:
      return "⏳ Processing..."
  }
}

export async function startTelegramAdapter(opts: TelegramAdapterOptions): Promise<void> {
  const bot = new Bot(opts.token)
  let flushingOutbox = false

  const flushOutbox = async () => {
    if (flushingOutbox) return
    flushingOutbox = true
    try {
      const pending = await listOutbox()
      for (const item of pending) {
        const chunks = splitTextChunks(item.message.text, 3000)
        for (const chunk of chunks) {
          await bot.api.sendMessage(item.message.userID, chunk)
        }
        await ackOutbox(item.filePath)
        opts.logger.info({ userID: item.message.userID, chunkCount: chunks.length }, "telegram proactive message sent")
      }
    } catch (error) {
      opts.logger.warn({ error }, "telegram outbox flush failed")
    } finally {
      flushingOutbox = false
    }
  }

  bot.command("start", async (ctx) => {
    const userID = String(ctx.from?.id ?? ctx.chat.id)
    const allowed = opts.whitelist.isWhitelisted(userID)
    opts.logger.info({ chatID: ctx.chat.id, userID, allowed }, "telegram /start")
    if (!allowed) {
      await ctx.reply(whitelistInstruction(userID, opts.whitelist.displayFile()))
      return
    }
    await ctx.reply("ZiroClaw is online. Try /remember <note>.")
  })

  bot.command("pair", async (ctx) => {
    const userID = String(ctx.from?.id ?? ctx.chat.id)
    const token = ctx.match?.toString().trim() ?? ""
    if (!opts.pairToken) {
      await ctx.reply("Pairing is disabled by admin. Ask admin to whitelist your account.")
      return
    }
    if (!token) {
      await ctx.reply("Usage: /pair <token>")
      return
    }
    if (token !== opts.pairToken) {
      await ctx.reply("Invalid pairing token.")
      return
    }
    const created = await opts.whitelist.add(userID)
    opts.logger.info({ userID, created }, "telegram pairing")
    await ctx.reply(created ? "Pairing successful. You are now whitelisted." : "You are already whitelisted.")
  })

  bot.command("new", async (ctx) => {
    const userID = String(ctx.from?.id ?? ctx.chat.id)
    const allowed = opts.whitelist.isWhitelisted(userID)
    if (!allowed) {
      await ctx.reply(whitelistInstruction(userID, opts.whitelist.displayFile()))
      return
    }
    const sessionID = await opts.assistant.startNewMainSession(`telegram:${userID}`)
    await ctx.reply(`Started new shared session: ${sessionID}`)
  })

  bot.command("remember", async (ctx) => {
    const userID = String(ctx.from?.id ?? ctx.chat.id)
    const allowed = opts.whitelist.isWhitelisted(userID)
    opts.logger.info({ chatID: ctx.chat.id, userID, allowed }, "telegram /remember")
    if (!allowed) {
      await ctx.reply(whitelistInstruction(userID, opts.whitelist.displayFile()))
      return
    }
    const text = ctx.match?.toString().trim() ?? ""
    if (!text) {
      await ctx.reply("Usage: /remember <text>")
      return
    }

    const source = `telegram:${userID}`
    await opts.assistant.remember(text, source)
    await ctx.reply("Saved to long-term memory.")
  })

  bot.on("message:text", async (ctx) => {
    const text = ctx.message.text.trim()
    if (!text || text.startsWith("/")) return

    const startedAt = Date.now()
    const userID = String(ctx.from?.id ?? ctx.chat.id)
    const allowed = opts.whitelist.isWhitelisted(userID)
    opts.logger.info(
      {
        updateID: ctx.update.update_id,
        chatID: ctx.chat.id,
        userID,
        allowed,
        textLength: text.length,
      },
      "telegram message received",
    )
    if (!allowed) {
      await ctx.reply(whitelistInstruction(userID, opts.whitelist.displayFile()))
      return
    }

    let statusMessageId: number | undefined
    let statusMessageCreatedAt: number | undefined
    let updatingStatus = true

    const sendStatusMessage = async (): Promise<void> => {
      const msg = await ctx.reply("⏳ Processing your request...")
      statusMessageId = msg.message_id
      statusMessageCreatedAt = Date.now()
    }

    const updateStatusMessage = async (text: string): Promise<void> => {
      if (!updatingStatus || !statusMessageId || !statusMessageCreatedAt) {
        opts.logger.debug({ updatingStatus, hasMessageId: !!statusMessageId, hasCreatedAt: !!statusMessageCreatedAt }, "updateStatusMessage early return")
        return
      }

      // Check if message is too old (> 30 minutes)
      if (Date.now() - statusMessageCreatedAt > THIRTY_MINUTES_MS) {
        updatingStatus = false
        return
      }

      try {
        opts.logger.debug({ text, messageId: statusMessageId }, "updating status message")
        await ctx.api.editMessageText(ctx.chat.id, statusMessageId, text)
        opts.logger.debug({ text }, "status message updated successfully")
      } catch (error) {
        // Check if it's just "message not modified" error (harmless)
        const errorMsg = String(error)
        if (errorMsg.includes("message is not modified")) {
          opts.logger.debug({ text }, "status update skipped - message not modified")
          return
        }
        // Stop trying to update on real errors
        updatingStatus = false
        opts.logger.warn({ error, chatID: ctx.chat.id, messageId: statusMessageId, text }, "status update failed, stopping updates")
      }
    }

    const deleteStatusMessage = async (): Promise<void> => {
      if (!statusMessageId) return
      try {
        await ctx.api.deleteMessage(ctx.chat.id, statusMessageId)
      } catch (error) {
        // Ignore delete errors
        opts.logger.debug({ error, chatID: ctx.chat.id, messageId: statusMessageId }, "status delete failed")
      }
    }

    try {
      // Send initial status message
      await sendStatusMessage()

      // Create progress callback
      let answerReceived = false
      const onProgress = (update: ProgressUpdate): void => {
        // Don't update status after answer is received
        if (answerReceived) return
        
        opts.logger.debug({ updateType: update.type, toolName: (update as { name?: string }).name }, "onProgress called")
        const newText = formatStatusMessage(update)
        // Skip update if text is the same as current status
        if (newText === "⏳ Processing your request...") {
          opts.logger.debug("skipping status update - same as initial message")
          return
        }
        void updateStatusMessage(newText)
      }

      const answer = await opts.assistant.ask(
        {
          channel: "telegram",
          userID,
          text,
        },
        onProgress
      )

      // Mark that answer is received - prevent further status updates
      answerReceived = true

      // Delete status message before sending final response
      await deleteStatusMessage()

      const chunks = splitTextChunks(answer, 3000)
      for (const chunk of chunks) {
        await ctx.reply(chunk)
      }
      opts.logger.info(
        {
          updateID: ctx.update.update_id,
          chatID: ctx.chat.id,
          userID,
          durationMs: Date.now() - startedAt,
          answerLength: answer.length,
          chunkCount: chunks.length,
        },
        "telegram reply sent",
      )
    } catch (error) {
      opts.logger.error(
        {
          error,
          updateID: ctx.update.update_id,
          chatID: ctx.chat.id,
          userID,
          durationMs: Date.now() - startedAt,
        },
        "telegram message handling failed",
      )
      await ctx.reply("I hit an internal error while preparing the reply. Check server logs.")
    } finally {
      // Clean up status message on error too
      await deleteStatusMessage().catch(() => {})
    }
  })

  bot.catch((err) => {
    opts.logger.error({ err, updateID: err.ctx?.update?.update_id }, "telegram bot error")
  })

  const startPromise = bot.start()
  void flushOutbox()
  setInterval(() => {
    void flushOutbox()
  }, 60000)
  opts.logger.info("telegram adapter started")
  await startPromise
}
