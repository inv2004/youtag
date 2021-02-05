import db_sqlite
import os
import logging
import terminaltables

const FILE = "db/db.db"
const DB_NAME = "facetag"
const TAG_LOW = 3
const TAG_HIGH = 25

const INIT_SQL = sql"""
  CREATE TABLE IF NOT EXISTS tags (
    setter TEXT,
    user TEXT,
    tag TEXT,
    PRIMARY KEY(setter, user, tag)
  )
"""

const INSERT_SQL = sql"INSERT INTO tags (setter, user, tag) VALUES(?,?,?)"

type
  DB* = ref object
    db: DbConn

using
  self: DB

proc newDB*(): DB =
  createDir(parentDir(FILE));
  let db = db_sqlite.open(FILE, "", "", DB_NAME)
  db.exec(INIT_SQL)

  DB(db: db)

proc set*(self; setter, user: string, tags: seq[string]) =
  info "set from ", setter, ": ", user, ": ", $tags
  for t in tags:
    if t.len notin TAG_LOW..TAG_HIGH:
      continue
    try:
      discard self.db.insertID(INSERT_SQL, setter, user, t)
    except DbError:
      warn "set failed: ", getCurrentExceptionMsg()

proc stat*(self; user: string): string =
  let t = newUnicodeTable()
  t.setHeaders @["tag", "count"]
  for row in self.db.rows(sql"SELECT tag, COUNT(1) FROM tags WHERE user = ? GROUP BY tag", user):
    t.addRow @[row[0], row[1]]
  return "<pre>\n" & t.render() & "\n</pre>"

proc my*(self; user: string): string =
  for row in self.db.rows(sql"""SELECT user, GROUP_CONCAT(tag, ", ") FROM tags WHERE setter = ? GROUP BY user""", user):
    result.add row[0] & ": " & row[1] & "\n"
  
  return "<pre>\n" & result & "</pre>"

proc topTags*(self): seq[string] =
  for row in self.db.rows(sql"SELECT tag, COUNT(1) AS C FROM tags GROUP BY tag ORDER BY C DESC LIMIT 10"):
    result.add row[0]

proc dump*(self) =
  for row in self.db.rows(sql"SELECT * FROM tags"):
    echo row

func close*(self) =
  self.db.close()

