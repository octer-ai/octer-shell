"""Exercise actual installer selection without calling a client or gateway."""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RETIREMENTS = {"gemini-3.1-pro-preview": "gpt-6.1-sol", "gemini-3-flash-preview": "gemini-3.8-flash"}


class RetiredModelSelection(unittest.TestCase):
    def test_bash_selection_migrates_legacy_ids_before_configuration(self):
        for filename in ("set-hermes-model.sh", "set-openclaw-model.sh"):
            source = (ROOT / filename).read_text().split('echo "→ 选定模型:', 1)[0]
            source += '\nprintf "RESULT:%s\\n" "$MODEL"\nprintf "MENU:%s\\n" "${MODELS[@]}"\n'
            for old, new in {**RETIREMENTS, "custom-active-model": "custom-active-model"}.items():
                with self.subTest(filename=filename, model=old):
                    result = subprocess.run(["bash", "-c", source, filename, "evo_" + "a" * 30, old], text=True, capture_output=True, check=True)
                    self.assertIn("RESULT:" + new, result.stdout.splitlines())
                    menu = [line[5:] for line in result.stdout.splitlines() if line.startswith("MENU:")]
                    self.assertTrue(set(RETIREMENTS).isdisjoint(menu))
                    self.assertTrue(set(RETIREMENTS.values()).issubset(menu))
                    self.assertEqual(len(menu), len(set(menu)))
