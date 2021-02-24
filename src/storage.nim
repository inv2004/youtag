import db_sqlite
import os
import logging
import terminaltables
import options
import strutils
import locale
import sequtils
import tables
import strutils

const FILE = "db/db.db"
const DB_NAME = "youtag"
const NOW = "now"

const DEF_NOTIFY=60

const INIT_SQL = @[
  sql"""
CREATE TABLE IF NOT EXISTS tags (
  setter INT,
  user INT,
  tag TEXT,
  datetime TEXT,
  PRIMARY KEY(setter, user, tag)
)
""",
  sql"""
CREATE TABLE IF NOT EXISTS users (
  id INT,
  username TEXT,
  locale TEXT,
  active BOOLEAN,
  notify INTEGER,
  last TEXT,
  datetime TEXT,
  PRIMARY KEY(id)
)
"""
]

const INSERT_USER_SQL = sql"INSERT INTO users (id, username, locale, active, notify, last, datetime) VALUES(?,?,?,?,?,datetime(?),datetime(?))"
const REPLACE_USER_SQL = sql"REPLACE INTO users (id, username, locale, active, notify, last, datetime) VALUES(?,?,?,?,?,datetime(?),datetime(?))"
const INSERT_TAG_SQL = sql"INSERT INTO tags (setter, user, tag, datetime) VALUES(?,?,?,datetime(?))"
const SELECT_NOTIFICATIONS = sql"""
SELECT U.id, U.locale, T.tag, COUNT(1), datetime('now')
  FROM users U
 INNER JOIN tags T
    ON T.user = U.id
   AND T.datetime > U.last
 INNER JOIN tags TT
    ON TT.user = U.id
   AND TT.tag = T.tag
 WHERE U.active = 1
   AND U.notify > 0
   AND DATETIME(U.last, '+'||U.notify||' seconds') <= DATETIME('now')
 GROUP BY U.id, T.tag
"""

type
  DB* = ref object
    db*: DbConn

  User* = object
    id*: int
    username*: Option[string]
    locale*: Locale

using
  self: DB

proc newDB*(init = false): DB =
  createDir(parentDir(FILE));
  let db = db_sqlite.open(FILE, "", "", DB_NAME)

  if init:
    for sql in INIT_SQL:
      try:
        db.exec(sql)
      except DbError:
        let errMsg = getCurrentExceptionMsg()
        if not errMsg.startsWith("duplicate column name"):
          error errMsg
          raise getCurrentException()

  DB(db: db)

proc setUser*(self; user: User, active: bool) =
  try:
    if active:
      self.db.exec(REPLACE_USER_SQL, user.id, user.username.get(""), user.locale, 1, DEF_NOTIFY, NOW, NOW)
    else:
      self.db.exec(INSERT_USER_SQL, user.id, user.username.get(""), user.locale, 0, 0, NOW, NOW)
  except DbError:
    let errMsg = getCurrentExceptionMsg()
    if not errMsg.startsWith("UNIQUE constraint failed"):
      error "set failed: ", getCurrentExceptionMsg()
      raise getCurrentException()

# proc checkChat*(self; user: User) =
#   debug "user.id ", user.id, " set chat = ", user.chat
#   self.db.exec(sql"UPDATE users SET chat = ? WHERE id = ? AND chat <> ?", user.chat, user.id, user.chat)

proc setTag*(self; setterID: int, user: User, tags: seq[string]) =
  info "set from ", setterID, ": ", user, ": ", $tags

  setUser(self, user, false)

  for t in tags:
    try:
      discard self.db.insertID(INSERT_TAG_SQL, setterID, user.id, t.toLower(), NOW)
    except DbError:
      warn "set failed: ", getCurrentExceptionMsg()

proc checkMe*(self; userID: int): bool =
  0 < parseInt(self.db.getValue(sql"SELECT COUNT(1) FROM tags WHERE user = ?", userID))

proc setNotify*(self; userID: int, interval: int) =
  self.db.exec(sql"UPDATE users SET notify = ? WHERE id = ?", interval, userID)

proc me*(self; userID: int): string =
  let t = newUnicodeTable()
  t.setHeaders @["tag", "count"]
  for row in self.db.rows(sql"SELECT tag, COUNT(1) FROM tags WHERE user = ? GROUP BY tag", userID):
    t.addRow @[row[0], row[1]]
  return "<pre>" & t.render() & "</pre>"

proc my*(self; userID: int): string =
  for row in self.db.rows(sql"""SELECT IFNULL(users.username, tags.user), GROUP_CONCAT(tag, ", ")
  FROM tags
  LEFT OUTER JOIN users ON tags.user = users.id
  WHERE setter = ? GROUP BY user""",
      userID):
    result.add row[0] & ": " & row[1] & "\n"

  if result.len == 0:
    result = "You haven't tag anything yet"
  
  return "<pre>" & result & "</pre>"

proc userTags*(self; userID: int): seq[(string, int)] = # TODO: fix privacy
  for row in self.db.rows(sql"SELECT tag, COUNT(1) FROM tags WHERE user = ? GROUP BY tag", userID):
    result.add (row[0], row[1].parseInt())

proc userNameTags*(self; userName: string): seq[(string, int)] = # TODO: fix privacy
  for row in self.db.rows(sql"SELECT tag, COUNT(1) FROM tags INNER JOIN users ON users.username = ? WHERE tags.user = users.id GROUP BY tag", userName):
    result.add (row[0], row[1].parseInt())

proc topTags*(self): seq[string] =
  for row in self.db.rows(sql"SELECT tag, COUNT(1) AS C FROM tags GROUP BY tag ORDER BY C DESC, tag LIMIT 10"):
    result.add row[0]

proc top*(self): string =
  let t = newUnicodeTable()
  t.setHeaders @["tag", "count"]
  for row in self.db.rows(sql"SELECT tag, COUNT(1) AS C FROM tags GROUP BY tag ORDER BY C DESC, tag LIMIT 10"):
    t.addRow @[row[0], row[1]]
  return "<pre>" & t.render() & "</pre>"

proc getNotifications*(self): seq[(int, Locale, seq[(string, int)], string)] =
  var t = initTable[int, (Locale, seq[(string, int)], string)]()
  for row in self.db.rows(SELECT_NOTIFICATIONS):
    var a = t.getOrDefault(row[0].parseInt)
    a[0] = row[1].parseEnum(Ru)
    a[1].add (row[2], row[3].parseInt())
    a[2] = row[4]
    t[row[0].parseInt] = a

  for (k, v) in t.pairs:
    result.add (k, v[0], v[1], v[2])

proc setLast*(self; userID: int, datetime: string) =
  self.db.exec(sql"UPDATE users SET last = datetime(?) WHERE id = ?", datetime, userID)

proc getLocale*(self; userID: int, default: Locale): Locale =
  let locale = self.db.getValue(sql"SELECT locale from users WHERE id = ?", userID)
  locale.parseEnum(default)

proc setLocale*(self; userID: int, locale: Locale) =
  self.db.exec(sql"UPDATE users SET locale = ? WHERE id = ?", locale, userID)

proc toRow(x: InstantRow): seq[string] =
  for i in 0..<len(x):
    result.add x[i]

proc dump*(self; tblName: string) =
  let t = newUnicodeTable()
  t.separateRows = false

  var i = 0
  var cols: DbColumns
  for row in self.db.instantRows(cols, sql"SELECT * FROM ?", tblName):
    if i == 0:
      echo cols[0].tableName
      t.setHeaders cols.mapIt(it.name)
    t.addRow row.toRow()
    i.inc()
  t.printTable()

func close*(self) =
  self.db.close()
