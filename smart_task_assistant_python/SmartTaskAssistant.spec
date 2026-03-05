# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(['main.py'],
             pathex=[],
             binaries=[],
             datas=[('ui', 'ui'), ('core', 'core')],
             hiddenimports=['PyQt5', 'requests'],
             hookspath=[],
             hooksconfig={},
             runtime_hooks=[],
             excludes=[],
             win_no_prefer_redirects=False,
             runtime_tmpdir=None,
             console=False,
             disable_windowed_traceback=False,
             argv_emulation=False,
             target_arch=None,
             codesign_identity=None,
             entitlements_file=None)

pyz = PYZ(a.pure)

exe = EXE(pyz,
          a.scripts,
          a.binaries,
          a.datas,
          [],
          name='SmartTaskAssistant',
          debug=False,
          bootloader_ignore_signals=False,
          strip=False,
          upx_dir=False,
          runtime_tmpdir=None,
          console=False,
          disable_windowed_traceback=False,
          argv_emulation=False,
          target_arch=None,
          codesign_identity=None,
          entitlements_file=None)

coll = COLLECT(exe,
               a.binaries,
               a.datas,
               strip=False,
               name='SmartTaskAssistant')
