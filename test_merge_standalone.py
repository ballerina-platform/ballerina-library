"""Standalone test to verify three_way_merge logic without package imports."""
import difflib
from typing import List, Tuple


def three_way_merge(a_lines: List[str], b_lines: List[str], c_lines: List[str]) -> Tuple[List[str], bool]:
    """Perform a line-based three-way merge of A (base), B (current/user),
    and C (new/generated).

    Returns a tuple (merged_lines, has_conflicts).
    """
    sm_b = difflib.SequenceMatcher(a=a_lines, b=b_lines)
    sm_c = difflib.SequenceMatcher(a=a_lines, b=c_lines)

    opcodes_b = sm_b.get_opcodes()
    opcodes_c = sm_c.get_opcodes()

    def build_hunks(opcodes):
        hunks = []
        for tag, a0, a1, b0, b1 in opcodes:
            hunks.append((a0, a1, tag, b0, b1))
        return hunks

    hunks_b = build_hunks(opcodes_b)
    hunks_c = build_hunks(opcodes_c)

    ai = 0
    ib = 0
    ic = 0
    merged: List[str] = []
    has_conflict = False

    def peek(hunks, idx):
        return hunks[idx] if idx < len(hunks) else None

    while ai < len(a_lines):
        hb = peek(hunks_b, ib)
        hc = peek(hunks_c, ic)

        a_next_change = min(
            hb[0] if hb else len(a_lines),
            hc[0] if hc else len(a_lines)
        )

        # Output unchanged lines up to the next change
        while ai < a_next_change:
            merged.append(a_lines[ai])
            ai += 1

        if hb and hb[0] == ai and hc and hc[0] == ai:
            _, a1_b, tag_b, b0, b1 = hb
            _, a1_c, tag_c, c0, c1 = hc

            b_chunk = b_lines[b0:b1]
            c_chunk = c_lines[c0:c1]

            # Advance only to the end of the region both hunks cover
            a_end = min(a1_b, a1_c) if a1_b > ai and a1_c > ai else max(a1_b, a1_c)

            if tag_b == 'equal' and tag_c == 'equal':
                # both equal -> output the base lines
                while ai < a_end:
                    merged.append(a_lines[ai])
                    ai += 1
            elif tag_b == 'equal' and tag_c != 'equal':
                # C changed, B didn't -> take C's portion
                for i in range(c0, c0 + (a_end - hb[0])):
                    if i < len(c_lines):
                        merged.append(c_lines[i])
                ai = a_end
            elif tag_b != 'equal' and tag_c == 'equal':
                # B changed, C didn't -> take B's portion
                for i in range(b0, b0 + (a_end - hc[0])):
                    if i < len(b_lines):
                        merged.append(b_lines[i])
                ai = a_end
            else:
                # Both changed
                if b_chunk == c_chunk:
                    merged.extend(b_chunk)
                else:
                    has_conflict = True
                    merged.append('<<<<<<< CURRENT\n')
                    merged.extend(b_chunk)
                    merged.append('=======\n')
                    merged.extend(c_chunk)
                    merged.append('>>>>>>> GENERATED\n')
                ai = max(a1_b, a1_c)

            # Only advance past the hunks if we consumed them fully
            if ai >= a1_b:
                ib += 1
            if ai >= a1_c:
                ic += 1
            continue

        if hb and hb[0] == ai:
            _, a1_b, tag_b, b0, b1 = hb
            b_chunk = b_lines[b0:b1]
            if tag_b != 'equal':
                merged.extend(b_chunk)
            else:
                while ai < a1_b:
                    merged.append(a_lines[ai])
                    ai += 1
            ai = a1_b
            ib += 1
            continue

        if hc and hc[0] == ai:
            _, a1_c, tag_c, c0, c1 = hc
            c_chunk = c_lines[c0:c1]
            if tag_c != 'equal':
                merged.extend(c_chunk)
            else:
                while ai < a1_c:
                    merged.append(a_lines[ai])
                    ai += 1
            ai = a1_c
            ic += 1
            continue

        if not hb and not hc:
            while ai < len(a_lines):
                merged.append(a_lines[ai])
                ai += 1

    hb = peek(hunks_b, ib)
    while hb:
        a0, a1, tag_b, b0, b1 = hb
        if a0 == len(a_lines):
            if tag_b != 'equal':
                merged.extend(b_lines[b0:b1])
        ib += 1
        hb = peek(hunks_b, ib)

    hc = peek(hunks_c, ic)
    while hc:
        a0, a1, tag_c, c0, c1 = hc
        if a0 == len(a_lines):
            if tag_c != 'equal':
                merged.extend(c_lines[c0:c1])
        ic += 1
        hc = peek(hunks_c, ic)

    return merged, has_conflict


