
# Deploying a SLES 16 MariaDB Image on EC2 with cloud-init + S3 Overrides

This guide shows how to:

1. Launch  **prebuilt SLES 16 MariaDB AMI** on AWS EC2.
2. Use **cloud-init user-data** to:

   * Create a database, role, user, and password on first boot.
   * Optionally pull those settings from an **external S3 config file**.
   * Fall back to **built-in defaults** if S3 is unavailable.

---

## 1. Prepare the S3 config file (optional but recommended)

This file lets you override DB/user/password **without rebuilding** the image. You store it in S3 and cloud-init will read it at first boot.

### 1.1 Create `mariadb.conf` locally

On your workstation:

```bash
cat > mariadb.conf << 'EOF'
# mariadb.conf (this file goes to S3)
DB_NAME=prodappdb
DB_USER=produser
DB_PASSWORD='SuperSecretPass123!'
DB_ROLE=prod_rw_role
DB_HOST=%
EOF
```

> **Important:** This is a **shell env file**, not YAML or XML.
> Each line is `VAR=value`. Comments starting with `#` are OK.

### 1.2 Upload to your S3 bucket

Assume:

* Bucket: `my-kiwi-images-bucket`
* Region: `us-west-1`
* Object key: `config/mariadb.conf`

Upload:

```bash
aws s3 cp mariadb.conf \
  s3://my-kiwi-images-bucket/config/mariadb.conf \
  --region us-west-1
```

If you want EC2 to fetch it via plain `curl` (no IAM):

```bash
aws s3 cp mariadb.conf \
  s3://my-kiwi-images-bucket/config/mariadb.conf \
  --region us-west-1 \
  --acl public-read
```

You’ll then be able to fetch it from instances at:

```text
https://my-kiwi-images-bucket.s3.us-west-1.amazonaws.com/config/mariadb.conf
```

> If you keep the object private instead, use an **IAM role** + `aws s3 cp` in the script, or a **pre-signed URL** in `CONFIG_URL`.

---

## 2. Cloud-init user-data: S3 + fallback defaults

This cloud-config does:

* Starts & enables `mariadb.service`.
* Runs a one-time init script:

  * Tries to download and source `mariadb.conf` from S3.
  * If successful → uses those values.
  * If not → uses built-in defaults.
  * Generates `/root/init-mariadb.sql` and runs it with `mysql -u root`.
  * Logs everything to `/var/log/mariadb-init.log`.
  * Marks completion with `/root/.mariadb_cloudinit_done`.


### 2.1 Complete cloud-config to paste into EC2 “User data”

When launching the instance, in **Advanced details → User data**, paste:

```yaml
#cloud-config

write_files:
  - path: /root/init-mariadb-from-s3-or-default.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail

      LOG=/var/log/mariadb-init.log
      exec >>"$LOG" 2>&1

      echo "==== MariaDB init (S3 + fallback) starting at $(date) ===="

      # Only run once
      if [ -f /root/.mariadb_cloudinit_done ]; then
        echo "Marker file exists, skipping MariaDB init."
        exit 0
      fi

      # === EDIT THIS: S3 (or HTTPS) URL to your config file ===
      # The file at this URL must be a shell-style env file with lines like:
      #   DB_NAME=...
      #   DB_USER=...
      #   DB_PASSWORD='...'
      #   DB_ROLE=...
      #   DB_HOST=...
      CONFIG_URL="https://my-kiwi-images-bucket.s3.us-west-1.amazonaws.com/config/mariadb.conf"

      # Try to download config; fallback to defaults if it fails or is not usable
      if curl -fsSL "$CONFIG_URL" -o /root/mariadb.conf; then
        echo "Downloaded config from $CONFIG_URL"
        # If sourcing fails (e.g. bad format), fall back to defaults
        . /root/mariadb.conf || echo "WARNING: Failed to source /root/mariadb.conf, using defaults."
      else
        echo "WARNING: Failed to download $CONFIG_URL, using default DB settings."
      fi

      # Defaults if not supplied by S3
      DB_NAME="${DB_NAME:-myappdb}"
      DB_USER="${DB_USER:-appuser}"
      DB_PASSWORD="${DB_PASSWORD:-ChangeMe123!}"
      DB_ROLE="${DB_ROLE:-app_rw_role}"
      DB_HOST="${DB_HOST:-%}"

      echo "Using DB_NAME=$DB_NAME DB_USER=$DB_USER DB_ROLE=$DB_ROLE DB_HOST=$DB_HOST"

      cat > /root/init-mariadb.sql <<EOF
      -- === MariaDB bootstrap via cloud-init (S3 + fallback) ===

      CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci;

      CREATE ROLE IF NOT EXISTS '${DB_ROLE}';

      GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_ROLE}';

      CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}'
        IDENTIFIED BY '${DB_PASSWORD}';

      GRANT '${DB_ROLE}' TO '${DB_USER}'@'${DB_HOST}';

      FLUSH PRIVILEGES;
      EOF

      echo "Running SQL init script with mysql..."
      mysql -u root < /root/init-mariadb.sql

      touch /root/.mariadb_cloudinit_done
      echo "Init done, marker file created."
      echo "==== MariaDB init (S3 + fallback) finished at $(date) ===="

runcmd:
  # Start and enable MariaDB at boot
  # If your service is called mysql.service instead, change this line.
  - [ systemctl, enable, --now, mariadb.service ]

  # Run the combined S3+fallback init script
  - [ bash, /root/init-mariadb-from-s3-or-default.sh ]
```

