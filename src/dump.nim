import storage
import terminal
import db_sqlite

let toEval = if isatty(stdin): "" else: readAll(stdin)

let db = newDB()
if toEval.len > 0:
  try:
    let q = sql(toEval)
    echo "Exe: ", repr q
    for r in db.db.rows(q):
      echo r
  except DbError:
    echo "Err: ", getCurrentExceptionMsg()
else:
  db.dump("users")
  db.dump("tags")
