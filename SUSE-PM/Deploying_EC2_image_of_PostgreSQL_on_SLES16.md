

````markdown
# Deploying EC2 image of PostgreSQL on SLES16

This document describes how to deploy the **PostgreSQL on SUSE Linux Enterprise Server** image from the AWS Marketplace and bootstrap it using **cloud-init**:

- Option A: Load database settings from an external **S3/HTTPS config** file.
- Option B: Fall back to **simple defaults** if the external config cannot be loaded.

The approach mirrors the MariaDB example and is designed for **idempotent, one-time bootstrapping** with a clear way to rerun the init when needed.

---

## 1. Architecture overview

At a high level:

1. You launch an EC2 instance from the **SLES16 PostgreSQL** image.
2. The instance already has PostgreSQL installed and running.
3. A **cloud-init** script runs on first boot and:
   - Attempts to download a shell-style config file from S3/HTTPS.
   - If the download fails (or variables are missing), uses default values.
   - Connects locally as the `postgres` OS user and:
     - Drops & recreates the application role.
     - Drops & recreates the application database.
     - Applies ownership and privileges.
   - Appends a **managed block** to `pg_hba.conf` to allow password auth for the app user over 127.0.0.1.
   - Writes a marker file so it does not run again automatically.
4. You validate that PostgreSQL is up and that the app credentials work.

Later, you can **rerun the init** with a new S3 config by removing the marker file and executing the script again (with the caveat that it will drop/recreate the configured database).

---

## 2. Prerequisites

You will need:

- An **AWS account** with permission to:
  - Subscribe to the **SLES16 PostgreSQL** Marketplace AMI.
  - Launch EC2 instances.
  - Create or use an existing S3 bucket.
- An **S3 bucket** (optional, but recommended) to store your PostgreSQL config:
  - e.g. `s3://my-kiwi-images-bucket/config/postgresql.conf`
- A suitable **VPC & subnet**.
- An **EC2 key pair** for SSH access.
- A **Security Group** that:
  - Allows SSH (port 22) from your admin IPs.
  - Allows PostgreSQL (port 5432) from your app/client CIDR ranges (or you can keep it private-only for now).
- (Optional but recommended) An **IAM role** attached to the instance with permission to `s3:GetObject` on the config object if you do not use a public/presigned URL.

---

## 3. Launching the EC2 instance

1. In the AWS console, go to **EC2 → Launch instance**.
2. Choose an AMI:
   - Search for **PostgreSQL on SUSE Linux Enterprise Server** on the AWS Marketplace (SLES16-based image).
3. Choose an instance type, e.g. `t3.medium` for a small test.
4. Configure network:
   - Select the **VPC** and **subnet** where the database should live.
   - Assign Security Groups that allow SSH and (optionally) PostgreSQL from trusted clients.
5. Attach an IAM role (optional):
   - If you will access a **private S3 object** (non-public, non-presigned), the role must have at least:
     - `s3:GetObject` on the config object.
6. In the **Advanced details** → **User data** section, paste the `#cloud-config` from the next section.
7. Launch the instance.

---

## 4. Cloud-init: S3 + fallback PostgreSQL bootstrap

The following `#cloud-config`:

- Writes `/root/init-postgresql-from-s3-or-default.sh`.
- On first boot:
  - Tries to download a `postgresql.conf` from `CONFIG_URL`.
  - Falls back to defaults if the download fails.
  - Ensures PostgreSQL service is enabled and running.
  - Generates `/var/lib/pgsql/init-postgresql.sql` with the chosen DB/user/password.
  - Runs that SQL as the `postgres` OS user.
  - Appends a managed block to `pg_hba.conf` to allow password auth from `127.0.0.1/32`.
  - Creates `/root/.postgresql_cloudinit_done` as a marker.

> **Note:** this script is deliberately **destructive** for the configured DB/role: it will drop and recreate them on each run.

````
#cloud-config

