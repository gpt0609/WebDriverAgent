#!/usr/bin/env python3
"""
云端重签名 WebDriverAgent IPA

在没有 macOS 的情况下，通过 GitHub Actions 云端编译并重签名 IPA。
用户只需提供：p12 证书、provisioning profile、证书密码。

使用方法:
    python cloud_resign.py --p12 path/to/cert.p12 \
                           --profile path/to/profile.mobileprovision \
                           --password "your_password" \
                           --identity "iPhone Distribution: Name (TEAMID)"

安全说明:
    - p12 证书包含私钥，脚本会将证书内容编码为 GitHub Secret
    - 请确保使用私有仓库或临时仓库
    - 重签名完成后建议删除 secrets (使用 --cleanup 参数)
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
    """GitHub API 客户端"""

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
        """获取仓库公钥用于加密 secrets"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/public-key"
        resp = requests.get(url, headers=self.headers)
        if resp.status_code == 200:
            data = resp.json()
            return data["key"], data["key_id"]
        else:
            print(f"获取公钥失败: {resp.status_code} {resp.text}")
            return None, None

    def create_or_update_secret(self, secret_name: str, value: str) -> bool:
        """创建或更新仓库 Secret (使用 libsodium 加密)"""
        pubkey, key_id = self.get_repo_public_key()
        if not pubkey:
            return False

        # 使用 pynacl 加密
        try:
            from nacl import encoding, public

            public_key = public.PublicKey(pubkey, encoding.Base64Encoder())
            sealed_box = public.SealedBox(public_key)
            encrypted = sealed_box.encrypt(value.encode())
            encrypted_b64 = base64.b64encode(encrypted).decode()
        except ImportError:
            print("错误: 需要安装 pynacl 库来加密 secrets")
            print("请运行: pip install pynacl")
            return False

        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/{secret_name}"
        data = {
            "encrypted_value": encrypted_b64,
            "key_id": key_id,
        }

        resp = requests.put(url, headers=self.headers, json=data)
        if resp.status_code in (201, 204):
            print(f"  ✓ Secret '{secret_name}' 已创建/更新")
            return True
        else:
            print(f"  ✗ 创建 Secret 失败: {resp.status_code} {resp.text}")
            return False

    def delete_secret(self, secret_name: str) -> bool:
        """删除仓库 Secret"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/secrets/{secret_name}"
        resp = requests.delete(url, headers=self.headers)
        if resp.status_code == 204:
            print(f"  ✓ Secret '{secret_name}' 已删除")
            return True
        return False

    def get_workflow_runs(self, workflow_file: str = None, limit: int = 10) -> list:
        """获取 workflow runs"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs"
        params = {"per_page": limit}
        if workflow_file:
            params["workflow_id"] = workflow_file

        resp = requests.get(url, headers=self.headers, params=params)
        if resp.status_code == 200:
            return resp.json()["workflow_runs"]
        return []

    def trigger_workflow(self, workflow_file: str, ref: str = "master", inputs: dict = None) -> int:
        """触发 workflow，返回 run ID"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/workflows/{workflow_file}/dispatches"
        data = {"ref": ref}
        if inputs:
            data["inputs"] = inputs

        resp = requests.post(url, headers=self.headers, json=data)
        if resp.status_code == 204:
            print(f"  ✓ Workflow '{workflow_file}' 已触发")
            # 等待一下让 run 出现
            time.sleep(5)
            # 获取最新的 run ID
            runs = self.get_workflow_runs(workflow_file, limit=1)
            if runs:
                return runs[0]["id"]
        else:
            print(f"  ✗ 触发 Workflow 失败: {resp.status_code} {resp.text}")
        return 0

    def wait_for_run_completion(self, run_id: int, timeout: int = 900, poll_interval: int = 30) -> str:
        """等待 workflow run 完成，返回 conclusion"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}"
        start_time = time.time()

        print(f"  等待构建完成 (run_id: {run_id})...")
        print(f"  查看进度: https://github.com/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}")

        while time.time() - start_time < timeout:
            resp = requests.get(url, headers=self.headers)
            if resp.status_code == 200:
                data = resp.json()
                status = data["status"]
                conclusion = data.get("conclusion") or "pending"

                elapsed = int(time.time() - start_time)
                print(f"  [{elapsed}s] 状态: {status}, 结论: {conclusion}")

                if status == "completed":
                    return conclusion

            time.sleep(poll_interval)

        return "timeout"

    def get_artifacts(self, run_id: int) -> list:
        """获取 run 的 artifacts 列表"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/runs/{run_id}/artifacts"
        resp = requests.get(url, headers=self.headers)
        if resp.status_code == 200:
            return resp.json().get("artifacts", [])
        return []

    def download_artifact(self, artifact_id: int, output_path: str) -> bool:
        """下载 artifact"""
        url = f"{self.base_url}/repos/{self.repo_owner}/{self.repo_name}/actions/artifacts/{artifact_id}/zip"
        resp = requests.get(url, headers=self.headers, stream=True)
        if resp.status_code == 200:
            with open(output_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
            print(f"  ✓ 已下载: {output_path} ({os.path.getsize(output_path)} bytes)")
            return True
        else:
            print(f"  ✗ 下载失败: {resp.status_code}")
            return False


class CloudResigner:
    """云端重签名管理器"""

    SECRETS = [
        "WDA_P12_CERTIFICATE",
        "WDA_PROVISIONING_PROFILE",
        "WDA_P12_PASSWORD",
    ]

    def __init__(self, github_token: str, repo_owner: str, repo_name: str):
        self.github = GitHubClient(github_token, repo_owner, repo_name)
        self.repo_path = Path(__file__).parent.parent.parent  # WebDriverAgent 目录

    def setup_secrets(self, p12_path: str, profile_path: str, password: str) -> bool:
        """设置重签名所需的 GitHub Secrets"""
        print("\n[1/4] 设置 GitHub Secrets...")

        # 读取文件并编码为 base64
        with open(p12_path, "rb") as f:
            p12_b64 = base64.b64encode(f.read()).decode()

        with open(profile_path, "rb") as f:
            profile_b64 = base64.b64encode(f.read()).decode()

        # 设置 secrets
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
        """提交 workflow 文件到仓库"""
        print("\n[2/4] 提交 workflow 到 GitHub...")

        workflow_file = self.repo_path / ".github" / "workflows" / "wda-build-resign.yml"
        if not workflow_file.exists():
            print(f"  ✗ Workflow 文件不存在: {workflow_file}")
            return False

        try:
            # 检查是否有变更
            result = subprocess.run(
                ["git", "status", "--porcelain", ".github/workflows/wda-build-resign.yml"],
                cwd=self.repo_path,
                capture_output=True,
                text=True,
            )

            if result.stdout.strip():
                # 有变更，需要提交
                subprocess.run(["git", "add", ".github/workflows/wda-build-resign.yml"], cwd=self.repo_path, check=True)
                subprocess.run(
                    ["git", "commit", "-m", "feat: add cloud build and resign workflow"],
                    cwd=self.repo_path,
                    check=True,
                )
                subprocess.run(["git", "push", "origin", "master"], cwd=self.repo_path, check=True)
                print("  ✓ Workflow 已提交并推送")
            else:
                print("  ✓ Workflow 无变更，已存在")

            return True
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Git 操作失败: {e}")
            return False

    def trigger_build(self, identity: str, build_only: bool = False) -> int:
        """触发云端构建"""
        print("\n[3/4] 触发云端构建...")

        inputs = {"identity": identity, "build_only": str(build_only).lower()}
        run_id = self.github.trigger_workflow("wda-build-resign.yml", inputs=inputs)

        if not run_id:
            print("  ✗ 触发失败")
            return 0

        return run_id

    def wait_and_download(self, run_id: int, output_path: str, artifact_name: str = "tj-easyclick-agent") -> bool:
        """等待构建完成并下载 IPA"""
        print("\n[4/4] 等待构建完成并下载...")

        # 等待完成
        conclusion = self.github.wait_for_run_completion(run_id)

        if conclusion != "success":
            print(f"  ✗ 构建失败: {conclusion}")
            return False

        print("  ✓ 构建成功!")

        # 获取 artifacts
        artifacts = self.github.get_artifacts(run_id)
        artifact_id = None
        for art in artifacts:
            if art["name"] == artifact_name:
                artifact_id = art["id"]
                break

        if not artifact_id:
            print(f"  ✗ 未找到 artifact '{artifact_name}'")
            print(f"  可用的 artifacts: {[a['name'] for a in artifacts]}")
            return False

        # 下载
        return self.github.download_artifact(artifact_id, output_path)

    def cleanup_secrets(self) -> None:
        """清理 GitHub Secrets"""
        print("\n清理 Secrets...")
        for secret in self.SECRETS:
            self.github.delete_secret(secret)


def find_signing_identity(p12_path: str, password: str) -> str:
    """尝试从 p12 文件中提取签名身份名称 (需要 openssl)"""
    try:
        result = subprocess.run(
            ["openssl", "pkcs12", "-in", p12_path, "-nodes", "-passin", f"pass:{password}"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            # 查找 CN (Common Name)
            for line in result.stdout.split("\n"):
                if "CN=" in line:
                    # 提取 CN 值
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
        description="云端重签名 WebDriverAgent IPA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--p12", required=True, help="p12 证书文件路径")
    parser.add_argument("--profile", required=True, help="provisioning profile 文件路径")
    parser.add_argument("--password", required=True, help="p12 证书密码")
    parser.add_argument(
        "--identity",
        help="签名身份 (如 'iPhone Distribution: Name (TEAMID)')，不指定则尝试自动提取",
    )
    parser.add_argument(
        "--token",
        help="GitHub Token (或设置环境变量 GITHUB_TOKEN)",
    )
    parser.add_argument(
        "--repo",
        default="gpt0609/WebDriverAgent",
        help="GitHub 仓库 (默认: gpt0609/WebDriverAgent)",
    )
    parser.add_argument(
        "--output",
        default="tj-easyclick-agent.ipa",
        help="输出 IPA 文件名 (默认: tj-easyclick-agent.ipa)",
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="仅构建，不重签名",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="完成后清理 GitHub Secrets",
    )

    args = parser.parse_args()

    # 获取 token
    token = args.token or os.environ.get("GITHUB_TOKEN")
    if not token:
        print("错误: 需要提供 GitHub Token")
        print("  方式 1: --token YOUR_TOKEN")
        print("  方式 2: 设置环境变量 GITHUB_TOKEN")
        sys.exit(1)

    # 解析仓库
    repo_parts = args.repo.split("/")
    if len(repo_parts) != 2:
        print("错误: 仓库格式应为 owner/name")
        sys.exit(1)

    # 检查文件存在
    if not os.path.exists(args.p12):
        print(f"错误: p12 文件不存在: {args.p12}")
        sys.exit(1)

    if not os.path.exists(args.profile):
        print(f"错误: provisioning profile 文件不存在: {args.profile}")
        sys.exit(1)

    # 确定签名身份
    identity = args.identity
    if not identity and not args.build_only:
        identity = find_signing_identity(args.p12, args.password)
        if identity:
            print(f"自动检测到签名身份: {identity}")
        else:
            print("警告: 无法自动检测签名身份，请使用 --identity 参数指定")
            print("示例: --identity 'iPhone Distribution: Your Name (TEAMID)'")
            sys.exit(1)

    # 创建重签名管理器
    resigner = CloudResigner(token, repo_parts[0], repo_parts[1])

    # 执行流程
    print("=" * 60)
    print("WebDriverAgent 云端构建 & 重签名")
    print("=" * 60)

    # 1. 设置 Secrets (除非只是构建)
    if not args.build_only:
        if not resigner.setup_secrets(args.p12, args.profile, args.password):
            print("设置 Secrets 失败")
            sys.exit(1)

    # 2. 提交 workflow
    if not resigner.commit_workflow():
        print("提交 workflow 失败")
        sys.exit(1)

    # 3. 触发构建
    run_id = resigner.trigger_build(identity or "dummy", args.build_only)
    if not run_id:
        print("触发构建失败")
        sys.exit(1)

    # 4. 等待并下载
    artifact_name = "WebDriverAgentRunner-unsigned" if args.build_only else "tj-easyclick-agent"
    if not resigner.wait_and_download(run_id, args.output, artifact_name):
        if args.cleanup:
            resigner.cleanup_secrets()
        sys.exit(1)

    # 5. 清理
    if args.cleanup:
        resigner.cleanup_secrets()

    # 完成
    print("\n" + "=" * 60)
    print("✓ 完成!")
    print(f"  IPA 文件: {os.path.abspath(args.output)}")
    print("=" * 60)

    print("\n下一步:")
    if args.build_only:
        print("  未签名 IPA 已生成，需要在 macOS 上手动签名")
    else:
        print("  1. 安装 IPA: tidevice install " + args.output)
        print("  2. 启动 WDA: tidevice xctest -B com.wa.agent")
        print("  3. 验证状态: 访问 http://<设备IP>:8100/health")


if __name__ == "__main__":
    main()
