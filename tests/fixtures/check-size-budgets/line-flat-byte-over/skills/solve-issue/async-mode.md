# async-mode (size-budget fixture)

Throwaway filler for the check-size-budgets golden matrix. The words carry no meaning of their own; only this file's
line count and byte count are asserted, and both are pinned on purpose. It stands at 40 lines against the 40-line
ceiling for this governed path, and at exactly 4500 bytes against its 4500-byte ceiling. Sitting AT both ceilings is
what proves the checker compares with "greater than" and not "greater than or equal to", on each axis independently.

## What the sibling fixture proves

tests/fixtures/check-size-budgets/line-flat-byte-over/ is a copy of this whole tree with one sentence appended to the
end of an existing line further down. Its line count is identical, still 40, so a line-only ratchet reads no movement
at all and exits 0 with an all-OK stream. Its byte count is over 4500, so the byte ceiling fails it and names the
file. That pair is issue #399 reproduced in miniature: the growth a line count cannot see, and the count that sees it.

The shape is not hypothetical. PR #398 appended 1052 bytes to skills/solve-milestone/SKILL.md at a flat 664 lines and
the ratchet reported no change, and three later merges in the same milestone added another 3818 bytes the same way.

## Why a byte count and not a character count

A 🔴 marker sits in this sentence deliberately. It is an astral character: 4 bytes in UTF-8, 1 character to a
UTF-8-aware counter, and 2 UTF-16 code units to a naive .NET .Length. A character ceiling would therefore read
differently on the bash side than on the pwsh side for this very file, which is why the ratchet governs bytes. Both
twins read the same bytes off disk, so both report 4500 here and neither needs a locale to do it.

## Why the line ceiling holds at 40 while the byte ceiling drops to 4500

Five percent of a 33-line file is 2 lines, which an ordinary three-line bullet breaks while the file still sits
hundreds of bytes under its byte ceiling. The line axis therefore floors at `actual + 5`, which is why 40 holds.

## The line the sibling appends to

Prose appended to the tail of an existing line is the exact growth shape the ratchet could not see before the byte
ceiling landed, so the sibling fixture appends to the end of this very line to reproduce it. Appending here adds bytes and no line at all, so the line-only ratchet stays silent while the file grows.

## Padding

Everything below is filler that exists only to carry this file to its pinned counts. Editing any line above without
adjusting the padding line at the bottom will move the byte total and break the goldens, which is intended: the
fixture is sensitive to bytes. Regenerate the goldens deliberately, never incidentally, and record the reason.
<!-- padding, sized so this fixture lands on exactly 4500 bytes: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->
