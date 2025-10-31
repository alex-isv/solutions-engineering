
 **MCP client in Cockpit** (Ansible extension) and a **FastAPI MCP server** that fronts three Ollama models.

---

# Step-by-Step: MCP Client (Cockpit/Ansible) + MCP Server (FastAPI + Ollama)

## 0) Prereqs (SLES 16)

```bash
# Base
sudo zypper install -y python313 python313-pip git curl unzip
sudo python3 -m pip install --upgrade pip setuptools wheel

# Cockpit + Ansible (if not already)
sudo zypper install -y cockpit ansible

# Python deps used by client + server
sudo python3 -m pip install requests fastapi uvicorn
```

> If you’ll run the MCP server on this host and use Docker for Ollama, also install Docker/Compose.

---

## 1) Deploy the MCP Server (FastAPI) + Ollama

### 1.1 Create folder and server code

```bash
sudo mkdir -p /opt/mcp-server
sudo tee /opt/mcp-server/server.py > /dev/null <<'PY'
#!/usr/bin/env python3
"""
FastAPI-based MCP Server exposing three Ollama models:
- Llama 3.1 8B   (port 11400)
- Mistral 7B     (port 11401)
- DeepSeek-R1 14B (port 11402)
"""

import json
import requests
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware
import uvicorn

# Manual CORS middleware (robust across Starlette versions)
class SimpleCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        if request.method == "OPTIONS":
            headers = {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
            }
            return Response(status_code=204, headers=headers)
        response = await call_next(request)
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        return response

def call_ollama(port: int, model: str, prompt: str) -> str:
    """Send a prompt to an Ollama container and return generated text."""
    url = f"http://localhost:{port}/api/generate"
    payload = {"model": model, "prompt": prompt}
    try:
        with requests.post(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            stream=True,
            timeout=600,
        ) as r:
            r.raise_for_status()
            text = ""
            for chunk in r.iter_content(chunk_size=None):
                if not chunk:
                    continue
                try:
                    line = chunk.decode("utf-8", errors="ignore")
                    if '"response"' in line:
                        part = line.split('"response":"')[1].split('"')[0]
                        text += part
                except Exception:
                    pass
            return text.strip() or "(no response)"
    except Exception as e:
        return f"⚠️ Error calling {model}: {e}"

TOOLS = {
    "llama3_8b":       {"port": 11400, "model": "llama3.1:8b",   "description": "Llama 3.1 8B"},
    "mistral_7b":      {"port": 11401, "model": "mistral:7b",    "description": "Mistral 7B"},
    "deepseek_r1_14b": {"port": 11402, "model": "deepseek-r1:14b","description": "DeepSeek-R1 14B"},
}

app = FastAPI(title="Ollama MCP Server", version="1.2")
app.add_middleware(SimpleCORSMiddleware)

@app.get("/tools")
def list_tools():
    return list(TOOLS.keys())

@app.post("/call_tool")
async def call_tool(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON body"})
    name = body.get("name")
    args = body.get("arguments", {})
    prompt = args.get("prompt", "")
    if not name or name not in TOOLS:
        return JSONResponse(status_code=404, content={"error": f"Tool '{name}' not found"})
    tool = TOOLS[name]
    result = call_ollama(tool["port"], tool["model"], prompt)
    return {"tool": name, "response": result}

if __name__ == "__main__":
    print("🚀 Starting FastAPI MCP Server for Ollama models on port 8787 …")
    uvicorn.run(app, host="0.0.0.0", port=8787)
PY
```

### 1.2 (Optional) Run Ollama models as containers

Create `/opt/ollama-compose/docker-compose.yml`:

```yaml
services:
  ollama-llama3-8b:
    image: ollama/ollama:latest
    container_name: ollama-llama3-8b
    ports: ["11400:11434"]
    volumes: ["ollama_llama3_8b:/root/.ollama"]
    restart: unless-stopped
    entrypoint: ["/bin/sh","-lc","ollama serve & sleep 2 && ollama pull `echo llama3.1:8b` && tail -f /dev/null"]

  ollama-mistral-7b:
    image: ollama/ollama:latest
    container_name: ollama-mistral-7b
    ports: ["11401:11434"]
    volumes: ["ollama_mistral_7b:/root/.ollama"]
    restart: unless-stopped
    entrypoint: ["/bin/sh","-lc","ollama serve & sleep 2 && ollama pull `echo mistral:7b` && tail -f /dev/null"]

  ollama-deepseek-r1-14b:
    image: ollama/ollama:latest
    container_name: ollama-deepseek-r1-14b
    ports: ["11402:11434"]
    volumes: ["ollama_deepseek_r1_14b:/root/.ollama"]
    restart: unless-stopped
    entrypoint: ["/bin/sh","-lc","ollama serve & sleep 2 && ollama pull `echo deepseek-r1:14b` && tail -f /dev/null"]

volumes:
  ollama_llama3_8b:
  ollama_mistral_7b:
  ollama_deepseek_r1_14b:
```

