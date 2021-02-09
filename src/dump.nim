import storage
import terminal
import db_sqlite
import strutils

let toEval = if isatty(stdin): "" else: readAll(stdin)

let db = newDB()
if toEval.len > 0:
  try:
    for s in toEval.split(";"):
      let q = s.strip(true, true)
      if q.len == 0:
        continue
      echo "Exe: ", q
      for r in db.db.rows(sql(q)):
        echo r
  except DbError:
    echo "Err: ", getCurrentExceptionMsg()
else:
  db.dump("users")
  db.dump("tags")
