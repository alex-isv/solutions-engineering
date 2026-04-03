# MCP Server and Cockpit MCP Client Plugin on SLES 16

This document provides a complete, copy-paste-ready guide for building an MCP server on SLES 16 with all validated fixes applied, and for using the Cockpit MCP client plugin to interact with it.

It covers:

- Podman-based Ollama containers on SLES 16
- Python virtual environment setup to avoid dependency conflicts
- A complete `server.py` with both LLM tools and native SLES analysis tools
- A systemd unit for the MCP server
- A readable `deploy-mcpclient` wrapper for Cockpit output
- Installation and use of the Cockpit MCP client RPM
- Practical usage examples for `analyze_logs`, `collect_logs`, `verify_service`, `install_package`, and `restart_service`

---

## 1. Architecture

```text
Cockpit client host
  -> ansible-playbook-extension RPM
  -> deploy-mcpclient wrapper
  -> MCP Server URL

MCP server host
  -> FastAPI MCP server on :8787
  -> Native SLES tools
  -> Ollama model backends
     * llama3.1:8b       on :11400
     * mistral:7b        on :11401
     * deepseek-r1:14b   on :11402
```

---

## 2. Prerequisites on the MCP Server Host

Install the required packages:

```bash
sudo zypper refresh
sudo zypper install -y   python313 python313-pip python313-virtualenv   podman curl git jq ca-certificates
```

Create the server directories:

```bash
sudo mkdir -p /opt/mcp-server
sudo mkdir -p /opt/ollama
```

---

## 3. Create a Python Virtual Environment

Using a virtual environment avoids Python package conflicts, especially around `typing_extensions`.

```bash
sudo python3.13 -m venv /opt/mcp-server/venv
sudo /opt/mcp-server/venv/bin/pip install --upgrade pip setuptools wheel
sudo /opt/mcp-server/venv/bin/pip install   fastapi uvicorn requests starlette typing_extensions
```

Validate:

```bash
sudo /opt/mcp-server/venv/bin/python -c "from fastapi import FastAPI; from typing_extensions import Sentinel; print('ok')"
```

---

## 4. Start Ollama with Podman

Create persistent Podman volumes:

```bash
podman volume create ollama_llama3_8b
podman volume create ollama_mistral_7b
podman volume create ollama_deepseek_r1_14b
```

Start the three model containers:

```bash
podman run -d   --name ollama-llama3-8b   -p 11400:11434   -v ollama_llama3_8b:/root/.ollama   docker.io/ollama/ollama:latest   /bin/sh -lc "ollama serve & sleep 5 && ollama pull llama3.1:8b && tail -f /dev/null"

podman run -d   --name ollama-mistral-7b   -p 11401:11434   -v ollama_mistral_7b:/root/.ollama   docker.io/ollama/ollama:latest   /bin/sh -lc "ollama serve & sleep 5 && ollama pull mistral:7b && tail -f /dev/null"

podman run -d   --name ollama-deepseek-r1-14b   -p 11402:11434   -v ollama_deepseek_r1_14b:/root/.ollama   docker.io/ollama/ollama:latest   /bin/sh -lc "ollama serve & sleep 5 && ollama pull deepseek-r1:14b && tail -f /dev/null"
```

Verify the containers:

```bash
podman ps
curl http://localhost:11400/api/tags
curl http://localhost:11401/api/tags
curl http://localhost:11402/api/tags
```

---

## 5. Install the MCP Server

Create `/opt/mcp-server/server.py`:

<details><summary>Expand for detailed values</summary>
  