Bring it up:

```bash
cd /opt/ollama-compose
sudo docker compose up -d
sudo docker ps
```

### 1.3 Systemd unit for the MCP server

```bash
sudo tee /etc/systemd/system/mcp-server.service > /dev/null <<'UNIT'
[Unit]
Description=FastAPI MCP Server for Ollama Models
After=network.target docker.service

[Service]
WorkingDirectory=/opt/mcp-server
ExecStart=/usr/bin/python3 /opt/mcp-server/server.py
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now mcp-server
sudo systemctl status mcp-server
```

### 1.4 Sanity checks

```bash
curl -v http://<MCP_SERVER_IP>:8787/tools
# → ["llama3_8b","mistral_7b","deepseek_r1_14b"]
```

---

## 2) Cockpit “Ansible Playbook” extension + MCP client

Folder layout:

```
/usr/share/cockpit/ansible-playbook/
├── index.html
├── index.js
├── manifest.json
├── bin/
│   └── deploy-mcpclient
└── ansible/   (your other playbooks live here)
```

### 2.1 manifest.json

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

### 2.2 index.html (only the MCP section shown here—keep your Tomcat/Postgres/MariaDB as-is)

```html
<!-- MCP client options -->
<fieldset id="mcpclient-options" class="hidden" style="display:none;">
  <legend>MCP Client Settings</legend>

  <label>MCP Server URL
    <input id="mcp_server" type="text" value="http://<MCP_SERVER_IP>:8787" style="width: 300px;" />
  </label>

  <label>Tool name
    <select id="mcp_tool" style="width: 200px;">
      <option value="">-- Select a model --</option>
    </select>
    <button id="refresh_tools" style="margin-left:10px;">↻ Refresh</button>
  </label>

  <label>Prompt
    <textarea id="mcp_prompt" rows="4" cols="60" placeholder="Ask your question here..."></textarea>
  </label>
</fieldset>
```

### 2.3 index.js (full working file)

```js
(function () {
  'use strict';
  function $(id) { return document.getElementById(id); }

  function appendOutput(text) {
    const out = $('output');
    out.textContent += text;
    out.scrollTop = out.scrollHeight;
  }
  function clearOutput() { $('output').textContent = ''; }
  function disableForm(disabled) { $('deploy').disabled = disabled; $('clear').disabled = disabled; }

  function setDeployLabel(sel) {
    const map = { tomcat:'Deploy Apache Tomcat 11', postgresql:'Deploy PostgreSQL 17',
                  mariadb:'Deploy MariaDB 11', mcpclient:'Invoke MCP Client' };
    $('deploy').textContent = map[sel] || 'Deploy';
  }

  function showOnly(selected) {
    const panels = ['tomcat-options','postgres-options','mariadb-options','mcpclient-options'];
    panels.forEach(id => { const el = $(id); if (el) el.style.display = (id.startsWith(selected)) ? 'block' : 'none'; });
    setDeployLabel(selected);
    if (selected === 'mcpclient') { loadTools(); }
  }

  // Load tool list using host-side wrapper (CSP-safe)
  async function loadTools() {
    const server = $('mcp_server').value || 'http://localhost:8787';
    const select = $('mcp_tool');
    select.innerHTML = '<option>-- Loading models... --</option>';
    try {
      const args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient','--list-tools',server];
      const proc = cockpit.spawn(args, {err:'out',superuser:true});
      let buffer = '';
      proc.stream(d => buffer += d);
      proc.done(() => {
        try {
          const result = JSON.parse(buffer.trim());
          select.innerHTML = '';
          if (Array.isArray(result) && result.length) {
            result.forEach(t => { const o = document.createElement('option'); o.value = t; o.textContent = t; select.appendChild(o); });
            appendOutput(`✅ Loaded ${result.length} models from ${server}\n`);
          } else if (result.error) {
            select.innerHTML = '<option>⚠️ Error loading models</option>'; appendOutput('⚠️ '+result.error+'\n');
          } else { select.innerHTML = '<option>⚠️ Invalid response</option>'; }
        } catch (e) { select.innerHTML = '<option>⚠️ Parse error</option>'; appendOutput('⚠️ '+e+'\n'); }
      });
      proc.fail(err => { select.innerHTML = '<option>⚠️ Failed to load</option>'; appendOutput('⚠️ spawn error '+JSON.stringify(err)+'\n'); });
    } catch (e) { select.innerHTML = '<option>⚠️ Spawn failed</option>'; appendOutput('⚠️ '+e+'\n'); }
  }

  document.addEventListener('DOMContentLoaded', function(){
    const select = $('playbook');
    showOnly(select.value);
    select.addEventListener('change', () => showOnly(select.value));
    $('clear').addEventListener('click', clearOutput);
    const refresh = $('refresh_tools'); if (refresh) refresh.addEventListener('click', loadTools);

    $('deploy').addEventListener('click', function () {
      clearOutput(); disableForm(true);
      const choice = select.value; let args = [];

      if (choice === 'tomcat') {
        const http = $('http_port').value || '8080';
        const shut = $('shutdown_port').value || '8005';
        const ajp  = $('ajp_port').value || '8009';
        const user = $('username').value || 'admin';
        const pass = $('password').value || 'changeme';
        args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-tomcat','--http-port',http,'--shutdown-port',shut,'--ajp-port',ajp,'--username',user,'--password',pass];
      } else if (choice === 'postgresql') {
        const user = $('pg_username').value || 'dbadmin';
        const pass = $('pg_password').value || 'secret';
        args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-postgres','--username',user,'--password',pass];
      } else if (choice === 'mariadb') {
        const user = $('mdb_username').value || 'dbadmin';
        const pass = $('mdb_password').value || 'secret';
        const db   = $('mdb_dbname').value || 'appdb';
        args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-mariadb','--username',user,'--password',pass,'--dbname',db];
      } else if (choice === 'mcpclient') {
        const server = $('mcp_server').value || 'http://localhost:8787';
        const tool   = $('mcp_tool').value || 'llama3_8b';
        const prompt = $('mcp_prompt').value.trim();
        if (!tool)   { appendOutput('⚠️ Please select a model first.\n'); disableForm(false); return; }
        if (!prompt) { appendOutput('⚠️ Please enter a prompt.\n'); disableForm(false); return; }
        const payload = JSON.stringify({ prompt });
        args = ['/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient','--server',server,'--tool',tool,'--payload',payload];
        appendOutput(`Running model '${tool}' with prompt: "${prompt}"\n\n`);
      }

      appendOutput('Running: '+args.join(' ')+'\n\n');

      try {
        const proc = cockpit.spawn(args, {err:'out', superuser:true, directory:'/usr/share/cockpit/ansible-playbook/ansible'});
        proc.stream(d => appendOutput(String(d)));
        proc.done(() => { appendOutput('\n== Success ==\n'); disableForm(false); });
        proc.fail(err => { appendOutput('\n== Failed ==\n'+JSON.stringify(err)+'\n'); disableForm(false); });
      } catch (e) { appendOutput('\nException: '+e+'\n'); disableForm(false); }
    });
  });
})();
```

