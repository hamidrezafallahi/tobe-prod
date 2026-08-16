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
# 15 2 * * * cd /opt/institute && ./scripts/backup-db.sh >> /var/log/institute-backup.log 2>&1
```

## Restore (destructive)

```bash
./scripts/backup-db.sh                    # safety dump first
./scripts/restore-db.sh backups/LanguageInstituteDb-YYYYMMDD-HHMMSS.dump --force
```

Stops `institute-backend-prod`, restores DB, starts backend again.

## After restore

Login as Staff/Director and spot-check one enrollment / invoice / class list.

## Out of scope

WAL/PITR, S3 sync UI, soft-delete restore.
