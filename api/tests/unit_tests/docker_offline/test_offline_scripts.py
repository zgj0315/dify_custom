from __future__ import annotations

import os
import stat
import subprocess
import tarfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
BUILD_SCRIPT = REPO_ROOT / "docker" / "offline" / "build-offline-package.sh"
INSTALL_SCRIPT = REPO_ROOT / "docker" / "offline" / "install-offline.sh"
VERIFY_SCRIPT = REPO_ROOT / "docker" / "offline" / "verify-offline.sh"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    current_mode = path.stat().st_mode
    path.chmod(current_mode | stat.S_IXUSR)


def _make_fake_bin(tmp_path: Path) -> tuple[Path, Path]:
    fake_bin = tmp_path / "fake-bin"
    fake_bin.mkdir()
    docker_log = tmp_path / "docker.log"

    _write_executable(
        fake_bin / "docker",
        """#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "${FAKE_DOCKER_LOG}"
if [ "$1" = "build" ]; then
  exit 0
fi
if [ "$1" = "save" ]; then
  shift
  output=""
  content=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      output="$2"
      shift 2
      continue
    fi
    content="${content}${1}\\n"
    shift
  done
  printf '%b' "$content" > "$output"
  exit 0
fi
if [ "$1" = "load" ]; then
  exit 0
fi
if [ "$1" = "compose" ]; then
  command_line="$*"
  case "$command_line" in
    *"config --images"*)
      printf '%s\\n' \
        "local/dify-api:testtag" \
        "local/dify-web:testtag" \
        "postgres:15-alpine" \
        "redis:6-alpine" \
        "local/dify-api:testtag"
      exit 0
      ;;
    *"exec api env"*)
      printf '%s\\n' "COMMIT_SHA=deadbee"
      exit 0
      ;;
    *" ps"|*" images"|*" up -d")
      exit 0
      ;;
  esac
fi
echo "unexpected docker invocation: $*" >&2
exit 1
""",
    )

    _write_executable(
        fake_bin / "git",
        """#!/bin/sh
set -eu
if [ "$1" = "-C" ]; then
  shift 2
fi
if [ "$1" = "rev-parse" ] && [ "$2" = "--short" ] && [ "$3" = "HEAD" ]; then
  printf '%s\\n' "deadbee"
  exit 0
fi
echo "unexpected git invocation: $*" >&2
exit 1
""",
    )

    return fake_bin, docker_log


