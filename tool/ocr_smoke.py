"""Offline native-model smoke check: python3 tool/ocr_smoke.py (Tesseract 4+)."""
from pathlib import Path
import subprocess
import re

root = Path(__file__).resolve().parents[1]
for language in ('greek', 'english'):
    result = subprocess.run([
        'tesseract', str(root / f'test/fixtures/receipts/{language}.png'), 'stdout',
        '--tessdata-dir', str(root / 'assets/tessdata'), '-l', 'ell+eng', '--psm', '6',
    ], check=True, capture_output=True, text=True).stdout
    assert re.search(r'4[.,]30', result), (language, result)
    assert '16/10/2026' in result, (language, result)
    if language == 'greek':
        assert re.search('[Α-Ωα-ω]', result), result
    print(f'{language}: bundled ell+eng models recognized date, amount and script')
