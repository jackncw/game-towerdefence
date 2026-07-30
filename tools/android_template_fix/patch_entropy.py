"""Repoint mbedtls_platform_dev_random from /dev/random to /dev/urandom
inside libgodot_android.so (Godot Android export template).

Strategy:
 1. Find file offsets of the NUL-terminated strings "/dev/random" and
    "/dev/urandom"; map them to virtual addresses via PT_LOAD segments.
 2. Find every reference to vaddr("/dev/random"):
    a. RELA relocations (R_AARCH64_RELATIVE) whose addend == vaddr
    b. raw 8-byte little-endian words in the file equal to vaddr
       (covers RELR relocations, whose addend is stored in place)
 3. Rewrite them to vaddr("/dev/urandom").
Prints what it did; exits nonzero if no reference was found.
"""
import struct
import sys

from elftools.elf.elffile import ELFFile

path = sys.argv[1]
data = bytearray(open(path, "rb").read())


def find_string(blob: bytes, s: bytes):
    """Return offsets of exact NUL-terminated string (preceded by NUL)."""
    hits = []
    start = 0
    needle = s + b"\x00"
    while True:
        i = blob.find(needle, start)
        if i < 0:
            break
        if i == 0 or blob[i - 1] == 0:
            hits.append(i)
        start = i + 1
    return hits


with open(path, "rb") as f:
    elf = ELFFile(f)
    segs = [
        (s["p_offset"], s["p_filesz"], s["p_vaddr"])
        for s in elf.iter_segments()
        if s["p_type"] == "PT_LOAD"
    ]

    def off2va(off):
        for o, fsz, va in segs:
            if o <= off < o + fsz:
                return va + (off - o)
        return None

    def va2off(va):
        for o, fsz, seg_va in segs:
            if seg_va <= va < seg_va + fsz:
                return o + (va - seg_va)
        return None

    rnd_offs = find_string(data, b"/dev/random")
    urnd_offs = find_string(data, b"/dev/urandom")
    print("string offsets /dev/random:", rnd_offs, "/dev/urandom:", urnd_offs)
    if not rnd_offs or not urnd_offs:
        sys.exit("strings not found")
    rnd_va = off2va(rnd_offs[0])
    urnd_va = off2va(urnd_offs[0])
    print(f"vaddr /dev/random=0x{rnd_va:x} /dev/urandom=0x{urnd_va:x}")

    patched = 0

    # a) RELA relocations with matching addend
    for secname in (".rela.dyn", ".rela.plt"):
        sec = elf.get_section_by_name(secname)
        if sec is None:
            continue
        ent = sec["sh_entsize"]
        base = sec["sh_offset"]
        for i in range(sec.num_relocations()):
            r = sec.get_relocation(i)
            if r["r_addend"] == rnd_va:
                aoff = base + i * ent + 16  # r_offset(8) + r_info(8) -> addend
                data[aoff : aoff + 8] = struct.pack("<q", urnd_va)
                patched += 1
                print(f"patched RELA addend @file 0x{aoff:x} (r_offset 0x{r['r_offset']:x})")

# b) raw in-place pointer words (RELR-style)
needle = struct.pack("<Q", rnd_va)
start = 0
while True:
    i = data.find(needle, start)
    if i < 0:
        break
    va = None
    for o, fsz, seg_va in segs:
        if o <= i < o + fsz:
            va = seg_va + (i - o)
            break
    data[i : i + 8] = struct.pack("<Q", urnd_va)
    patched += 1
    print(f"patched raw pointer @file 0x{i:x} (vaddr 0x{va:x})" if va else f"patched raw pointer @file 0x{i:x}")
    start = i + 8

print("total patched:", patched)
if patched == 0:
    sys.exit("no references found - string likely inlined; needs instruction patch")
open(path, "wb").write(data)
print("written", path)