# Test cases
def test_no_change():
    a = ['line1\n', 'line2\n']
    b = ['line1\n', 'line2\n']
    c = ['line1\n', 'line2\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts"
    print(f"DEBUG: a={a}")
    print(f"DEBUG: merged={merged}")
    assert merged == a, f"Merged should equal base when nothing changed. Got {merged}, expected {a}"
    print("✓ test_no_change PASSED")


def test_user_only_change():
    a = ['a\n', 'b\n']
    b = ['a modified\n', 'b\n']
    c = ['a\n', 'b\n']
    
    # Debug opcodes
    import difflib
    sm_b = difflib.SequenceMatcher(a=a, b=b)
    sm_c = difflib.SequenceMatcher(a=a, b=c)
    print(f"DEBUG opcodes B: {sm_b.get_opcodes()}")
    print(f"DEBUG opcodes C: {sm_c.get_opcodes()}")
    
    merged, conflicts = three_way_merge(a, b, c)
    print(f"DEBUG: b={b}")
    print(f"DEBUG: merged={merged}")
    assert not conflicts, "Should have no conflicts"
    assert merged == b, f"Should preserve user changes. Got {merged}, expected {b}"
    print("✓ test_user_only_change PASSED")


def test_generated_only_change():
    a = ['a\n', 'b\n']
    b = ['a\n', 'b\n']
    c = ['a changed\n', 'b\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts"
    assert merged == c, "Should apply generated changes"
    print("✓ test_generated_only_change PASSED")


def test_nonconflicting_both_change():
    a = ['l1\n', 'l2\n', 'l3\n']
    b = ['l1\n', 'l2 modified\n', 'l3\n']
    c = ['l1\n', 'l2\n', 'l3 new\n']
    
    # Debug opcodes
    import difflib
    sm_b = difflib.SequenceMatcher(a=a, b=b)
    sm_c = difflib.SequenceMatcher(a=a, b=c)
    print(f"DEBUG opcodes B: {sm_b.get_opcodes()}")
    print(f"DEBUG opcodes C: {sm_c.get_opcodes()}")
    
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts for non-overlapping edits"
    expected = ['l1\n', 'l2 modified\n', 'l3 new\n']
    print(f"DEBUG: merged={merged}")
    assert merged == expected, f"Expected {expected}, got {merged}"
    print("✓ test_nonconflicting_both_change PASSED")


def test_conflict():
    a = ['x\n']
    b = ['user edit\n']
    c = ['generated edit\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert conflicts, "Should have conflicts"
    assert '<<<<<<< CURRENT\n' in merged, "Should have conflict marker"
    assert '=======\n' in merged, "Should have separator"
    assert '>>>>>>> GENERATED\n' in merged, "Should have end marker"
    print("✓ test_conflict PASSED")


if __name__ == '__main__':
    print("Running three_way_merge tests...\n")
    try:
        test_no_change()
        test_user_only_change()
        test_generated_only_change()
        test_nonconflicting_both_change()
        test_conflict()
        print("\n✅ All tests PASSED")
    except AssertionError as e:
        print(f"\n❌ Test FAILED: {e}")
        raise SystemExit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        raise SystemExit(1)
