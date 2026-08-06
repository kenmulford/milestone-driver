# A sibling that shares the name stem, and is STILL SCANNED

The exclusion pattern is `.milestone-feeder/`, with the trailing slash. This
directory is `.milestone-feeder-archive/`, so it must NOT match: `-` (0x2D) sits
where the pattern requires `/` (0x2F). It also sorts BEFORE the excluded
directory under a byte sort, which is why it is the right guard to pin.

Grounded in `src/target.md (unique-anchor-alpha)`.
