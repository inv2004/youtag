import storage

import telebot, asyncdispatch, logging, options
import strutils
import sequtils
import tables
import unicode
import uchars
import locale

const API_KEY = slurp("telegram.key")

const MSG_TIMEOUT = 900
const BTNS_TIMEOUT = 30 * 1000
const BTNS_ROW_SIZE = 2

const NOTIFY_DELAY = 60 * 1000

let BOT_COMMANDS = @[
  BotCommand(command: "help", description: "Usage"),
  BotCommand(command: "on", description: "Receive notifications about new tags"),
  BotCommand(command: "off", description: "Receive notifications (default)"),
  BotCommand(command: "me", description: "Tags on me"),
  BotCommand(command: "my", description: "My tags"),
  BotCommand(command: "id", description: "Id for user (after message forward)"),
  BotCommand(command: "top", description: "Top tags/users"),
  BotCommand(command: "lang", description: "Switch language"),
]

type
  ProtectedUserError = object of ValueError

  SetKind = enum KReadyFrom, KReadyText, KFrom, KText 

  CacheEntity = ref object
    id: int
    fID: int
    f: Option[storage.User]
    t: string
    btnsMsg: Option[Message]

  Bot = object
    db: DB
    cache: TableRef[int, CacheEntity]

proc set(e: CacheEntity, msg: Message): SetKind =
  if msg.forwardDate.isSome:
    if msg.forwardFrom.isSome:
      let user = storage.User(
        id: msg.forwardFrom.get.id,
        username: msg.forwardFrom.get.username,
        locale: msg.fromUser.get().languageCode.get("ru").parseEnum(Ru)
      )
      e.f = some(user)
      e.id = msg.messageId
      e.fID = msg.messageId

      if e.t.len > 0:
        return KReadyFrom
      else:
        return KFrom
    raise newException(ProtectedUserError, "protected user")
  elif msg.text.isSome:
    e.t = msg.text.get
    e.id = msg.messageId

    if e.f.isSome:
      return KReadyText
    else:
      return KText
  else:
    raise newException(ValueError, "unknown state")

proc mapTag(x: (string, int)): string =
  result = x[0]
  if x[1] > 1:
    result = "*" & result & "*"

proc sendNotifications(b: TeleBot, ft: Bot) {.async.} =
  while true:
    debug "notify timer"
    for (userID, locale, tags, datetime) in ft.db.getNotifications():
      debug userID, "(", locale, "): ", tags, " ", datetime
      let text = "New tags: " & tags.map(mapTag).join(", ") & "\n\n" & userTagsHelp[locale]
      discard await b.sendMessage(userID, text, "markdown", disableNotification = true)
      ft.db.setLast(userID, datetime)
      await sleepAsync(100)
    await sleepAsync(NOTIFY_DELAY)

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

proc tags(b: TeleBot, orig: Message, user: storage.User, x: string): Future[seq[string]] {.async.} =
  var errTags: seq[string]

  for t in unicode.split(x, spacesRunes):
    let tag = unicode.strip(t, true, true, stripRunes)
    let len = tag.runeLen()
    if len == 0:
      continue
    if len in TAG_RUNES:
      result.add tag
    else:
      errTags.add tag

  if errTags.len > 0:
    await b.reply(orig, wrong[user.locale] & errTags.join(", "))

proc checkOnStart(b: TeleBot, ft: Bot, orig: Message, user: storage.User) {.async.} =
  if ft.db.checkMe(user.id):
    await b.reply(orig, found[user.locale])

proc replyTags(b: Telebot, orig: Message, user: storage.User, userT: seq[(string, int)]) {.async.} =
    let respT = if userT.len > 0:
                  tagsForUser[user.locale] & userT.map(mapTag).join(", ") & "\n\n" & userTagsHelp[user.locale]
                else:
                  noTagsForUser[user.locale]
    await b.reply(orig, respT)

proc replyIn1S(b: TeleBot, ft: Bot, msg: Message, userID: int, text: string) {.async.} =
  await sleepAsync(MSG_TIMEOUT)
  if userID in ft.cache and ft.cache[userID].id == msg.messageId:
    await b.reply(msg, text)
    ft.cache.del(userID)

