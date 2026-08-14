#!/usr/bin/env python3
"""Idempotent Hermes configuration helpers shared by shell and PowerShell."""

from __future__ import annotations

import argparse
import copy
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import yaml


OCTER_NAME = "Octer"
OCTER_PROVIDER = "custom:octer"
OCTER_KEY_ENV = "OCTER_LLM_API_KEY"
OCTER_API_MODE = "codex_responses"
_OCTER_ALIASES = {"octer", "custom:octer"}
_API_KEY_RE = re.compile(r"evo_[A-Za-z0-9]{26,}")


def _identity(value: Any) -> str:
    return str(value or "").strip().lower().replace(" ", "-")


def _is_octer_entry(entry: Any, provider_key: str = "") -> bool:
    if not isinstance(entry, dict):
        return False
    identities = {
        _identity(provider_key),
        _identity(entry.get("name")),
        _identity(entry.get("provider_key")),
    }
    return bool(identities & _OCTER_ALIASES)


def normalize_base_url(raw: str) -> str:
    value = str(raw or "").strip().rstrip("/")
    if not value:
        raise ValueError("base URL is empty")
    parts = urlsplit(value)
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        raise ValueError("base URL must be an absolute http(s) URL")
    if parts.query or parts.fragment:
        raise ValueError("base URL must not contain a query string or fragment")

    path = parts.path.rstrip("/")
    if path.endswith("/chat/completions"):
        path = path[: -len("/chat/completions")]
    if parts.hostname in {"oclaw.octer.ai", "test.octer.ai"} and not path:
        path = "/v1"
    return urlunsplit((parts.scheme, parts.netloc, path, "", "")).rstrip("/")


def configure_data(
    config: dict[str, Any], *, base_url: str, model: str, models: list[str], max_tokens: int
) -> dict[str, Any]:
    config = copy.deepcopy(config)
    base_url = normalize_base_url(base_url)
    selected_model = str(model or "").strip()
    if not selected_model:
        raise ValueError("model is empty")

    model_ids = []
    for item in [*models, selected_model]:
        item = str(item or "").strip()
        if item and item not in model_ids:
            model_ids.append(item)

    providers = config.get("custom_providers")
    if not isinstance(providers, list):
        providers = []

    merged_models: dict[str, Any] = {}
    first_octer_index: int | None = None
    kept_providers: list[Any] = []
    for entry in providers:
        if _is_octer_entry(entry):
            if first_octer_index is None:
                first_octer_index = len(kept_providers)
            old_models = entry.get("models") if isinstance(entry, dict) else None
            if isinstance(old_models, dict):
                merged_models.update(copy.deepcopy(old_models))
            continue
        kept_providers.append(entry)

    for model_id in model_ids:
        metadata = merged_models.get(model_id)
        merged_models[model_id] = metadata if isinstance(metadata, dict) else {}

    canonical = {
        "name": OCTER_NAME,
        "base_url": base_url,
        "key_env": OCTER_KEY_ENV,
        "model": selected_model,
        "api_mode": OCTER_API_MODE,
        "models": merged_models,
        "discover_models": False,
    }
    insert_at = first_octer_index if first_octer_index is not None else len(kept_providers)
    kept_providers.insert(insert_at, canonical)
    config["custom_providers"] = kept_providers

    keyed_providers = config.get("providers")
    if isinstance(keyed_providers, dict):
        config["providers"] = {
            key: entry
            for key, entry in keyed_providers.items()
            if not _is_octer_entry(entry, str(key))
        }

    active = config.get("model")
    if not isinstance(active, dict):
        active = {}
    active.update(
        {
            "provider": OCTER_PROVIDER,
            "base_url": base_url,
            "default": selected_model,
            "max_tokens": int(max_tokens),
            "api_mode": OCTER_API_MODE,
        }
    )
    active.pop("api_key", None)
    active.pop("custom_provider_id", None)
    config["model"] = active
    return config


def clear_data(config: dict[str, Any]) -> dict[str, Any]:
    config = copy.deepcopy(config)

    active = config.get("model")
    if isinstance(active, dict):
        provider = _identity(active.get("provider"))
        base_url = str(active.get("base_url") or "").lower()
        if provider in _OCTER_ALIASES or "octer" in base_url:
            for key in (
                "provider",
                "base_url",
                "default",
                "model",
                "max_tokens",
                "api_key",
                "api_mode",
                "custom_provider_id",
            ):
                active.pop(key, None)
        if not active:
            config.pop("model", None)

    providers = config.get("custom_providers")
    if isinstance(providers, list):
        kept = [entry for entry in providers if not _is_octer_entry(entry)]
        if kept:
            config["custom_providers"] = kept
        else:
            config.pop("custom_providers", None)

    keyed_providers = config.get("providers")
    if isinstance(keyed_providers, dict):
        kept = {
            key: entry
            for key, entry in keyed_providers.items()
            if not _is_octer_entry(entry, str(key))
        }
        if kept:
            config["providers"] = kept
        else:
            config.pop("providers", None)

    return config


