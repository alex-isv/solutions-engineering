# MCP Client/Server on SLES 16 — Final Reference

This guide reflects the validated working design:

- **MCP server** acts as the **analysis engine**
- **MCP client** (Cockpit plugin on each client node) acts as the **executor** and **local log collector**
- Client-side actions:
  - `analyze_uploaded_logs`
  - `install_package`
  - `install_pip_package`
  - `restart_service`
- Server-side tools:
  - LLM tools (`llama3_8b`, `mistral_7b`, `deepseek_r1_14b`)
  - `analyze_uploaded_logs` analysis endpoint
  - optional server-local tools if you still want them

This document is intended to help you **rewrite your guide** and **rebuild your Cockpit MCP client RPM**.

---

## 1. Final architecture

```text
Cockpit client node
  -> ansible-playbook-extension
  -> /usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
  -> collects logs locally
  -> runs local zypper / pip / systemctl when approved

MCP server host
  -> FastAPI MCP server on :8787
  -> Ollama model backends
  -> analyze_uploaded_logs
  -> LLM reasoning tools
```

---

## 2. Final `server.py`

Save as:

```bash
/opt/mcp-server/server.py
```
<details><summary>Expand for detailed values</summary>
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

## 3. Final `deploy-mcpclient`

Install on the **client node** at:

```bash
/usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
```

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

Then:

```bash
sudo chmod 755 /usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
sudo systemctl restart cockpit.socket
```

---

## 4. Tool examples for Cockpit

### LLM tools

Tool:
```text
mistral_7b
```

Prompt:
```json
{"prompt":"Explain how to debug a failed systemd service on SLES"}
```

Tool:
```text
deepseek_r1_14b
```

Prompt:
```json
{"prompt":"Explain a Python dependency mismatch involving typing_extensions"}
```

### Analyze logs from the client node

Tool:
```text
analyze_uploaded_logs
```

Prompt:
```json
{"service":"cloud-final.service","lines":200}
```

Other useful client examples:

```json
{"service":"sshd.service","lines":200}
```

```json
{"service":"podman.service","lines":200}
```

```json
{"service":"cockpit.socket","lines":200}
```

### Install an OS package on the client

Tool:
```text
install_package
```

Prompt:
```json
{"package":"curl","approved":true}
```

Other examples:

```json
{"package":"git","approved":true}
```

```json
{"package":"jq","approved":true}
```

### Install a Python package on the client

Tool:
```text
install_pip_package
```

Prompt:
```json
{"package":"typing_extensions","approved":true}
```

### Restart a service on the client

Tool:
```text
restart_service
```

Prompt:
```json
{"service":"cloud-final.service","approved":true}
```

### Verify a service on the MCP server

Tool:
```text
verify_service
```

Prompt:
```json
{"service":"mcp-server"}
```

---

## 5. Recommended client workflow

### Diagnose a client issue

Tool:
```text
analyze_uploaded_logs
```

Prompt:
```json
{"service":"cloud-final.service","lines":200}
```

If the response suggests `typing_extensions`, then run:

Tool:
```text
install_pip_package
```

Prompt:
```json
{"package":"typing_extensions","approved":true}
```

If the response suggests a service restart:

Tool:
```text
restart_service
```

Prompt:
```json
{"service":"cloud-final.service","approved":true}
```

---

## 6. RPM rebuild checklist

Your package should include at least:

```text
/usr/share/cockpit/ansible-playbook-extension/
├── manifest.json
├── index.html
├── index.js
└── bin/
    └── deploy-mcpclient
```

### Verify `index.js`

It must call:

```text
/usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient
```

and not the old path.

### rpmbuild layout

```bash
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
```

Copy your plugin tree into `~/rpmbuild/SOURCES/ansible-playbook-extension/`.

Create a tarball:

```bash
cd ~/rpmbuild/SOURCES
tar czf ansible-playbook-extension-1.0.3.tar.gz ansible-playbook-extension
```

### Example spec outline

Save as `~/rpmbuild/SPECS/ansible-playbook-extension.spec`

```spec
Name:           ansible-playbook-extension
Version:        1.0.3
Release:        1%{?dist}
Summary:        Cockpit MCP client extension for SLES 16
License:        MIT
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

Requires:       cockpit
Requires:       python3
Requires:       curl

%description
Cockpit extension for MCP client workflows on SLES 16.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}/usr/share/cockpit/ansible-playbook-extension
cp -a * %{buildroot}/usr/share/cockpit/ansible-playbook-extension/
chmod 755 %{buildroot}/usr/share/cockpit/ansible-playbook-extension/bin/deploy-mcpclient

%files
/usr/share/cockpit/ansible-playbook-extension

%changelog
* Thu Apr 02 2026 Your Name <you@example.com> - 1.0.3-1
- Updated client-side MCP execution for log analysis, package install, pip install, and service restart
```

Build:

```bash
rpmbuild -ba ~/rpmbuild/SPECS/ansible-playbook-extension.spec
```

Install the new RPM:

```bash
sudo zypper install --allow-unsigned-rpm -y ~/rpmbuild/RPMS/noarch/ansible-playbook-extension-1.0.3-1.noarch.rpm
sudo systemctl restart cockpit.socket
```

---

## 7. Final notes

For your design, the clean split is:

- **MCP server**
  - analyze uploaded client logs
  - provide LLM reasoning

- **MCP client**
  - collect logs locally
  - install packages locally
  - install Python packages locally
  - restart services locally

That is the model you should document and package into the next RPM release.
