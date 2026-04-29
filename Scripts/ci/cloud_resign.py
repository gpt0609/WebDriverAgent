#!/usr/bin/env python3
"""
Cloud Resign WebDriverAgent IPA

Build and resign WebDriverAgent IPA using GitHub Actions cloud,
without requiring a local macOS machine.
User provides: p12 certificate, provisioning profile, certificate password.

Usage:
    python cloud_resign.py --p12 path/to/cert.p12 \
                           --profile path/to/profile.mobileprovision \
                           --password "your_password" \
                           --identity "iPhone Distribution: Name (TEAMID)"

Security note:
    - p12 contains private key, stored in GitHub Secrets (encrypted)
    - Use private repo or cleanup secrets after completion
"""

import argparse
import base64
import os
import subprocess
import sys
import time
from pathlib import Path

import requests


class GitHubClient:
    """GitHub API client"""

    def __init__(self, token: str, repo_owner: str, repo_name: str):
        self.token = token
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.base_url = "https://api.github.com"
        self.headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
        }

    def get_repo_public_key(self) -> tuple:
        """Get repo public key for encrypting secrets"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/public-key"
        resp = requests.get(url, headers=self.headers)
        if resp.status_code == 200:
            data = resp.json()
            return data["key"], data["key_id"]
        else:
            print(f"[FAIL] Get public key failed: {resp.status_code} {resp.text}")
            return None, None

    def create_or_update_secret(self, secret_name: str, value: str) -> bool:
        """Create or update repo Secret (libsodium encrypted)"""
        pubkey, key_id = self.get_repo_public_key()
        if not pubkey:
            return False

        # Encrypt with pynacl
        try:
            from nacl import encoding, public

            public_key = public.PublicKey(pubkey, encoding.Base64Encoder())
            sealed_box = public.SealedBox(public_key)
            encrypted = sealed_box.encrypt(value.encode())
            encrypted_b64 = base64.b64encode(encrypted).decode()
        except ImportError:
            print("[FAIL] Need pynacl library to encrypt secrets")
            print("       Run: pip install pynacl")
            return False

        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/{secret_name}"
        data = {
            "encrypted_value": encrypted_b64,
            "key_id": key_id,
        }

        resp = requests.put(url, headers=self.headers, json=data)
        if resp.status_code in (201, 204):
            print(f"  [OK] Secret '{secret_name}' created/updated")
            return True
        else:
            print(f"  [FAIL] Create Secret failed: {resp.status_code} {resp.text}")
            return False

    def delete_secret(self, secret_name: str) -> bool:
        """Delete repo Secret"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/{secret_name}"
        resp = requests.delete(url, headers=self.headers)
        if resp.status_code == 204:
            print(f"  [OK] Secret '{secret_name}' deleted")
            return True
        return False

    def get_workflow_runs(self, workflow_file: str = None, limit: int = 10) -> list:
        """Get workflow runs"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs"
        params = {"per_page": limit}
        if workflow_file:
            params["workflow_id"] = workflow_file

        resp = requests.get(url, headers=self.headers, params=params)
        if resp.status_code == 200:
            return resp.json()["workflow_runs"]
        return []

    def trigger_workflow(self, workflow_file: str, ref: str = "master", inputs: dict = None) -> int:
        """Trigger workflow, return run ID"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/workflows/{workflow_file}/dispatches"
        data = {"ref": ref}
        if inputs:
            data["inputs"] = inputs

        resp = requests.post(url, headers=self.headers, json=data)
        if resp.status_code == 204:
            print(f"  [OK] Workflow '{workflow_file}' triggered")
            # Wait for run to appear
            time.sleep(5)
            # Get latest run ID
            runs = self.get_workflow_runs(workflow_file, limit=1)
            if runs:
                return runs[0]["id"]
        else:
            print(f"  [FAIL] Trigger Workflow failed: {resp.status_code} {resp.text}")
        return 0

    def wait_for_run_completion(self, run_id: int, timeout: int = 900, poll_interval: int = 30) -> str:
        """Wait for workflow run completion, return conclusion"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}"
        start_time = time.time()

        print(f"  Waiting for build (run_id: {run_id})...")
        print(f"  View progress: https://github.com/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}")

        while time.time() - start_time < timeout:
            resp = requests.get(url, headers=self.headers)
            if resp.status_code == 200:
                data = resp.json()
                status = data["status"]
                conclusion = data.get("conclusion") or "pending"

                elapsed = int(time.time() - start_time)
                print(f"  [{elapsed}s] Status: {status}, Conclusion: {conclusion}")

                if status == "completed":
                    return conclusion

            time.sleep(poll_interval)

        return "timeout"

    def get_artifacts(self, run_id: int) -> list:
        """Get run artifacts list"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}/artifacts"
        resp = requests.get(url, headers=self.headers)
        if resp.status_code == 200:
            return resp.json().get("artifacts", [])
        return []

    def download_artifact(self, artifact_id: int, output_path: str) -> bool:
        """Download artifact and extract IPA from artifact zip"""
        import zipfile
        import tempfile

        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/artifacts/{artifact_id}/zip"
        resp = requests.get(url, headers=self.headers, stream=True)
        if resp.status_code != 200:
            print(f"  [FAIL] Download failed: {resp.status_code}")
            return False

        # Download artifact zip to temp file
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
            for chunk in resp.iter_content(chunk_size=8192):
                tmp.write(chunk)
            tmp_zip = tmp.name

        print(f"  Downloaded artifact zip: {os.path.getsize(tmp_zip)} bytes")

        # GitHub artifact zip contains the IPA file inside
        # Extract the IPA and save to output_path
        try:
            with zipfile.ZipFile(tmp_zip, "r") as zf:
                # Find .ipa file inside artifact zip
                ipa_files = [n for n in zf.namelist() if n.endswith(".ipa")]
                if not ipa_files:
                    # Maybe the artifact itself is the IPA content
                    # (e.g., Payload/ directory directly)
                    all_files = zf.namelist()
                    print(f"  No .ipa in artifact, files: {all_files[:10]}")
                    # Just extract all and re-zip as IPA
                    pass
                else:
                    ipa_name = ipa_files[0]
                    with zf.open(ipa_name) as ipa_src, open(output_path, "wb") as ipa_dst:
                        ipa_dst.write(ipa_src.read())
                    print(f"  [OK] Extracted IPA: {output_path} ({os.path.getsize(output_path)} bytes)")
                    os.unlink(tmp_zip)
                    return True

                # Fallback: artifact contains Payload/ directly
                payload_files = [n for n in zf.namelist() if n.startswith("Payload/")]
                if payload_files:
                    with zf.open(ipa_files[0]) if ipa_files else open(tmp_zip, "rb") as src:
                        pass
                    # Re-zip Payload contents as IPA
                    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as ipa_zf:
                        for f in payload_files:
                            ipa_zf.writestr(f, zf.read(f))
                    print(f"  [OK] Re-packaged IPA: {output_path} ({os.path.getsize(output_path)} bytes)")
                    os.unlink(tmp_zip)
                    return True

                print(f"  [FAIL] No IPA or Payload found in artifact")
                os.unlink(tmp_zip)
                return False
        except Exception as e:
            print(f"  [FAIL] Error extracting IPA: {e}")
            os.unlink(tmp_zip)
            return False