proc convInterval(str: string): int =
  case str:
  of "1m": 60
  of "1h": 60*60
  of "1d": 24*60*60
  else:
    raise newException(ValueError, "Error: Inteval can be 1m, 1h or 1d")

proc genLangKeyboard(user: storage.User): InlineKeyboardMarkup =
  if user.locale == Ru:
    var btn = initInlineKeyBoardButton("English")
    btn.callbackData = some(@["loc", $user.id, "en"].join(":"))
    result = newInlineKeyboardMarkup(@[btn])
  else:
    var btn = initInlineKeyBoardButton("Русский")
    btn.callbackData = some(@["loc", $user.id, "ru"].join(":"))
    result = newInlineKeyboardMarkup(@[btn])

proc processCmd(b: TeleBot, ft: Bot, orig: Message, user: storage.User, cmd: string) {.async.} =
  case cmd:
  of "/start":
    ft.db.setUser(user, true)

    discard await b.sendMessage(orig.chat.id, locale.title & "\n\n" & hello[user.locale],
                          parseMode = "markdown",
                          disableNotification = true,
                          replyToMessageId = orig.messageId,
                          replyMarkup = genLangKeyboard(user)
                          )

    await checkOnStart(b, ft, orig, user)
  of "/help": await b.reply(orig, help[user.locale])
  of "/on":
    ft.db.setNotify(user.id, convInterval("1m"))
    await b.reply(orig, onNote[user.locale])
  of "/off":
    ft.db.setNotify(user.id, 0)
    await b.reply(orig, offNote[user.locale])
  of "/me": await b.reply(orig, ft.db.me(user.id))
  of "/my": await b.reply(orig, ft.db.my(user.id))
  of "/id": await b.reply(orig, idUsage[user.locale])
  of "/lang en", "/lang ru":
    let locale = cmd[6..^1].parseEnum(Ru)
    ft.db.setLocale(user.id, locale)
    await b.reply(orig, localeSwitch[locale])
  of "/stop": await b.reply(orig, stopped[user.locale])
  elif cmd.startsWith("/top"): await b.reply(orig, top[user.locale])
  elif cmd.startsWith("/id @"): await b.replyTags(orig, user, ft.db.userNameTags(cmd[5..^1]))
  elif cmd.startsWith("/on "):
    ft.db.setNotify(user.id, convInterval(cmd[4..^1]))
    await b.reply(orig, onNote[user.locale])
  else: await b.reply(orig, unknown[user.locale])

proc hideButtons(b: Telebot, orig: Message, msg: string, delete: bool) {.async.} =
  if delete:
    discard await b.deleteMessage($orig.chat.id, orig.messageId)
  else:
    let markup = newInlineKeyboardMarkup()
    discard await b.editMessageText(msg, $orig.chat.id, orig.messageId, replyMarkup = markup)

proc showTopButtons30S(b: Telebot, ft: Bot, orig: Message, entity: CacheEntity, user: storage.User) {.async.} =
  if orig.fromUser.isNone:
    raise newException(ValueError, "fromUser")

  let setter = orig.fromUser.get().id
  let fID = entity.f.get.id

  var btns = newSeq[seq[InlineKeyboardButton]](10 div BTNS_ROW_SIZE)
  for i, tt in ft.db.topTags():
    var b = initInlineKeyBoardButton($(i+1) & ". " & tt)
    b.callbackData = some(@["set",$setter,$fID,tt].join(":"))
    btns[int(i / BTNS_ROW_SIZE)].add b

  let replyMarkup = newInlineKeyboardMarkup(btns)

  var entity = ft.cache[user.id]
  if entity.btnsMsg.isSome:
    let oldBtnsMsg = entity.btnsMsg.get
    entity.btnsMsg = none(Message)
    debug "BTN OLD: ", oldBtnsMsg.messageId
    asyncCheck hideButtons(b, oldBtnsMsg, done[user.locale], true)

  let btnsMsg = await b.sendMessage(orig.chat.id, tag[user.locale], disableNotification = true, replyMarkup = replyMarkup)
  debug "BTN ASSIGN: ", btnsMsg.messageId
  entity.btnsMsg = some(btnsMsg)

  await sleepAsync(BTNS_TIMEOUT)

  if user.id in ft.cache:
    let entity = ft.cache[user.id]
    if entity.btnsMsg.isSome:
      debug "BTN DROP de: ", entity.btnsMsg.get.messageId
      await hideButtons(b, entity.btnsMsg.get, done[user.locale], false)
      ft.cache.del(user.id)

