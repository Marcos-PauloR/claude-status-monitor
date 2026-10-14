// Claude Status Monitor — plasmoid do KDE Plasma 6.
// Roda claude-status-summary.sh --format json a cada N segundos (mesmas regras do painel do GNOME).

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

import "format.js" as Fmt

PlasmoidItem {
    id: root

    property var summary: null
    property string error: ""

    readonly property var cfg: Plasmoid.configuration
    // O plasmashell nem sempre tem ~/.local/bin no PATH; o motor "executable" roda via shell.
    readonly property string command: 'PATH="$HOME/.local/bin:$PATH" claude-status-summary.sh --format json'
        + " --warn " + cfg.warnThreshold + " --crit " + cfg.critThreshold + " --inactive " + cfg.inactiveMinutes
    readonly property string dataDir: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/claude-status"

    function levelColor(level) {
        return level >= 2 ? Kirigami.Theme.negativeTextColor
            : level === 1 ? Kirigami.Theme.neutralTextColor
            : Kirigami.Theme.textColor;
    }
    function levelOf(p) {
        return typeof p !== "number" ? 0 : p >= cfg.critThreshold ? 2 : p >= cfg.warnThreshold ? 1 : 0;
    }

    Plasmoid.status: summary && !summary.empty ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "Claude Status"
    toolTipSubText: error || Fmt.panelText(summary)

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.error = (data.stderr || "claude-status-summary.sh failed").trim();
                return;
            }
            try {
                root.summary = JSON.parse(data.stdout);
                root.error = "";
            } catch (e) {
                root.error = "invalid output: " + e;
            }
        }
    }

    Timer {
        interval: Math.max(1, root.cfg.intervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.command)
    }
    // Mudou a configuração: atualiza já.
    onCommandChanged: exec.connectSource(root.command)

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Open data folder"
            icon.name: "folder-open"
            onTriggered: Qt.openUrlExternally(root.dataDir)
        }
    ]

    compactRepresentation: MouseArea {
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        acceptedButtons: Qt.LeftButton
        onClicked: root.expanded = !root.expanded

        PlasmaComponents.Label {
            id: label
            anchors.centerIn: parent
            text: root.error ? "Claude ?" : Fmt.panelText(root.summary)
            color: root.levelColor(root.summary ? root.summary.level : 0)
            opacity: root.summary && !root.summary.empty ? 1 : 0.6
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.smallSpacing

        component QuotaRow: RowLayout {
            property string title
            property var quota
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            PlasmaComponents.Label {
                text: parent.title
                opacity: 0.75
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            }
            PlasmaComponents.ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 100
                value: parent.quota ? parent.quota.pct : 0
                visible: !!parent.quota
            }
            PlasmaComponents.Label {
                text: Fmt.quotaDetail(parent.quota)
                color: root.levelColor(root.levelOf(parent.quota ? parent.quota.pct : null))
            }
        }

        Kirigami.Heading {
            level: 4
            text: "Claude Status"
        }
        PlasmaComponents.Label {
            visible: !!root.error
            text: root.error
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            visible: !root.error && (!root.summary || root.summary.empty)
            text: "no active windows"
            opacity: 0.6
        }

        ColumnLayout {
            visible: !!root.summary && !root.summary.empty
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QuotaRow { title: "session"; quota: root.summary ? root.summary.session : null }
            QuotaRow { title: "weekly"; quota: root.summary ? root.summary.weekly : null }
            PlasmaComponents.Label {
                text: "compacts this week: " + (root.summary ? root.summary.week_compacts : 0)
                opacity: 0.75
            }

            Repeater {
                model: root.summary ? root.summary.windows : []
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: 0

                    Kirigami.Separator { Layout.fillWidth: true; Layout.bottomMargin: Kirigami.Units.smallSpacing }
                    PlasmaComponents.Label {
                        text: Fmt.windowTitle(modelData)
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: (modelData.model || "—") + " · compacts " + modelData.compacts
                        opacity: 0.65
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        PlasmaComponents.Label {
                            text: "ctx"
                            opacity: 0.75
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        }
                        PlasmaComponents.ProgressBar {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: modelData.ctx || 0
                        }
                        PlasmaComponents.Label {
                            text: Fmt.pct(modelData.ctx) + "  " + Fmt.tokens(modelData.tokens) + " / " + Fmt.tokens(modelData.window)
                            color: root.levelColor(modelData.level)
                        }
                    }
                }
            }
        }

        PlasmaComponents.Button {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Kirigami.Units.smallSpacing
            icon.name: "folder-open"
            text: "Open data folder"
            onClicked: Qt.openUrlExternally(root.dataDir)
        }
    }
}