write_files:
  - path: /root/init-postgresql-from-s3-or-default.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail

      LOG=/var/log/postgresql-init.log
      exec >>"$LOG" 2>&1

      echo "==== PostgreSQL init (S3/HTTPS + fallback) starting at $(date) ===="

      # Only run once per instance
      MARKER=/root/.postgresql_cloudinit_done
      if [ -f "$MARKER" ]; then
        echo "Marker file exists, skipping PostgreSQL init."
        exit 0
      fi

      # === EDIT THIS: S3 (or HTTPS) URL to your config file ===
      # The file at this URL must be a shell-style env file, e.g.:
      #   DB_NAME=prodappdb-v1
      #   DB_USER=produser
      #   DB_PASSWORD=AnotherS3cret123!
      # Optional:
      #   PG_HBA_LOCAL_CIDR=127.0.0.1/32
      #   PG_SUPERUSER=postgres
      #   PG_SERVICE=postgresql.service
      CONFIG_URL="https://your-image-bucket.s3.us-west-1.amazonaws.com/config/postgresql.conf"

      # Try to download config; fall back to defaults on failure
      if curl -fsSL "$CONFIG_URL" -o /root/postgresql.conf; then
        echo "Downloaded config from $CONFIG_URL"
        # If sourcing fails (bad format, etc.), we still use defaults below
        . /root/postgresql.conf || echo "WARNING: Failed to source /root/postgresql.conf, using defaults."
      else
        echo "WARNING: Failed to download $CONFIG_URL, using default DB settings."
      fi

      # DEFAULTS (used if not provided by S3)
      DB_NAME="${DB_NAME:-prodappdb-v1}"
      DB_USER="${DB_USER:-produser}"
      DB_PASSWORD="${DB_PASSWORD:-AnotherS3cret123!}"

      PG_SUPERUSER="${PG_SUPERUSER:-postgres}"
      PG_SERVICE="${PG_SERVICE:-postgresql.service}"
      PG_HBA_LOCAL_CIDR="${PG_HBA_LOCAL_CIDR:-127.0.0.1/32}"

      echo "Using DB_NAME=$DB_NAME DB_USER=$DB_USER"
      echo "PG_SUPERUSER=$PG_SUPERUSER PG_SERVICE=$PG_SERVICE PG_HBA_LOCAL_CIDR=$PG_HBA_LOCAL_CIDR"

      # Ensure service is enabled and running (safe if already up)
      echo "Ensuring PostgreSQL service is enabled and running..."
      systemctl enable --now "$PG_SERVICE" || echo "WARNING: systemctl enable --now $PG_SERVICE failed (service name different?)"

      # Path for the SQL bootstrap file (must be readable by postgres)
      SQL_FILE="/var/lib/pgsql/init-postgresql.sql"
      mkdir -p "$(dirname "$SQL_FILE")"

      cat > "$SQL_FILE" <<EOF
      -- === PostgreSQL bootstrap via cloud-init (S3/HTTPS + fallback) ===
      -- WARNING: This will DROP and RE-CREATE the database "${DB_NAME}"
      -- and DROP and RE-CREATE the role "${DB_USER}".

      -- 1) Kill any existing sessions for this role
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE usename = '${DB_USER}'
        AND pid <> pg_backend_pid();

      -- 2) Drop and recreate role
      DROP ROLE IF EXISTS ${DB_USER};
      CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';

      -- 3) Kill any existing sessions on this database (if it exists)
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '${DB_NAME}'
        AND pid <> pg_backend_pid();

      -- 4) Drop and recreate database
      DROP DATABASE IF EXISTS "${DB_NAME}";
      CREATE DATABASE "${DB_NAME}" OWNER ${DB_USER};

      -- 5) Connect to the new DB and fix ownership/privileges
      \\connect "${DB_NAME}"

      ALTER DATABASE "${DB_NAME}" OWNER TO ${DB_USER};
      ALTER SCHEMA public OWNER TO ${DB_USER};

      GRANT ALL PRIVILEGES ON DATABASE "${DB_NAME}" TO ${DB_USER};
      GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_USER};

      GRANT CREATE ON SCHEMA public TO ${DB_USER};

      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT ALL ON TABLES TO ${DB_USER};

      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT ALL ON SEQUENCES TO ${DB_USER};
      EOF

      chown "$PG_SUPERUSER":"$PG_SUPERUSER" "$SQL_FILE"
      chmod 600 "$SQL_FILE"

      echo "Running SQL init script with psql..."
      sudo -u "$PG_SUPERUSER" psql -v ON_ERROR_STOP=1 -f "$SQL_FILE"

      # Configure pg_hba.conf for password auth from PG_HBA_LOCAL_CIDR
      echo "Configuring pg_hba.conf for password auth..."

      HBA_FILE="$(sudo -u "$PG_SUPERUSER" psql -tA -c 'SHOW hba_file;' || echo '')"

      if [ -n "$HBA_FILE" ] && [ -f "$HBA_FILE" ]; then
        if ! grep -q "BEGIN MANAGED BY CLOUD-INIT (POSTGRESQL)" "$HBA_FILE"; then
          cat >> "$HBA_FILE" <<EOF

      # BEGIN MANAGED BY CLOUD-INIT (POSTGRESQL)
      # Allow password auth for app DB/user on loopback (or configured CIDR)
      host    ${DB_NAME}    ${DB_USER}    ${PG_HBA_LOCAL_CIDR}    password
      # END MANAGED BY CLOUD-INIT (POSTGRESQL)
      EOF
        else
          echo "Managed block already present in pg_hba.conf; not duplicating."
        fi

        echo "Reloading PostgreSQL configuration..."
        systemctl reload "$PG_SERVICE" || systemctl restart "$PG_SERVICE" || echo "WARNING: reload/restart $PG_SERVICE failed"
      else
        echo "WARNING: Could not determine pg_hba.conf location; skipping pg_hba modification."
      fi

      touch "$MARKER"
      echo "Init done, marker file created."
      echo "==== PostgreSQL init (S3/HTTPS + fallback) finished at $(date) ===="

