import db_sqlite
import os
import logging
import terminaltables
import options

const FILE = "db/db.db"
const DB_NAME = "youtag"
const TAG_LOW = 4
const TAG_HIGH = 25

const INIT_TBL_1 = sql"""
  CREATE TABLE IF NOT EXISTS tags (
    setter INT,
    user INT,
    tag TEXT,
    PRIMARY KEY(setter, user, tag)
  )
"""

const INIT_TBL_2 = sql"""
  CREATE TABLE IF NOT EXISTS users (
    id INT,
    username TEXT,
    active BOOLEAN,
    PRIMARY KEY(id, username)
  )
"""

const INSERT_USER_SQL = sql"INSERT INTO users (id, username, active) VALUES(?,?,1)"
const INSERT_TAG_SQL = sql"INSERT INTO tags (setter, user, tag) VALUES(?,?,?)"

type
  DB* = ref object
    db: DbConn

  User* = object
    id*: int
    username*: Option[string]

using
  self: DB

proc newDB*(): DB =
  createDir(parentDir(FILE));
  let db = db_sqlite.open(FILE, "", "", DB_NAME)
  db.exec(INIT_TBL_1)
  db.exec(INIT_TBL_2)

  DB(db: db)

proc setUser*(self; user: User) =
  if user.username.isSome:
    try:
      discard self.db.insertID(INSERT_USER_SQL, user.id, user.username.get)
    except DbError:
      warn "set failed: ", getCurrentExceptionMsg()

proc setTag*(self; setterID: int, user: User, tags: seq[string]) =
  info "set from ", setterID, ": ", user, ": ", $tags

  setUser(self, user)

  for t in tags:
    if t.len notin TAG_LOW..TAG_HIGH:
      continue
    try:
      discard self.db.insertID(INSERT_TAG_SQL, setterID, user.id, t)
    except DbError:
      warn "set failed: ", getCurrentExceptionMsg()

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

proc topTags*(self): seq[string] =
  for row in self.db.rows(sql"SELECT tag, COUNT(1) AS C FROM tags GROUP BY tag ORDER BY C DESC LIMIT 10"):
    result.add row[0]

proc dump*(self; tblName: string) =
  for row in self.db.rows(sql"SELECT * FROM ?", tblName):
    echo row

func close*(self) =
  self.db.close()

