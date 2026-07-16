#!/usr/bin/env python3
"""Disassemble InfantryClass::MouseOverObject from gamemd.exe"""
import struct
import capstone

EXE_PATH = r"c:\Users\Vampire\Desktop\AGWar1.3.1\gamemd.exe"
IMAGE_BASE = 0x400000

# Function: InfantryClass::MouseOverObject
# Start VA: 0x51E3B0
# We want to see the flow from start to past our hook at 0x51EE62
START_VA = 0x51E3B0
END_VA = 0x51F200  # covers the full function

def rva_to_offset(rva, sections):
    for s in sections:
        if s['VA'] <= rva < s['VA'] + s['VSize']:
            return rva - s['VA'] + s['RawOffset']
    return None

def main():
    OUT_FILE = r"e:\WorkSpace\cncnet\Ra2.Vampire.Extend\disasm_full.txt"
    out = []
    with open(EXE_PATH, 'rb') as f:
        data = f.read()

    # Parse PE headers
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
        sections.append({'Name': name, 'VA': va, 'VSize': vsize, 'RawSize': rawsize, 'RawOffset': rawoffset})

    # Convert VA to RVA to file offset
    start_rva = START_VA - IMAGE_BASE
    end_rva = END_VA - IMAGE_BASE
    start_off = rva_to_offset(start_rva, sections)
    end_off = rva_to_offset(end_rva, sections)

    out.append(f"Disassembling {START_VA:08X} - {END_VA:08X}")
    out.append(f"RVA: {start_rva:08X} - {end_rva:08X}")
    out.append(f"File offset: {start_off:08X} - {end_off:08X}")
    out.append("=" * 80)

    code = data[start_off:end_off]

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True

    for insn in md.disasm(code, START_VA):
        addr = insn.address
        # Mark important addresses
        marker = ""
        if addr == 0x51EE62:
            marker = "  <<< HOOK 1: MouseOverObject (our hook)"
        elif addr == 0x51EEED:
            marker = "  <<< SkipToInfiltrationSetup target"
        elif addr == 0x51F0AF:
            marker = "  <<< 'grinding area' (non-attack branch)"
        elif addr == 0x51E4D9:
            marker = "  <<< engi enter to fix/takeover"
        elif addr == 0x51E7D1:
            marker = "  <<< VehicleThief steal"
        elif addr == 0x51EA06:
            marker = "  <<< C4 demo"
        elif addr == 0x51E3B0:
            marker = "  <<< FUNCTION START"

        bytes_hex = ' '.join(f'{b:02x}' for b in insn.bytes)
        out.append(f"  {addr:08X}: {bytes_hex:<20s} {insn.mnemonic:8s} {insn.op_str}{marker}")

    with open(OUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print(f"Written {len(out)} lines to {OUT_FILE}")

if __name__ == '__main__':
    main()
