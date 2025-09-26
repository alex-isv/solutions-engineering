

# 🚀 Cockpit Ansible Extension – Tomcat 11 Deployment (SLES16)

This guide installs a Cockpit extension that allows deploying and configuring **Apache Tomcat 11** via Ansible.

---

## 1. Prerequisites

On a clean SLES16 server:

```bash
sudo zypper refresh
sudo zypper install -y cockpit cockpit-ws ansible firewalld jq tree
sudo systemctl enable --now cockpit.socket firewalld
```

Then open Cockpit in your browser:
👉 `https://<server-ip>:9090`

---

## 2. Create Cockpit Extension Directory

  
```bash
sudo mkdir -p /usr/share/cockpit/ansible-playbook/{bin,ansible}
```

---

## 3. `manifest.json`

Minimal manifest (Cockpit doesn’t support deep nested menus – we build the hierarchy in the page UI):

<details><summary>Expand for detailed values</summary>

```bash
sudo tee /usr/share/cockpit/ansible-playbook/manifest.json > /dev/null <<'EOF'
{
  "version": 0,
  "tools": {
    "ansible-playbook": {
      "label": "Ansible Playbook",
      "icon": "applications-engineering",
      "path": "index.html"
    }
  }
}
EOF
```
</details>
---

## 4. `index.html`

UI page with hierarchical selection and deployment form:

<details><summary>Expand for detailed values</summary>

```bash
sudo tee /usr/share/cockpit/ansible-playbook/index.html > /dev/null <<'EOF'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Ansible Playbook</title>
  <style>
    body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial; padding: 18px; }
    .panel { max-width: 900px; }
    label { display:block; margin-top:10px; }
    input, select { padding:6px; width:260px; }
    button { margin-top:12px; padding:8px 12px; }
    pre#output { background:#111; color:#eee; padding:10px; height:320px; overflow:auto; white-space:pre-wrap; margin-top:12px; }
    .small { font-size:0.9em; color:#666; }
  </style>
</head>
<body>
  <div class="panel">
    <h2>Ansible Playbook Cockpit Extension</h2>
    <p class="small">Select a playbook and configure settings, then click <strong>Deploy Tomcat 11</strong>.</p>

    <label>Category
      <select id="category">
        <option value="apache-tomcat-11">Apache Tomcat 11</option>
      </select>
    </label>

    <label>Playbook
      <select id="playbook">
        <option value="tomcat-11-deployment">Tomcat 11 Deployment (Use custom settings)</option>
      </select>
    </label>

    <fieldset style="border:1px solid #ddd; padding:10px; margin-top:12px;">
      <legend>Custom settings</legend>

      <label>HTTP port
        <input id="http_port" type="number" value="8080" />
      </label>

      <label>Shutdown port
        <input id="shutdown_port" type="number" value="8005" />
      </label>

      <label>AJP port
        <input id="ajp_port" type="number" value="8009" />
      </label>

      <label>Manager username
        <input id="username" type="text" value="admin" />
      </label>

      <label>Manager password
        <input id="password" type="password" value="changeme" />
      </label>
    </fieldset>

    <div style="margin-top:12px;">
      <button id="deploy">Deploy Tomcat 11</button>
      <button id="clear">Clear Output</button>
    </div>

    <pre id="output" aria-live="polite"></pre>
  </div>

  <script src="../base1/cockpit.js"></script>
  <script src="index.js"></script>
</body>
</html>
EOF
```
</details>

---

## 5. `index.js`

Logic for running the deploy script via `cockpit.spawn`:

<details><summary>Expand for detailed values</summary>

