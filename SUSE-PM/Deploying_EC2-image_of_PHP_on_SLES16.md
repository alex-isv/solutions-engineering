
---

# Deploying EC2 image of PHP on SLES16

This document describes how to deploy a **PHP web application** on an **EC2 instance running SLES16** using **cloud-init**.

The deployment uses:

* **Apache + PHP 8** installed at first boot.
* A **PHP site bundle from S3** (tar.gz) downloaded via **HTTPS**.
* A **fallback sample page** if the S3 object is not reachable.


---

## 1. Prerequisites

You’ll need:

* An **AWS account** and basic familiarity with EC2 and S3.
* A **S3 bucket**, for example:

  * `my-image-bucket`
* A **sample PHP site bundle** (`php-site.tar.gz`) you can upload to S3.
* AWS CLI installed locally and configured with credentials that can write to the bucket:

  * `aws configure`
* Access to a **SLES16 EC2 image** (PAYG or BYOS, but with working SLES 16 repositories).
* A **Security Group** that allows:

  * Inbound `TCP/80` from your client IP / test network.

In the examples below:

* **Region**: `us-west-1`
* **Bucket**: `my-image-bucket`
* **Object key**: `config/php-site.tar.gz`

Adjust these names as needed.

---

## 2. Build a sample PHP site bundle

On your workstation (Linux/macOS or WSL), create a small PHP site and bundle it as `php-site.tar.gz`.

```bash
mkdir -p php-site/assets

cat > php-site/index.php <<'EOF'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>PHP Sample Site (SLES16)</title>
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <div class="card">
    <h1>PHP Sample Site ✅</h1>
    <p>This page was deployed from an S3 bundle (<code>php-site.tar.gz</code>).</p>

    <h2>Instance info</h2>
    <ul>
      <li><b>Hostname:</b> <?php echo htmlspecialchars(gethostname()); ?></li>
      <li><b>Server time:</b> <?php echo htmlspecialchars(date('c')); ?></li>
      <li><b>Client IP:</b> <?php echo htmlspecialchars($_SERVER['REMOTE_ADDR'] ?? 'unknown'); ?></li>
    </ul>

    <h2>Links</h2>
    <ul>
      <li><a href="/health.php">Health check</a></li>
      <li><a href="/info.php">PHP info</a></li>
    </ul>

    <p class="footer">Deployed at: <?php echo htmlspecialchars(@file_get_contents(__DIR__ . '/.deployed_at') ?: 'unknown'); ?></p>
  </div>
</body>
</html>
EOF

cat > php-site/health.php <<'EOF'
<?php
http_response_code(200);
header('Content-Type: text/plain; charset=utf-8');
echo "ok\n";
echo "hostname=" . gethostname() . "\n";
echo "time=" . date('c') . "\n";
EOF

cat > php-site/info.php <<'EOF'
<?php phpinfo();
EOF

cat > php-site/assets/style.css <<'EOF'
body {
  font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial, sans-serif;
  margin: 0;
  padding: 2rem;
}
.card {
  max-width: 720px;
  margin: 0 auto;
  padding: 1.5rem 1.75rem;
  border: 1px solid rgba(0,0,0,.15);
  border-radius: 14px;
}
code {
  padding: 0.15rem 0.35rem;
  border: 1px solid rgba(0,0,0,.15);
  border-radius: 8px;
}
a { text-decoration: none; }
a:hover { text-decoration: underline; }
.footer {
  margin-top: 1.5rem;
  color: rgba(0,0,0,.65);
  font-size: 0.95rem;
}
EOF

# Optional: record deploy timestamp
date -Is > php-site/.deployed_at
```

Create the tarball:

```bash
tar -C php-site -czf php-site.tar.gz .
tar -tzf php-site.tar.gz | head
```

You should see entries like:

* `index.php`
* `health.php`
* `info.php`
* `assets/style.css`
* `.deployed_at`

---

## 3. Upload the bundle to S3 (quick test mode)

For this **simple test** we make the object **public-readable**. This matches the cloud-init example which uses an unauthenticated HTTPS URL with the region in the hostname.

