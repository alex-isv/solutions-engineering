

---

# Deploying EC2 image of WordPress on SLES16

This document describes how to deploy a **WordPress** site on an **EC2 instance running SLES16** using **cloud-init** and a **WordPress bundle stored in S3**.

The deployment uses:

* **Apache + PHP 8** on SLES16 (mod_php) or **NGINX + PHP8-fmp**
* A **WordPress tar.gz bundle** downloaded from **S3 over HTTPS** at first boot.
* A **local MariaDB instance on the same server** (WordPress connects via `localhost`).
* A **fallback placeholder page** if the WordPress bundle cannot be downloaded or unpacked.

> This example uses a **public S3 object (`--acl public-read`)** for simplicity and quick testing. For production, you should use an EC2 instance role + S3 API, or pre-signed URLs and private objects.

---

## 1. Prerequisites

You’ll need:

* An **AWS account** and basic familiarity with EC2 and S3.
* A **SLES16 EC2 image** (aarch64 or x86_64, with SLES 16 repositories working).
* A **Security Group** that allows:

  * Inbound **TCP/80** from your client IP/CIDR (HTTP).
* An **S3 bucket** (e.g. `my-bucket`).
* AWS CLI installed locally and configured with credentials that can write to that bucket:

  * `aws configure`
* Basic MariaDB knowledge (for creating the WordPress database and user on the instance).

In the examples below:

* **Region**: `us-west-1`
* **Bucket**: `my-bucket`
* **Object key**: `config/wordpress-site.tar.gz`

Adjust names as needed.

---

## 2. Build the WordPress site bundle

You’ll create a **WordPress bundle** that cloud-init will download from S3 and unpack into `/srv/www/htdocs`.

### 2.1 Download and unpack WordPress

On your workstation (or any Linux/macOS/WSL machine with curl and tar):

```bash
mkdir -p wordpress-build
cd wordpress-build

# Download latest WordPress
curl -O https://wordpress.org/latest.tar.gz

# Unpack
tar -xzf latest.tar.gz
ls wordpress
```

You should see files inside `wordpress/` (e.g. `index.php`, `wp-config-sample.php`, `wp-admin/`, etc.).

### 2.2 Optional: prepare `wp-config.php` for local MariaDB

If you want WordPress to connect to a **local MariaDB server on the same instance**, you can pre-create `wp-config.php`. Otherwise, WordPress will show the standard install screen and ask for DB details.

Inside `wordpress-build`:

```bash
cd wordpress

cp wp-config-sample.php wp-config.php
```

Edit `wp-config.php` and set:

```php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wp_user' );
define( 'DB_PASSWORD', 'SuperSecret!' );
define( 'DB_HOST', 'localhost' );  // database on the same instance
```

You can leave the salts/keys as defaults for a quick test, or generate new ones from the WordPress key service.

When done:

```bash
cd ..
```

### 2.3 Create `wordpress-site.tar.gz` with top-level WP files

You want the archive contents to unpack **directly into the Apache document root** (`/srv/www/htdocs`), so tar from inside the `wordpress` directory:

```bash
# In wordpress-build/
tar -C wordpress -czf wordpress-site.tar.gz .
ls -lh wordpress-site.tar.gz
tar -tzf wordpress-site.tar.gz | head
```

You should see entries like:

* `index.php`
* `wp-config.php` (if created)
* `wp-admin/`
* `wp-content/`
* `wp-includes/`

---

## 3. Upload the bundle to S3

For quick testing, upload the bundle as a **public-readable** object:

```bash
aws s3 cp wordpress-site.tar.gz \
  s3://my-bucket/config/wordpress-site.tar.gz \
  --region us-west-1 \
  --acl public-read
```

Verify that the object is reachable:

```bash
curl -I https://my-bucket.s3.us-west-1.amazonaws.com/config/wordpress-site.tar.gz
```

You should see `HTTP/1.1 200 OK`.