proc processTag(b: TeleBot, ft: Bot, msg: Message, user: storage.User, entity: CacheEntity, delay: bool) {.async.} =
  if delay:
    await sleepAsync(MSG_TIMEOUT)
  if entity.t == "/id":
    if user.id in ft.cache and ft.cache[user.id].fID != entity.fID:
      debug("exit processTag")
      return
    await b.replyTags(msg, user, ft.db.userTags(entity.f.get.id))
    ft.cache.del(user.id)
  else:
    let t = await tags(b, msg, user, entity.t)
    if user.id in ft.cache and ft.cache[user.id].fID != entity.fID:
      debug("exit processTag")
      return
    ft.db.setTag(user.id, entity.f.get, t)
    await showTopButtons30S(b, ft, msg, entity, user)

proc processMsg(b: Telebot, ft: Bot, user: storage.User, msg: Message) {.async.} =
  # ft.db.checkChat(user)
  let text = msg.text.get("")
  if text.startsWith("/") and msg.forwardDate.isNone and text != "/id":
    await b.processCmd(ft, msg, user, text)
    ft.cache.del(user.id)
  else:
    var entity = ft.cache.mgetOrPut(user.id, CacheEntity())
    let st = entity.set(msg)
    case st:
    of KReadyFrom:
      debug st
      await processTag(b, ft, msg, user, entity, false)
    of KReadyText:
      debug st
      await processTag(b, ft, msg, user, entity, true)
    of KFrom:
      debug st
      await showTopButtons30S(b, ft, msg, entity, user)
    of KText:
      debug st
      if text == "/id":
        await b.replyIn1S(ft, msg, user.id, idUsage[user.locale])
      else:
        await b.replyIn1S(ft, msg, user.id, forwardHelp[user.locale])

proc main() =
  addHandler(newConsoleLogger(fmtStr=verboseFmtStr))
  addHandler(newRollingFileLogger(fmtStr=verboseFmtStr, maxlines=100000))
  setLogFilter(lvlDebug)

  let ft = Bot(cache: newTable[int, CacheEntity](), db: newDB(init = true))
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
      elif fs[0] == "loc":
        let user = storage.User(id: fs[1].parseInt(), locale: fs[2].parseEnum(Ru))
        ft.db.setLocale(user.id, user.locale)
        debug msg.text.get
        try:
          discard await b.editMessageText(hello[user.locale], $msg.chat.id, msg.messageId, replyMarkup = genLangKeyboard(user))
        except IOError:
          if getCurrentExceptionMsg() != "Bad Request: message is not modified":
            raise getCurrentException()

      return false
    if not u.message.isSome:
      warn "not a message"
      return false
    let msg = u.message.get

    let id = msg.fromUser.get().id
    let locale = ft.db.getLocale(id, msg.fromUser.get().languageCode.get("ru").parseEnum(Ru))

    var user = storage.User(
      id: id,
      username: msg.fromUser.get().username,
      locale: locale
    )
    debug "User: ", user

    try:
      await processMsg(b, ft, user, msg)
    except ProtectedUserError:
      warn getCurrentExceptionMsg()
      await b.reply(msg, protected[user.locale])
    except:
      error getCurrentExceptionMsg()
      await b.reply(msg, getCurrentExceptionMsg().split("\n")[0])

  info("set commands")

  doAssert waitFor bot.setMyCommands(BOT_COMMANDS)

  asyncCheck sendNotifications(bot, ft)

  info("started")

  bot.onUpdate(updateHandler)

  while true:
    try:
      bot.poll(timeout=300)
    except:
      error getCurrentExceptionMsg()

when isMainModule:
  main()
