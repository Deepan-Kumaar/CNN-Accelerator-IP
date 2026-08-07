#!/bin/bash

# Stress test script for CNN_IP testbench
# Runs the testbench multiple times to verify consistent behavior
# RUN FROM MAIN DIRECTORY

echo "=== CNN_IP Testbench Stress Test ==="
echo "Starting stress test at $(date)"
echo ""

# Configuration
NUM_RUNS=10
PASS_COUNT=0
FAIL_COUNT=0

# Function to run a single test iteration
run_test() {
    
    local run_num=$1
    echo "--- Run $run_num/$NUM_RUNS ---"
    
    # Clean previous build
    make clean > /dev/null 2>&1
    
    # Run the simulation and capture output
    OUTPUT=$(make all 2>&1)
    EXIT_CODE=$?
    
    # Check for errors and warnings
    if echo "$OUTPUT" | grep -q "Errors: 0, Warnings: 0"; then
        if echo "$OUTPUT" | grep -q "ALL TESTS PASSED"; then
            echo "✓ PASS"
            return 0
        else
            echo "✗ FAIL - Tests did not pass (but no errors/warnings)"
            echo "$OUTPUT" | tail -20
            return 1
        fi
    else
        echo "✗ FAIL - Errors or warnings detected"
        echo "$OUTPUT" | grep -E "(Errors:|Warnings:|Fatal:|Error:)" | head -5
        return 1
    fi
}

# Run multiple iterations
for i in $(seq 1 $NUM_RUNS); do
    if run_test $i; then
        ((PASS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    echo ""
done

# Summary
echo "=== Stress Test Summary ==="
echo "Total runs: $NUM_RUNS"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED - Stress test successful!"
    exit 0
else
    echo "❌ SOME TESTS FAILED - Check output above"
    exit 1
fi