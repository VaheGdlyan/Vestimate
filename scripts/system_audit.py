import os
import sys
import subprocess
from pathlib import Path

# Do this BEFORE importing rich or other third-party libs
try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
    from rich.text import Text
    import redis
    import boto3
    from botocore.exceptions import ClientError
    from dotenv import load_dotenv
    from supabase import create_client, Client
    import urllib.request
    import urllib.error
except ImportError:
    print("[FATAL] Required packages are not installed.")
    print("Run: pip install rich redis supabase boto3 python-dotenv")
    sys.exit(1)

def main():
    ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
    load_dotenv(dotenv_path=ENV_PATH)
    
    console = Console()
    fail_count = 0
    pass_count = 0
    warn_count = 0

    def get_status_text(result):
        if result == "PASS":
            return Text("PASS", style="bold green")
        elif result == "FAIL":
            return Text("FAIL", style="bold red")
        else:
            return Text("WARN", style="bold yellow")

    def update_counts(result):
        nonlocal fail_count, pass_count, warn_count
        if result == "PASS":
            pass_count += 1
        elif result == "FAIL":
            fail_count += 1
        else:
            warn_count += 1

    # Panel 1 — Local Environment
    table1 = Table(box=box.SIMPLE, show_header=True)
    table1.add_column("Component", style="white")
    table1.add_column("Status")
    table1.add_column("Detail", style="white")

    # Virtual Environment
    is_venv = sys.prefix != sys.base_prefix
    res1 = "PASS" if is_venv else "FAIL"
    update_counts(res1)
    table1.add_row("Virtual Environment", get_status_text(res1), str(is_venv))

    # Python Version
    py_version = sys.version.split()[0]
    is_py_pass = sys.version_info >= (3, 11)
    res2 = "PASS" if is_py_pass else "FAIL"
    update_counts(res2)
    table1.add_row("Python Version", get_status_text(res2), py_version)

    # .env File
    env_exists = ENV_PATH.exists()
    res3 = "PASS" if env_exists else "FAIL"
    update_counts(res3)
    table1.add_row(".env File", get_status_text(res3), str(env_exists))

    # Git Branch
    try:
        git_proc = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
        if git_proc.returncode == 0:
            branch = git_proc.stdout.strip() or "(detached or empty repo)"
            res4 = "PASS"
        else:
            branch = "(not a git repo)"
            res4 = "WARN"
    except Exception as e:
        branch = "(git command failed)"
        res4 = "WARN"
    update_counts(res4)
    table1.add_row("Git Branch", get_status_text(res4), branch)

    console.print(Panel(table1, title="LOCAL ENVIRONMENT", title_align="left", style="bold white on dark_blue"))

    # Panel 2 — Environment Variables
    table2 = Table(box=box.SIMPLE, show_header=True)
    table2.add_column("Component", style="white")
    table2.add_column("Status")
    table2.add_column("Detail", style="white")

    required_env_vars = [
        "SUPABASE_URL",
        "SUPABASE_SERVICE_KEY",
        "R2_ACCOUNT_ID",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_BUCKET_NAME",
        "MODAL_ENDPOINT_SEGMENT",
        "MODAL_ENDPOINT_EMBED"
    ]

    for key in required_env_vars:
        val = os.getenv(key)
        if not val:
            res = "FAIL"
            detail = "Missing or empty"
        else:
            res = "PASS"
            detail = val[:6] + "..."
        update_counts(res)
        table2.add_row(key, get_status_text(res), detail)

    console.print(Panel(table2, title="ENVIRONMENT VARIABLES", title_align="left", style="bold white on dark_blue"))

    # Panel 3 — Memurai / Redis
    table3 = Table(box=box.SIMPLE, show_header=True)
    table3.add_column("Component", style="white")
    table3.add_column("Status")
    table3.add_column("Detail", style="white")

    try:
        import time
        start_time = time.perf_counter()
        r = redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=3)
        ping_res = r.ping()
        latency_ms = (time.perf_counter() - start_time) * 1000
        
        # TCP Connection
        res_tcp = "PASS" if ping_res else "FAIL"
        update_counts(res_tcp)
        table3.add_row("TCP Connection", get_status_text(res_tcp), str(ping_res))

        # Memurai CLI
        try:
            memurai_proc = subprocess.run(["memurai-cli", "PING"], capture_output=True, text=True)
            if "PONG" in memurai_proc.stdout:
                res_cli = "PASS"
                detail_cli = "PONG"
            else:
                res_cli = "FAIL"
                detail_cli = "PONG not in stdout"
        except FileNotFoundError:
            res_cli = "WARN"
            detail_cli = "memurai-cli not in PATH, TCP ping used instead"
        update_counts(res_cli)
        table3.add_row("Memurai CLI", get_status_text(res_cli), detail_cli)

        # Latency
        res_lat = "WARN" if latency_ms > 50 else "PASS"
        update_counts(res_lat)
        table3.add_row("Latency", get_status_text(res_lat), f"{latency_ms:.2f}ms")

    except redis.exceptions.ConnectionError:
        res = "FAIL"
        detail = "Connection refused on 127.0.0.1:6379"
        update_counts(res)
        table3.add_row("TCP Connection", get_status_text(res), detail)
        update_counts(res)
        table3.add_row("Memurai CLI", get_status_text(res), detail)
        update_counts(res)
        table3.add_row("Latency", get_status_text(res), detail)
    except Exception as e:
        res = "FAIL"
        detail = str(e)
        update_counts(res)
        table3.add_row("TCP Connection", get_status_text(res), detail)
        update_counts(res)
        table3.add_row("Memurai CLI", get_status_text(res), detail)
        update_counts(res)
        table3.add_row("Latency", get_status_text(res), detail)

    console.print(Panel(table3, title="LOCAL BROKER (MEMURAI / REDIS)", title_align="left", style="bold white on dark_blue"))

    # Panel 4 — Supabase
    table4 = Table(box=box.SIMPLE, show_header=True)
    table4.add_column("Component", style="white")
    table4.add_column("Status")
    table4.add_column("Detail", style="white")

    try:
        supa_url = os.getenv("SUPABASE_URL")
        supa_key = os.getenv("SUPABASE_SERVICE_KEY")
        if not supa_url or not supa_key:
            raise Exception("Missing SUPABASE_URL or SUPABASE_SERVICE_KEY")

        from urllib.parse import urlparse
        parsed_url = urlparse(supa_url)
        display_host = parsed_url.netloc or supa_url

        client = create_client(supa_url, supa_key)
        update_counts("PASS")
        table4.add_row("Client Init", get_status_text("PASS"), display_host)

        # Table Access
        response = client.table("wardrobe_items").select("id").limit(1).execute()
        if hasattr(response, 'data'):
            update_counts("PASS")
            table4.add_row("Table Access", get_status_text("PASS"), "Data attribute present")
            
            # Row Count
            update_counts("PASS")
            table4.add_row("Row Count", get_status_text("PASS"), str(len(response.data)))
        else:
            update_counts("FAIL")
            table4.add_row("Table Access", get_status_text("FAIL"), "No data attribute")
            update_counts("FAIL")
            table4.add_row("Row Count", get_status_text("FAIL"), "Skipped")
            
    except Exception as e:
        res = "FAIL"
        detail = str(e)
        update_counts(res)
        table4.add_row("Client Init", get_status_text(res), detail)
        update_counts(res)
        table4.add_row("Table Access", get_status_text(res), detail)
        update_counts(res)
        table4.add_row("Row Count", get_status_text(res), detail)

    console.print(Panel(table4, title="SUPABASE (DATABASE)", title_align="left", style="bold white on dark_blue"))

    # Panel 5 — Cloudflare R2
    table5 = Table(box=box.SIMPLE, show_header=True)
    table5.add_column("Component", style="white")
    table5.add_column("Status")
    table5.add_column("Detail", style="white")

    try:
        r2_account_id = os.getenv("R2_ACCOUNT_ID")
        if not r2_account_id:
            raise ClientError({"Error": {"Code": "MissingAccountID"}}, "Init")

        s3_client = boto3.client(
            "s3",
            endpoint_url=f"https://{r2_account_id}.r2.cloudflarestorage.com",
            aws_access_key_id=os.getenv("R2_ACCESS_KEY_ID"),
            aws_secret_access_key=os.getenv("R2_SECRET_ACCESS_KEY"),
            region_name="auto",
        )
        update_counts("PASS")
        table5.add_row("Client Init", get_status_text("PASS"), "Success")

        r2_bucket = os.getenv("R2_BUCKET_NAME", "vestimate-assets")
        resp = s3_client.list_objects_v2(Bucket=r2_bucket, MaxKeys=1)
        update_counts("PASS")
        table5.add_row("Bucket Access", get_status_text("PASS"), "HTTP 200")

        key_count = resp.get("KeyCount", 0)
        update_counts("PASS")
        table5.add_row("Object Count", get_status_text("PASS"), str(key_count))

    except ClientError as e:
        res = "FAIL"
        detail = e.response.get("Error", {}).get("Code", str(e))
        update_counts(res)
        table5.add_row("Client Init", get_status_text(res), detail)
        update_counts(res)
        table5.add_row("Bucket Access", get_status_text(res), detail)
        update_counts(res)
        table5.add_row("Object Count", get_status_text(res), detail)
    except Exception as e:
        res = "FAIL"
        detail = str(e)
        update_counts(res)
        table5.add_row("Client Init", get_status_text(res), detail)
        update_counts(res)
        table5.add_row("Bucket Access", get_status_text(res), detail)
        update_counts(res)
        table5.add_row("Object Count", get_status_text(res), detail)

    console.print(Panel(table5, title="CLOUDFLARE R2 (OBJECT STORAGE)", title_align="left", style="bold white on dark_blue"))

    # Panel 6 — Modal Endpoints
    table6 = Table(box=box.SIMPLE, show_header=True)
    table6.add_column("Component", style="white")
    table6.add_column("Status")
    table6.add_column("Detail", style="white")

    modal_endpoints = [
        ("MODAL_ENDPOINT_SEGMENT", os.getenv("MODAL_ENDPOINT_SEGMENT")),
        ("MODAL_ENDPOINT_EMBED", os.getenv("MODAL_ENDPOINT_EMBED"))
    ]

    for name, url in modal_endpoints:
        if not url:
            update_counts("FAIL")
            table6.add_row(name, get_status_text("FAIL"), "URL is empty")
            continue
        
        req = urllib.request.Request(url, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                http_code = response.status
        except urllib.error.HTTPError as e:
            http_code = e.code
        except urllib.error.URLError as e:
            http_code = None
        except Exception as e:
            http_code = None

        if http_code in (200, 405):
            res = "PASS"
        elif http_code == 404:
            res = "WARN"
        else:
            res = "FAIL"
            
        update_counts(res)
        table6.add_row(name, get_status_text(res), str(http_code) if http_code else "No response / timeout")

    console.print(Panel(table6, title="MODAL GPU ENDPOINTS", title_align="left", style="bold white on dark_blue"))

    # Final Summary Panel
    summary_text = (
        f"Total checks: {pass_count + fail_count + warn_count}\n"
        f"PASS: [bold green]{pass_count}[/bold green]\n"
        f"FAIL: [bold red]{fail_count}[/bold red]\n"
        f"WARN: [bold yellow]{warn_count}[/bold yellow]\n\n"
    )

    if fail_count == 0:
        summary_text += "[bold green]All systems operational. Ready to develop.[/bold green]"
    else:
        summary_text += f"[bold red]ACTION REQUIRED: {fail_count} critical check(s) failed. Fix before proceeding.[/bold red]"

    console.print(Panel(summary_text, title="AUDIT SUMMARY", title_align="left", style="bold white on dark_blue"))

    sys.exit(0 if fail_count == 0 else 1)

if __name__ == "__main__":
    main()
