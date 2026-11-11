import QtQuick 2.0

// Periphery OS — Calamares install slideshow.
//
// Pure QtQuick 2.0 (no calamares.slideshow components), so it runs on any
// Calamares 3.x. Written for slideshowAPI 1: the timer autostarts when the
// page loads. onActivate/onLeave are honored if the API is ever bumped to 2.
Item {
    id: root
    clip: true

    property int slideIndex: 0
    property var slides: [
        {
            "title": "Welcome to Periphery OS",
            "text": "A deliberate-practice Linux for CS and CE students. No shortcuts here — just you, the docs, and the machine."
        },
        {
            "title": "AI-free by default",
            "text": "Periphery Focus blocks AI chatbots, code assistants, and answer mills out of the box. Relax it any time — it is your machine."
        },
        {
            "title": "Tools for your field",
            "text": "After install, the Welcome app sets up your field's toolchain: 11 fields, 51 verified tools, one click each."
        },
        {
            "title": "Learn like an engineer",
            "text": "Read the man pages. Break things. Debug them. That is the whole method — welcome to the periphery."
        }
    ]

    function onActivate() {
        slideIndex = 0;
        advanceTimer.restart();
    }

    function onLeave() {
        advanceTimer.stop();
    }

    Image {
        id: background
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/periphery/periphery-wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    Rectangle {
        anchors.fill: parent
        color: "#17231F"
        opacity: 0.55
    }

    Rectangle {
        id: logoBadge
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 22
        width: 76
        height: 76
        radius: 38
        color: "#F1EEE4"
        opacity: 0.92
    }

    Image {
        id: logo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 28
        source: "logo.png"
        width: 64
        height: 64
        fillMode: Image.PreserveAspectFit
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: dots.top
        anchors.leftMargin: 36
        anchors.rightMargin: 36
        anchors.bottomMargin: 20
        height: titleText.height + bodyText.height + goldRule.height + 32

        Rectangle {
            id: goldRule
            width: 64
            height: 4
            color: "#D6A85D"
        }
        Text {
            id: titleText
            anchors.top: goldRule.bottom
            anchors.topMargin: 12
            width: parent.width
            text: slides[slideIndex].title
            color: "#F1EEE4"
            font.pixelSize: 30
            font.bold: true
            style: Text.Outline
            styleColor: "#17231F"
        }
        Text {
            id: bodyText
            anchors.top: titleText.bottom
            anchors.topMargin: 8
            width: parent.width
            text: slides[slideIndex].text
            color: "#F1EEE4"
            font.pixelSize: 16
            wrapMode: Text.WordWrap
            style: Text.Outline
            styleColor: "#17231F"
        }
    }

    Row {
        id: dots
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.bottomMargin: 28
        spacing: 8

        Repeater {
            model: slides.length
            Rectangle {
                width: 28
                height: 6
                radius: 3
                color: index === slideIndex ? "#D6A85D" : "#F1EEE4"
                opacity: index === slideIndex ? 1.0 : 0.45
            }
        }
    }

    Timer {
        id: advanceTimer
        interval: 8000
        repeat: true
        running: true
        onTriggered: fadeOut.start()
    }

    SequentialAnimation {
        id: fadeOut
        NumberAnimation {
            target: content
            property: "opacity"
            to: 0
            duration: 400
        }
        ScriptAction {
            script: {
                slideIndex = (slideIndex + 1) % slides.length;
                fadeIn.start();
            }
        }
    }

    NumberAnimation {
        id: fadeIn
        target: content
        property: "opacity"
        to: 1
        duration: 400
    }
}
