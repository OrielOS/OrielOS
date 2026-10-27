# shellcheck shell=sh
# Sourced by Plasma when a session starts. OrielOS's English wording for Plasma's own text, such as
# "Pin to taskbar" in the taskbar's menu, is a catalogue for the language en@orielos. Plasma never
# looks up a translation for US English, the language its text is written in, so this puts
# en@orielos first in LANGUAGE whenever the first language is English. Every other string still
# comes from the user's languages. A language list chosen in Settings > Region & Language is
# applied after this script, and replaces it.
orielos_first_language="${LANGUAGE%%:*}"
[ -n "$orielos_first_language" ] || orielos_first_language="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
case "$orielos_first_language" in
    en@orielos*) ;;
    en | en_* | en.* | en@*)
        if [ -n "${LANGUAGE:-}" ]; then
            LANGUAGE="en@orielos:$LANGUAGE"
        else
            LANGUAGE="en@orielos:${orielos_first_language%%.*}"
        fi
        export LANGUAGE
        ;;
esac
unset orielos_first_language
