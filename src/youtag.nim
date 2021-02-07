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
const BTNS_ROW_SIZE = 5

let BOT_COMMANDS = @[
  BotCommand(command: "help", description: "usage"),
  BotCommand(command: "me", description: "tags on me"),
  BotCommand(command: "my", description: "my tags"),
  BotCommand(command: "id", description: "id for user (after message forward)"),
  BotCommand(command: "top", description: "top tags/users")
]

type
  ProtectedUserError = object of ValueError

  Bot = object
    db: DB
    cache: TableRef[int, Message]

proc `from`(msg: Message): (bool, storage.User) =
  if msg.forwardDate.isSome:
    if msg.forwardFrom.isSome:
      let user = storage.User(
        id: msg.forwardFrom.get.id,
        username: msg.forwardFrom.get.username,
        locale: msg.fromUser.get().languageCode.get("ru").parseEnum(Ru)
      )
      return (true, user)
    raise newException(ProtectedUserError, "protected user")

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

proc mapTag(x: (string, int)): string =
  result = x[0]
  if x[1] > 1:
    result = "*" & result & "*"

proc replyTags(b: Telebot, orig: Message, user: storage.User, userT: seq[(string, int)]) {.async.} =
    let respT = if userT.len > 0:
                  tagsForUser[user.locale] & userT.map(mapTag).join(", ") & "\n\n" & userTagsHelp[user.locale]
                else:
                  noTagsForUser[user.locale]
    await b.reply(orig, respT)

proc replyIn1S(b: TeleBot, ft: Bot, msg: Message, userID: int, text: string) {.async.} =
  await sleepAsync(MSG_TIMEOUT)
  if ft.cache.getOrDefault(userID).messageId == msg.messageId:
    await b.reply(msg, text)
    ft.cache.del(userID)


proc processCmd(b: TeleBot, ft: Bot, orig: Message, user: storage.User, cmd: string) {.async.} =
  case cmd:
  of "/start":
    ft.db.setUser(user)
    await b.reply(orig, locale.title & "\n\n" & hello[user.locale])

    await checkOnStart(b, ft, orig, user)
  of "/help": await b.reply(orig, help[user.locale])
  of "/me": await b.reply(orig, ft.db.me(user.id))
  of "/my": await b.reply(orig, ft.db.my(user.id))
  of "/id": await b.reply(orig, idUsage[user.locale])
  of "/stop": await b.reply(orig, stopped[user.locale])
  elif cmd.startsWith("/top"): await b.reply(orig, top[user.locale])
  elif cmd.startsWith("/id @"): await b.replyTags(orig, user, ft.db.userNameTags(cmd[5..^1]))
  else: await b.reply(orig, unknown[user.locale])

proc hideButtons(b: Telebot, orig: Message, msg: string) {.async.} =
  let markup = newInlineKeyboardMarkup()
  discard await b.editMessageText(msg, $orig.chat.id, orig.messageId, replyMarkup = markup)

proc showTopButtons30S(b: Telebot, ft: Bot, orig: Message, userID: int, user: storage.User) {.async.} =
  if orig.fromUser.isNone:
    raise newException(ValueError, "fromUser")

  let setter = orig.fromUser.get().id

  var btns = newSeq[seq[InlineKeyboardButton]](2)
  for i, tt in ft.db.topTags():
    var b = initInlineKeyBoardButton($(i+1) & ". " & tt)
    b.callbackData = some(@["set",$setter,$userID,tt].join(":"))
    btns[int(i / BTNS_ROW_SIZE)].add b

  let replyMarkup = newInlineKeyboardMarkup(btns)
  let btnsMsg = await b.sendMessage(orig.chat.id, tag[user.locale], disableNotification = true, replyMarkup = replyMarkup)

  await sleepAsync(BTNS_TIMEOUT)
  await hideButtons(b, btnsMsg, done[user.locale])
  ft.cache.del(userID)

proc processTag(b: TeleBot, ft: Bot, msg: Message, user, fromUser: storage.User, txtMsg, fromMsg: Message, delay: bool) {.async.} =
  if delay:
    await sleepAsync(MSG_TIMEOUT)
  let text = txtMsg.text.get
  if text == "/id":
    if ft.cache.getOrDefault(user.id).messageId != fromMsg.messageId:
      debug("exit processTag")
      return
    await b.replyTags(msg, user, ft.db.userTags(fromUser.id))
    ft.cache.del(user.id)
  else:
    let t = await tags(b, msg, user, text)
    if ft.cache.getOrDefault(user.id).messageId != fromMsg.messageId:
      debug("exit processTag")
      return
    ft.db.setTag(user.id, fromUser, t)
    await showTopButtons30S(b, ft, msg, fromUser.id, user)

proc processMsg(b: Telebot, ft: Bot, user: storage.User, msg: Message) {.async.} =
  let text = msg.text.get("")
  if text.startsWith("/") and msg.forwardDate.isNone and text != "/id":
    await b.processCmd(ft, msg, user, text)
    ft.cache.del(user.id)
  else:
    if ft.cache.hasKey(user.id):
      debug "has cache for ", user.id
      let prev = ft.cache[user.id]
      let (isPrevFrom, prevFrom) = `from`(prev)
      let (isCurFrom, curFrom) = `from`(msg)
      if isCurFrom and not isPrevFrom:
        debug "prev text"
        ft.cache[user.id] = msg
        await processTag(b, ft, msg, user, curFrom, prev, msg, false)
      elif (not isCurFrom) and isPrevFrom:
        debug "current text"
        await processTag(b, ft, msg, user, prevFrom, msg, prev, true)
      else:
        error "brr"
    else:
      debug "no cache for ", user.id
      ft.cache[user.id] = msg
      if text == "/id":
        await b.replyIn1S(ft, msg, user.id, idUsage[user.locale])
      else:
        let (isCurFrom, curFrom) = `from`(msg)
        if isCurFrom:
          await showTopButtons30S(b, ft, msg, curFrom.id, user)
        else:
          await b.replyIn1S(ft, msg, user.id, forwardHelp[user.locale])

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
      warn "not a message"
      return false
    let msg = u.message.get
    let user = storage.User(
      id: msg.fromUser.get().id,
      username: msg.fromUser.get().username,
      locale: msg.fromUser.get().languageCode.get("ru").parseEnum(Ru)
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

  info("started")

  bot.onUpdate(updateHandler)
  bot.poll(timeout=300)

when isMainModule:
  main()
