#!/bin/bash

# Script to process eprof output and overwrite with top 20 functions by time percentage
# Usage: ./process_eprof.sh <eprof_output_file>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <eprof_output_file>"
    echo "Example: $0 eprof_analysis_1756530207.txt"
    exit 1
fi

EPROF_FILE="$1"

if [ ! -f "$EPROF_FILE" ]; then
    echo "Error: File '$EPROF_FILE' not found!"
    exit 1
fi

# Create temporary file for the new content
TEMP_FILE=$(mktemp)

# Write header to temp file (using exact original format)
cat > "$TEMP_FILE" << 'EOF'
TOP 20 PERFORMANCE BOTTLENECKS (by time %)
==============================================
FUNCTION                                                                      CALLS        %     TIME  [uS / CALLS]
--------                                                                      -----  -------     ----  [----------]
EOF

# Find the "Total:" line which marks the end of the main analysis
total_line=$(grep -n "^Total:" "$EPROF_FILE" | head -1 | cut -d: -f1)

if [ -n "$total_line" ]; then
    # Get 20 lines before the Total line
    start_line=$((total_line - 30))
    end_line=$((total_line - 1))
    
    if [ $start_line -lt 1 ]; then
        start_line=1
    fi
    
    # Extract the lines and reverse them (highest % first)
    sed -n "${start_line},${end_line}p" "$EPROF_FILE" | tac >> "$TEMP_FILE"
    
    # Add separator and total line
    echo "" >> "$TEMP_FILE"
    echo "📊 SUMMARY:" >> "$TEMP_FILE"
    sed -n "${total_line}p" "$EPROF_FILE" >> "$TEMP_FILE"
    
    # Add focus points
    cat >> "$TEMP_FILE" << 'EOF'


EOF

    # Overwrite original file with processed content
    mv "$TEMP_FILE" "$EPROF_FILE"

    
else
    echo "Error: Could not find 'Total:' line in the eprof output"
    rm -f "$TEMP_FILE"
    exit 1
fi
