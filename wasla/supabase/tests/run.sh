#!/usr/bin/env bash
# تشغيل اختبارات SQL لدالة التسوية ضد Postgres.
# الاستخدام: DATABASE_URL=postgres://... ./run.sh
#   أو مع psql محلي:  PGHOST=... PGPORT=... PGUSER=... ./run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PSQL=(psql -v ON_ERROR_STOP=1)
[[ -n "${DATABASE_URL:-}" ]] && PSQL+=("$DATABASE_URL")

echo "== تطبيق الترحيلات =="
for f in migrations/*.sql; do
  echo "  $f"
  "${PSQL[@]}" -qf "$f" >/dev/null
done

echo "== تشغيل الاختبارات =="
# دمج stderr: الإشعارات (ok:) والأخطاء تظهر؛ ON_ERROR_STOP + pipefail يفشلان البناء.
"${PSQL[@]}" -f tests/settle_accept_test.sql 2>&1 | grep -E "ok:|ALL SQL TESTS PASSED"