def _backup(path: Path) -> Path | None:
    if not path.exists():
        return None
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    target = path.with_name(f"{path.name}.bak.{stamp}")
    shutil.copy2(path, target)
    return target


def _atomic_write(path: Path, content: str, *, default_mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode if path.exists() else default_mode
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    os.chmod(temp_path, mode)
    os.replace(temp_path, path)


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError("Hermes config root must be a mapping")
    return data


def _write_yaml(path: Path, data: dict[str, Any]) -> None:
    rendered = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
    _atomic_write(path, rendered, default_mode=0o600)


def _set_env_key(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    prefix = f"{key}="
    kept = [line for line in lines if not line.startswith(prefix)]
    kept.append(f"{key}={value}")
    _atomic_write(path, "\n".join(kept) + "\n", default_mode=0o600)
    os.chmod(path, 0o600)


def _remove_env_key(path: Path, key: str) -> None:
    if not path.exists():
        return
    prefix = f"{key}="
    lines = [
        line for line in path.read_text(encoding="utf-8").splitlines() if not line.startswith(prefix)
    ]
    _atomic_write(path, ("\n".join(lines) + "\n") if lines else "", default_mode=0o600)
    os.chmod(path, 0o600)


def configure_files(args: argparse.Namespace) -> int:
    api_key = sys.stdin.read().strip()
    if not _API_KEY_RE.fullmatch(api_key):
        print("ERROR: API key must start with evo_ and contain at least 30 characters", file=sys.stderr)
        return 2

    config_path = Path(args.config).expanduser()
    env_path = Path(args.env).expanduser()
    data = configure_data(
        _load_yaml(config_path),
        base_url=args.base_url,
        model=args.model,
        models=[item for item in args.models_csv.split(",") if item],
        max_tokens=args.max_tokens,
    )
    config_backup = _backup(config_path)
    env_backup = _backup(env_path)
    _set_env_key(env_path, OCTER_KEY_ENV, api_key)
    _write_yaml(config_path, data)
    print(f"OK: configured one {OCTER_PROVIDER} provider at {normalize_base_url(args.base_url)}")
    if config_backup:
        print(f"Config backup: {config_backup}")
    if env_backup:
        print(f"Env backup: {env_backup}")
    return 0


def clear_files(args: argparse.Namespace) -> int:
    config_path = Path(args.config).expanduser()
    env_path = Path(args.env).expanduser()
    data = clear_data(_load_yaml(config_path))
    config_backup = _backup(config_path)
    env_backup = _backup(env_path)
    _write_yaml(config_path, data)
    _remove_env_key(env_path, OCTER_KEY_ENV)
    print("OK: removed Octer model/provider configuration")
    if config_backup:
        print(f"Config backup: {config_backup}")
    if env_backup:
        print(f"Env backup: {env_backup}")
    return 0


def self_test(args: argparse.Namespace) -> int:
    try:
        result = subprocess.run(
            [args.hermes_bin, "-z", args.prompt],
            text=True,
            capture_output=True,
            timeout=args.timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        if exc.stdout:
            print(exc.stdout, end="")
        if exc.stderr:
            print(exc.stderr, end="", file=sys.stderr)
        print(f"ERROR: Hermes self-test timed out after {args.timeout}s", file=sys.stderr)
        return 124
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode:
        print(f"ERROR: Hermes self-test exited with {result.returncode}", file=sys.stderr)
    return result.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("--config", required=True)
    set_parser.add_argument("--env", required=True)
    set_parser.add_argument("--base-url", required=True)
    set_parser.add_argument("--model", required=True)
    set_parser.add_argument("--models-csv", required=True)
    set_parser.add_argument("--max-tokens", type=int, default=65536)
    set_parser.set_defaults(func=configure_files)

    clear_parser = subparsers.add_parser("clear")
    clear_parser.add_argument("--config", required=True)
    clear_parser.add_argument("--env", required=True)
    clear_parser.set_defaults(func=clear_files)

    test_parser = subparsers.add_parser("self-test")
    test_parser.add_argument("--hermes-bin", required=True)
    test_parser.add_argument("--timeout", type=int, default=60)
    test_parser.add_argument("--prompt", default="请只回复 OK")
    test_parser.set_defaults(func=self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.func(args))
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
