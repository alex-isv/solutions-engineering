**Deployment guide** for
**“Ansible Playbook + Cockpit Integration on SLES 16”**,
covering complete playbook integration for **Apache Tomcat 11**, **PostgreSQL 17**, **MariaDB 11**, and the **MCP Client**, including the **RPM packaging process**.


---

#  Ansible Playbooks Integrated with Cockpit on SLES 16

This document provides **end-to-end steps** to:

* Deploy Ansible playbooks integrated with Cockpit
* Configure Apache Tomcat 11, PostgreSQL 17, and MariaDB 11
* Add the MCP Client plugin for remote model inference
* Package the complete Cockpit extension as an **RPM**

---

##  System Prerequisites

Ensure your SLES 16 system has base tools and Python ready.

```bash
sudo zypper install -y python313 python313-pip git curl unzip tar gzip make
sudo python3 -m pip install --upgrade pip setuptools wheel requests fastapi uvicorn
```

---

## 1. Install Cockpit and Ansible Environment

```bash
sudo zypper install -y cockpit cockpit-ws ansible firewalld jq tree
sudo systemctl enable --now cockpit.socket firewalld
```

Access Cockpit at:

```
https://<your_server_ip>:9090
```

---

##  2. Directory Layout

All Cockpit-related files will reside under:

```
/usr/share/cockpit/ansible-playbook/
├── manifest.json
├── index.html
├── index.js
├── ansible/
│   ├── deploy_tomcat.yml
│   ├── deploy_postgres.yml
│   ├── deploy_mariadb.yml
│   └── (any future playbooks)
└── bin/
    ├── deploy-tomcat
    ├── deploy-postgres
    ├── deploy-mariadb
    └── deploy-mcpclient
```

---

##  3. manifest.json

Defines the Cockpit module.

```json
{
  "version": 0,
  "tools": {
    "ansible-playbook": {
      "label": "Ansible Playbook",
      "path": "index.html",
      "icon": "applications-engineering"
    }
  }
}
```

Save as `/usr/share/cockpit/ansible-playbook/manifest.json`.

---

##  4. Ansible Playbooks

Each playbook lives under `/usr/share/cockpit/ansible-playbook/ansible/`.

###  4.1 Apache Tomcat 11

**File:** `/usr/share/cockpit/ansible-playbook/ansible/deploy_tomcat.yml`

<details><summary>Expand for detailed values</summary>
    
```yaml
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

    - name: Install Tomcat 11
      zypper:
        name:
          - tomcat11
          - tomcat11-webapps
          - tomcat11-admin-webapps
          - tomcat11-lib
        state: present
        update_cache: yes

    - name: Ensure JAVA_HOME
      lineinfile:
        path: /etc/tomcat11/tomcat.conf
        regexp: '^JAVA_HOME='
        line: "JAVA_HOME={{ java_home_path }}"
      notify: restart tomcat

    - name: Ensure Tomcat config directory exists
      file:
        path: "{{ tomcat_config_dir }}"
        state: directory
        owner: tomcat
        group: tomcat

    - name: Ensure server.xml exists
      copy:
        dest: "{{ tomcat_config_dir }}/server.xml"
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
      when: not ansible_check_mode

    - name: Add Tomcat user
      blockinfile:
        path: "{{ tomcat_config_dir }}/tomcat-users.xml"
        marker: "<!-- {mark} ANSIBLE MANAGED BLOCK -->"
        block: |
          <role rolename="{{ tomcat_user_role | default('manager-gui') }}"/>
          <user username="{{ tomcat_username | default('admin') }}" password="{{ tomcat_password | default('changeme') }}" roles="{{ tomcat_user_role | default('manager-gui') }}"/>
      notify: restart tomcat

    - name: Start and enable Tomcat
      systemd:
        name: tomcat
        state: started
        enabled: yes

  handlers:
    - name: restart tomcat
      systemd:
        name: tomcat
        state: restarted
```

</details>
---

###  4.2 PostgreSQL 17

**File:** `/usr/share/cockpit/ansible-playbook/ansible/deploy_postgres.yml`

<details><summary>Expand for detailed values</summary>


