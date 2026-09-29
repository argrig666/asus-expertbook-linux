# Draft: libdisplay-info — out-of-bounds read and leak in DisplayID v2 data-block parsing

This is a memory-safety bug in a library that compositors run on EDIDs from
any connected display. This draft, with its reproducer, and the fixes in
`hdr-fix/patches/` have been public in this repository since 2026-09-28, so a
confidential report no longer buys anything: file it as a normal issue at
<https://gitlab.freedesktop.org/emersion/libdisplay-info/-/issues/new> or open
a merge request with the two patches, soon, and say that the details are
already public. The overread is one byte past a heap buffer on a crafted,
checksum-valid EDID, reached when a compositor parses a connected display.

Patches (apply with `git am -3` to main `62a9346`; all 69 tests pass):

- [`../hdr-fix/patches/0008-displayid2-don-t-read-past-the-section-after-an-over.patch`](../hdr-fix/patches/0008-displayid2-don-t-read-past-the-section-after-an-over.patch)
- [`../hdr-fix/patches/0009-displayid2-don-t-leak-data-blocks-when-parsing-fails.patch`](../hdr-fix/patches/0009-displayid2-don-t-leak-data-blocks-when-parsing-fails.patch)

---

**Title:** displayid2: out-of-bounds read after an oversized data block (and leak on parse failure)

Since 788c056 ("displayid2: decode data blocks structure"), a checksum-valid
EDID whose DisplayID v2 extension contains one data block with a length larger
than the rest of the section makes `di_info_parse_edid()` read past the end of
the EDID buffer. Reproduced on main `62a9346` with AddressSanitizer:

```
ERROR: AddressSanitizer: heap-buffer-overflow ... READ of size 1
```

Cause: `parse_data_block()` returns the declared block length on the "exceeds
the number of bytes remaining" path. `_di_displayid2_parse()` then advances `i`
past the end of the section, leaves the loop, and checks the padding at
`&data[i]` with `max_data_block_size` left over from the previous iteration.
The same stale length makes a section whose last block ends exactly at the
checksum report "Padding: Contains non-zero bytes." (the checksum byte is read
as padding); the `jdi-lpm135m467-edp` test expectation contains that false
failure, which edid-decode does not report.

Separately, when a CTA-861 data block fails to parse, `parse_data_block()`
frees the DisplayID data block but not the CTA data blocks already attached to
it, and when a data block fails `_di_displayid2_parse()` returns false while
`parse_ext()` frees the extension without `_di_displayid2_finish()`.

Minimal reproducer (256 bytes, hex; base block + DisplayID v2 extension with
one CTA-861 data block declaring 240 bytes in a 10-byte section):

```
00ffffffffffff00000000000000000000000104000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000100
70200a00008100f0000000000000006500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000090
```

`di-edid-decode` reads its input into a 32 KiB static buffer, so the overread
stays inside that buffer and ASan does not see it. Parse from an exact-size
heap allocation instead:

```c
/* repro.c: cc -fsanitize=address -Iinclude -Ibuild-asan/include repro.c \
 *   -Lbuild-asan -ldisplay-info -Wl,-rpath,build-asan */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libdisplay-info/info.h>
int main(int argc, char **argv) {
	unsigned char tmp[4096];
	FILE *f = fopen(argv[1], "rb");
	size_t n = fread(tmp, 1, sizeof(tmp), f);
	fclose(f);
	unsigned char *buf = malloc(n);
	memcpy(buf, tmp, n);
	struct di_info *info = di_info_parse_edid(buf, n);
	if (info)
		di_info_destroy(info);
	free(buf);
	return 0;
}
```

```sh
meson setup build-asan -Db_sanitize=address -Db_lundef=false && ninja -C build-asan
xxd -r -p repro.hex > repro.edid
./repro repro.edid
```

With the two patches, that input and 300,000 randomized checksum-valid DisplayID
v2 EDIDs parse under ASan/UBSan without an error; the patches also update the
`jdi-lpm135m467-edp` expectation accordingly.
