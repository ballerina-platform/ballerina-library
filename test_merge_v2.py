"""Standalone test with simplified three-way merge."""
import difflib
from typing import List, Tuple


def three_way_merge(a_lines: List[str], b_lines: List[str], c_lines: List[str]) -> Tuple[List[str], bool]:
    """Simplified line-based three-way merge."""
    # Build lookup maps for each line in A to track what happened in B and C
    opcodes_b = difflib.SequenceMatcher(a=a_lines, b=b_lines).get_opcodes()
    opcodes_c = difflib.SequenceMatcher(a=a_lines, b=c_lines).get_opcodes()
    
    merged = []
    has_conflict = False
    ai = 0  # Current position in A
    
    # Process each opcode pair to build the merged result
    bi = 0
    ci = 0
    
    while ai < len(a_lines) or bi < len(opcodes_b) or ci < len(opcodes_c):
        # Get current opcodes for B and C
        op_b = opcodes_b[bi] if bi < len(opcodes_b) else None
        op_c = opcodes_c[ci] if ci < len(opcodes_c) else None
        
        # If both opcodes are done, we're done
        if op_b is None and op_c is None:
            break
            
        # Check if opcodes start at or before current AI position
        b_starts_here = op_b and op_b[1] <= ai < op_b[2]
        c_starts_here = op_c and op_c[1] <= ai < op_c[2]
        
        # Process based on what opcodes we have
        if b_starts_here and c_starts_here:
            # Both opcodes cover current position
            tag_b, a0_b, a1_b, b0_b, b1_b = op_b
            tag_c, a0_c, a1_c, c0_c, c1_c = op_c
            
            if tag_b == 'equal' and tag_c == 'equal':
                # Both unchanged - copy from A (just this one line at ai)
                merged.append(a_lines[ai])
                ai += 1
                if ai >= a1_b:
                    bi += 1
                if ai >= a1_c:
                    ci += 1
            elif tag_b != 'equal' and tag_c == 'equal':
                # Only B changed - take corresponding line from B
                b_offset = ai - a0_b
                merged.append(b_lines[b0_b + b_offset])
                ai += 1
                if ai >= a1_b:
                    bi += 1
                if ai >= a1_c:
                    ci += 1
            elif tag_b == 'equal' and tag_c != 'equal':
                # Only C changed - take corresponding line from C
                c_offset = ai - a0_c
                merged.append(c_lines[c0_c + c_offset])
                ai += 1
                if ai >= a1_b:
                    bi += 1
                if ai >= a1_c:
                    ci += 1
            else:
                # Both changed - check if same
                b_offset = ai - a0_b
                c_offset = ai - a0_c
                b_line = b_lines[b0_b + b_offset]
                c_line = c_lines[c0_c + c_offset]
                if b_line == c_line:
                    merged.append(b_line)
                else:
                    has_conflict = True
                    merged.append('<<<<<<< CURRENT\n')
                    merged.append(b_line)
                    merged.append('=======\n')
                    merged.append(c_line)
                    merged.append('>>>>>>> GENERATED\n')
                ai += 1
                if ai >= a1_b:
                    bi += 1
                if ai >= a1_c:
                    ci += 1
        elif b_starts_here:
            # Only B has an opcode at this position
            tag_b, a0_b, a1_b, b0_b, b1_b = op_b
            if tag_b == 'equal':
                merged.append(a_lines[ai])
            else:
                b_offset = ai - a0_b
                merged.append(b_lines[b0_b + b_offset])
            ai += 1
            if ai >= a1_b:
                bi += 1
        elif c_starts_here:
            # Only C has an opcode at this position
            tag_c, a0_c, a1_c, c0_c, c1_c = op_c
            if tag_c == 'equal':
                merged.append(a_lines[ai])
            else:
                c_offset = ai - a0_c
                merged.append(c_lines[c0_c + c_offset])
            ai += 1
            if ai >= a1_c:
                ci += 1
        else:
            # No opcode at current position - skip to next opcode
            next_b = op_b[1] if op_b else len(a_lines)
            next_c = op_c[1] if op_c else len(a_lines)
            next_ai = min(next_b, next_c)
            while ai < next_ai and ai < len(a_lines):
                merged.append(a_lines[ai])
                ai += 1
    
    return merged, has_conflict


# Test cases
def test_no_change():
    a = ['line1\n', 'line2\n']
    b = ['line1\n', 'line2\n']
    c = ['line1\n', 'line2\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts"
    assert merged == a, f"Merged should equal base when nothing changed. Got {merged}, expected {a}"
    print("✓ test_no_change PASSED")


def test_user_only_change():
    a = ['a\n', 'b\n']
    b = ['a modified\n', 'b\n']
    c = ['a\n', 'b\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts"
    assert merged == b, f"Should preserve user changes. Got {merged}, expected {b}"
    print("✓ test_user_only_change PASSED")


def test_generated_only_change():
    a = ['a\n', 'b\n']
    b = ['a\n', 'b\n']
    c = ['a changed\n', 'b\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts"
    assert merged == c, f"Should apply generated changes. Got {merged}, expected {c}"
    print("✓ test_generated_only_change PASSED")


def test_nonconflicting_both_change():
    a = ['l1\n', 'l2\n', 'l3\n']
    b = ['l1\n', 'l2 modified\n', 'l3\n']
    c = ['l1\n', 'l2\n', 'l3 new\n']
    merged, conflicts = three_way_merge(a, b, c)
    assert not conflicts, "Should have no conflicts for non-overlapping edits"
    expected = ['l1\n', 'l2 modified\n', 'l3 new\n']
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
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
