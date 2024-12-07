#!/bin/sh

################################################################################
#
# FILE:        update-symlinks.sh
#
# DESCRIPTION: This script manages synchronization between symbolic links
#              listed in 'symlinks.list' and their counterparts in various
#              directories within the 'NeoMoka' folder. It ensures that any
#              changes made to 'symlinks.list' are accurately reflected
#              within these directories.
#
# AUTHOR:      Zoltán Király <public@zoltankiraly.com>
#
# USAGE:       ./update-symlinks.sh [--dry-run]
#
# OPTIONS:
#   --dry-run  : Perform a dry run without actually modifying any symlinks.
#
# NOTES:       - The script expects 'NeoMoka' directory to be located one folder
#                above where this script resides.
#
################################################################################

# Check if --dry-run option is provided
dry_run=false
if [ "$1" = "--dry-run" ]; then
  dry_run=true
  echo "Running in dry-run mode. No changes will be made."
fi

# Resolve the path to the "NeoMoka" directory
neomoka_dir=$(realpath "$(dirname "$(readlink -f "$0")")/../NeoMoka")

if [ ! -d "$neomoka_dir" ]; then
  echo "Error: The 'NeoMoka' directory does not exist or is not accessible."
  exit 1
fi

# Resolve the path to the file containing symlinks
symlinks_file=$(dirname "$0")/symlinks.list

if [ ! -f "$symlinks_file" ]; then
  echo "Error: The file $symlinks_file does not exist or is not accessible."
  exit 1
fi

# Validate the symlinks file
if grep -qEv '^\S+\s+\S+$' "$symlinks_file"; then
  echo "Error: Invalid format in $symlinks_file. Each line should contain exactly two columns."
  exit 1
fi

# Function to create symlink in a specific folder
create_symlink() {
  folder="$1"
  source="$2"
  destination="$3"

  # Check if the source file exists and destination is not a symbolic link
  if [ -f "$folder/$source" ] && [ ! -L "$folder/$destination" ]; then
    if [ "$dry_run" != "true" ]; then
      ln -s "$source" "$folder/$destination"
      echo "Created symlink $destination -> $source in $folder"
    else
      echo "Dry run: creating symlink $destination -> $source in $folder"
    fi
  fi
}

# Function to remove symlink from a specific folder
remove_symlink() {
  folder="$1"
  destination="$2"

  # Remove the symlink if it exists
  if [ -L "$folder/$destination" ]; then
    if [ "$dry_run" != "true" ]; then
      rm "$folder/$destination"
      echo "Removed symlink $destination from $folder"
    else
      echo "Dry run: removing symlink $destination from $folder"
    fi
  fi
}

# Find differences between sorted unique symlinks in $symlinks_file and actual symlinks in $neomoka_dir
# For more information, see 'man comm'
script_dir="$(dirname "$(realpath "$0")")"

sort -u "$symlinks_file" > "$script_dir/symlinks_sorted.tmp"

find "$neomoka_dir" -type l | while read -r symlink; do
    target=$(readlink "$symlink")
    name=$(basename "$symlink")
    echo "$target $name"
done | sort -u > "$script_dir/find_output_sorted.tmp"

# Use comm to compare the sorted files
comm_output=$(comm -3 "$script_dir/symlinks_sorted.tmp" "$script_dir/find_output_sorted.tmp" | sort)

# Clean up temporary files
rm "$script_dir/symlinks_sorted.tmp" "$script_dir/find_output_sorted.tmp"

# NOTE: We cannot assure that the 'comm' command always displays items marked for deletion first,
# so we use two while loops to ensure the order.

# Process deletions first
echo "$comm_output" | while IFS= read -r line; do
  # Check if the line is indented (indicating a remove action)
  case "$line" in
    [[:space:]]*)  # Match if the line starts with spaces (indentation)
      # Remove action (destination is the second part of the line)
      destination=${line##* }
      # Iterate through each subdirectory in $neomoka_dir and remove symlink
      for subdir in "$neomoka_dir"/*/*; do
        remove_symlink "$subdir" "$destination"
      done
      ;;
  esac
done

# Process additions after deletions
echo "$comm_output" | while IFS= read -r line; do
  # Check if the line is not indented (indicating an add action)
  case "$line" in
    [[:space:]]*)  # This matches lines that are indented (remove action)
      # Skip this iteration (we don't want to process indented lines)
      continue
      ;;
    *)  # This matches lines that are not indented (add action)
      # Add action (source is the first part, destination is the second part)
      source=${line%% *}
      destination=${line##* }
      # Iterate through each subdirectory in $neomoka_dir and create symlink
      for subdir in "$neomoka_dir"/*/*; do
        create_symlink "$subdir" "$source" "$destination"
      done
      ;;
  esac
done