#!/bin/bash

# Input file
files=$(find contracts -name "*.sol" ! -path "contracts/interfaces/*" ! -path "contracts/test/*")
#echo $files
echo "Counting number of lines"
echo ""

let all=0
for file in $files
do
  # Count lines excluding comments, empty lines, interfaces, and errors
  count=$(grep -vE '^\s*(//|/\*|\*/|\*|$)' "$file" | grep -vE '^\s*(interface|error|import|pragma)' | wc -l)
  echo "$file: $count"
  echo ""

  all=$((all + count))
done

echo "All lines: $all"