**Things you should edit:**

* `CONFIG_URL` → point it to your real S3 URL or a presigned URL.
* Default values in the script (`DB_NAME`, `DB_USER`, `DB_PASSWORD`, etc.) if you want different built-in defaults.
* If your unit is `mysql.service` instead of `mariadb.service`, update the `systemctl` line.

---

## 3. Launching the instance from the EC2 console

1. **Open the EC2 Console**
   Go to “Instances → Launch instances”.

2. **Choose your AMI**

   * Select  **SLES 16 MariaDB AMI** (the one built with KIWI and imported as an AMI).

3. **Choose instance type**

   * For aarch64 (ARM) images, pick an **ARM-based instance** (e.g. `t4g.small`, etc.).

4. **Key pair**

   * Select an existing key pair or create a new one.
   * You’ll use this to SSH in as your configured user (e.g. `ec2-user`).

5. **Network & security group**

   * Attach to the desired VPC/subnet.
   * Security group should allow:

     * SSH (port 22) from your IP.
     * Optionally MariaDB (3306) and/or Cockpit (9090) if you plan external access.

6. **Advanced details → User data**

   * Expand **Advanced details**.
   * Under **User data**, choose “As text”.
   * Paste the **cloud-config** from section 2.
   * Make sure there is **no extra indentation** at the very beginning of the file and it starts with `#cloud-config`.

7. **IAM role (optional but better)**
   If you want to keep the S3 object private and avoid `--acl public-read`, attach an IAM role to the instance with `s3:GetObject` permission on `s3://my-kiwi-images-bucket/config/mariadb.conf`, and adjust the script to use `aws s3 cp` instead of `curl`.

8. **Launch**

   * Click **Launch instance**.

---

## 4. Verifying after launch

Once the instance state is “running” and status checks are OK:

### 4.1 Connect via SSH

From your machine:

```bash
ssh -i /path/to/key.pem ec2-user@<public-ip-or-dns>
```

(Replace `ec2-user` if your image uses a different default user.)

### 4.2 Check MariaDB status

On the instance:

```bash
sudo systemctl status mariadb
# or, if you use mysql.service:
sudo systemctl status mysql
```

You should see `Active: active (running)`.

### 4.3 Check the init log

```bash
sudo cat /var/log/mariadb-init.log
```

You want to see something like:

```text
==== MariaDB init (S3 + fallback) starting at ...
Downloaded config from https://my-kiwi-images-bucket.s3.us-west-1.amazonaws.com/config/mariadb.conf
Using DB_NAME=prodappdb DB_USER=produser DB_ROLE=prod_rw_role DB_HOST=%
Running SQL init script with mysql...
Init done, marker file created.
==== MariaDB init (S3 + fallback) finished at ...
```

If S3 failed or the file was missing, you’ll see:

```text
WARNING: Failed to download ... using default DB settings.
Using DB_NAME=myappdb DB_USER=appuser ...
```

### 4.4 Verify DB and user in MariaDB

```bash
sudo mysql -e "SHOW DATABASES;"
sudo mysql -e "SELECT User, Host FROM mysql.user;"
```

You should see:

* Database: `prodappdb` (or your default `myappdb`).
* User: `produser`@`%` (or default `appuser`@`%`).
* Role: `prod_rw_role` in `mysql.user` / `mysql.roles_mapping` if roles are enabled.

You can also test logging in as that user:

```bash
mysql -h 127.0.0.1 -u produser -p prodappdb
# Enter the password from S3 or the default in the script.
```

---

## 5. Behavior summary

* **First boot only:**

  * `mariadb.service` is enabled and started.
  * `/root/init-mariadb-from-s3-or-default.sh`:

    * Tries to read overrides from S3.
    * Falls back to built-ins if S3 fails.
    * Writes and runs `/root/init-mariadb.sql`.
    * Creates `/root/.mariadb_cloudinit_done`, so it won’t re-run.

* **Later boots:**

  * Only MariaDB is started (due to `systemctl enable`); the init script sees the marker file and exits immediately.

* **To re-run with new S3 settings** on an existing instance:

  * Remove the marker file:

    ```bash
    sudo rm -f /root/.mariadb_cloudinit_done
    ```
  * Run the script again:

    ```bash
    sudo bash /root/init-mariadb-from-s3-or-default.sh
    ```

---

