# shellcheck shell=bash
# Helpers for the build scripts that change desktop entries. Source it; it defines functions only.

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Rename a desktop entry: drop its translated names, which would still show the old name in
# other languages, then set the English Name and GenericName. GenericName goes after Name, so an
# entry that has none gets one. The build fails if the entry is missing or no longer has the
# expected name, so a package change cannot undo the rename silently.
#   rename_entry <file> <old name> <new name> <generic name> <script to update>
rename_entry() {
    local file="$1" old="$2" new="$3" generic="$4" script="$5"
    [[ -f "$file" ]] || die "$file does not exist; its packaging changed, so update $script"
    grep -qxF "Name=$old" "$file" || die "$file does not have Name=$old; update $script"
    sed -i -e '/^Name\[[^]]*\]=/d' -e '/^GenericName\[[^]]*\]=/d' -e '/^GenericName=/d' \
        -e "s/^Name=${old}\$/Name=${new}\nGenericName=${generic}/" "$file"
    grep -qxF "Name=$new" "$file" || die "could not rename $old in $file"
    grep -qxF "GenericName=$generic" "$file" || die "could not set GenericName in $file"
}