```bash
---
sudo tee /opt/mcp-server/server.py > /dev/null <<'PY'
#!/usr/bin/env python3
"""
FastAPI-based MCP Server for SLES16

Features:
- Ollama-backed LLM tools
- Native SLES log collection
- Rule-based log analysis
- Safe remediation tools
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
    "install_package": {"type": "native"},
    "restart_service": {"type": "native"},
    "verify_service": {"type": "native"},
}

TOOLS: Dict[str, Dict[str, Any]] = {}
TOOLS.update(LLM_TOOLS)
TOOLS.update(NATIVE_TOOLS)

ALLOWED_PACKAGES = {
    "typing_extensions",
    "python313-pip",
    "curl",
    "jq",
    "git",
    "python313-requests",
}

ALLOWED_SERVICES = {
    "mcp-server",
    "cockpit.socket",
}

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
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
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
        "service": service,
        "lines": lines,
        "service_logs": run_cmd(["journalctl", "-u", service, "-n", str(lines), "--no-pager"]),
        "failed_units": run_cmd(["systemctl", "--failed", "--no-pager"]),
        "warnings": run_cmd(["journalctl", "-p", "warning..alert", "-n", str(lines), "--no-pager"]),
        "zypper_history": run_cmd(["tail", "-n", "50", "/var/log/zypp/history"]),
    }


def analyze_sles_logs(log_bundle: Dict[str, Any]) -> Dict[str, Any]:
    text = json.dumps(log_bundle, ensure_ascii=False).lower()

    if "cannot import name 'sentinel'" in text:
        return {
            "issue": "python dependency mismatch",
            "fix": "upgrade typing_extensions",
            "confidence": "high",
            "package_candidates": ["typing_extensions"],
            "service_candidates": ["mcp-server"],
            "needs_human_approval": True,
        }

    if "no space left on device" in text:
        return {
            "issue": "disk full",
            "fix": "clean logs or expand disk",
            "confidence": "high",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "failed to start" in text:
        return {
            "issue": "service start failure",
            "fix": "inspect service logs and verify dependencies",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": ["mcp-server", "cockpit.socket"],
            "needs_human_approval": True,
        }

    if "dependency failed" in text:
        return {
            "issue": "systemd dependency problem",
            "fix": "verify dependent units and restart approved services",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": ["mcp-server", "cockpit.socket"],
            "needs_human_approval": True,
        }

    if "connection refused" in text and "11400" in text:
        return {
            "issue": "ollama llama3 backend unavailable",
            "fix": "check ollama-llama3-8b container",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "connection refused" in text and "11401" in text:
        return {
            "issue": "ollama mistral backend unavailable",
            "fix": "check ollama-mistral-7b container",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    if "connection refused" in text and "11402" in text:
        return {
            "issue": "ollama deepseek backend unavailable",
            "fix": "check ollama-deepseek-r1-14b container",
            "confidence": "medium",
            "package_candidates": [],
            "service_candidates": [],
            "needs_human_approval": True,
        }

    return {
        "issue": "unknown",
        "fix": "manual investigation required",
        "confidence": "low",
        "package_candidates": [],
        "service_candidates": [],
        "needs_human_approval": True,
    }


app = FastAPI(title="SLES16 MCP Server", version="2.0")
app.add_middleware(SimpleCORSMiddleware)


@app.get("/")
def root() -> Dict[str, Any]:
    return {"name": "SLES16 MCP Server", "version": "2.0", "tools_count": len(TOOLS)}


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
    result: Dict[str, Any] = {"analysis": analysis}
    if include_logs:
        result["logs"] = logs
    return result


@app.post("/install_package")
async def install_package(request: Request):
    body = await request.json()
    pkg = body.get("package", "").strip()
    approved = bool(body.get("approved", False))
    if not approved:
        return JSONResponse(status_code=403, content={"error": "approval required"})
    if pkg not in ALLOWED_PACKAGES:
        return JSONResponse(status_code=403, content={"error": f"{pkg} not allowed"})
    return run_cmd(["zypper", "--non-interactive", "install", "-y", pkg])


@app.post("/restart_service")
async def restart_service(request: Request):
    body = await request.json()
    svc = body.get("service", "").strip()
    approved = bool(body.get("approved", False))
    if not approved:
        return JSONResponse(status_code=403, content={"error": "approval required"})
    if svc not in ALLOWED_SERVICES:
        return JSONResponse(status_code=403, content={"error": f"{svc} not allowed"})
    return run_cmd(["systemctl", "restart", svc])


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
    arguments = body.get("arguments", {})

    if name not in TOOLS:
        return JSONResponse(status_code=404, content={"error": f"Tool {name} not found"})

    tool = TOOLS[name]

    if tool["type"] == "llm":
        prompt = arguments.get("prompt", "")
        return {"tool": name, "type": "llm", "response": call_ollama(tool["port"], tool["model"], prompt)}

    if name == "collect_logs":
        service = arguments.get("service", "mcp-server")
        lines = int(arguments.get("lines", 200))
        return {"tool": name, "type": "native", "response": collect_logs_data(service=service, lines=lines)}

    if name == "analyze_logs":
        service = arguments.get("service", "mcp-server")
        lines = int(arguments.get("lines", 200))
        logs = collect_logs_data(service=service, lines=lines)
        return {"tool": name, "type": "native", "response": {"analysis": analyze_sles_logs(logs), "logs": logs}}

    if name == "install_package":
        pkg = str(arguments.get("package", "")).strip()
        approved = bool(arguments.get("approved", False))
        if not approved:
            return JSONResponse(status_code=403, content={"error": "approval required"})
        if pkg not in ALLOWED_PACKAGES:
            return JSONResponse(status_code=403, content={"error": f"{pkg} not allowed"})
        return {"tool": name, "type": "native", "response": run_cmd(["zypper", "--non-interactive", "install", "-y", pkg])}

    if name == "restart_service":
        svc = str(arguments.get("service", "")).strip()
        approved = bool(arguments.get("approved", False))
        if not approved:
            return JSONResponse(status_code=403, content={"error": "approval required"})
        if svc not in ALLOWED_SERVICES:
            return JSONResponse(status_code=403, content={"error": f"{svc} not allowed"})
        return {"tool": name, "type": "native", "response": run_cmd(["systemctl", "restart", svc])}

    if name == "verify_service":
        svc = arguments.get("service", "mcp-server")
        result = {
            "service_status": run_cmd(["systemctl", "status", svc, "--no-pager"]),
            "failed_units": run_cmd(["systemctl", "--failed", "--no-pager"]),
            "mcp_tools": list(TOOLS.keys()),
            "health": {"status": "ok"},
        }
        return {"tool": name, "type": "native", "response": result}

    return JSONResponse(status_code=500, content={"error": f"Unhandled tool {name}"})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=MCP_PORT)
PY
```
</details>
---