```yaml
---
- hosts: database_servers
  become: yes
  vars:
    pg_username: dbadmin
    pg_password: secret
  tasks:
    - name: Install PostgreSQL
      zypper:
        name: postgresql17
        state: present
        update_cache: yes

    - name: Ensure PostgreSQL is running
      systemd:
        name: postgresql
        state: started
        enabled: yes

    - name: Create database user
      become_user: postgres
      postgresql_user:
        name: "{{ pg_username }}"
        password: "{{ pg_password }}"
        state: present
```

</details>
---

### 4.3 MariaDB 11

**File:** `/usr/share/cockpit/ansible-playbook/ansible/deploy_mariadb.yml`

<details><summary>Expand for detailed values</summary>


```yaml
---
- hosts: database_servers
  become: yes
  vars:
    mdb_username: dbadmin
    mdb_password: secret
    mdb_dbname: appdb
  tasks:
    - name: Install MariaDB
      zypper:
        name: mariadb
        state: present
        update_cache: yes

    - name: Ensure service is started
      systemd:
        name: mariadb
        state: started
        enabled: yes

    - name: Secure installation
      mysql_user:
        name: "{{ mdb_username }}"
        password: "{{ mdb_password }}"
        priv: "{{ mdb_dbname }}.*:ALL"
        state: present
```

</details>
---

##  5. MCP Client Integration

**Wrapper script:** `/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient`

<details><summary>Expand for detailed values</summary>

```bash
#!/bin/bash
SERVER_URL="http://localhost:8787"
TOOL="list_tools"
PAYLOAD="{}"

# --list-tools mode
if [[ "$1" == "--list-tools" ]]; then
    SERVER_URL="${2:-http://localhost:8787}"
    python3 - <<PYCODE
import json, requests
server = "$SERVER_URL"
try:
    r = requests.get(f"{server}/tools", timeout=10)
    r.raise_for_status()
    tools = r.json()
    print(json.dumps(tools if isinstance(tools, list) else {"error": "Unexpected response"}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYCODE
    exit 0
fi

# Normal run
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) SERVER_URL="$2"; shift 2 ;;
    --tool) TOOL="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "Invoking MCP client..."
echo "Server: $SERVER_URL"
echo "Tool: $TOOL"
echo "Payload: $PAYLOAD"

python3 - <<PYCODE
import json, requests, sys, textwrap
server = "$SERVER_URL"
tool = "$TOOL"
try:
    payload = json.loads("""$PAYLOAD""")
except Exception:
    payload = {}
try:
    print(f"→ Connecting to {server}/call_tool ...")
    r = requests.post(f"{server}/call_tool", json={"name": tool, "arguments": payload}, timeout=600)
    print(f"← Status: {r.status_code}")
    if r.ok:
        try:
            data = r.json()
            response_text = data.get("response", "").strip()
            print("✅ MCP Response:")
            for line in textwrap.wrap(response_text, width=100):
                print(line)
        except Exception:
            print("✅ MCP Raw Response:")
            print(r.text)
    else:
        print("❌ Error:", r.text)
        sys.exit(1)
except Exception as e:
    print("❌ MCP invocation failed:", e)
    sys.exit(1)
PYCODE
```

</details>
---

##  6. Cockpit UI Integration

**index.html** and **index.js** define Cockpit interaction —
They include all four modules (Tomcat, PostgreSQL, MariaDB, MCP Client)
with dropdown-based playbook selection and a shared deploy button.

`index.html`

<details><summary>Expand for detailed values</summary>
  
