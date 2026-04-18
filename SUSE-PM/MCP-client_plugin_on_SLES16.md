
 **SLES16 MCP client in Cockpit** (Ansible extension) and a **FastAPI MCP server** that fronts three Ollama models - **Version-1.0**.

---

# Step-by-Step: MCP Client (Cockpit/Ansible) + MCP Server (FastAPI + Ollama)

## 0) Prereqs (SLES 16)

```bash
# Base
sudo zypper install -y python313 python313-pip git curl unzip docker-compose
sudo python3 -m pip install --upgrade pip setuptools wheel

# Cockpit + Ansible (if not already)
sudo zypper install -y cockpit ansible

# Python deps used by client + server
sudo python3 -m pip install requests fastapi uvicorn
```

> If you’ll run the MCP server on this host and use Docker for Ollama, also install Docker/Compose.

---

## 1) Deploy the MCP Server (FastAPI) + Ollama

> [!NOTE]
> This test deployment used SLES 16 for ARM64 systems and validated on a local physical aarch64 servers as well as AWS aarch64 images.
> MCP-server is this case is an arm64 based server with 3 Ollama models Docker containers running. (No GPUs involved)
>

### 1.1 Create folder and server code

````
sudo mkdir -p /opt/mcp-server
````

Create a server.py config:

<details><summary>Expand for detailed values</summary>
  
```bash
  
```python
#!/usr/bin/env python3
"""
FastAPI-based MCP Server for SLES16

Features:
- Ollama-backed LLM tools
- Analysis of uploaded logs from remote/client hosts
- Optional local log collection on the MCP server host
- Rule-based log analysis
- Compatibility with existing MCP client wrapper:
    GET  /tools
    POST /call_tool
"""

import json
import subprocess
from typing import Any, Dict, List

import requests
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware

MCP_PORT = 8787

LLM_TOOLS: Dict[str, Dict[str, Any]] = {
    "llama3_8b": {"port": 11400, "model": "llama3.1:8b", "type": "llm"},
    "mistral_7b": {"port": 11401, "model": "mistral:7b", "type": "llm"},
    "deepseek_r1_14b": {"port": 11402, "model": "deepseek-r1:14b", "type": "llm"},
}

NATIVE_TOOLS: Dict[str, Dict[str, Any]] = {
    "collect_logs": {"type": "native"},
    "analyze_logs": {"type": "native"},
    "analyze_uploaded_logs": {"type": "native"},
    "verify_service": {"type": "native"},
}

TOOLS: Dict[str, Dict[str, Any]] = {}
TOOLS.update(LLM_TOOLS)
TOOLS.update(NATIVE_TOOLS)

MAX_STDOUT = 20000
MAX_STDERR = 5000


class SimpleCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
        }

        if request.method == "OPTIONS":
            return Response(status_code=204, headers=headers)

        response = await call_next(request)
        response.headers.update(headers)
        return response


def truncate_text(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[-limit:]


def run_cmd(cmd: List[str]) -> Dict[str, Any]:
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
        )
        return {
            "cmd": " ".join(cmd),
            "rc": proc.returncode,
            "stdout": truncate_text(proc.stdout, MAX_STDOUT),
            "stderr": truncate_text(proc.stderr, MAX_STDERR),
        }
    except Exception as exc:
        return {
            "cmd": " ".join(cmd),
            "rc": 999,
            "stdout": "",
            "stderr": f"Exception: {exc}",
        }


def call_ollama(port: int, model: str, prompt: str) -> str:
    url = f"http://localhost:{port}/api/generate"
    payload = {"model": model, "prompt": prompt}

    try:
        with requests.post(url, json=payload, stream=True, timeout=600) as resp:
            resp.raise_for_status()
            chunks: List[str] = []

            for line in resp.iter_lines():
                if not line:
                    continue
                try:
                    obj = json.loads(line.decode("utf-8", "ignore"))
                    if "response" in obj:
                        chunks.append(obj["response"])
                except Exception:
                    continue

            text = "".join(chunks).strip()
            return text or "(no response)"
    except Exception as exc:
        return f"Error calling {model}: {exc}"