```bash
aws s3 cp php-site.tar.gz \
  s3://my-image-bucket/config/php-site.tar.gz \
  --region us-west-1 \
  --acl public-read
```

Verify that the object is reachable:

```bash
curl -I https://my-image-bucket.s3.us-west-1.amazonaws.com/config/php-site.tar.gz
```

You should see: `HTTP/1.1 200 OK`.

> For production, remove `--acl public-read` and switch to using an EC2 instance role + S3 API (not covered in this simple doc).

---

## 4. Cloud-init configuration

This cloud-config:

* Installs **Apache + PHP 8** on SLES16.
* Downloads the **PHP site bundle** from S3 over **HTTPS**.
* Extracts it into `/srv/www/htdocs`.
* If the S3 object is not reachable (403/404), it deploys a **fallback sample page**.
* Enables and starts Apache on port **80**.

**User data (cloud-init):**

```yaml
#cloud-config
package_update: false

write_files:
  - path: /usr/local/sbin/init-php-from-https-or-default.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      exec > >(tee -a /var/log/init-php-site.log) 2>&1

      echo "== $(date -Is) init starting =="

      # ---- CONFIG ----
      # Region-specific S3 HTTPS URL (or a pre-signed URL)
      APP_SOURCE_HTTPS="https://my-image-bucket.s3.us-west-1.amazonaws.com/config/php-site.tar.gz"
      DOCROOT="/srv/www/htdocs"
      APACHE_PORT="80"
      MARKER="/var/lib/cloud/instance/sem/php_site_initialized"
      TMP="/tmp/php-site-bundle"
      # ----------------

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

      # Install web stack + tools
      echo "[info] Installing packages..."
      zypper -n install --no-recommends \
        apache2 apache2-mod_php8 php8 \
        curl tar gzip unzip

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
          AllowOverride None
          Require all granted
        </Directory>

        ErrorLog /var/log/apache2/error_log
        CustomLog /var/log/apache2/access_log combined
      </VirtualHost>
      EOF

      deploy_default_site() {
        echo "[info] Deploying fallback default sample site."
        cat >"${DOCROOT}/index.php" <<'EOF'
      <!doctype html>
      <html>
      <head><meta charset="utf-8"><title>SLES16 + PHP on EC2</title></head>
      <body style="font-family: system-ui, sans-serif;">
        <h1>It works ✅</h1>
        <p>Fallback site (bundle not found or not accessible via HTTPS).</p>
        <ul>
          <li>Hostname: <?php echo gethostname(); ?></li>
          <li>Server time: <?php echo date('c'); ?></li>
        </ul>
        <p><a href="/phpinfo.php">PHP Info</a></p>
      </body>
      </html>
      EOF

        cat >"${DOCROOT}/phpinfo.php" <<'EOF'
      <?php phpinfo();
      EOF
      }

      deploy_bundle_from_file() {
        local file="$1"
        echo "[info] Deploying bundle from $file"
        rm -rf "${DOCROOT:?}/"* 2>/dev/null || true

        if [[ "$APP_SOURCE_HTTPS" == *.tar.gz ]] || [[ "$APP_SOURCE_HTTPS" == *.tgz ]]; then
          tar -xzf "$file" -C "$DOCROOT"
        elif [[ "$APP_SOURCE_HTTPS" == *.zip ]]; then
          unzip -o "$file" -d "$DOCROOT"
        else
          echo "[warn] Unknown bundle extension; expected .tar.gz/.tgz or .zip"
          return 1
        fi

        if [[ ! -f "${DOCROOT}/index.php" && ! -f "${DOCROOT}/index.html" ]]; then
          echo "[warn] No index.* found in bundle; creating minimal index.php"
          cat >"${DOCROOT}/index.php" <<'EOF'
      <?php
      echo "Bundle deployed but missing index.php/index.html\n";
      echo "Hostname: " . gethostname() . "\n";
      echo "Time: " . date('c') . "\n";
      ?>
      EOF
        fi
      }

      echo "[info] Checking HTTPS bundle URL:"
      echo "[info]   $APP_SOURCE_HTTPS"

      DEPLOYED="no"

      # HEAD request to see if object is reachable
      HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' -I "$APP_SOURCE_HTTPS" || true)"
      echo "[info] HEAD status: $HTTP_CODE"

      if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
        echo "[info] Bundle appears reachable. Downloading..."
        if curl -fLsS --retry 5 --retry-delay 2 "$APP_SOURCE_HTTPS" -o "$TMP"; then
          if deploy_bundle_from_file "$TMP"; then
            DEPLOYED="yes"
          else
            echo "[warn] Downloaded but failed to unpack."
          fi
        else
          echo "[warn] Download failed."
        fi
      elif [[ "$HTTP_CODE" == "403" ]]; then
        echo "[warn] Got 403 Forbidden. Object may exist but is private."
        echo "[warn] Use a pre-signed URL as APP_SOURCE_HTTPS or adjust bucket/object policy."
      else
        echo "[warn] Bundle not reachable via HTTPS (HTTP $HTTP_CODE)."
      fi

      if [[ "$DEPLOYED" != "yes" ]]; then
        deploy_default_site
      else
        echo "[info] Bundle deployed successfully."
      fi

      systemctl enable apache2
      systemctl restart apache2

      # Optional firewall open if firewalld is enabled
      if systemctl is-enabled --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
      fi

      echo "[info] Local curl check:"
      curl -fsS "http://127.0.0.1:${APACHE_PORT}/" | head -n 8 || true

      mkdir -p "$(dirname "$MARKER")"
      touch "$MARKER"
      echo "== $(date -Is) init done =="

  - path: /etc/systemd/system/php-site-init.service
    permissions: "0644"
    owner: root:root
    content: |
      [Unit]
      Description=Initialize PHP site from HTTPS S3 URL if present, else deploy default
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/init-php-from-https-or-default.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now php-site-init.service

final_message: "PHP site init finished. Logs: /var/log/init-php-site.log"
```

