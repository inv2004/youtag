import db_sqlite
import os
import logging
import terminaltables
import options
import strutils
import locale

const FILE = "db/db.db"
const DB_NAME = "youtag"

const INIT_SQL = @[
  sql"""
CREATE TABLE IF NOT EXISTS tags (
  setter INT,
  user INT,
  tag TEXT,
  PRIMARY KEY(setter, user, tag)
)
""",
  sql"""
CREATE TABLE IF NOT EXISTS users (
  id INT,
  username TEXT,
  locale TEXT,
  active BOOLEAN,
  PRIMARY KEY(id, username)
)
""",
  sql"ALTER TABLE users ADD COLUMN datetime TEXT",
  sql"UPDATE users SET datetime = datetime('now') WHERE datetime IS NULL",
  sql"ALTER TABLE tags ADD COLUMN datetime TEXT",
  sql"UPDATE tags SET datetime = datetime('now') WHERE datetime IS NULL"
]

const INSERT_USER_SQL = sql"INSERT INTO users (id, username, locale, active, datetime) VALUES(?,?,?,?,datetime('now'))"
const REPLACE_USER_SQL = sql"REPLACE INTO users (id, username, locale, active, datetime) VALUES(?,?,?,datetime('now'))"
const INSERT_TAG_SQL = sql"INSERT INTO tags (setter, user, tag, datetime) VALUES(?,?,?,datetime('now'))"

type
  DB* = ref object
    db*: DbConn

  User* = object
    id*: int
    username*: Option[string]
    locale*: Locale

using
  self: DB

proc newDB*(): DB =
  createDir(parentDir(FILE));
  let db = db_sqlite.open(FILE, "", "", DB_NAME)
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
  # if user.username.isSome:
  try:
    if active:
      self.db.exec(REPLACE_USER_SQL, user.id, user.username.get, user.locale, "1")
    else:
      self.db.exec(INSERT_USER_SQL, user.id, user.username.get, user.locale, "0")
  except DbError:
    let errMsg = getCurrentExceptionMsg()
    if not errMsg.startsWith("UNIQUE constraint failed"):
      error "set failed: ", getCurrentExceptionMsg()
      raise getCurrentException()

proc setTag*(self; setterID: int, user: User, tags: seq[string]) =
  info "set from ", setterID, ": ", user, ": ", $tags

  setUser(self, user, false)

  for t in tags:
    try:
      discard self.db.insertID(INSERT_TAG_SQL, setterID, user.id, t)
    except DbError:
      warn "set failed: ", getCurrentExceptionMsg()

proc checkMe*(self; userID: int): bool =
  0 < parseInt(self.db.getValue(sql"SELECT COUNT(1) FROM tags WHERE user = ?", userID))

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
  for row in self.db.rows(sql"SELECT tag, COUNT(1) AS C FROM tags GROUP BY tag ORDER BY C DESC LIMIT 10"):
    result.add row[0]

proc dump*(self; tblName: string) =
  for row in self.db.rows(sql"SELECT * FROM ?", tblName):
    echo row

func close*(self) =
  self.db.close()