> For production, remove `--acl public-read` and use **EC2 instance IAM roles + S3 API** or **pre-signed URLs** instead of public objects.

---

## 4. Cloud-init configuration (WordPress from S3 or fallback)

This cloud-config:

* Installs **Apache 2.4 + PHP 8** and required **WordPress extensions**.
* Downloads `wordpress-site.tar.gz` from S3 over HTTPS.
* Unpacks WordPress into `/srv/www/htdocs`.
* If download/unpack fails, deploys a simple **placeholder page**.
* Enables and starts Apache on **port 80**.
* Leaves logs in `/var/log/init-wordpress-site.log`.

> Replace `APP_SOURCE_HTTPS` with your actual S3 HTTPS URL.

```yaml
#cloud-config
package_update: false

write_files:
  - path: /usr/local/sbin/init-wordpress-from-https-or-default.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      exec > >(tee -a /var/log/init-wordpress-site.log) 2>&1

      echo "== $(date -Is) WordPress init starting =="

      # ---- CONFIG ----
      APP_SOURCE_HTTPS="https://my-bucket.s3.us-west-1.amazonaws.com/config/wordpress-site.tar.gz"
      DOCROOT="/srv/www/htdocs"
      APACHE_PORT="80"
      MARKER="/var/lib/cloud/instance/sem/wordpress_site_initialized"
      TMP="/tmp/wordpress-site-bundle"
      # ---------------

      if [[ -f "$MARKER" ]]; then
        echo "Marker exists ($MARKER). Skipping."
        exit 0
      fi

      # Wait for zypper to be ready
      for i in {1..30}; do
        if zypper -n lr >/dev/null 2>&1; then
          echo "[info] zypper repos available"
          break
        fi
        echo "[info] Waiting for zypper/repos... ($i/30)"
        sleep 2
      done

      # Refresh repos with retries
      for i in {1..10}; do
        if zypper -n --gpg-auto-import-keys refresh; then
          echo "[info] Repo refresh OK"
          break
        fi
        echo "[warn] Repo refresh failed, retrying... ($i/10)"
        sleep 5
      done

      # Install Apache + PHP + WordPress extensions
      echo "[info] Installing Apache, PHP and extensions needed for WordPress..."
      zypper -n install --no-recommends \
        apache2 apache2-mod_php8 \
        php8 php8-cli \
        php8-mysql \
        php8-gd \
        php8-mbstring \
        php8-zip \
        php8-curl \
        php8-intl \
        php8-openssl \
        php8-xmlreader \
        php8-xmlwriter \
        curl tar gzip unzip

      echo "[info] Installed packages:"
      rpm -q apache2 apache2-mod_php8 php8 php8-cli php8-mysql || true

      mkdir -p "$DOCROOT"

      # Apache listen + vhost
      cat >/etc/apache2/listen.conf <<EOF
      Listen ${APACHE_PORT}
      EOF

      cat >/etc/apache2/vhosts.d/000-default.conf <<EOF
      <VirtualHost *:${APACHE_PORT}>
        DocumentRoot "${DOCROOT}"
        DirectoryIndex index.php index.html

        <Directory "${DOCROOT}">
          AllowOverride All
          Require all granted
        </Directory>

        ErrorLog /var/log/apache2/error_log
        CustomLog /var/log/apache2/access_log combined
      </VirtualHost>
      EOF

      deploy_fallback_site() {
        echo "[info] Deploying fallback WordPress placeholder site."
        rm -rf "${DOCROOT:?}/"* 2>/dev/null || true
        cat >"${DOCROOT}/index.php" <<'EOF'
      <!doctype html>
      <html>
      <head><meta charset="utf-8"><title>SLES16 WordPress placeholder</title></head>
      <body style="font-family: system-ui, sans-serif;">
        <h1>WordPress placeholder ✅</h1>
        <p>The WordPress bundle could not be downloaded or unpacked.</p>
        <ul>
          <li>Check S3 URL and ACL (public-read or pre-signed).</li>
          <li>Check /var/log/init-wordpress-site.log for details.</li>
        </ul>
      </body>
      </html>
      EOF
      }

      deploy_bundle_from_file() {
        local file="$1"
        echo "[info] Deploying WordPress bundle from $file"
        rm -rf "${DOCROOT:?}/"* 2>/dev/null || true

        if [[ "$APP_SOURCE_HTTPS" == *.tar.gz ]] || [[ "$APP_SOURCE_HTTPS" == *.tgz ]]; then
          tar -xzf "$file" -C "$DOCROOT"
        elif [[ "$APP_SOURCE_HTTPS" == *.zip ]]; then
          unzip -o "$file" -d "$DOCROOT"
        else
          echo "[warn] Unknown bundle extension; expected .tar.gz/.tgz or .zip"
          return 1
        fi

        # If bundle extracted into a 'wordpress' subdir, move it up
        if [[ -d "${DOCROOT}/wordpress" && ! -f "${DOCROOT}/index.php" ]]; then
          echo "[info] Moving wordpress/ contents to DOCROOT"
          mv "${DOCROOT}/wordpress/"* "${DOCROOT}/"
          rmdir "${DOCROOT}/wordpress" || true
        fi

        if [[ ! -f "${DOCROOT}/index.php" ]]; then
          echo "[warn] No index.php found in WordPress bundle; deployment incomplete."
          return 1
        fi

        # Ensure Apache user owns files (for uploads/plugins)
        if id wwwrun >/dev/null 2>&1; then
          chown -R wwwrun:www "${DOCROOT}"
        fi
      }

      echo "[info] Checking HTTPS bundle URL:"
      echo "[info]   $APP_SOURCE_HTTPS"

      DEPLOYED="no"

      # HEAD request: 200/302 == reachable, 403 == private, others == not found
      HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' -I "$APP_SOURCE_HTTPS" || true)"
      echo "[info] HEAD status: $HTTP_CODE"

      if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
        echo "[info] WordPress bundle appears reachable. Downloading..."
        if curl -fLsS --retry 5 --retry-delay 2 "$APP_SOURCE_HTTPS" -o "$TMP"; then
          if deploy_bundle_from_file "$TMP"; then
            DEPLOYED="yes"
          else
            echo "[warn] Downloaded WordPress bundle but failed to unpack/deploy."
          fi
        else
          echo "[warn] Download failed."
        fi
      elif [[ "$HTTP_CODE" == "403" ]]; then
        echo "[warn] Got 403 Forbidden. Object may exist but is private."
        echo "[warn] For quick tests, upload with: --acl public-read"
      else
        echo "[warn] WordPress bundle not reachable via HTTPS (HTTP $HTTP_CODE)."
      fi

      if [[ "$DEPLOYED" != "yes" ]]; then
        deploy_fallback_site
      else
        echo "[info] WordPress bundle deployed successfully."
      fi

      systemctl enable apache2
      systemctl restart apache2 || {
        echo "[error] apache2 failed to start";
        journalctl -u apache2 -n 50 || true;
      }

      # Optional firewall open if enabled
      if systemctl is-enabled --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
      fi

      echo "[info] Local curl check:"
      curl -fsS "http://127.0.0.1:${APACHE_PORT}/" | head -n 8 || true

      mkdir -p "$(dirname "$MARKER")"
      touch "$MARKER"
      echo "== $(date -Is) WordPress init done =="

  - path: /etc/systemd/system/wordpress-site-init.service
    permissions: "0644"
    owner: root:root
    content: |
      [Unit]
      Description=Initialize WordPress site from HTTPS S3 URL if present, else deploy fallback
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/init-wordpress-from-https-or-default.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now wordpress-site-init.service

final_message: "WordPress site init finished. Logs: /var/log/init-wordpress-site.log"
```