runcmd:
  # Run the combined S3+fallback init script
  - [ bash, /root/init-postgresql-from-s3-or-default.sh ]
````

---

## 5. External S3 config file format

If you use the S3/HTTPS option, the config file is a simple shell-style `KEY=VALUE` env file.

Example object at `https://your-image-bucket.s3.us-west-1.amazonaws.com/config/postgresql.conf`:

```bash
# Required (or defaults will be used)
DB_NAME=prodappdb-v1
DB_USER=produser
DB_PASSWORD=AnotherS3cret123!

# Optional overrides
PG_HBA_LOCAL_CIDR=127.0.0.1/32
PG_SUPERUSER=postgres
PG_SERVICE=postgresql.service
```

You can safely change values and rerun the script later (see §8), keeping in mind that it **drops & recreates** the configured DB and role.

---

## 6. Validating the deployment

After the instance is up:

### 6.1 Check cloud-init and init logs

```bash
sudo cloud-init status --long
sudo tail -n 80 /var/log/postgresql-init.log
```

You should see lines like:

* `WARNING: Failed to download ... using default DB settings.` (if S3 failed) **or**
* `Downloaded config from ...`
* `Running SQL init script with psql...`
* `Init done, marker file created.`

And you should see **no** unhandled errors at the end.

### 6.2 Verify DB and roles

List databases:

```bash
sudo -u postgres psql -c "\l"
```

You should see something like:

```text
   Name       |  Owner    | ...
--------------+-----------+-----
 prodappdb-v1 | produser  | ...
 postgres     | postgres  | ...
 template0    | postgres  | ...
 template1    | postgres  | ...
```

List roles:

```bash
sudo -u postgres psql -c "\du"
```

You should see:

* `postgres`
* `produser`

### 6.3 Test password-based login

From the instance:

```bash
export PGPASSWORD='AnotherS3cret123!'
psql -h 127.0.0.1 -U produser -d prodappdb-v1 \
  -c "SELECT current_user, current_database();"
unset PGPASSWORD
```

Expected:

```text
 current_user | current_database
-------------+------------------
 produser     | prodappdb-v1
(1 row)
```

If that works, your bootstrap and `pg_hba.conf` rule are correct.

---

## 7. Security considerations

* The default `PG_HBA_LOCAL_CIDR` is `127.0.0.1/32`, so the password rule only applies to **loopback**.

  * For remote clients, you can:

    * Add additional `pg_hba.conf` entries (e.g. your VPC CIDR).
    * Adjust the Security Group to allow port 5432 from your trusted CIDR(s).
* The script **drops and recreates** `DB_NAME` and `DB_USER` on each run:

  * This is helpful for repeatable tests.
  * For production, you might want a variant that:

    * Only creates the DB if it doesn’t exist.
    * Only resets the password if the role exists, without dropping it.
* Store your S3 config object securely:

  * Restrict access with IAM.
  * Avoid hard-coding secrets in public buckets.

---

## 8. Rerunning the bootstrap on an existing instance

If you want to apply a **new S3 config** to an already running instance:

1. Update the config object in S3 (`postgresql.conf`).

2. On the instance, remove the marker file:

   ```bash
   sudo rm -f /root/.postgresql_cloudinit_done
   ```

3. Run the script again:

   ```bash
   sudo bash /root/init-postgresql-from-s3-or-default.sh
   ```

4. Re-validate:

   ```bash
   sudo -u postgres psql -c "\l"
   sudo -u postgres psql -c "\du"

   export PGPASSWORD='NewSecret123!'
   psql -h 127.0.0.1 -U produser -d <new-or-updated-DB-NAME> \
     -c "SELECT current_user, current_database();"
   unset PGPASSWORD
   ```

Remember: **each run will drop & recreate** the configured database and role.

---

## 9. Next steps

* Integrate this deployment pattern into:

  * CloudFormation / Terraform templates.
  * SUSE-based automation or internal tooling.
* Extend the SQL bootstrap to:

  * Create application schemas/tables.
  * Apply extensions or initial data.
* Introduce a **“safe” bootstrap** variant for production that:

  * Avoids dropping existing databases.
  * Only applies non-destructive schema and user changes.