```bash
sudo tee /usr/share/cockpit/ansible-playbook/index.js > /dev/null <<'EOF'
(function () {
  'use strict';

  function appendOutput(text) {
    const out = document.getElementById('output');
    out.textContent += text;
    out.scrollTop = out.scrollHeight;
  }

  function clearOutput() {
    document.getElementById('output').textContent = '';
  }

  function disableForm(disabled) {
    document.getElementById('deploy').disabled = disabled;
    document.getElementById('clear').disabled = disabled;
  }

  document.addEventListener('DOMContentLoaded', function () {
    const deployBtn = document.getElementById('deploy');
    const clearBtn  = document.getElementById('clear');

    clearBtn.addEventListener('click', function () { clearOutput(); });

    deployBtn.addEventListener('click', function () {
      clearOutput();
      disableForm(true);
      appendOutput('Preparing Tomcat 11 deployment...\\n');

      const httpPort    = document.getElementById('http_port').value || '8080';
      const shutdownPort= document.getElementById('shutdown_port').value || '8005';
      const ajpPort     = document.getElementById('ajp_port').value || '8009';
      const username    = document.getElementById('username').value || 'admin';
      const password    = document.getElementById('password').value || 'changeme';

      const scriptPath = '/usr/share/cockpit/ansible-playbook/bin/deploy-tomcat';
      const args = [
        scriptPath,
        '--http-port', String(httpPort),
        '--shutdown-port', String(shutdownPort),
        '--ajp-port', String(ajpPort),
        '--username', String(username),
        '--password', String(password)
      ];

      appendOutput('Running: ' + args.join(' ') + '\\n\\n');

      try {
        const proc = cockpit.spawn(args, {
          err: 'out',
          directory: '/usr/share/cockpit/ansible-playbook/ansible',
          superuser: true
        });

        proc.stream(function (data) {
          appendOutput(String(data));
        });

        proc.done(function () {
          appendOutput('\\n== Process finished successfully ==\\n');
          disableForm(false);
        });

        proc.fail(function (err) {
          appendOutput('\\n== Process failed ==\\n' + JSON.stringify(err) + '\\n');
          disableForm(false);
        });
      } catch (e) {
        appendOutput('\\nException starting process: ' + e + '\\n');
        disableForm(false);
      }
    });
  });
})();
EOF
```
</details>

---

## 6. `deploy_tomcat.yml`

The Ansible playbook (with **restart only**, no reload):

<details><summary>Expand for detailed values</summary>