def collect_logs_data(service: str = "mcp-server", lines: int = 200) -> Dict[str, Any]:
    return {
        "source": "mcp-server-host",
        "service": service,
        "lines": lines,
        "service_logs": run_cmd(
            ["journalctl", "-u", service, "-n", str(lines), "--no-pager"]
        ),
        "failed_units": run_cmd(
            ["systemctl", "--failed", "--no-pager"]
        ),
        "warnings": run_cmd(
            ["journalctl", "-p", "warning..alert", "-n", str(lines), "--no-pager"]
        ),
        "zypper_history": run_cmd(
            ["tail", "-n", "50", "/var/log/zypp/history"]
        ),
    }


def analyze_sles_logs(log_bundle: Dict[str, Any]) -> Dict[str, Any]:
    text = json.dumps(log_bundle, ensure_ascii=False).lower()

    if "cannot import name 'sentinel'" in text:
        return {
            "issue": "python dependency mismatch",
            "fix": "upgrade typing_extensions on the client",
            "preferred_tool": "install_pip_package",
            "confidence": "high",
            "package_candidates": ["typing_extensions"],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "no space left on device" in text:
        return {
            "issue": "disk full",
            "fix": "clean logs or expand disk on the client",
            "preferred_tool": "manual",
            "confidence": "high",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "failed to start" in text:
        return {
            "issue": "service start failure",
            "fix": "inspect service logs and verify dependencies",
            "preferred_tool": "restart_service",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "dependency failed" in text:
        return {
            "issue": "systemd dependency problem",
            "fix": "verify dependent units and restart the client service if appropriate",
            "preferred_tool": "restart_service",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "cloud-init" in text or "cloud-final" in text:
        return {
            "issue": "cloud-init related issue detected",
            "fix": "inspect cloud-final logs on the client",
            "preferred_tool": "manual",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": ["cloud-final.service"],
            "needs_human_approval": True,
        }

    return {
        "issue": "unknown",
        "fix": "manual investigation required",
        "preferred_tool": "manual",
        "confidence": "low",
        "package_candidates": [],
        "service_candidates": [],
        "needs_human_approval": True,
    }


def normalize_arguments(arguments: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(arguments, dict):
        return {}

    if "prompt" in arguments:
        prompt_value = arguments.get("prompt")

        if isinstance(prompt_value, dict):
            return prompt_value

        if isinstance(prompt_value, str):
            prompt_text = prompt_value.strip()
            try:
                parsed = json.loads(prompt_text)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass

    return arguments


app = FastAPI(title="SLES16 MCP Server", version="5.0")
app.add_middleware(SimpleCORSMiddleware)


@app.get("/")
def root() -> Dict[str, Any]:
    return {
        "name": "SLES16 MCP Server",
        "version": "5.0",
        "tools_count": len(TOOLS),
    }


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/tools")
def list_tools() -> List[str]:
    return list(TOOLS.keys())


@app.post("/collect_logs")
async def collect_logs(request: Request) -> Dict[str, Any]:
    body = await request.json()
    service = body.get("service", "mcp-server")
    lines = int(body.get("lines", 200))
    return collect_logs_data(service=service, lines=lines)


@app.post("/analyze_logs")
async def analyze_logs(request: Request) -> Dict[str, Any]:
    body = await request.json()
    service = body.get("service", "mcp-server")
    lines = int(body.get("lines", 200))
    include_logs = bool(body.get("include_logs", True))

    logs = collect_logs_data(service=service, lines=lines)
    analysis = analyze_sles_logs(logs)

    result: Dict[str, Any] = {
        "analysis": analysis,
        "target": {
            "source": "mcp-server-host",
            "service": service,
            "lines": lines,
        },
    }
    if include_logs:
        result["logs"] = logs
    return result


@app.post("/analyze_uploaded_logs")
async def analyze_uploaded_logs(request: Request) -> Dict[str, Any]:
    body = await request.json()
    log_bundle = body.get("logs", {})
    analysis = analyze_sles_logs(log_bundle)

    return {
        "analysis": analysis,
        "target": {
            "source": "uploaded-client-logs",
            "service": log_bundle.get("service", "unknown"),
            "lines": log_bundle.get("lines", "unknown"),
            "hostname": log_bundle.get("hostname", "unknown"),
        },
        "logs": log_bundle,
    }


@app.post("/verify_service")
async def verify_service(request: Request) -> Dict[str, Any]:
    body = await request.json()
    svc = body.get("service", "mcp-server")

    return {
        "service_status": run_cmd(["systemctl", "status", svc, "--no-pager"]),
        "failed_units": run_cmd(["systemctl", "--failed", "--no-pager"]),
        "mcp_tools": list(TOOLS.keys()),
        "health": {"status": "ok"},
    }


@app.post("/call_tool")
async def call_tool(request: Request):
    body = await request.json()
    name = body.get("name")
    arguments = normalize_arguments(body.get("arguments", {}))

    if name not in TOOLS:
        return JSONResponse(
            status_code=404,
            content={"error": f"Tool {name} not found"},
        )

    tool = TOOLS[name]

    if tool["type"] == "llm":
        prompt = arguments.get("prompt", "")
        result = call_ollama(tool["port"], tool["model"], prompt)
        return {
            "tool": name,
            "type": "llm",
            "response": result,
        }

    if name == "collect_logs":
        service = arguments.get("service", "mcp-server")
        lines = int(arguments.get("lines", 200))
        return {
            "tool": name,
            "type": "native",
            "response": collect_logs_data(service=service, lines=lines),
        }

    if name == "analyze_logs":
        service = arguments.get("service", "mcp-server")
        lines = int(arguments.get("lines", 200))
        logs = collect_logs_data(service=service, lines=lines)
        return {
            "tool": name,
            "type": "native",
            "response": {
                "analysis": analyze_sles_logs(logs),
                "target": {
                    "source": "mcp-server-host",
                    "service": service,
                    "lines": lines,
                },
                "logs": logs,
            },
        }

    if name == "analyze_uploaded_logs":
        log_bundle = arguments.get("logs", {})
        return {
            "tool": name,
            "type": "native",
            "response": {
                "analysis": analyze_sles_logs(log_bundle),
                "target": {
                    "source": "uploaded-client-logs",
                    "service": log_bundle.get("service", "unknown"),
                    "lines": log_bundle.get("lines", "unknown"),
                    "hostname": log_bundle.get("hostname", "unknown"),
                },
                "logs": log_bundle,
            },
        }

    if name == "verify_service":
        svc = arguments.get("service", "mcp-server")
        return {
            "tool": name,
            "type": "native",
            "response": {
                "service_status": run_cmd(["systemctl", "status", svc, "--no-pager"]),
                "failed_units": run_cmd(["systemctl", "--failed", "--no-pager"]),
                "mcp_tools": list(TOOLS.keys()),
                "health": {"status": "ok"},
            },
        }

    return JSONResponse(
        status_code=500,
        content={"error": f"Unhandled tool {name}"},
    )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=MCP_PORT)
```
</details>
---


````
sudo chmod 755 /opt/mcp-server/server.py
````

---

### 1.2 (Optional) Run Ollama models as containers

Create `/opt/ollama-compose/docker-compose.yml`:

<details><summary>Expand for detailed values</summary>

```bash

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
</details>
---

Bring it up:

```bash
cd /opt/ollama-compose
sudo podman compose up -d
sudo podman ps
```

<img width="1627" height="421" alt="image" src="https://github.com/user-attachments/assets/4099b3f0-65a2-4d9f-87ef-96b8d4a957cd" />

<img width="1242" height="113" alt="image" src="https://github.com/user-attachments/assets/fc70e959-d3a0-4fff-a461-8204e13bc99f" />


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
````

````
sudo systemctl daemon-reload
````

````
sudo systemctl enable --now mcp-server
````
````
sudo systemctl status mcp-server
````

<img width="1041" height="335" alt="image" src="https://github.com/user-attachments/assets/52d51338-4ce5-4d49-86c2-49b25248f1d0" />


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

<details><summary>Expand for detailed values</summary>

```bash

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
</details>
---

### 2.4 MCP client wrapper (host-side)

Create `deploy-mcpclient`:

````
mkdir /usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
````

<details><summary>Expand for detailed values</summary>
    

```bash
#!/bin/bash

SERVER_URL="http://localhost:8787"
TOOL="list_tools"
PAYLOAD="{}"

if [[ "$1" == "--list-tools" ]]; then
    SERVER_URL="${2:-http://localhost:8787}"
    MCP_SERVER_URL="$SERVER_URL" python3 - <<'PYCODE'
import json
import os
import requests

server = os.environ["MCP_SERVER_URL"]

try:
    r = requests.get(f"{server}/tools", timeout=10)
    r.raise_for_status()
    tools = r.json()
    if isinstance(tools, list):
        print(json.dumps(tools))
    else:
        print(json.dumps({"error": "Unexpected response"}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYCODE
    exit 0
fi

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

MCP_SERVER_URL="$SERVER_URL" MCP_TOOL="$TOOL" MCP_PAYLOAD="$PAYLOAD" python3 - <<'PYCODE'
import json
import os
import requests
import socket
import subprocess
import sys

server = os.environ["MCP_SERVER_URL"]
tool = os.environ["MCP_TOOL"]
raw_payload = os.environ.get("MCP_PAYLOAD", "{}")

ALLOWED_ZYPPER_PACKAGES = {
    "curl": "curl",
    "git": "git",
    "jq": "jq",
    "python313-pip": "python313-pip",
    "python313-requests": "python313-requests",
    "python313-typing_extensions": "python313-typing_extensions",
}

ALLOWED_PIP_PACKAGES = {
    "typing_extensions": "typing_extensions",
    "requests": "requests",
    "fastapi": "fastapi",
    "uvicorn": "uvicorn",
    "starlette": "starlette",
}

ALLOWED_SERVICES = {
    "cockpit.socket",
    "sshd.service",
    "wicked.service",
    "NetworkManager.service",
    "podman.service",
    "cloud-final.service",
    "mcp-server",
}

def run_cmd(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, check=False)
        return {
            "cmd": " ".join(cmd),
            "rc": p.returncode,
            "stdout": p.stdout[-20000:],
            "stderr": p.stderr[-5000:],
        }
    except Exception as e:
        return {
            "cmd": " ".join(cmd),
            "rc": 999,
            "stdout": "",
            "stderr": f"Exception: {e}",
        }

def collect_local_logs(service="mcp-server", lines=200):
    return {
        "hostname": socket.gethostname(),
        "service": service,
        "lines": lines,
        "service_logs": run_cmd(["journalctl", "-u", service, "-n", str(lines), "--no-pager"]),
        "failed_units": run_cmd(["systemctl", "--failed", "--no-pager"]),
        "warnings": run_cmd(["journalctl", "-p", "warning..alert", "-n", str(lines), "--no-pager"]),
        "zypper_history": run_cmd(["tail", "-n", "50", "/var/log/zypp/history"]),
    }

def unwrap_payload(payload):
    if isinstance(payload, dict) and "prompt" in payload:
        p = payload["prompt"]
        if isinstance(p, dict):
            return p
        if isinstance(p, str):
            pt = p.strip()
            if pt.startswith("{") and pt.endswith("}"):
                try:
                    parsed = json.loads(pt)
                    if isinstance(parsed, dict):
                        return parsed
                except Exception:
                    pass
    return payload

def print_block(title, text, indent=0):
    pad = " " * indent
    print(f"{pad}{title}:")
    if text is None or text == "":
        print(f"{pad}  (empty)")
        return
    for line in str(text).splitlines():
        print(f"{pad}  {line}")

def print_obj(obj, indent=0):
    pad = " " * indent
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, (dict, list)):
                print(f"{pad}{k}:")
                print_obj(v, indent + 2)
            else:
                print_block(k, v, indent)
    elif isinstance(obj, list):
        if not obj:
            print(f"{pad}[]")
        for item in obj:
            if isinstance(item, (dict, list)):
                print(f"{pad}-")
                print_obj(item, indent + 2)
            else:
                print(f"{pad}- {item}")
    else:
        print(f"{pad}{obj}")

def zypper_install_local(pkg_alias):
    if pkg_alias not in ALLOWED_ZYPPER_PACKAGES:
        return {"error": f"{pkg_alias} not allowed on client", "allowed_packages": sorted(ALLOWED_ZYPPER_PACKAGES.keys())}
    resolved_pkg = ALLOWED_ZYPPER_PACKAGES[pkg_alias]
    return {
        "requested_package": pkg_alias,
        "resolved_package": resolved_pkg,
        "target": "client",
        "result": run_cmd(["zypper", "--non-interactive", "--auto-agree-with-licenses", "install", "-y", resolved_pkg]),
    }

def pip_install_local(pkg_alias):
    if pkg_alias not in ALLOWED_PIP_PACKAGES:
        return {"error": f"{pkg_alias} not allowed on client", "allowed_pip_packages": sorted(ALLOWED_PIP_PACKAGES.keys())}
    resolved_pkg = ALLOWED_PIP_PACKAGES[pkg_alias]
    return {
        "requested_package": pkg_alias,
        "resolved_package": resolved_pkg,
        "target": "client",
        "result": run_cmd(["/usr/bin/python3", "-m", "pip", "install", "--upgrade", resolved_pkg]),
    }

def restart_service_local(service_name):
    if service_name not in ALLOWED_SERVICES:
        return {"error": f"{service_name} not allowed on client", "allowed_services": sorted(ALLOWED_SERVICES)}
    return {
        "service": service_name,
        "target": "client",
        "result": run_cmd(["systemctl", "restart", service_name]),
    }

try:
    payload = json.loads(raw_payload)
except Exception:
    payload = {}

payload = unwrap_payload(payload)

if tool == "analyze_uploaded_logs":
    service = payload.get("service", "mcp-server")
    lines = int(payload.get("lines", 200))
    outgoing = {
        "name": "analyze_uploaded_logs",
        "arguments": {"logs": collect_local_logs(service=service, lines=lines)}
    }
    print(f"→ Collecting logs locally on client for service: {service}")
    print(f"→ Connecting to {server}/call_tool ...")
    r = requests.post(f"{server}/call_tool", json=outgoing, timeout=600)
    print(f"← Status: {r.status_code}")
    if r.ok:
        print("")
        print("✅ MCP Response")
        print("")
        print_obj(r.json())
    else:
        print("❌ Error")
        print(r.text)
        sys.exit(1)
    sys.exit(0)

if tool == "install_package":
    approved = bool(payload.get("approved", False))
    package = str(payload.get("package", "")).strip()
    if not approved:
        print("❌ Error")
        print("approval required")
        sys.exit(1)
    result = zypper_install_local(package)
    print("")
    print("✅ MCP Client Local Action")
    print("")
    print_obj({"tool": tool, "type": "client-native", "response": result})
    sys.exit(0)

if tool == "install_pip_package":
    approved = bool(payload.get("approved", False))
    package = str(payload.get("package", "")).strip()
    if not approved:
        print("❌ Error")
        print("approval required")
        sys.exit(1)
    result = pip_install_local(package)
    print("")
    print("✅ MCP Client Local Action")
    print("")
    print_obj({"tool": tool, "type": "client-native", "response": result})
    sys.exit(0)

if tool == "restart_service":
    approved = bool(payload.get("approved", False))
    service = str(payload.get("service", "")).strip()
    if not approved:
        print("❌ Error")
        print("approval required")
        sys.exit(1)
    result = restart_service_local(service)
    print("")
    print("✅ MCP Client Local Action")
    print("")
    print_obj({"tool": tool, "type": "client-native", "response": result})
    sys.exit(0)

outgoing = {"name": tool, "arguments": payload}
print(f"→ Connecting to {server}/call_tool ...")
r = requests.post(f"{server}/call_tool", json=outgoing, timeout=600)
print(f"← Status: {r.status_code}")
if r.ok:
    print("")
    print("✅ MCP Response")
    print("")
    print_obj(r.json())
else:
    print("❌ Error")
    print(r.text)
    sys.exit(1)
PYCODE
```
</details>

```bash
sudo chmod 755 /usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
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
  * streaming and **wrapped** response text

 From a command prompt:
 
 <img width="942" height="675" alt="image" src="https://github.com/user-attachments/assets/298e3816-3c05-4c90-8148-373d38025234" />

From Cockpit Ansible:

<img width="1725" height="887" alt="image" src="https://github.com/user-attachments/assets/d03612e7-6e59-4f9e-8225-631394c69704" />