class CloudResigner:
    """Cloud resign manager"""

    SECRETS = [
        "WDA_P12_CERTIFICATE",
        "WDA_PROVISIONING_PROFILE",
        "WDA_P12_PASSWORD",
    ]

    def __init__(self, github_token: str, repo_owner: str, repo_name: str):
        self.github = GitHubClient(github_token, repo_owner, repo_name)
        self.repo_path = Path(__file__).parent.parent.parent  # WebDriverAgent dir

    def setup_secrets(self, p12_path: str, profile_path: str, password: str) -> bool:
        """Setup GitHub Secrets for resigning"""
        print("\n[1/4] Setting up GitHub Secrets...")

        # Read files and encode base64
        with open(p12_path, "rb") as f:
            p12_b64 = base64.b64encode(f.read()).decode()

        with open(profile_path, "rb") as f:
            profile_b64 = base64.b64encode(f.read()).decode()

        # Set secrets
        secrets = {
            "WDA_P12_CERTIFICATE": p12_b64,
            "WDA_PROVISIONING_PROFILE": profile_b64,
            "WDA_P12_PASSWORD": password,
        }

        success = True
        for name, value in secrets.items():
            if not self.github.create_or_update_secret(name, value):
                success = False

        return success

    def commit_workflow(self) -> bool:
        """Commit workflow file to repo"""
        print("\n[2/4] Committing workflow to GitHub...")

        workflow_file = self.repo_path / ".github" / "workflows" / "wda-build-resign.yml"
        if not workflow_file.exists():
            print(f"  [FAIL] Workflow file not found: {workflow_file}")
            return False

        try:
            # Check for changes
            result = subprocess.run(
                ["git", "status", "--porcelain", ".github/workflows/wda-build-resign.yml"],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
            )

            if result.stdout.strip():
                # Has changes, need to commit
                subprocess.run(["git", "add", ".github/workflows/wda-build-resign.yml"], cwd=self.repo_path, check=True)
                subprocess.run(
                    ["git", "commit", "-m", "feat: add cloud build and resign workflow"],
                    cwd=self.repo_path,
                    check=True,
                )
                subprocess.run(["git", "push", "origin", "master"], cwd=self.repo_path, check=True)
                print("  [OK] Workflow committed and pushed")
            else:
                print("  [OK] Workflow already up-to-date")

            return True
        except subprocess.CalledProcessError as e:
            print(f"  [FAIL] Git operation failed: {e}")
            return False

    def trigger_build(self, identity: str, build_only: bool = False) -> int:
        """Trigger cloud build"""
        print("\n[3/4] Triggering cloud build...")

        inputs = {"identity": identity, "build_only": str(build_only).lower()}
        run_id = self.github.trigger_workflow("wda-build-resign.yml", inputs=inputs)

        if not run_id:
            print("  [FAIL] Trigger failed")
            return 0

        return run_id

    def wait_and_download(self, run_id: int, output_path: str, artifact_name: str = "tj-easyclick-agent") -> bool:
        """Wait for build completion and download IPA"""
        print("\n[4/4] Waiting for build and downloading...")

        # Wait for completion
        conclusion = self.github.wait_for_run_completion(run_id)

        if conclusion != "success":
            print(f"  [FAIL] Build failed: {conclusion}")
            return False

        print("  [OK] Build succeeded!")

        # Get artifacts
        artifacts = self.github.get_artifacts(run_id)
        artifact_id = None
        for art in artifacts:
            if art["name"] == artifact_name:
                artifact_id = art["id"]
                break

        if not artifact_id:
            print(f"  [FAIL] Artifact '{artifact_name}' not found")
            print(f"  Available artifacts: {[a['name'] for a in artifacts]}")
            return False

        # Download
        return self.github.download_artifact(artifact_id, output_path)

    def cleanup_secrets(self) -> None:
        """Cleanup GitHub Secrets"""
        print("\nCleaning up Secrets...")
        for secret in self.SECRETS:
            self.github.delete_secret(secret)