```
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
    .hidden { display:none !important; }
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
        <option value="mariadb">Deploy MariaDB 11</option>
        <option value="mcpclient">Invoke MCP Client</option>
      </select>
    </label>

    <!-- Tomcat options -->
    <fieldset id="tomcat-options" class="hidden" style="display:none;">
      <legend>Tomcat 11 Settings</legend>
      <label>HTTP port <input id="http_port" type="number" value="8080" /></label>
      <label>Shutdown port <input id="shutdown_port" type="number" value="8005" /></label>
      <label>AJP port <input id="ajp_port" type="number" value="8009" /></label>
      <label>Manager username <input id="username" type="text" value="admin" /></label>
      <label>Manager password <input id="password" type="password" value="changeme" /></label>
    </fieldset>

    <!-- PostgreSQL options -->
    <fieldset id="postgres-options" class="hidden" style="display:none;">
      <legend>PostgreSQL 17 Settings</legend>
      <label>DB username <input id="pg_username" type="text" value="dbadmin" /></label>
      <label>DB password <input id="pg_password" type="password" value="secret" /></label>
    </fieldset>

    <!-- MariaDB options -->
    <fieldset id="mariadb-options" class="hidden" style="display:none;">
      <legend>MariaDB 11 Settings</legend>
      <label>DB username <input id="mdb_username" type="text" value="dbadmin" /></label>
      <label>DB password <input id="mdb_password" type="password" value="secret" /></label>
      <label>Database name <input id="mdb_dbname" type="text" value="appdb" /></label>
    </fieldset>

    <!-- MCP client options -->
    <fieldset id="mcpclient-options" class="hidden" style="display:none;">
      <legend>MCP Client Settings</legend>

      <label>MCP Server URL
        <input id="mcp_server" type="text" value="http://192.168.150.152:8787" style="width: 300px;" />
      </label>

      <label>Tool name
        <select id="mcp_tool" style="width: 300px;">
          <option value="">-- Select a model --</option>
        </select>
        <button id="refresh_tools" style="margin-left:10px;">↻ Refresh</button>
      </label>

      <label>Prompt
        <textarea id="mcp_prompt" rows="4" cols="60" placeholder="Ask your question here..."></textarea>
      </label>
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

```
</details>
---


`index.js`

<details><summary>Expand for detailed values</summary>
  