````
sudo chmod 755 /opt/mcp-server/server.py
````

---

## 6. Create the systemd Service

Create `/etc/systemd/system/mcp-server.service`:

```bash
sudo tee /etc/systemd/system/mcp-server.service > /dev/null <<'UNIT'
[Unit]
Description=FastAPI MCP Server for Ollama Models
After=network.target

[Service]
WorkingDirectory=/opt/mcp-server
ExecStart=/opt/mcp-server/venv/bin/python /opt/mcp-server/server.py
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now mcp-server
sudo systemctl status mcp-server
```

---

## 7. Sanity Checks on the MCP Server Host

```bash
curl http://localhost:8787/health
curl http://localhost:8787/tools
```

Expected tool list:

```json
[
  "llama3_8b",
  "mistral_7b",
  "deepseek_r1_14b",
  "collect_logs",
  "analyze_logs",
  "install_package",
  "restart_service",
  "verify_service"
]
```

---

## 8. Install the Cockpit MCP Client Plugin on the Client Host

Download the RPM:

```bash
curl -L -o /tmp/ansible-playbook-extension-1.0-2.noarch.rpm   https://github.com/alex-isv/solutions-engineering/raw/main/SUSE-PM/ansible-playbook-extension-1.0-2.noarch.rpm
```

Install it:

```bash
sudo zypper install --allow-unsigned-rpm -y /tmp/ansible-playbook-extension-1.0-2.noarch.rpm
sudo systemctl enable --now cockpit.socket
sudo systemctl restart cockpit.socket
```

Alternative installation:

