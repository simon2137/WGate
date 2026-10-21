"""Regenerate the two Material Symbols glyphs used by the Support page.

Both come from google/material-design-icons (Symbols, 960-unit canvas); the
mapping onto the classic 24 grid is done by tools/svg_symbols_to_24.py, which is
the project's single implementation of that projection. Run from the repo root.
"""
import pathlib
import subprocess
import sys

TOOL = pathlib.Path('tools/svg_symbols_to_24.py')
MEDIA = pathlib.Path('entry/src/main/resources/base/media')

QUESTION = (
    'M424-320q0-81 14.5-116.5T500-514q41-36 62.5-62.5T584-637q0-41-27.5-68'
    'T480-732q-51 0-77.5 31T365-638l-103-44q21-64 77-111t141-47q105 0 161.5 58.5'
    'T698-641q0 50-21.5 85.5T609-475q-49 47-59.5 71.5T539-320H424Zm56 240'
    'q-33 0-56.5-23.5T400-160q0-33 23.5-56.5T480-240q33 0 56.5 23.5T560-160'
    'q0 33-23.5 56.5T480-80Z'
)
BALANCE = (
    'M80-120v-80h360v-447q-26-9-45-28t-28-45H240l120 280q0 50-41 85t-99 35'
    'q-58 0-99-35t-41-85l120-280h-80v-80h247q12-35 43-57.5t70-22.5q39 0 70 22.5'
    't43 57.5h247v80h-80l120 280q0 50-41 85t-99 35q-58 0-99-35t-41-85l120-280'
    'H593q-9 26-28 45t-45 28v447h360v80H80Zm585-320h150l-75-174-75 174Z'
    'm-520 0h150l-75-174-75 174Zm335-280q17 0 28.5-11.5T520-760q0-17-11.5-28.5'
    'T480-800q-17 0-28.5 11.5T440-760q0 17 11.5 28.5T480-720Z'
)


def bake(path_data: str) -> str:
    out = subprocess.run([sys.executable, str(TOOL), path_data],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def document(path_data: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
            'viewBox="0 0 24 24"><path d="' + bake(path_data) +
            '" fill="#FF000000"/></svg>\n')


targets = {
    'ic_question.svg': QUESTION,
    'ic_question_filled.svg': QUESTION,
    'ic_balance.svg': BALANCE,
}
for name, data in targets.items():
    target = MEDIA / name
    before = target.read_text(encoding='utf-8') if target.exists() else ''
    after = document(data)
    target.write_text(after, encoding='utf-8')
    print(name, 'unchanged' if before.strip() == after.strip() else 'rewritten',
          len(after.encode('utf-8')), 'bytes')
