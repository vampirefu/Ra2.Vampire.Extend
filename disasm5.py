#!/usr/bin/env python3
"""Disassemble full BuildingClass::InfiltratedBy at 0x4571E0 - 0x4575B0"""
import struct
import capstone

EXE_PATH = r"c:\Users\Vampire\Desktop\AGWar1.3.1\gamemd.exe"
IMAGE_BASE = 0x400000


def rva_to_offset(rva, sections):
    for s in sections:
        if s['VA'] <= rva < s['VA'] + s['VSize']:
            return rva - s['VA'] + s['RawOffset']
    return None


def main():
    OUT_FILE = r"e:\WorkSpace\cncnet\Ra2.Vampire.Extend\disasm_infiltratedby_full.txt"
    out = []

    with open(EXE_PATH, 'rb') as f:
        data = f.read()

    pe_offset = struct.unpack_from('<I', data, 0x3C)[0]
    num_sections = struct.unpack_from('<H', data, pe_offset + 6)[0]
    opt_hdr_size = struct.unpack_from('<H', data, pe_offset + 0x14)[0]
    section_start = pe_offset + 0x18 + opt_hdr_size

    sections = []
    for i in range(num_sections):
        off = section_start + i * 40
        name = data[off:off+8].rstrip(b'\x00').decode('ascii', errors='replace')
        vsize = struct.unpack_from('<I', data, off + 8)[0]
        va = struct.unpack_from('<I', data, off + 12)[0]
        rawsize = struct.unpack_from('<I', data, off + 16)[0]
        rawoffset = struct.unpack_from('<I', data, off + 20)[0]
        sections.append({'Name': name, 'VA': va, 'VSize': vsize,
                         'RawSize': rawsize, 'RawOffset': rawoffset})

    start_va = 0x4571E0
    end_va = 0x4575B0  # full function range covering exit addrs 0x457590/0x45759f
    start_rva = start_va - IMAGE_BASE
    end_rva = end_va - IMAGE_BASE
    start_off = rva_to_offset(start_rva, sections)
    end_off = rva_to_offset(end_rva, sections)

    code = data[start_off:end_off]
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)

    out.append(f"\n{'='*60}")
    out.append(f"BuildingClass::InfiltratedBy FULL (0x{start_va:08X} - 0x{end_va:08X})")
    out.append(f"{'='*60}")
    for insn in md.disasm(code, start_va):
        bytes_hex = ' '.join(f'{b:02x}' for b in insn.bytes)
        out.append(f"  {insn.address:08X}: {bytes_hex:<24s} {insn.mnemonic:8s} {insn.op_str}")

    with open(OUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print(f"Written {len(out)} lines to {OUT_FILE}")


if __name__ == '__main__':
    main()