```bash
sudo rpm -ivh --nosignature /tmp/ansible-playbook-extension-1.0-2.noarch.rpm
```

Verify the plugin files:

```bash
rpm -ql ansible-playbook-extension
```

---



## 10. Configure the MCP Client in Cockpit

Open Cockpit:

```text
https://<cockpit-client-host>:9090
```

Go to:

```text
Tools -> Ansible Playbook -> Invoke MCP Client
```

Set:

- **MCP Server URL**: `http://<mcp-server-ip>:8787`
- Click **Refresh** to populate the tools from `/tools`

---

## 11. How to Use the MCP Client Plugin from Cockpit

The current Cockpit UI uses a single prompt field.

- For **LLM tools**, enter plain text.
- For **native tools**, enter JSON in the prompt field.

### 11.1 LLM Tool Examples

Tool:

```text
mistral_7b
```

Prompt:

```text
Explain what journalctl does in SLES Linux.
```

Tool:

```text
deepseek_r1_14b
```

Prompt:

```text
Explain how to debug a failed systemd service.
```

### 11.2 `analyze_logs`

Tool:

```text
analyze_logs
```

Prompt:

```json
{"service":"mcp-server","lines":200}
```

### 11.3 `collect_logs`

Tool:

```text
collect_logs
```

Prompt:

```json
{"service":"mcp-server","lines":100}
```

### 11.4 `verify_service`

Tool:

```text
verify_service
```

Prompt:

```json
{"service":"mcp-server"}
```

### 11.5 `install_package`

Tool:

```text
install_package
```

Prompt:

```json
{"package":"typing_extensions","approved":true}
```

### 11.6 `restart_service`

Tool:

```text
restart_service
```

Prompt:

```json
{"service":"mcp-server","approved":true}
```

---

## 12. Recommended Test Flow from Cockpit

Step 1:

Tool:

```text
verify_service
```

Prompt:

```json
{"service":"mcp-server"}
```

Step 2:

Tool:

```text
analyze_logs
```

Prompt:

```json
{"service":"mcp-server","lines":200}
```

Step 3:

Tool:

```text
install_package
```

Prompt:

```json
{"package":"typing_extensions","approved":true}
```

Step 4:

Tool:

```text
restart_service
```

Prompt:

```json
{"service":"mcp-server","approved":true}
```

Step 5:

Tool:

```text
verify_service
```

Prompt:

```json
{"service":"mcp-server"}
```

---

## 13. CLI Examples Against the MCP Server

```bash
curl -X POST http://<mcp-server-ip>:8787/call_tool   -H "Content-Type: application/json"   -d '{"name":"analyze_logs","arguments":{"service":"mcp-server","lines":200}}'

curl -X POST http://<mcp-server-ip>:8787/call_tool   -H "Content-Type: application/json"   -d '{"name":"install_package","arguments":{"package":"typing_extensions","approved":true}}'

curl -X POST http://<mcp-server-ip>:8787/call_tool   -H "Content-Type: application/json"   -d '{"name":"restart_service","arguments":{"service":"mcp-server","approved":true}}'
```

---

## 14. Troubleshooting

Check the MCP server logs:

```bash
sudo journalctl -u mcp-server -n 100 --no-pager
sudo systemctl status mcp-server
```

If you are not using a virtual environment and hit the old Python issue:

```bash
sudo /usr/bin/python3 -m pip install --upgrade typing_extensions
```

Check Cockpit plugin files:

```bash
rpm -ql ansible-playbook-extension
sudo find /usr/share/cockpit -maxdepth 3 -type f | sort
sudo systemctl restart cockpit.socket
```

---

## 15. Result

You now have:

- a Podman-based MCP server host running three Ollama backends
- a FastAPI MCP server exposing both LLM tools and native SLES operational tools
- a Cockpit MCP client plugin installed from the RPM artifact
- readable Cockpit output for log analysis and remediation
- working examples for `analyze_logs`, `collect_logs`, `verify_service`, `install_package`, and `restart_service`