```bash
sudo tee /usr/share/cockpit/ansible-playbook/ansible/deploy_tomcat.yml > /dev/null <<'EOF'
---
- hosts: tomcat_servers
  become: yes
  vars:
    java_home_path: /usr/lib64/jvm/java-17-openjdk-17
    tomcat_config_dir: /etc/tomcat11
  tasks:
    - name: Install Java
      zypper:
        name: java-17-openjdk-headless
        state: present
        update_cache: yes

    - name: Install Tomcat 11 and related packages
      zypper:
        name:
          - tomcat11
          - tomcat11-webapps
          - tomcat11-admin-webapps
          - tomcat11-lib
        state: present
        update_cache: yes

    - name: Ensure JAVA_HOME in Tomcat environment
      lineinfile:
        path: /etc/tomcat11/tomcat.conf
        regexp: '^JAVA_HOME='
        line: "JAVA_HOME={{ java_home_path }}"
        create: yes
        owner: tomcat
        group: tomcat
        mode: '0644'
      notify: restart tomcat

    - name: Ensure Tomcat config directory exists
      file:
        path: "{{ tomcat_config_dir }}"
        state: directory
        owner: tomcat
        group: tomcat
        mode: '0755'

    - name: Ensure server.xml exists
      copy:
        content: |
          <?xml version="1.0" encoding="UTF-8"?>
          <Server port="8005" shutdown="SHUTDOWN">
            <Service name="Catalina">
              <Connector port="8080" protocol="HTTP/1.1" connectionTimeout="20000" redirectPort="8443" />
              <Connector protocol="AJP/1.3" port="8009" redirectPort="8443" secretRequired="false" />
              <Engine name="Catalina" defaultHost="localhost">
                <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
              </Engine>
            </Service>
          </Server>
        dest: "{{ tomcat_config_dir }}/server.xml"
        owner: tomcat
        group: tomcat
        mode: '0644'
        force: no
      when: not lookup('file', '{{ tomcat_config_dir }}/server.xml', errors='ignore')

    - name: Ensure tomcat-users.xml exists
      copy:
        content: |
          <?xml version="1.0" encoding="UTF-8"?>
          <tomcat-users xmlns="http://tomcat.apache.org/xml"
                        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                        xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
                        version="1.0">
          </tomcat-users>
        dest: "{{ tomcat_config_dir }}/tomcat-users.xml"
        owner: tomcat
        group: tomcat
        mode: '0644'
        force: no
      when: not lookup('file', '{{ tomcat_config_dir }}/tomcat-users.xml', errors='ignore')

    - name: Configure HTTP port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Connector port="8080" protocol="HTTP/1.1"'
        line: "<Connector port=\"{{ tomcat_http_port | default('8080') }}\" protocol=\"HTTP/1.1\" connectionTimeout=\"20000\" redirectPort=\"8443\" />"
        backup: yes
      notify: restart tomcat

    - name: Configure shutdown port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Server port="8005"'
        line: "<Server port=\"{{ tomcat_shutdown_port | default('8005') }}\" shutdown=\"SHUTDOWN\">"
        backup: yes
      notify: restart tomcat

    - name: Configure AJP port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Connector protocol="AJP/1.3" port="8009"'
        line: "<Connector protocol=\"AJP/1.3\" port=\"{{ tomcat_ajp_port | default('8009') }}\" redirectPort=\"8443\" secretRequired=\"false\" />"
        backup: yes
      notify: restart tomcat

    - name: Add user and role to tomcat-users.xml
      blockinfile:
        path: "{{ tomcat_config_dir }}/tomcat-users.xml"
        marker: "<!-- {mark} ANSIBLE MANAGED BLOCK -->"
        block: |
          <role rolename="{{ tomcat_user_role | default('manager-gui') }}"/>
          <user username="{{ tomcat_username | default('admin') }}" password="{{ tomcat_password | default('changeme') }}" roles="{{ tomcat_user_role | default('manager-gui') }}"/>
        backup: yes
      notify: restart tomcat

    - name: Reload systemd
      systemd:
        daemon_reload: yes

    - name: Start and enable Tomcat
      systemd:
        name: tomcat
        state: started
        enabled: yes

    - name: Open firewall for HTTP port
      firewalld:
        port: "{{ tomcat_http_port | default('8080') }}/tcp"
        permanent: yes
        state: enabled
        immediate: yes

  handlers:
    - name: restart tomcat
      systemd:
        name: tomcat
        state: restarted
EOF
```
</details>

---

## 7. `hosts` file

Define local host group:

```bash
sudo tee /usr/share/cockpit/ansible-playbook/ansible/hosts > /dev/null <<'EOF'
[tomcat_servers]
localhost ansible_connection=local
EOF
```

---

## 8. `deploy-tomcat` wrapper script

<details><summary>Expand for detailed values</summary>