Paste this into the **User data** field when launching the EC2 instance.

---

## 4.1 For NginX and php8-fpm use the following cloud-config example:

> Replace `APP_SOURCE_HTTPS` with your actual S3 HTTPS URL.

```yaml
#cloud-config
package_update: false

write_files:
  - path: /usr/local/sbin/init-wordpress-nginx-from-https-or-default.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      exec > >(tee -a /var/log/init-wordpress-site.log) 2>&1

      echo "== $(date -Is) WordPress (Nginx) init starting =="

      # ---- CONFIG ----
      APP_SOURCE_HTTPS="https://my-bucket.s3.us-west-1.amazonaws.com/config/wordpress-site.tar.gz"
      DOCROOT="/srv/www/htdocs"
      NGINX_PORT="80"
      MARKER="/var/lib/cloud/instance/sem/wordpress_site_initialized"
      TMP="/tmp/wordpress-site-bundle"
      PHP_FPM_SOCKET="/run/php-fpm/www.sock"
      # ---------------

      if [[ -f "$MARKER" ]]; then
        echo "Marker exists ($MARKER). Skipping."
        exit 0
      fi

      # Wait for zypper to be ready
      for i in {1..30}; do
        if zypper -n lr >/dev/null 2>&1; then
          echo "[info] zypper repos available"
          break
        fi
        echo "[info] Waiting for zypper/repos... ($i/30)"
        sleep 2
      done

      # Refresh repos with retries
      for i in {1..10}; do
        if zypper -n --gpg-auto-import-keys refresh; then
          echo "[info] Repo refresh OK"
          break
        fi
        echo "[warn] Repo refresh failed, retrying... ($i/10)"
        sleep 5
      done

      # Install Nginx + PHP + WordPress extensions
      echo "[info] Installing Nginx, PHP-FPM and extensions needed for WordPress..."
      zypper -n install --no-recommends \
        nginx \
        php8 php8-cli \
        php8-fpm \
        php8-mysql \
        php8-gd \
        php8-mbstring \
        php8-zip \
        php8-curl \
        php8-intl \
        php8-openssl \
        php8-xmlreader \
        php8-xmlwriter \
        curl tar gzip unzip || {
          echo "[error] Package installation failed"
          exit 1
        }

      echo "[info] Installed packages (subset):"
      rpm -q nginx php8 php8-fpm php8-mysql || true

      mkdir -p "$DOCROOT"

      # Silence PCRE JIT warning (optional but nice)
      mkdir -p /etc/php8/conf.d
      cat >/etc/php8/conf.d/90-pcre.ini <<EOF
      ; Disable PCRE JIT to avoid JIT memory warnings in WordPress
      pcre.jit=0
      EOF

      # Configure PHP-FPM pool (www) to listen on Unix socket
      if [[ -d /etc/php8/fpm/php-fpm.d ]]; then
        cat >/etc/php8/fpm/php-fpm.d/www.conf <<EOF
      [www]
      user = wwwrun
      group = www

      listen = ${PHP_FPM_SOCKET}
      listen.owner = wwwrun
      listen.group = www
      listen.mode  = 0660

      pm = dynamic
      pm.max_children = 5
      pm.start_servers = 2
      pm.min_spare_servers = 1
      pm.max_spare_servers = 3

      php_admin_value[error_log] = /var/log/php8-fpm-www-error.log
      php_admin_flag[log_errors] = on
      EOF
      else
        echo "[warn] /etc/php8/fpm/php-fpm.d not found; adjust PHP-FPM config path as needed."
      fi

      # Minimal Nginx config for WordPress + PHP-FPM via Unix socket
      cat >/etc/nginx/nginx.conf <<EOF
      user  wwwrun;
      worker_processes  auto;

      error_log  /var/log/nginx/error.log;
      pid        /run/nginx.pid;

      events {
          worker_connections  1024;
      }

      http {
          include       /etc/nginx/mime.types;
          default_type  application/octet-stream;

          log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                            '\$status \$body_bytes_sent "\$http_referer" '
                            '"\$http_user_agent" "\$http_x_forwarded_for"';

          access_log  /var/log/nginx/access.log  main;

          sendfile        on;
          keepalive_timeout  65;

          server {
              listen       ${NGINX_PORT} default_server;
              server_name  _;

              root   ${DOCROOT};
              index  index.php index.html index.htm;

              # Pretty permalinks support
              location / {
                  try_files \$uri \$uri/ /index.php?\$args;
              }

              location ~ \.php$ {
                  fastcgi_split_path_info ^(.+\.php)(/.+)$;

                  # Standard fastcgi params (SUSE provides this file)
                  include fastcgi.conf;

                  # Path to the actual PHP script file
                  fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

                  # Use the Unix socket from php-fpm
                  fastcgi_pass unix:${PHP_FPM_SOCKET};

                  fastcgi_index index.php;
              }

              # Deny access to .ht* (leftover from Apache-based plugins)
              location ~ /\.ht {
                  deny all;
              }
          }
      }
      EOF

      deploy_fallback_site() {
        echo "[info] Deploying fallback WordPress placeholder site."
        rm -rf "${DOCROOT:?}/"* 2>/dev/null || true
        cat >"${DOCROOT}/index.php" <<'EOF'
      <!doctype html>
      <html>
      <head><meta charset="utf-8"><title>SLES16 WordPress placeholder (Nginx)</title></head>
      <body style="font-family: system-ui, sans-serif;">
        <h1>WordPress placeholder ✅</h1>
        <p>The WordPress bundle could not be downloaded or unpacked.</p>
        <ul>
          <li>Check S3 URL and ACL (public-read or pre-signed).</li>
          <li>Check /var/log/init-wordpress-site.log for details.</li>
        </ul>
      </body>
      </html>
      EOF
      }

      deploy_bundle_from_file() {
        local file="$1"
        echo "[info] Deploying WordPress bundle from $file"
        rm -rf "${DOCROOT:?}/"* 2>/null || true 2>/dev/null || true

        if [[ "$APP_SOURCE_HTTPS" == *.tar.gz ]] || [[ "$APP_SOURCE_HTTPS" == *.tgz ]]; then
          tar -xzf "$file" -C "$DOCROOT"
        elif [[ "$APP_SOURCE_HTTPS" == *.zip ]]; then
          unzip -o "$file" -d "$DOCROOT"
        else
          echo "[warn] Unknown bundle extension; expected .tar.gz/.tgz or .zip"
          return 1
        fi

        # If bundle extracted into a 'wordpress' subdir, move it up
        if [[ -d "${DOCROOT}/wordpress" && ! -f "${DOCROOT}/index.php" ]]; then
          echo "[info] Moving wordpress/ contents to DOCROOT"
          mv "${DOCROOT}/wordpress/"* "${DOCROOT}/"
          rmdir "${DOCROOT}/wordpress" || true
        fi

        if [[ ! -f "${DOCROOT}/index.php" ]]; then
          echo "[warn] No index.php found in WordPress bundle; deployment incomplete."
          return 1
        fi

        # Ensure web user owns files (for uploads/plugins)
        if id wwwrun >/dev/null 2>&1; then
          chown -R wwwrun:www "${DOCROOT}"
        fi
      }

      echo "[info] Checking HTTPS bundle URL:"
      echo "[info]   $APP_SOURCE_HTTPS"

      DEPLOYED="no"

      # HEAD request to see if object is reachable
      HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' -I "$APP_SOURCE_HTTPS" || true)"
      echo "[info] HEAD status: $HTTP_CODE"

      if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
        echo "[info] WordPress bundle appears reachable. Downloading..."
        if curl -fLsS --retry 5 --retry-delay 2 "$APP_SOURCE_HTTPS" -o "$TMP"; then
          if deploy_bundle_from_file "$TMP"; then
            DEPLOYED="yes"
          else
            echo "[warn] Downloaded WordPress bundle but failed to unpack/deploy."
          fi
        else
          echo "[warn] Download failed."
        fi
      elif [[ "$HTTP_CODE" == "403" ]]; then
        echo "[warn] Got 403 Forbidden. Object may exist but is private."
        echo "[warn] For quick tests, upload with: --acl public-read"
      else
        echo "[warn] WordPress bundle not reachable via HTTPS (HTTP $HTTP_CODE)."
      fi

      if [[ "$DEPLOYED" != "yes" ]]; then
        deploy_fallback_site
      else
        echo "[info] WordPress bundle deployed successfully."
      fi

      # Enable & start PHP-FPM + Nginx
      echo "[info] Enabling and starting php-fpm + nginx..."
      systemctl enable php-fpm || echo "[warn] php-fpm service not found; adjust service name if needed"
      systemctl restart php-fpm || echo "[error] php-fpm failed to start"

      systemctl enable nginx
      systemctl restart nginx || {
        echo "[error] nginx failed to start"
        journalctl -u nginx -n 50 || true
      }

      # Optional firewall open if enabled
      if systemctl is-enabled --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
      fi

      echo "[info] Local curl check:"
      curl -fsS "http://127.0.0.1:${NGINX_PORT}/" | head -n 8 || true

      mkdir -p "$(dirname "$MARKER")"
      touch "$MARKER"
      echo "== $(date -Is) WordPress (Nginx) init done =="

  - path: /etc/systemd/system/wordpress-site-init.service
    permissions: "0644"
    owner: root:root
    content: |
      [Unit]
      Description=Initialize WordPress site (Nginx + PHP-FPM) from HTTPS S3 URL if present, else deploy fallback
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/init-wordpress-nginx-from-https-or-default.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now wordpress-site-init.service

final_message: "WordPress (Nginx) site init finished. Logs: /var/log/init-wordpress-site.log"
````
----

## 5. Prepare the local MariaDB database and user

On the same SLES16 instance, install and run MariaDB (if not already):

```bash
sudo zypper -n install mariadb mariadb-client
sudo systemctl enable --now mariadb
```

Log in as an admin user (often `sudo mariadb` works by default):

```bash
sudo mariadb
```

Inside the MariaDB shell:

```sql
-- Create the WordPress database
CREATE DATABASE IF NOT EXISTS wordpress
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create or replace the local WordPress DB user
CREATE OR REPLACE USER 'wp_user'@'localhost'
  IDENTIFIED BY 'SuperSecret!';

