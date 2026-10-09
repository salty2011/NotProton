#!/usr/bin/env python3
"""Reuse NotProton's Steam export forwarding in a source-built Wine loader.

Only modifies the specified disposable Wine source tree. It is not a game patch.
The normal packaged Sikarugir runner continues to use its verified PE detours.
"""
from pathlib import Path
import re
import sys

repo = Path(__file__).resolve().parent.parent
wine = Path(sys.argv[1]).resolve()
loader = wine / 'dlls/ntdll/loader.c'
source = loader.read_text()
marker = '#include "notproton_steam.h"'
if marker in source:
    raise SystemExit('Steam source hook is already present; use a clean source tree')

def adapt(bits):
    text = (repo / 'ntdll-patch' / ('detour.c' if bits == 64 else 'detour32.c')).read_text()
    # Use this tree's actual loader fields, rather than a binary-layout assumption.
    replacements = {
        'WM_DLLBASE': '(((WINE_MODREF *)(wm))->ldr.DllBase)',
        'WM_FLAGS': '(&((WINE_MODREF *)(wm))->ldr.Flags)',
        'WM_BASENAME': '(((WINE_MODREF *)(wm))->ldr.BaseDllName.Buffer)',
        'WM_FULLNAME': '((const struct us *)&((WINE_MODREF *)(wm))->ldr.FullDllName)',
    }
    for name, value in replacements.items():
        text = re.sub(r'^#define ' + name + r'\(wm\).*$', '#define ' + name + '(wm) ' + value, text, flags=re.M)
    text = re.sub(r'^#define LDR_DONT_RESOLVE_REFS.*\n', '', text, flags=re.M)
    text = text.replace('find_named_export', 'np_find_named_export')
    text = text.replace('*(const u16 **)((u8 *)wm + 0x60)', '(const u16 *)((WINE_MODREF *)wm)->ldr.BaseDllName.Buffer')
    if bits == 32:
        text = re.sub(r'^#define ARG_FLAGS\(fp\).*$', '#define ARG_FLAGS(fp) (((struct np_load_args *)(fp))->flags)', text, flags=re.M)
        text = re.sub(r'^#define ARG_LOAD_PATH\(fp\).*$', '#define ARG_LOAD_PATH(fp) (((struct np_load_args *)(fp))->load_path)', text, flags=re.M)
        text = '#define FLAGS_BIT DONT_RESOLVE_DLL_REFERENCES\nstruct np_load_args { void *load_path; DWORD *flags; };\n' + text
        call = 'struct np_load_args args = {(void *)load_path, flags}; detour_build_module32(&c, wm, &args);'
        extra = ', (nt_openfile_t)NtOpenFile, (nt_readfile_t)NtReadFile, (nt_close_t)NtClose, 0'
    else:
        call = 'detour_build_module(&c, wm, (void *)load_path);'
        extra = ''
    text += '\nstatic void np_steam_hook(WINE_MODREF *wm, LPCWSTR load_path, DWORD *flags)\n{\n'
    text += '    struct ctx c = {(ldr_getdllhandle_t)LdrGetDllHandle, (ldr_loaddll_t)LdrLoadDll, (nt_protect_t)NtProtectVirtualMemory' + extra + '};\n'
    text += '    ' + call + '\n}\n'
    return text

header = '/* Generated from this repository\'s ntdll-patch helpers. */\n#if defined(__i386__)\n' + adapt(32)
header += '\n#elif defined(__x86_64__)\n' + adapt(64)
header += '\n#else\nstatic void np_steam_hook(WINE_MODREF *wm, LPCWSTR load_path, DWORD *flags) {}\n#endif\n'
(wine / 'dlls/ntdll/notproton_steam.h').write_text(header)
anchor = 'static NTSTATUS build_module( LPCWSTR load_path,'
if source.count(anchor) != 1:
    raise SystemExit('Unexpected Wine loader layout')
source = source.replace(anchor, marker + '\n\n' + anchor)
anchor = '    /* fixup imports */\n'
if source.count(anchor) != 1:
    raise SystemExit('Unexpected Wine import hook location')
source = source.replace(anchor, '    np_steam_hook(wm, load_path, &flags);\n\n' + anchor)
loader.write_text(source)
print('Prepared source Steam hook for 32-bit and 64-bit Wine')