```bash
sudo tee /usr/share/cockpit/ansible-playbook/bin/deploy-tomcat > /dev/null <<'EOF'
#!/bin/bash
HTTP_PORT=8080
SHUTDOWN_PORT=8005
AJP_PORT=8009
USERNAME="admin"
PASSWORD="changeme"
USER_ROLE="manager-gui"

while [[ $# -gt 0 ]]; do
    case $1 in
        --http-port) HTTP_PORT="$2"; shift 2 ;;
        --shutdown-port) SHUTDOWN_PORT="$2"; shift 2 ;;
        --ajp-port) AJP_PORT="$2"; shift 2 ;;
        --username) USERNAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --user-role) USER_ROLE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "Starting Tomcat 11 Deployment..."
echo "Ports: HTTP $HTTP_PORT, Shutdown $SHUTDOWN_PORT, AJP $AJP_PORT | User: $USERNAME ($USER_ROLE)"

cd /usr/share/cockpit/ansible-playbook/ansible || exit 1
ansible-playbook -i hosts deploy_tomcat.yml \
  -e tomcat_http_port="$HTTP_PORT" \
  -e tomcat_shutdown_port="$SHUTDOWN_PORT" \
  -e tomcat_ajp_port="$AJP_PORT" \
  -e tomcat_username="$USERNAME" \
  -e tomcat_password="$PASSWORD" \
  -e tomcat_user_role="$USER_ROLE"

if [[ $? -eq 0 ]]; then
  echo "Deployment Finished."
  echo "Verify: sudo systemctl status tomcat.service"
  echo "Access Tomcat at http://<server_ip>:$HTTP_PORT and Manager at http://<server_ip>:$HTTP_PORT/manager/html"
else
  echo "Deployment Failed. Check logs: journalctl -u tomcat.service or /var/log/tomcat/catalina.out"
  exit 1
fi
EOF
```
</details>

```
sudo chmod +x /usr/share/cockpit/ansible-playbook/bin/deploy-tomcat
```

---

## 9. Fix Permissions

```bash
sudo chmod -R a+rX /usr/share/cockpit/ansible-playbook
```

---

## 10. Restart Cockpit

```bash
sudo systemctl restart cockpit
```

Open Cockpit in your browser → **Tools → Ansible Playbook**
You’ll see the **Deploy Tomcat 11** form.
Run it and watch Ansible output stream in real time.

---

## ✅ Result

* Installs Java 17 + Tomcat 11
* Configures ports and admin user from UI
* Starts Tomcat service and opens firewall
* Accessible at:

  * `http://<server-ip>:8080`
  * `http://<server-ip>:8080/manager/html`

---

<img width="1270" height="916" alt="image" src="https://github.com/user-attachments/assets/a20c0553-7419-4109-93a0-88b5b62d175a" />
<img width="865" height="189" alt="image" src="https://github.com/user-attachments/assets/212fed14-9a0a-4df2-9b21-e5fe7915054c" />
<img width="1069" height="883" alt="image" src="https://github.com/user-attachments/assets/f7d7d296-2aff-4e1b-9c28-d2b11b338ad6" />


To add another application the following structure can be used:

 **Cockpit Ansible Playbook extension** so that under

**Tools → Ansible Playbook → Ansible Playbooks (Select a playbook to run:)**

you’ll see **two options**:

* **Deploy Apache Tomcat 11** (with the same custom form as before)
* **Deploy PostgreSQL 17** (with a few custom settings: username + password)



---

# 🔧 Updated Cockpit Extension: Tomcat 11 + PostgreSQL 17

## 1. `manifest.json`

We keep the manifest **minimal** (Cockpit doesn’t auto-render child menus). The hierarchy will be handled inside `index.html`.

```bash
sudo tee /usr/share/cockpit/ansible-playbook/manifest.json > /dev/null <<'EOF'
{
  "version": 0,
  "tools": {
    "ansible-playbook": {
      "label": "Ansible Playbook",
      "icon": "applications-engineering",
      "path": "index.html"
    }
  }
}
EOF
```

---

## 2. `index.html`

We now show a **playbook selector** with two entries: *Tomcat 11* and *PostgreSQL 17*.
Each shows a custom form depending on selection.

