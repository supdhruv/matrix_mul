# =============================================================
#  Matrix Multiplier PYNQ Driver
#  Board  : PYNQ-Z2
#  Design : 4×4 register-based matrix multiplier
#  Author : Your name
#
#  REGISTER MAP:
#  0x00  W   m1 element value  (write index first to 0x08)
#  0x04  W   m2 element value  (write index first to 0x08)
#  0x08  W   element index     (0 .. N²-1)
#  0x0C  W   control           bit0=rst, bit1=start
#  0x10  R   done              1 when result ready
#  0x14+ R   result elements   result[0] at 0x14, result[1] at 0x18 ...
# =============================================================

from pynq import Overlay
import numpy as np
import time


# ── configuration ────────────────────────────────────────────
BITFILE = "matrix_mult.bit"   # must be in same folder as this script
N       = 4                   # matrix size — must match your Verilog N
WIDTH   = 18                  # must match your Verilog WIDTH

# Register addresses
ADDR_M1_ELEMENT  = 0x00
ADDR_M2_ELEMENT  = 0x04
ADDR_INDEX       = 0x08
ADDR_CONTROL     = 0x0C
ADDR_DONE        = 0x10
ADDR_RESULT_BASE = 0x14

# Control register bits
RST_BIT   = 0b01   # bit 0
START_BIT = 0b10   # bit 1


class MatrixMultiplier:
    """
    Python driver for the FPGA matrix multiplier.
    Usage:
        mm = MatrixMultiplier()
        C  = mm.multiply(A, B)
    """

    def __init__(self, bitfile=BITFILE, n=N):
        print(f"Loading bitstream: {bitfile}")
        self.ol   = Overlay(bitfile)
        self.ip   = self.ol.axi_wrapper_0   # must match your IP name in Vivado
        self.N    = n
        print(f"Bitstream loaded. Running {n}×{n} matrix multiplier.")
        self._reset()

    def _reset(self):
        """Assert then deassert reset — puts hardware in clean state"""
        self.ip.write(ADDR_CONTROL, RST_BIT)   # rst=1
        time.sleep(0.0001)                      # hold 100 µs
        self.ip.write(ADDR_CONTROL, 0)          # rst=0
        time.sleep(0.00001)                     # settle 10 µs

    def _load_matrix(self, M, addr_element):
        """
        Load an N×N matrix into either m1 (addr=0x00) or m2 (addr=0x04).
        Always write the index to 0x08 BEFORE writing the value.
        """
        for i in range(self.N):
            for j in range(self.N):
                idx  = i * self.N + j
                val  = int(M[i, j]) & 0x3FFFF   # mask to 18 bits
                self.ip.write(ADDR_INDEX,    idx)
                self.ip.write(addr_element,  val)

    def multiply(self, A, B, timeout_ms=10):
        """
        Multiply matrices A and B using FPGA hardware.

        Args:
            A: numpy array (N×N), integer values 0..262143
            B: numpy array (N×N), integer values 0..262143
            timeout_ms: max wait time for done signal

        Returns:
            C: numpy array (N×N) — hardware result

        Raises:
            ValueError:   if matrix dimensions don't match N
            TimeoutError: if FPGA doesn't assert done in time
        """
        # validate inputs
        if A.shape != (self.N, self.N) or B.shape != (self.N, self.N):
            raise ValueError(
                f"Expected {self.N}×{self.N} matrices, "
                f"got {A.shape} and {B.shape}")

        # reset before each multiply
        self._reset()

        # load m1 (matrix A)
        self._load_matrix(A, ADDR_M1_ELEMENT)

        # load m2 (matrix B)
        self._load_matrix(B, ADDR_M2_ELEMENT)

        # pulse start — FSM: IDLE → RUNNING
        self.ip.write(ADDR_CONTROL, START_BIT)   # start=1
        self.ip.write(ADDR_CONTROL, 0)           # start=0

        # poll for done with timeout
        deadline = time.perf_counter() + timeout_ms / 1000.0
        while self.ip.read(ADDR_DONE) == 0:
            if time.perf_counter() > deadline:
                raise TimeoutError(
                    f"FPGA multiply did not complete within {timeout_ms}ms. "
                    f"Check bitstream, reset, and start logic.")

        # read result — 16 elements (for N=4)
        C = np.zeros((self.N, self.N), dtype=np.int64)
        for i in range(self.N):
            for j in range(self.N):
                idx    = i * self.N + j
                addr   = ADDR_RESULT_BASE + idx * 4
                C[i,j] = self.ip.read(addr)

        return C

    def verify(self, A, B, C_hw):
        """Compare hardware result against numpy ground truth"""
        C_expected = A.astype(np.int64) @ B.astype(np.int64)
        match      = np.array_equal(C_hw, C_expected)
        return match, C_expected

    def run_tests(self, num_tests=1000, max_val=256, verbose=True):
        """
        Run num_tests random matrix multiplications and verify each.
        Prints pass/fail summary and timing statistics.
        """
        passed = 0
        failed = 0
        times  = []
        errors = []

        print(f"\nRunning {num_tests} random {self.N}×{self.N} tests...")
        print(f"Input range: 0..{max_val-1}")
        print("-" * 50)

        for trial in range(num_tests):
            A = np.random.randint(0, max_val, (self.N, self.N), dtype=np.uint32)
            B = np.random.randint(0, max_val, (self.N, self.N), dtype=np.uint32)

            t0   = time.perf_counter()
            C_hw = self.multiply(A, B)
            t1   = time.perf_counter()
            times.append((t1 - t0) * 1e6)   # microseconds

            ok, C_exp = self.verify(A, B, C_hw)
            if ok:
                passed += 1
                if verbose and trial % 100 == 0:
                    print(f"  Trial {trial:4d}: PASS  ({times[-1]:.1f} µs)")
            else:
                failed += 1
                errors.append({
                    "trial": trial, "A": A, "B": B,
                    "expected": C_exp, "got": C_hw
                })
                print(f"  Trial {trial:4d}: FAIL")
                print(f"    A:\n{A}")
                print(f"    B:\n{B}")
                print(f"    Expected:\n{C_exp}")
                print(f"    Got:\n{C_hw}")
                print(f"    Diff:\n{C_exp - C_hw}")
                if failed >= 3:
                    print("  Stopping after 3 failures.")
                    break

        # summary
        print("\n" + "=" * 50)
        print(f"  RESULTS: {passed}/{num_tests} passed  |  {failed} failed")
        if times:
            print(f"  TIMING (µs):")
            print(f"    Mean   : {np.mean(times):.2f}")
            print(f"    Min    : {np.min(times):.2f}")
            print(f"    Max    : {np.max(times):.2f}")
            print(f"    StdDev : {np.std(times):.2f}")
        print("=" * 50)

        return passed, failed, errors