```
(function () {
  'use strict';
  function $(id) { return document.getElementById(id); }

  function appendOutput(text) {
    const out = $('output');
    out.textContent += text;
    out.scrollTop = out.scrollHeight;
  }
  function clearOutput() { $('output').textContent = ''; }
  function disableForm(disabled) {
    $('deploy').disabled = disabled;
    $('clear').disabled = disabled;
  }
  function setDeployLabel(sel) {
    const map = {
      tomcat: 'Deploy Apache Tomcat 11',
      postgresql: 'Deploy PostgreSQL 17',
      mariadb: 'Deploy MariaDB 11',
      mcpclient: 'Invoke MCP Client'
    };
    $('deploy').textContent = map[sel] || 'Deploy';
  }
  function showOnly(selected) {
    const panels = ['tomcat-options','postgres-options','mariadb-options','mcpclient-options'];
    panels.forEach(id=>{
      const el=$(id);
      if(el)el.style.display=(id.startsWith(selected))?'block':'none';
    });
    setDeployLabel(selected);
    if(selected==='mcpclient'){loadTools();}
  }

  // --- New: load tool list using cockpit.spawn (CSP safe)
  async function loadTools() {
    const server = $('mcp_server').value || 'http://localhost:8787';
    const select = $('mcp_tool');
    select.innerHTML='<option>-- Loading models... --</option>';
    try {
      const args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient','--list-tools',server];
      const proc = cockpit.spawn(args, {err:'out',superuser:true});
      let buffer='';
      proc.stream(data=>buffer+=data);
      proc.done(()=>{
        try {
          const result=JSON.parse(buffer.trim());
          select.innerHTML='';
          if(Array.isArray(result)){
            result.forEach(t=>{
              const o=document.createElement('option');
              o.value=t;o.textContent=t;
              select.appendChild(o);
            });
            appendOutput(`✅ Loaded ${result.length} models from ${server}\n`);
          } else if(result.error){
            select.innerHTML='<option>⚠️ Error loading models</option>';
            appendOutput('⚠️ '+result.error+'\n');
          } else {
            select.innerHTML='<option>⚠️ Invalid response</option>';
          }
        } catch(e){
          select.innerHTML='<option>⚠️ Parse error</option>';
          appendOutput('⚠️ '+e+'\n');
        }
      });
      proc.fail(err=>{
        select.innerHTML='<option>⚠️ Failed to load</option>';
        appendOutput('⚠️ spawn error '+JSON.stringify(err)+'\n');
      });
    } catch(e){
      select.innerHTML='<option>⚠️ Spawn failed</option>';
      appendOutput('⚠️ '+e+'\n');
    }
  }

  document.addEventListener('DOMContentLoaded',function(){
    const select=$('playbook');
    showOnly(select.value);
    select.addEventListener('change',()=>showOnly(select.value));
    $('clear').addEventListener('click',clearOutput);
    const refresh=$('refresh_tools');
    if(refresh)refresh.addEventListener('click',loadTools);

    $('deploy').addEventListener('click',function(){
      clearOutput();disableForm(true);
      const choice=select.value;let args=[];
      if(choice==='tomcat'){
        const http=$('http_port').value||'8080';
        const shut=$('shutdown_port').value||'8005';
        const ajp=$('ajp_port').value||'8009';
        const user=$('username').value||'admin';
        const pass=$('password').value||'changeme';
        args=['/usr/share/cockpit/ansible-playbook/bin/deploy-tomcat',
          '--http-port',http,'--shutdown-port',shut,
          '--ajp-port',ajp,'--username',user,'--password',pass];
      } else if(choice==='postgresql'){
        const user=$('pg_username').value||'dbadmin';
        const pass=$('pg_password').value||'secret';
        args=['/usr/share/cockpit/ansible-playbook/bin/deploy-postgres','--username',user,'--password',pass];
      } else if(choice==='mariadb'){
        const user=$('mdb_username').value||'dbadmin';
        const pass=$('mdb_password').value||'secret';
        const db=$('mdb_dbname').value||'appdb';
        args=['/usr/share/cockpit/ansible-playbook/bin/deploy-mariadb','--username',user,'--password',pass,'--dbname',db];
      } else if(choice==='mcpclient'){
        const server=$('mcp_server').value||'http://localhost:8787';
        const tool=$('mcp_tool').value||'llama3_8b';
        const prompt=$('mcp_prompt').value.trim();
        if(!tool){appendOutput('⚠️ Please select a model first.\n');disableForm(false);return;}
        if(!prompt){appendOutput('⚠️ Please enter a prompt.\n');disableForm(false);return;}
        const payload=JSON.stringify({prompt});
        args=['/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient',
          '--server',server,'--tool',tool,'--payload',payload];
        appendOutput(`Running model '${tool}' with prompt: "${prompt}"\n\n`);
      }
      appendOutput('Running: '+args.join(' ')+'\n\n');
      try{
        const proc=cockpit.spawn(args,{err:'out',superuser:true,directory:'/usr/share/cockpit/ansible-playbook/ansible'});
        proc.stream(d=>appendOutput(String(d)));
        proc.done(()=>{appendOutput('\n== Success ==\n');disableForm(false);});
        proc.fail(err=>{appendOutput('\n== Failed ==\n'+JSON.stringify(err)+'\n');disableForm(false);});
      }catch(e){appendOutput('\nException: '+e+'\n');disableForm(false);}
    });
  });
})();

```
</details>
---

##  7. Build the RPM Package

### 7.1 Build Script: `/usr/local/bin/build-rpm.sh`

<details><summary>Expand for detailed values</summary>