```bash
sudo tee /usr/share/cockpit/ansible-playbook/index.html > /dev/null <<'EOF'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Ansible Playbook</title>
  <style>
    body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, Arial; padding: 18px; }
    .panel { max-width: 900px; }
    label { display:block; margin-top:10px; }
    input, select { padding:6px; width:260px; }
    button { margin-top:12px; padding:8px 12px; }
    pre#output { background:#111; color:#eee; padding:10px; height:320px; overflow:auto; white-space:pre-wrap; margin-top:12px; }
    .small { font-size:0.9em; color:#666; }
    fieldset { border:1px solid #ddd; padding:10px; margin-top:12px; }
  </style>
</head>
<body>
  <div class="panel">
    <h2>Ansible Playbook Cockpit Extension</h2>
    <p class="small">Select a playbook and configure settings, then click <strong>Deploy</strong>.</p>

    <label>Playbook
      <select id="playbook">
        <option value="tomcat">Deploy Apache Tomcat 11</option>
        <option value="postgresql">Deploy PostgreSQL 17</option>
      </select>
    </label>

    <!-- Tomcat options -->
    <fieldset id="tomcat-options">
      <legend>Tomcat 11 Settings</legend>
      <label>HTTP port <input id="http_port" type="number" value="8080" /></label>
      <label>Shutdown port <input id="shutdown_port" type="number" value="8005" /></label>
      <label>AJP port <input id="ajp_port" type="number" value="8009" /></label>
      <label>Manager username <input id="username" type="text" value="admin" /></label>
      <label>Manager password <input id="password" type="password" value="changeme" /></label>
    </fieldset>

    <!-- PostgreSQL options -->
    <fieldset id="postgres-options" style="display:none;">
      <legend>PostgreSQL 17 Settings</legend>
      <label>DB username <input id="pg_username" type="text" value="dbadmin" /></label>
      <label>DB password <input id="pg_password" type="password" value="secret" /></label>
    </fieldset>

    <div style="margin-top:12px;">
      <button id="deploy">Deploy</button>
      <button id="clear">Clear Output</button>
    </div>

    <pre id="output" aria-live="polite"></pre>
  </div>

  <script src="../base1/cockpit.js"></script>
  <script src="index.js"></script>
</body>
</html>
EOF
```

---

## 3. `index.js`

Logic to toggle forms & run correct wrapper script.

```bash
sudo tee /usr/share/cockpit/ansible-playbook/index.js > /dev/null <<'EOF'
(function () {
  'use strict';

  function appendOutput(text) {
    const out = document.getElementById('output');
    out.textContent += text;
    out.scrollTop = out.scrollHeight;
  }

  function clearOutput() {
    document.getElementById('output').textContent = '';
  }

  function disableForm(disabled) {
    document.getElementById('deploy').disabled = disabled;
    document.getElementById('clear').disabled = disabled;
  }

  document.addEventListener('DOMContentLoaded', function () {
    const playbookSelect = document.getElementById('playbook');
    const tomcatOpts = document.getElementById('tomcat-options');
    const postgresOpts = document.getElementById('postgres-options');

    playbookSelect.addEventListener('change', function () {
      if (playbookSelect.value === 'tomcat') {
        tomcatOpts.style.display = 'block';
        postgresOpts.style.display = 'none';
      } else {
        tomcatOpts.style.display = 'none';
        postgresOpts.style.display = 'block';
      }
    });

    document.getElementById('clear').addEventListener('click', clearOutput);

    document.getElementById('deploy').addEventListener('click', function () {
      clearOutput();
      disableForm(true);

      const selected = playbookSelect.value;
      let args = [];

      if (selected === 'tomcat') {
        const httpPort = document.getElementById('http_port').value || '8080';
        const shutdownPort = document.getElementById('shutdown_port').value || '8005';
        const ajpPort = document.getElementById('ajp_port').value || '8009';
        const username = document.getElementById('username').value || 'admin';
        const password = document.getElementById('password').value || 'changeme';
        args = [
          '/usr/share/cockpit/ansible-playbook/bin/deploy-tomcat',
          '--http-port', httpPort,
          '--shutdown-port', shutdownPort,
          '--ajp-port', ajpPort,
          '--username', username,
          '--password', password
        ];
      } else if (selected === 'postgresql') {
        const pgUser = document.getElementById('pg_username').value || 'dbadmin';
        const pgPass = document.getElementById('pg_password').value || 'secret';
        args = [
          '/usr/share/cockpit/ansible-playbook/bin/deploy-postgres',
          '--username', pgUser,
          '--password', pgPass
        ];
      }

      appendOutput('Running: ' + args.join(' ') + '\\n\\n');

      try {
        const proc = cockpit.spawn(args, {
          err: 'out',
          directory: '/usr/share/cockpit/ansible-playbook/ansible',
          superuser: true
        });

        proc.stream(function (data) { appendOutput(String(data)); });
        proc.done(function () { appendOutput('\\n== Success ==\\n'); disableForm(false); });
        proc.fail(function (err) { appendOutput('\\n== Failed ==\\n' + JSON.stringify(err) + '\\n'); disableForm(false); });
      } catch (e) {
        appendOutput('\\nException starting process: ' + e + '\\n');
        disableForm(false);
      }
    });
  });
})();
EOF
```