You can paste this directly into the **User data** field when launching your EC2 instance.

---

## 5. Launch the EC2 instance

1. In the AWS Console, go to **EC2 → Instances → Launch instances**.
2. Choose a **SLES16** AMI (aarch64 in your current setup, if that’s what you used before).
3. Choose an instance type (for testing: `t4g.small` / `t4g.medium` or similar).
4. Under **Network settings**, select:

   * A **VPC** and **subnet** with Internet access (e.g., via an Internet Gateway or NAT).
   * A **Security Group** that allows **TCP/80** inbound from your client IP/CIDR.
5. Under **Advanced details → User data**, paste the cloud-config from the previous section.
6. Launch the instance.

---

## 6. Validate the deployment

Once the instance is in `running` state and `Status checks` are OK:

1. SSH into the instance (optional, for debugging):

   ```bash
   ssh ec2-user@<public-ip>
   ```

2. Check the init log:

   ```bash
   sudo tail -n 200 /var/log/init-php-site.log
   ```

   You should see the PHP/Apache packages being installed and the HTTPS HEAD request returning `200` if the object is public.

3. On your workstation, open:

   * `http://<public-ip>/`
   * `http://<public-ip>/health.php`
   * `http://<public-ip>/info.php`

You should see the **sample PHP site** from your `php-site.tar.gz` bundle. If the bundle cannot be downloaded, you’ll see the **fallback “It works ✅”** page instead.

<img width="887" height="502" alt="image" src="https://github.com/user-attachments/assets/c4399796-1be2-4a8d-8a5e-122580a3d448" />

---

## 7. Troubleshooting

Common cases:

* **HTTP 403 in init log**

  ```text
  [info] HEAD status: 403
  [warn] Got 403 Forbidden. Object may exist but is private.
  ```

  The object exists but is not readable. Either:

  * Re-upload with `--acl public-read` (for tests), or
  * Use a pre-signed HTTPS URL, or
  * Switch to IAM role + S3 API approach (no public ACL).

* **HTTP 404 in init log**

  * Check the object key:

    * `config/php-site.tar.gz` vs `config/php_site.tar.gz` etc.
  * Confirm with:

    ```bash
    aws s3 ls s3://my-image-bucket/config/
    ```

* **Apache not running**

  * On the instance:

    ```bash
    sudo systemctl status apache2
    sudo journalctl -u apache2 -n 50
    ```

---

