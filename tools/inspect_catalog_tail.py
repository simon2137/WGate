import pathlib

t = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets').read_text(encoding='utf-8')
marker = "['zh_CN', '"
at = t.find(marker) + len(marker)
end = t.find("'],", at)
payload = t[at:end]
print('rows:', payload.count('\x01'))
print('ends with separator:', payload.endswith('\x01'))
print('tail:', repr(payload[-160:]))
