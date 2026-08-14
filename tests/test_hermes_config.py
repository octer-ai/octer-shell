import tempfile
import unittest
from pathlib import Path

import yaml

from hermes_config import (
    OCTER_API_MODE,
    OCTER_PROVIDER,
    clear_data,
    configure_data,
    normalize_base_url,
)


class HermesConfigTests(unittest.TestCase):
    def test_normalizes_octer_root_and_chat_endpoint(self):
        self.assertEqual(normalize_base_url("https://oclaw.octer.ai"), "https://oclaw.octer.ai/v1")
        self.assertEqual(
            normalize_base_url("https://oclaw.octer.ai/v1/chat/completions"),
            "https://oclaw.octer.ai/v1",
        )

    def test_rejects_non_http_url(self):
        with self.assertRaises(ValueError):
            normalize_base_url("oclaw.octer.ai/v1")

    def test_three_legacy_octer_entries_collapse_to_one(self):
        source = {
            "custom_providers": [
                {"name": "Octer", "base_url": "https://octer.ai/v1", "api_key": "old"},
                {"name": "Octer", "base_url": "https://oclaw.octer.ai/v1", "api_key": "old"},
                {"name": "Octer", "base_url": "https://oclaw.octer.ai", "api_key": "old"},
                {"name": "Keep Me", "base_url": "https://example.test/v1"},
            ],
            "model": {"provider": "custom", "api_key": "old"},
        }
        result = configure_data(
            source,
            base_url="https://oclaw.octer.ai/v1",
            model="gpt-5.5",
            models=["gpt-5.5", "claude-opus-4-8"],
            max_tokens=65536,
        )
        octer = [entry for entry in result["custom_providers"] if entry.get("name") == "Octer"]
        self.assertEqual(len(octer), 1)
        self.assertEqual(octer[0]["key_env"], "OCTER_LLM_API_KEY")
        self.assertNotIn("api_key", octer[0])
        self.assertEqual(octer[0]["api_mode"], OCTER_API_MODE)
        self.assertEqual(result["model"]["provider"], OCTER_PROVIDER)
        self.assertEqual(result["model"]["api_mode"], OCTER_API_MODE)
        self.assertNotIn("api_key", result["model"])
        self.assertTrue(any(entry.get("name") == "Keep Me" for entry in result["custom_providers"]))

    def test_keyed_octer_provider_is_removed_without_touching_others(self):
        source = {
            "providers": {
                "octer": {"name": "Octer", "base_url": "https://old.test/v1"},
                "other": {"name": "Other", "base_url": "https://other.test/v1"},
            }
        }
        result = configure_data(
            source,
            base_url="https://oclaw.octer.ai/v1",
            model="gpt-5.5",
            models=["gpt-5.5"],
            max_tokens=65536,
        )
        self.assertEqual(set(result["providers"]), {"other"})

    def test_clear_removes_list_and_keyed_forms(self):
        source = {
            "model": {
                "provider": "custom:octer",
                "base_url": "https://oclaw.octer.ai/v1",
                "api_mode": "codex_responses",
                "default": "gpt-5.5",
            },
            "custom_providers": [
                {"name": "Octer", "base_url": "https://oclaw.octer.ai/v1"},
                {"name": "Other", "base_url": "https://other.test/v1"},
            ],
            "providers": {"octer": {"name": "Octer"}, "other": {"name": "Other"}},
        }
        result = clear_data(source)
        self.assertNotIn("model", result)
        self.assertEqual([entry["name"] for entry in result["custom_providers"]], ["Other"])
        self.assertEqual(set(result["providers"]), {"other"})


if __name__ == "__main__":
    unittest.main()