def _base_env(fake_bin: Path, docker_log: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    env["FAKE_DOCKER_LOG"] = str(docker_log)
    return env


def _write_runtime_envs(tmp_path: Path) -> tuple[Path, Path]:
    env_file = tmp_path / ".env"
    env_file.write_text("DB_TYPE=postgresql\nVECTOR_STORE=weaviate\n", encoding="utf-8")

    image_env_file = tmp_path / ".env.local-images"
    image_env_file.write_text(
        "\n".join(
            [
                "DOCKER_REGISTRY=local",
                "IMAGE_TAG=testtag",
                "API_IMAGE_NAME=dify-api",
                "WEB_IMAGE_NAME=dify-web",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    return env_file, image_env_file


def test_build_script_fails_when_image_env_file_is_missing(tmp_path: Path) -> None:
    fake_bin, docker_log = _make_fake_bin(tmp_path)
    env_file, _ = _write_runtime_envs(tmp_path)
    missing_image_env = tmp_path / "missing.local-images"

    result = subprocess.run(
        [
            "bash",
            str(BUILD_SCRIPT),
            "--env-file",
            str(env_file),
            "--image-env-file",
            str(missing_image_env),
            "--output",
            str(tmp_path / "dist"),
        ],
        cwd=REPO_ROOT,
        env=_base_env(fake_bin, docker_log),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert str(missing_image_env) in result.stderr


def test_build_script_creates_archive_and_manifest(tmp_path: Path) -> None:
    fake_bin, docker_log = _make_fake_bin(tmp_path)
    env_file, image_env_file = _write_runtime_envs(tmp_path)
    output_dir = tmp_path / "dist"

    result = subprocess.run(
        [
            "bash",
            str(BUILD_SCRIPT),
            "--env-file",
            str(env_file),
            "--image-env-file",
            str(image_env_file),
            "--output",
            str(output_dir),
        ],
        cwd=REPO_ROOT,
        env=_base_env(fake_bin, docker_log),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    archive_path = output_dir / "dify-offline-deadbee-testtag.tar.gz"
    assert archive_path.exists()

    with tarfile.open(archive_path, "r:gz") as archive:
        names = archive.getnames()
        assert "dify-offline-deadbee-testtag/manifest/images.txt" in names
        assert "dify-offline-deadbee-testtag/manifest/package-info.txt" in names
        assert "dify-offline-deadbee-testtag/scripts/install-offline.sh" in names
        assert "dify-offline-deadbee-testtag/scripts/verify-offline.sh" in names
        assert "dify-offline-deadbee-testtag/docker/volumes/sandbox/conf/config.yaml" in names
        images_member = archive.extractfile("dify-offline-deadbee-testtag/manifest/images.txt")
        assert images_member is not None
        images_text = images_member.read().decode("utf-8")
        assert images_text.splitlines() == [
            "local/dify-api:testtag",
            "local/dify-web:testtag",
            "postgres:15-alpine",
            "redis:6-alpine",
        ]

    docker_commands = docker_log.read_text(encoding="utf-8")
    assert "build --build-arg COMMIT_SHA=deadbee -t local/dify-api:testtag" in docker_commands
    assert "build --build-arg COMMIT_SHA=deadbee -t local/dify-web:testtag" in docker_commands
    assert "compose --env-file" in docker_commands
    assert "config --images" in docker_commands
    assert "save -o" in docker_commands


def test_install_script_copies_image_env_and_starts_stack(tmp_path: Path) -> None:
    fake_bin, docker_log = _make_fake_bin(tmp_path)
    package_root = tmp_path / "package"
    docker_dir = package_root / "docker"
    images_dir = package_root / "images"
    docker_dir.mkdir(parents=True)
    images_dir.mkdir()

    (docker_dir / ".env").write_text("DB_TYPE=postgresql\nVECTOR_STORE=weaviate\n", encoding="utf-8")
    (docker_dir / ".env.local-images.example").write_text(
        "DOCKER_REGISTRY=local\nIMAGE_TAG=testtag\nAPI_IMAGE_NAME=dify-api\nWEB_IMAGE_NAME=dify-web\n",
        encoding="utf-8",
    )
    (docker_dir / "docker-compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (docker_dir / "docker-compose.local-images.yaml").write_text("services: {}\n", encoding="utf-8")
    (images_dir / "images.tar").write_text("placeholder", encoding="utf-8")

    result = subprocess.run(
        ["bash", str(INSTALL_SCRIPT), "--package-root", str(package_root)],
        cwd=REPO_ROOT,
        env=_base_env(fake_bin, docker_log),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert (docker_dir / ".env.local-images").read_text(encoding="utf-8") == (
        docker_dir / ".env.local-images.example"
    ).read_text(encoding="utf-8")

    docker_commands = docker_log.read_text(encoding="utf-8")
    assert f"load -i {images_dir / 'images.tar'}" in docker_commands
    assert "compose -p dify-offline" in docker_commands
    assert "up -d" in docker_commands


def test_verify_script_runs_compose_checks(tmp_path: Path) -> None:
    fake_bin, docker_log = _make_fake_bin(tmp_path)
    package_root = tmp_path / "package"
    docker_dir = package_root / "docker"
    docker_dir.mkdir(parents=True)

    (docker_dir / ".env").write_text("DB_TYPE=postgresql\nVECTOR_STORE=weaviate\n", encoding="utf-8")
    (docker_dir / ".env.local-images").write_text(
        "DOCKER_REGISTRY=local\nIMAGE_TAG=testtag\nAPI_IMAGE_NAME=dify-api\nWEB_IMAGE_NAME=dify-web\n",
        encoding="utf-8",
    )
    (docker_dir / "docker-compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (docker_dir / "docker-compose.local-images.yaml").write_text("services: {}\n", encoding="utf-8")

    result = subprocess.run(
        ["bash", str(VERIFY_SCRIPT), "--package-root", str(package_root)],
        cwd=REPO_ROOT,
        env=_base_env(fake_bin, docker_log),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    docker_commands = docker_log.read_text(encoding="utf-8")
    assert "compose -p dify-offline" in docker_commands
    assert " ps" in docker_commands
    assert " images" in docker_commands
    assert "exec api env" in docker_commands
