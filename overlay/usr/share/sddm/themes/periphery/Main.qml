import QtQuick 2.1

// Periphery OS — SDDM login theme.
//
// Kept to QtQuick 2.1 on purpose (universal since Qt 5.1): no SddmComponents dependency, so this runs
// on any SDDM/Qt5. Only the long-stable sddm/session context API is used
// (login, powerOff, reboot, canPowerOff/canReboot, loginFailed,
// session.index). Single-session setups need no session chooser: the
// default session index is passed straight through to sddm.login().
Item {
    id: root

    property string bgSource: "file:///usr/share/backgrounds/periphery/periphery-wallpaper.jpg"

    Component.onCompleted: {
        if (typeof config !== "undefined" && config.background) {
            bgSource = config.background;
        }
        userField.forceActiveFocus();
    }

    Connections {
        target: sddm
        onLoginFailed: {
            message.text = "Login failed — please try again.";
            passField.text = "";
            passField.forceActiveFocus();
        }
        onLoginSucceeded: {
            message.text = "";
        }
    }

    function attemptLogin() {
        if (userField.text === "") {
            userField.forceActiveFocus();
            return;
        }
        message.text = "";
        sddm.login(userField.text, passField.text, session.index);
    }

    Image {
        anchors.fill: parent
        source: bgSource
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        anchors.fill: parent
        color: "#17231F"
        opacity: 0.5
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 380
        height: panelColumn.height + 64
        radius: 14
        color: "#E617231F"

        Column {
            id: panelColumn
            anchors.top: parent.top
            anchors.topMargin: 32
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 64
            spacing: 12

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 84
                height: 84
                radius: 42
                color: "#F1EEE4"

                Image {
                    anchors.centerIn: parent
                    source: "logo.png"
                    width: 64
                    height: 64
                    fillMode: Image.PreserveAspectFit
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Periphery OS"
                color: "#F1EEE4"
                font.pixelSize: 24
                font.bold: true
            }

            Text {
                id: message
                anchors.horizontalCenter: parent.horizontalCenter
                text: ""
                color: "#E08A7E"
                font.pixelSize: 13
                visible: text !== ""
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 8
                color: "#F1EEE4"

                TextInput {
                    id: userField
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 16
                    color: "#17231F"
                    selectionColor: "#D6A85D"
                    selectedTextColor: "#17231F"
                    clip: true
                    KeyNavigation.tab: passField
                    Keys.onReturnPressed: attemptLogin()
                }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 16
                    color: "#8A8578"
                    text: "Username"
                    visible: userField.text === "" && !userField.activeFocus
                }
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 8
                color: "#F1EEE4"

                TextInput {
                    id: passField
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 16
                    color: "#17231F"
                    selectionColor: "#D6A85D"
                    selectedTextColor: "#17231F"
                    echoMode: TextInput.Password
                    clip: true
                    KeyNavigation.tab: loginArea
                    Keys.onReturnPressed: attemptLogin()
                }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 16
                    color: "#8A8578"
                    text: "Password"
                    visible: passField.text === "" && !passField.activeFocus
                }
            }

            Rectangle {
                id: loginButton
                width: parent.width
                height: 46
                radius: 8
                color: loginArea.containsMouse || loginArea.activeFocus ? "#E0B877" : "#D6A85D"

                Text {
                    anchors.centerIn: parent
                    text: "Log In"
                    color: "#17231F"
                    font.pixelSize: 17
                    font.bold: true
                }
                MouseArea {
                    id: loginArea
                    anchors.fill: parent
                    hoverEnabled: true
                    activeFocusOnTab: true
                    KeyNavigation.tab: userField
                    onClicked: attemptLogin()
                    Keys.onReturnPressed: attemptLogin()
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28
                visible: sddm.canPowerOff || sddm.canReboot

                Text {
                    text: "Power Off"
                    color: powerOffArea.containsMouse ? "#F1EEE4" : "#B8B2A4"
                    font.pixelSize: 13
                    visible: sddm.canPowerOff
                    MouseArea {
                        id: powerOffArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sddm.powerOff()
                    }
                }
                Text {
                    text: "Reboot"
                    color: rebootArea.containsMouse ? "#F1EEE4" : "#B8B2A4"
                    font.pixelSize: 13
                    visible: sddm.canReboot
                    MouseArea {
                        id: rebootArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sddm.reboot()
                    }
                }
            }
        }
    }
}