def find_signing_identity(p12_path: str, password: str) -> str:
    """Try to extract signing identity name from p12 file"""
    try:
        result = subprocess.run(
            ["openssl", "pkcs12", "-in", p12_path, "-nodes", "-passin", f"pass:{password}"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            # Find CN (Common Name)
            for line in result.stdout.split("\n"):
                if "CN=" in line:
                    # Extract CN value
                    cn_start = line.find("CN=") + 3
                    cn_end = line.find(",", cn_start)
                    if cn_end == -1:
                        cn_end = line.find("/", cn_start)
                    if cn_end == -1:
                        cn_end = len(line)
                    cn = line[cn_start:cn_end].strip()
                    return cn
    except FileNotFoundError:
        pass
    return ""


def main():
    parser = argparse.ArgumentParser(
        description="Cloud resign WebDriverAgent IPA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--p12", required=True, help="p12 certificate file path")
    parser.add_argument("--profile", required=True, help="provisioning profile file path")
    parser.add_argument("--password", required=True, help="p12 certificate password")
    parser.add_argument(
        "--identity",
        help="Signing identity (e.g. 'iPhone Distribution: Name (TEAMID)'), auto-detected if not specified",
    )
    parser.add_argument(
        "--token",
        help="GitHub Token (or set env var GITHUB_TOKEN)",
    )
    parser.add_argument(
        "--repo",
        default="gpt0609/WebDriverAgent",
        help="GitHub repo (default: gpt0609/WebDriverAgent)",
    )
    parser.add_argument(
        "--output",
        default="tj-easyclick-agent.ipa",
        help="Output IPA filename (default: tj-easyclick-agent.ipa)",
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="Only build, skip resigning",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Cleanup GitHub Secrets after completion",
    )

    args = parser.parse_args()

    # Get token
    token = args.token or os.environ.get("GITHUB_TOKEN")
    if not token:
        print("[FAIL] Need GitHub Token")
        print("  Option 1: --token YOUR_TOKEN")
        print("  Option 2: set env var GITHUB_TOKEN")
        sys.exit(1)

    # Parse repo
    repo_parts = args.repo.split("/")
    if len(repo_parts) != 2:
        print("[FAIL] Repo format should be owner/name")
        sys.exit(1)

    # Check files exist
    if not os.path.exists(args.p12):
        print(f"[FAIL] p12 file not found: {args.p12}")
        sys.exit(1)

    if not os.path.exists(args.profile):
        print(f"[FAIL] provisioning profile not found: {args.profile}")
        sys.exit(1)

    # Determine signing identity
    identity = args.identity
    if not identity and not args.build_only:
        identity = find_signing_identity(args.p12, args.password)
        if identity:
            print(f"Auto-detected signing identity: {identity}")
        else:
            print("[WARN] Cannot auto-detect signing identity, use --identity parameter")
            print("Example: --identity 'iPhone Distribution: Your Name (TEAMID)'")
            sys.exit(1)

    # Create resigner
    resigner = CloudResigner(token, repo_parts[0], repo_parts[1])

    # Execute
    print("=" * 60)
    print("WebDriverAgent Cloud Build & Resign")
    print("=" * 60)

    # 1. Setup Secrets (unless build-only)
    if not args.build_only:
        if not resigner.setup_secrets(args.p12, args.profile, args.password):
            print("[FAIL] Setup Secrets failed")
            sys.exit(1)

    # 2. Commit workflow
    if not resigner.commit_workflow():
        print("[FAIL] Commit workflow failed")
        sys.exit(1)

    # 3. Trigger build
    run_id = resigner.trigger_build(identity or "dummy", args.build_only)
    if not run_id:
        print("[FAIL] Trigger build failed")
        sys.exit(1)

    # 4. Wait and download
    artifact_name = "WebDriverAgentRunner-unsigned" if args.build_only else "tj-easyclick-agent"
    if not resigner.wait_and_download(run_id, args.output, artifact_name):
        if args.cleanup:
            resigner.cleanup_secrets()
        sys.exit(1)

    # 5. Cleanup
    if args.cleanup:
        resigner.cleanup_secrets()

    # Done
    print("\n" + "=" * 60)
    print("[OK] Completed!")
    print(f"  IPA file: {os.path.abspath(args.output)}")
    print("=" * 60)

    print("\nNext steps:")
    if args.build_only:
        print("  Unsigned IPA generated, needs manual signing on macOS")
    else:
        print("  1. Install IPA: tidevice install " + args.output)
        print("  2. Start WDA: tidevice xctest -B com.wa.agent")
        print("  3. Verify: visit http://<device-ip>:8100/health")


if __name__ == "__main__":
    main()