# ── quick manual test ─────────────────────────────────────────
def quick_test(mm):
    """
    Runs one known test case so you can verify immediately
    after plugging in the board.
    Expected: C = A @ B = [[19,22],[43,50]] for top-left 2×2
    """
    print("\n--- Quick sanity test ---")
    A = np.array([[ 1,  2,  3,  4],
                  [ 5,  6,  7,  8],
                  [ 9, 10, 11, 12],
                  [13, 14, 15, 16]], dtype=np.uint32)

    B = np.eye(4, dtype=np.uint32)   # identity — C should equal A

    C_hw = mm.multiply(A, B)
    ok, C_exp = mm.verify(A, B, C_hw)

    print(f"A:\n{A}")
    print(f"B (identity):\n{B}")
    print(f"C (hardware):\n{C_hw}")
    print(f"C (expected):\n{C_exp}")
    print(f"Result: {'PASS ✓' if ok else 'FAIL ✗'}")
    return ok


# ── entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    # Step 1: load bitstream and create driver
    mm = MatrixMultiplier(bitfile=BITFILE, n=N)

    # Step 2: quick sanity check
    ok = quick_test(mm)

    if ok:
        # Step 3: full 1000-run test suite
        mm.run_tests(num_tests=1000, max_val=256, verbose=True)
    else:
        print("\nSanity test failed — check hardware before running full suite.")
        print("Common causes:")
        print("  1. IP block name wrong — change 'axi_wrapper_0' in driver.py")
        print("  2. N mismatch — check matrix_mult.sv has N=4")
        print("  3. Bitstream not matching wrapper — re-synthesize")
