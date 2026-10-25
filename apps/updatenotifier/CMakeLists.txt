# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The tray icon that tells the user about OrielOS updates. It is started at login in Plasma.

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS StatusNotifierItem Notifications DBusAddons WidgetsAddons)

# The update state and its rules, apart from the tray icon, so the unit tests can use them.
add_library(OrielOSUpdateState STATIC updatestate.cpp updatestate.h)
target_include_directories(OrielOSUpdateState PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSUpdateState PRIVATE TRANSLATION_DOMAIN="orielos-update-notifier")
target_link_libraries(OrielOSUpdateState PUBLIC Qt6::Core KF6::I18n)

add_executable(orielos-update-notifier main.cpp updatenotifier.cpp updatenotifier.h)
target_compile_definitions(orielos-update-notifier PRIVATE
    TRANSLATION_DOMAIN="orielos-update-notifier"
    ORIELOS_VERSION_STRING="${PROJECT_VERSION}"
)
target_link_libraries(orielos-update-notifier PRIVATE
    OrielOSUpdateState
    Qt6::Widgets
    Qt6::DBus
    KF6::I18n
    KF6::CoreAddons
    KF6::StatusNotifierItem
    KF6::Notifications
    KF6::DBusAddons
    KF6::WidgetsAddons
)

install(TARGETS orielos-update-notifier ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# The same entry starts it at login and, in the applications folder, names it for the desktop
# portal and the notifications; NoDisplay keeps it out of Start.
install(FILES org.orielos.UpdateNotifier.desktop DESTINATION ${KDE_INSTALL_AUTOSTARTDIR})
install(FILES org.orielos.UpdateNotifier.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES orielos-update-notifier.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