-- Grant access to the wordpress DB
GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'localhost';

FLUSH PRIVILEGES;
```

These values must match `wp-config.php`:

```php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wp_user' );
define( 'DB_PASSWORD', 'SuperSecret!' );
define( 'DB_HOST', 'localhost' );
```

> Because DB and WordPress are on the **same instance**, `DB_HOST` can be `localhost`. WordPress/PHP will connect via the local socket/TCP loopback.

---

## 6. Launch the EC2 instance

1. In the AWS Console, go to **EC2 → Instances → Launch instances**.
2. Choose a **SLES16** AMI.
3. Choose a small instance type (e.g. `t4g.small` / `t3.small`).
4. Select a **VPC** and **subnet** with Internet access (via Internet Gateway or NAT).
5. Attach a **Security Group** that allows **TCP/80** from your IP/CIDR.
6. Under **Advanced details → User data**, paste the WordPress cloud-config shown above.
7. Launch the instance.

---

## 7. Validate the deployment

Once the instance is running and status checks pass:

### 7.1 Check cloud-init + WordPress init log

SSH to the instance:

```bash
ssh ec2-user@<public-ip>
```

Then:

```bash
sudo tail -n 200 /var/log/init-wordpress-site.log
```

You should see:

* PHP and Apache packages installed. Or NGINX and PHP8-fpm depends on which configuration you used.
* `HEAD status: 200` for the S3 object.
* “WordPress bundle deployed successfully.”
* A final local curl check.

### 7.2 Check Apache or NGINX

```bash
sudo systemctl status apache2 --no-pager
curl -fsS http://127.0.0.1/ | head
```
or 

```bash
sudo systemctl status nginx --no-pager
sudo systemctl status php8-fpm --no-pager
curl -fsS http://127.0.0.1/ | head
```


You should see the WordPress front page or install screen HTML.

### 7.3 Open from your browser

Visit:

```text
http://<instance-public-ip>/
```
<img width="839" height="895" alt="image" src="https://github.com/user-attachments/assets/3d1b3845-88ad-46a9-b1f0-ae3c43bc02bd" />

Depending on whether you pre-configured `wp-config.php` and whether the DB has tables yet, you’ll either:

* See the WordPress **install wizard**, or
* See the WordPress site if you’ve already completed installation.

If the S3 bundle wasn’t reachable, you’ll see the **placeholder page** instead.

---

## 8. Troubleshooting

### 8.1 HTTP 500 or “Error establishing a database connection”

1. Check Apache logs:

   ```bash
   sudo tail -n 40 /var/log/apache2/error_log
   sudo tail -n 40 /var/log/apache2/access_log
   ```

2. Confirm PHP has MySQL extensions:

   ```bash
   php -m | grep -Ei 'mysql|mysqli|pdo'
   rpm -q php8-mysql
   ```

3. Confirm `wp-config.php` matches your DB:

   ```bash
   cd /srv/www/htdocs
   sudo sed -n '20,80p' wp-config.php | grep -E "DB_(NAME|USER|PASSWORD|HOST)"
   ```

4. Test DB login from the same instance:

   ```bash
   mysql -h localhost -u wp_user -p wordpress
   ```

   If this fails with `Access denied for user 'wp_user'@'localhost'`, revisit the `CREATE USER` / `GRANT` statements in MariaDB.

### 8.2 Basic PHP DB connectivity test

If you want a tiny PHP-only test (no CLI client needed):

```bash
sudo bash -c 'cat > /srv/www/htdocs/dbtest.php << "EOF"
<?php
$host = "localhost";
$user = "wp_user";
$pass = "SuperSecret!";
$db   = "wordpress";