---

## 4. PostgreSQL Playbook (`deploy_postgres.yml`)

```bash
sudo tee /usr/share/cockpit/ansible-playbook/ansible/deploy_postgres.yml > /dev/null <<'EOF'
---
- hosts: db_servers
  become: yes
  vars:
    pg_service: postgresql
  tasks:
    - name: Install PostgreSQL 17
      zypper:
        name: 
          - postgresql17-server
          - python313-psycopg2
        state: present
        update_cache: yes

    - name: Initialize PostgreSQL database
      become: yes
      become_user: postgres
      command: /usr/lib/postgresql17/bin/initdb -D /var/lib/pgsql/data 
      args:
        creates: /var/lib/pgsql/data/PG_VERSION

    - name: Ensure PostgreSQL is started and enabled
      systemd:
        name: "{{ pg_service }}"
        state: started
        enabled: yes

    - name: Create database user
      become_user: postgres
      postgresql_user:
        name: "{{ pg_username | default('dbadmin') }}"
        password: "{{ pg_password | default('secret') }}"
        role_attr_flags: CREATEDB,LOGIN
EOF
```

---

## 5. PostgreSQL Hosts file

```bash
sudo tee -a /usr/share/cockpit/ansible-playbook/ansible/hosts > /dev/null <<'EOF'

[db_servers]
localhost ansible_connection=local
EOF
```

---

## 6. `deploy-postgres` wrapper script

```bash
sudo tee /usr/share/cockpit/ansible-playbook/bin/deploy-postgres > /dev/null <<'EOF'
#!/bin/bash
USERNAME="dbadmin"
PASSWORD="secret"

while [[ $# -gt 0 ]]; do
    case $1 in
        --username) USERNAME="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "Starting PostgreSQL 17 Deployment..."
cd /usr/share/cockpit/ansible-playbook/ansible || exit 1
ansible-playbook -i hosts deploy_postgres.yml \
  -e pg_username="$USERNAME" \
  -e pg_password="$PASSWORD"

if [[ $? -eq 0 ]]; then
  echo "PostgreSQL Deployment Finished."
  echo "Access with: psql -U $USERNAME"
else
  echo "Deployment Failed. Check logs: journalctl -u postgresql"
  exit 1
fi
EOF

sudo chmod +x /usr/share/cockpit/ansible-playbook/bin/deploy-postgres
```

---

## 7. Restart Cockpit

```bash
sudo systemctl restart cockpit
```

---

## ✅ Result

In Cockpit:

* Go to **Tools → Ansible Playbook**
* Choose playbook:

  * **Deploy Apache Tomcat 11** → shows Tomcat custom form
  * **Deploy PostgreSQL 17** → shows Postgres custom form

Both can be deployed with **custom parameters** directly from the UI 🎉.

---

<img width="1671" height="592" alt="image" src="https://github.com/user-attachments/assets/eb65393e-fc81-4513-8b94-c22547ffd816" />

<img width="1171" height="592" alt="image" src="https://github.com/user-attachments/assets/32eaabb9-875b-495d-802a-6329ce060283" />


