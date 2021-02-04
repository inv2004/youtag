import telebot, asyncdispatch, logging, options
import strutils
import tables

const API_KEY = slurp("telegram.key")

const splitChar = Whitespace + {','}

var cache {.threadvar.}: TableRef[int, Message]

proc tags(x: string): seq[string] =
  x.split(splitChar)
  
proc processMsg(msg: Message): string {.gcsafe.} =
  let text = msg.text.get("")
  case text:
  of "/start": "send tag"
  of "/help": "usage"
  of "/stop": "stopped"
  else:
    let userID = msg.fromUser.get().id
    let user = msg.fromUser.get().username.get()
    if cache.hasKey(userID):
      let prev = cache[userID]
      if msg.forwardSenderName.isSome and prev.forwardSenderName.isNone:
        let t = tags(prev.text.get)
        let forUser = msg.forwardSenderName.get()
        info(user, ": set tag for ", forUser, ": ", $t)
        cache.del(userID)
      elif msg.forwardSenderName.isNone and prev.forwardSenderName.isSome:
        let t = tags(msg.text.get)
        let forUser = prev.forwardSenderName.get()
        info(user, ": set tag for ", forUser, ": ", $t)
        cache.del(userID)
      else:
        cache[userID] = msg
    else:
      cache[userID] = msg
    ""

proc updateHandler(b: Telebot, u: Update): Future[bool] {.async,gcsafe.} =
  if not u.message.isSome:
    return true
  let msg = u.message.get
  let resp = processMsg(msg)
  if resp.len > 0:
    discard await b.sendMessage(msg.chat.id, resp, parseMode = "markdown", disableNotification = true, replyToMessageId = msg.messageId)

proc main() =
  addHandler(newConsoleLogger())
  setLogFilter(lvlInfo)

  cache = newTable[int, Message]()

  # setLogFilter(lvlDebug)
  let bot = newTeleBot(API_KEY)
  info("started")
  bot.onUpdate(updateHandler)
  bot.poll(timeout=300)

when isMainModule:
  main()