$mysqli = @new mysqli($host, $user, $pass, $db);

if ($mysqli->connect_errno) {
    echo "CONNECT ERROR:\n";
    echo "errno=" . $mysqli->connect_errno . "\n";
    echo "error=" . $mysqli->connect_error . "\n";
    exit(1);
}

echo "OK: connected to DB successfully.\n";
EOF'
curl -sS http://127.0.0.1/dbtest.php
```

You should see either **OK** or a clear error message (1045 = access denied, 1049 = unknown database, 2002 = can’t connect).

### 8.3 PCRE JIT warning (noise only)

In the Apache error log you may see:

```text
PHP Warning: preg_match(): Allocation of JIT memory failed, PCRE JIT will be disabled.
```

This is **not fatal** and WordPress still works. To silence it later, add to your PHP configuration (e.g. `/etc/php8/conf.d/90-pcre.ini`):

```ini
pcre.jit=0
```

Then restart Apache:

```bash
sudo systemctl restart apache2
```

---

At this point you have a repeatable EC2 + SLES16 + WordPress deployment:

* WordPress code pulled from S3 at first boot.
* Apache/PHP or NGINX + PHP8-fpm configured with all needed extensions.
* Local MariaDB backing the site via `localhost`.

You can now build on this to:

* Move MariaDB to a separate instance or RDS.
* Use private S3 objects with an **EC2 instance role** instead of `public-read`.
* Add TLS (ALB/ELB in front, or Apache SSL directly).
