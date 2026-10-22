import pathlib
import plistlib
import struct
import sys

app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundlePackageType'] == 'APPL'
assert info['UIDeviceFamily'] == [1, 2]
binary = app / info['CFBundleExecutable']
header = binary.read_bytes()[:32]
assert len(header) == 32
magic, cpu, subtype, filetype, *_ = struct.unpack('<8I', header)
assert magic == 0xFEEDFACF, 'Expected a 64-bit Mach-O executable'
assert cpu == 0x0100000C, 'Expected arm64 device executable, not simulator'
assert filetype == 2, 'Expected MH_EXECUTE'
assert binary.stat().st_size > 10_000
assert not (app / 'embedded.mobileprovision').exists()
print('PASS arm64 iOS executable, app plist and unsigned packaging')
