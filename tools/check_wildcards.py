"""Sanity-check the two-pointer glob that SettingsStore.ruleMatches runs.

The algorithm is transliterated one to one from
`entry/src/main/ets/service/SettingsStore.ets` so a logic slip shows up here
before it reaches a device.
"""

CASES = [
    # pattern, value, wildcards, expected
    ('Xiaomi*', 'Xiaomi_90FA_5G_Game', True, True),
    ('Xiaomi*', 'Xiaomi_90FA_5G_Game', False, False),
    ('Xiaomi_90FA_5G_Game', 'Xiaomi_90FA_5G_Game', False, True),
    ('Xiaomi_90FA_5G_Game', 'Xiaomi_90FA_5G_Game', True, True),
    ('*', 'anything', True, True),
    ('*Guest*', 'Home_Guest_5G', True, True),
    ('Home*Guest', 'Home_Guest', True, True),
    ('Home*Guest', 'Home_Guest_5G', True, False),
    ('Xiaomi?', 'Xiaomi9', True, True),
    ('Xiaomi?', 'Xiaomi90', True, False),
    ('*', '', True, True),
    ('Office', 'Home', True, False),
    ('a*b*c', 'aXbYc', True, True),
    ('a*b*c', 'aXbY', True, False),
    ('Mi*', 'Xiaomi_5G', True, False),
]


def glob(pattern: str, value: str) -> bool:
    p = 0
    v = 0
    star = -1
    mark = 0
    while v < len(value):
        if p < len(pattern) and (pattern[p] == '?' or pattern[p] == value[v]):
            p += 1
            v += 1
        elif p < len(pattern) and pattern[p] == '*':
            star = p
            mark = v
            p += 1
        elif star >= 0:
            p = star + 1
            mark += 1
            v = mark
        else:
            return False
    while p < len(pattern) and pattern[p] == '*':
        p += 1
    return p == len(pattern)


def rule_matches(pattern: str, value: str, wildcards: bool) -> bool:
    has_wildcard = '*' in pattern or '?' in pattern
    if not wildcards or not has_wildcard:
        return pattern == value
    return glob(pattern, value)


failures = 0
for pattern, value, wildcards, expected in CASES:
    got = rule_matches(pattern, value, wildcards)
    if got != expected:
        failures += 1
        print(f'FAIL {pattern!r} vs {value!r} (wildcards={wildcards}) -> {got}, want {expected}')
print(f'{len(CASES)} checks, {failures} failures')