### 2.4 MCP client wrapper (host-side)

`/usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient`

```bash
#!/bin/bash
# Cockpit wrapper to call MCP server REST API or list available tools

SERVER_URL="http://localhost:8787"
TOOL="list_tools"
PAYLOAD="{}"

# --list-tools mode (prints pure JSON)
if [[ "$1" == "--list-tools" ]]; then
    SERVER_URL="${2:-http://localhost:8787}"
    python3 - <<PYCODE
import json, requests
server = "$SERVER_URL"
try:
    r = requests.get(f"{server}/tools", timeout=10)
    r.raise_for_status()
    tools = r.json()
    print(json.dumps(tools if isinstance(tools, list) else {"error":"Unexpected response"}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYCODE
    exit 0
fi

# Normal invocation mode
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
    r = requests.post(f"{server}/call_tool",
                      json={"name": tool, "arguments": payload},
                      timeout=600)
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

```bash
sudo chmod +x /usr/share/cockpit/ansible-playbook/bin/deploy-mcpclient
```

> This script also powers the **Tool name** dropdown: `index.js` calls it with `--list-tools` and parses the JSON it prints.

---

## 3) Restart Cockpit & test

```bash
sudo systemctl restart cockpit
```

Open Cockpit → **Tools → Ansible Playbook** → choose **Invoke MCP Client**.

1. Set **MCP Server URL** (e.g., `http://<MCP_SERVER_IP>:8787`).
2. Click **↻ Refresh** → “Tool name” populates with `llama3_8b`, `mistral_7b`, `deepseek_r1_14b`.
3. Type a **Prompt** (e.g., *“What is SUSE Linux?”*).
4. Click **Invoke MCP Client** → watch the formatted response.

---

## 4) What you now have

* A **FastAPI MCP server** proxying three Ollama models on `:8787`
* A **Cockpit Ansible extension** with:

  * model dropdown (fetched via host-side wrapper)
  * simple **Prompt** field
  * streaming and nicely **wrapped** response text

 From a command prompt:
 
 <img width="942" height="675" alt="image" src="https://github.com/user-attachments/assets/298e3816-3c05-4c90-8148-373d38025234" />

From Cockpit Ansible:

<img width="1725" height="887" alt="image" src="https://github.com/user-attachments/assets/d03612e7-6e59-4f9e-8225-631394c69704" />



