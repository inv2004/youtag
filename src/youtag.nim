import storage

import telebot, asyncdispatch, logging, options
import strutils
import sequtils
import tables
import unicode
import uchars

const API_KEY = slurp("telegram.key")

const BTNS_TIMEOUT = 30 * 1000
const BTNS_ROW_SIZE = 5

let BOT_COMMANDS = @[
  BotCommand(command: "help", description: "usage"),
  BotCommand(command: "me", description: "tags on me"),
  BotCommand(command: "my", description: "my tags"),
  BotCommand(command: "top", description: "top tags/users")
]

type
  Bot = object
    db: DB
    cache: TableRef[int, Message]

proc tags(x: string): seq[string] =
  for t in unicode.split(x, spacesRunes):
    result.add unicode.strip(t, true, true, stripRunes)

proc `from`(m: Message): (bool, storage.User) =
  if m.forwardDate.isSome:
    if m.forwardFrom.isSome:
      let user = storage.User(id: m.forwardFrom.get.id, username: m.forwardFrom.get.username)
      return (true, user)
    raise newException(ValueError, "The user is protected by her(his) privacy settings")

proc reply(b: TeleBot, orig: Message, msg: string) {.async.} =
  let mode = if msg.startsWith("<pre>"): "html" else: "markdown"

  let m =
    if msg.len > 4000:
      msg[0..3990] & "..."
    else:
      msg

  discard await b.sendMessage(orig.chat.id, m,
                        parseMode = mode,
                        disableNotification = true,
                        replyToMessageId = orig.messageId
                        )

proc processCmd(ft: Bot, user: storage.User, cmd: string): string =
  case cmd:
  of "/start":
    ft.db.setUser(user)
    return """YouTag   -   Tag the World!
  
Hello,
  The bot helps to collect anonymous feedbacks across the internet and classify users

*Forward* message from any user and *add* space or comma separated *tags* in text.

The user can check his tags without information about setter.

Tag length is from 4 to 25 characters.

Use /help for help

"""
  of "/help": return """
  Forward message from any user and add space- or comma-separated tags in text.

  /help        - usage
  /me          - show tags you marked with
  /my          - show tags set by you
  /top         - top tags and users
  /top #[tag]  - top user's with the tag
  /top @[user] - top tag's for the user

"""
  of "/me": return ft.db.me(user.id)
  of "/my": return ft.db.my(user.id)
  of "/stop": return "stopped"
  elif cmd.startsWith("/top"):
    return "This command is temporary disabled due to the toxicity of IT community"
  else:
    return "Unknown command, check /help please"

proc showTopButtons(b: Telebot, ft: Bot, orig: Message, msg: string, userID: int): Future[Message] {.async.} =
  if orig.fromUser.isNone:
    raise newException(ValueError, "fromUser")

  let setter = orig.fromUser.get().id

  var btns = newSeq[seq[InlineKeyboardButton]](2)
  for i, tt in ft.db.topTags():
    var b = initInlineKeyBoardButton(tt)
    b.callbackData = some(@["set",$setter,$userID,tt].join(":"))
    btns[int(i / BTNS_ROW_SIZE)].add b

  let replyMarkup = newInlineKeyboardMarkup(btns)
  return await b.sendMessage(orig.chat.id, msg, disableNotification = true, replyMarkup = replyMarkup)

proc hideButtons(b: Telebot, orig: Message, msg: string) {.async.} =
  let markup = newInlineKeyboardMarkup()
  discard await b.editMessageText(msg, $orig.chat.id, orig.messageId, replyMarkup = markup)

proc processMsg(b: Telebot, ft: Bot, msg: Message) {.async.} =
  let user = storage.User(id: msg.fromUser.get().id, username: msg.fromUser.get().username)
  debug "User: ", user

  let text = msg.text.get("")
  if text.startsWith("/") and msg.forwardDate.isNone:
    await b.reply(msg, processCmd(ft, user, text))
    ft.cache.del(user.id)
  else:
    if ft.cache.hasKey(user.id):
      debug "has cache for ", user.id
      let prev = ft.cache[user.id]
      let (isPrevFrom, prevFrom) = `from`(prev)
      let (isCurFrom, curFrom) = `from`(msg)
      if isCurFrom and not isPrevFrom:
        debug "prev text"
        let t = tags(prev.text.get)
        ft.db.setTag(user.id, curFrom, t)
        ft.cache[user.id] = msg
        let btns = await showTopButtons(b, ft, msg, "You can add more tags manually or with the following buttons:", curFrom.id)
        await sleepAsync(BTNS_TIMEOUT)
        await hideButtons(b, btns, "Done")
        ft.cache.del(user.id)
      elif (not isCurFrom) and isPrevFrom:
        debug "current text"
        let t = tags(text)
        ft.db.setTag(user.id, prevFrom, t)
        let btns = await showTopButtons(b, ft, msg, "You can add more tags manually or with the following buttons:", curFrom.id)
        await sleepAsync(BTNS_TIMEOUT)
        await hideButtons(b, btns, "Done")
        ft.cache.del(user.id)
      else:
        error "brr"
    else:
      debug "no cache for ", user.id
      ft.cache[user.id] = msg
      let (isCurFrom, curFrom) = `from`(msg)
      if isCurFrom:
        let btns = await showTopButtons(b, ft, msg, "Enter space or comma separated tags manually or add via the buttons:", curFrom.id)
        await sleepAsync(BTNS_TIMEOUT)
        await hideButtons(b, btns, "Done")
        ft.cache.del(user.id)

proc main() =
  addHandler(newConsoleLogger(fmtStr=verboseFmtStr))
  addHandler(newRollingFileLogger(fmtStr=verboseFmtStr, maxlines=100000))
  setLogFilter(lvlDebug)

  let ft = Bot(cache: newTable[int, Message](), db: newDB())
  defer: ft.db.close()

  let bot = newTeleBot(API_KEY)

  proc updateHandler(b: Telebot, u: Update): Future[bool] {.async.} =
    if u.callbackQuery.isSome:
      if u.callbackQuery.get.data.isNone:
        warn "data not found"
        return
      if u.callbackQuery.get.message.isNone:
        warn "message not found"
        return
      

      let msg = u.callbackQuery.get.message.get
      let markup = msg.replyMarkup.get
      let data = u.callbackQuery.get.data.get
      let fs = data.split(":")

      if fs[0] == "set":
        let user = storage.User(id:fs[2].parseInt(), username:none(string))
        ft.db.setTag(fs[1].parseInt(), user, @[fs[3]])
        for x in markup.inlineKeyboard.mitems:
          x.keepItIf(it.callbackData.get != data)
        discard await b.editMessageReplyMarkup($msg.chat.id, msg.messageId, "", markup)

      return false
    if not u.message.isSome:
      debug "ups"
      return false
    let msg = u.message.get
    try:
      await processMsg(b, ft, msg)
    except:
      error getCurrentExceptionMsg()
      await b.reply(msg, getCurrentExceptionMsg().split("\n")[0])

  info("set commands")

  doAssert waitFor bot.setMyCommands(BOT_COMMANDS)

  info("started")

  bot.onUpdate(updateHandler)
  bot.poll(timeout=300)

when isMainModule:
  main()
