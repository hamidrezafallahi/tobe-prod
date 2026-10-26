# Backup / restore — production (P092)

## What

| Data | How |
|------|-----|
| PostgreSQL | `./scripts/backup-db.sh` → `backups/*.dump` (`pg_dump -Fc`) |
| Uploads (optional) | `./scripts/backup-db.sh --uploads` |

Keep dumps **off** the VPS disk as well (copy elsewhere). Retention default: last **14** dumps.

## Backup

```bash
cd /opt/institute
./scripts/backup-db.sh
# cron example (daily 02:15):
# 15 2 * * * cd /opt/institute && ./scripts/backup-db.sh >> /opt/institute/logs/backup.log 2>&1
```

## Restore (destructive)

```bash
./scripts/backup-db.sh                    # safety dump first
./scripts/restore-db.sh backups/LanguageInstituteDb-YYYYMMDD-HHMMSS.dump --force
```

Stops `institute-backend-prod`, restores DB, starts backend again.

## After restore

Login as Staff/Director and spot-check one enrollment / invoice / class list.

## Panel backups (Backup page)

The director can also back up and restore from the panel (`/dashboard/backup`): full backups (database + uploads
in one zip), database-only SQL dumps, an optional daily automatic backup, and restore from a full backup zip.

- Files live in `data/backups` on the VPS, mounted at `/app/backups` in the backend. They are separate from the
  `backups/*.dump` files that `scripts/backup-db.sh` writes.
- The backend runs as the image's `app` user (uid 1654). `deploy.sh` creates `data/backups` and hands it to that
  uid on every run; without it, backups fail with a permission error.
- nginx allows restore uploads up to 4 GB and waits up to 10 minutes on `/auth/bff/Backup/`.
- These copies stay on the same VPS: download them from the panel and keep them somewhere else too.

## Out of scope

WAL/PITR, S3 sync UI, soft-delete restore.