```bash
#!/bin/bash
#
# Build Cockpit Ansible Playbook RPM for SLES16
# Includes prerequisites and automatic build environment setup

set -e

PKGNAME="ansible-playbook-extension"
VERSION="${1:-1.0}"
RELEASE="1"
SUMMARY="Cockpit Ansible Playbook extension (Tomcat, PostgreSQL, MariaDB, MCP)"
LICENSE="MIT"
MAINTAINER=" Builder <builder@example.com>"
TOPDIR="/usr/src/packages"
SRCDIR="${TOPDIR}/SOURCES/${PKGNAME}"
TARBALL="${PKGNAME}-${VERSION}.tar.gz"
SPECDIR="${TOPDIR}/SPECS"
RPM_OUTPUT="${TOPDIR}/RPMS/noarch"

echo "==> Installing prerequisites..."
zypper --non-interactive install -y \
    python313 python313-pip git curl unzip tar gzip make \
    cockpit cockpit-ws ansible firewalld jq tree rpm-build

echo "==> Enabling cockpit and firewalld..."
systemctl enable --now cockpit.socket firewalld || true

echo "==> Preparing build environment..."
mkdir -p "${TOPDIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "${SRCDIR}"

echo "==> Copying source files..."
rm -rf "${SRCDIR:?}"/*
cp -a /usr/share/cockpit/ansible-playbook/* "${SRCDIR}/"

echo "==> Creating tarball..."
cd "${TOPDIR}/SOURCES"
tar czf "${TARBALL}" "${PKGNAME}"

echo "==> Creating SPEC file..."
cat > "${SPECDIR}/${PKGNAME}.spec" <<SPEC
Name:           ${PKGNAME}
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        ${SUMMARY}
License:        ${LICENSE}
URL:            https://github.com/example/ansible-on-cockpit
Source0:        ${TARBALL}
BuildArch:      noarch
Requires:       cockpit cockpit-ws ansible firewalld jq tree python3 python3-requests
BuildRequires:  rpm-build

%description
Provides a Cockpit extension for managing Ansible playbooks for Apache Tomcat, PostgreSQL, MariaDB, and MCP.

%prep
%setup -q -n ${PKGNAME}

%install
mkdir -p %{buildroot}/usr/share/cockpit/${PKGNAME}
cp -a * %{buildroot}/usr/share/cockpit/${PKGNAME}/
find %{buildroot}/usr/share/cockpit/${PKGNAME}/bin -type f -exec chmod 755 {} \\;

%files
/usr/share/cockpit/${PKGNAME}

%post
systemctl restart cockpit || true

%changelog
* $(date +"%a %b %d %Y") ${MAINTAINER} - ${VERSION}-${RELEASE}
- Initial release for SLES16
SPEC

echo "==> Building RPM..."
cd "${SPECDIR}"
rpmbuild -ba "${PKGNAME}.spec"

RPM_FILE=$(find "${RPM_OUTPUT}" -name "${PKGNAME}-${VERSION}-${RELEASE}*.rpm" | head -n 1)

if [ -f "${RPM_FILE}" ]; then
  echo
  echo "✅ Build complete!"
  echo "RPM located at: ${RPM_FILE}"
  echo "To install: sudo zypper install -y ${RPM_FILE}"
else
  echo "❌ Build failed!"
  exit 1
fi
```

</details>
---

### 7.2 Make It Executable

```bash
sudo chmod +x /usr/local/bin/build-rpm.sh
```

---

### 7.3 Run the Build

```bash
sudo build-rpm.sh
```

Output:

```
✅ Build complete!
RPM located at: /usr/src/packages/RPMS/noarch/ansible-playbook-extension-1.0-1.noarch.rpm
```

---

##  8. Install & Verify

```bash
sudo zypper install /usr/src/packages/RPMS/noarch/ansible-playbook-extension-1.0-1.noarch.rpm
sudo systemctl restart cockpit
```

Then open Cockpit:

**Tools → Ansible Playbook**

You’ll see:

```
Deploy Apache Tomcat 11
Deploy PostgreSQL 17
Deploy MariaDB 11
Invoke MCP Client
```

---

<img width="1675" height="730" alt="image" src="https://github.com/user-attachments/assets/731d8032-c8b9-417e-b7fe-c7be9ad1cc6d" />


## ✅ Summary

| Component               | Purpose                                                  |
| ----------------------- | -------------------------------------------------------- |
| **Cockpit Extension**   | Integrates Ansible playbooks into Cockpit                |
| **Tomcat Playbook**     | Installs & configures Apache Tomcat 11                   |
| **PostgreSQL Playbook** | Deploys PostgreSQL 17                                    |
| **MariaDB Playbook**    | Deploys MariaDB 11                                       |
| **MCP Client Plugin**   | Connects Cockpit to external MCP/Ollama inference server |
| **RPM Build Script**    | Packages the entire setup for easy installation          |

---

