# PostgreSQL backup and restore

The daily CronJob writes custom-format `pg_dump` archives to a 2-GiB PVC and retains seven days. The PostgreSQL Pod mounts that PVC read-only so both local-path claims bind on the same node; the CronJob writes it. This is a logical backup on the database's failure domain, not protection against losing that node/VM. Export an archive and copy it to an access-controlled, encrypted destination outside the Colima disk before a destructive experiment.

Preconditions: a healthy source namespace with `backup.enabled=true`, a known completed job ID, enough local/PVC space, and an unused restore namespace. Export uses a narrowly scoped, non-root read-only reader Pod, not privileged host access.

```bash
bash scripts/backup.sh kind-sre-lab taskflow-dev
```

The script prints `BACKUP_PATH=...`; the adjacent checksum and job log are evidence. Use that exact path in the restore command (replace the marked placeholder):

```bash
bash scripts/restore.sh kind-sre-lab taskflow-dev <PRINTED_BACKUP_PATH.dump> taskflow-restore-drill
kubectl --context kind-sre-lab --namespace taskflow-restore-drill port-forward service/taskflow-taskflow 18082:80
curl --fail http://127.0.0.1:18082/v1/jobs/<KNOWN_JOB_UUID>
bash scripts/smoke.sh http://127.0.0.1:18082
```

Restore refuses an existing namespace, verifies the archive/checksum, creates a new random database password, installs an empty database with migrations/API/workers initially disabled, imports data with `--exit-on-error`, then starts the application. It does not overwrite the source or run `pg_restore --clean`. The source API must exist so its image reference can be copied; for total-cluster recovery, recover the exact digest from Git and perform an explicitly reviewed manual restore sequence before bringing the app up.

Acceptance: compare the known job's ID, terminal status and result; check schema migration records; create and complete a new job; record archive SHA256/size, backup start, restore start, ready time and validation time. RPO is time since the last recoverable archive, not the Cron schedule; RTO ends only after application validation.

Failure checks: a Pending backup PVC can indicate `WaitForFirstConsumer` or local-path node affinity; a failed dump may be authentication, database readiness or a full disk. Inspect the Job and logs without printing database credentials. A missing or never-successful CronJob also needs attention: a timestamp-only stale-backup alert cannot detect every absent series.

Keep the restored namespace for evidence review. Delete only that explicitly named disposable namespace after confirming it is not the source and no retained data is needed. Test scripts remove their own temporary cluster; manual recovery scripts intentionally do not delete your recovered data.
