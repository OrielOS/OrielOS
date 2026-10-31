/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// Slowing down guessing, as Windows does after repeated wrong passwords: after `allowedFailures`
// wrong tries in a row, the box asks for a shown phrase (such as "A1B2C3") to prove someone is
// there, then waits before taking a password again. Each lockout after that waits twice as long, up
// to `longestWait` seconds. The sign-in screen has the same rules, in a copy of this file
// (image/sddm/orielos/Lockout.qml); keep the two the same.

import QtQuick

QtObject {
    id: lockout

    property int allowedFailures: 5
    property int firstWait: 30
    property int longestWait: 900

    // What the box must be given before a password again, or "" when it takes a password.
    readonly property string phrase: _phrase
    // Seconds left before the box takes a password again.
    readonly property int secondsLeft: _secondsLeft

    property int _failures: 0
    property int _lockouts: 0
    property string _phrase: ""
    property int _secondsLeft: 0

    function failed() {
        _failures += 1;
        if (_failures >= allowedFailures) {
            const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";
            let phrase = "";
            for (let i = 0; i < 3; ++i) {
                phrase += letters[Math.floor(Math.random() * letters.length)];
                phrase += String(1 + Math.floor(Math.random() * 9));
            }
            _phrase = phrase;
        }
    }

    // Checks what was typed while a phrase is asked for; returns whether it matched.
    function answer(text) {
        if (text.toUpperCase() !== _phrase) {
            return false;
        }
        _phrase = "";
        // One more wrong password after this lockout asks for a phrase again.
        _failures = allowedFailures - 1;
        _secondsLeft = Math.min(longestWait, firstWait * Math.pow(2, _lockouts));
        _lockouts += 1;
        _countdown.start();
        return true;
    }

    readonly property Timer _countdown: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            lockout._secondsLeft -= 1;
            if (lockout._secondsLeft <= 0) {
                stop();
            }
        }
    }
}
