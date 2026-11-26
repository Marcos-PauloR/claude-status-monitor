// Claude Status Monitor — plasmoid do KDE Plasma 6.
// Roda claude-status-summary.sh --format json a cada N segundos (mesmas regras do painel do GNOME).
// Limiares, inatividade, idioma, tema e contas no painel vêm do config único, a não ser que
// tenham sido mudados aqui. O popup tem uma seção por conta e o botão de fixar a janela do painel.

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
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
    // Erro do último Fixar/Desafixar: fica no popup até o próximo clique (a atualização não apaga).
    property string pinError: ""

    readonly property var cfg: Plasmoid.configuration
    // O plasmashell nem sempre tem ~/.local/bin no PATH; o motor "executable" roda via shell.
    readonly property string command: 'PATH="$HOME/.local/bin:$PATH" claude-status-summary.sh ' + Fmt.summaryArgs(cfg)
    readonly property string lang: summary && summary.lang ? summary.lang : Fmt.fallbackLang(cfg.language, Qt.locale().name)
    readonly property string dataDir: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/claude-status"

    readonly property var theme: summary && summary.theme ? summary.theme : null

    // Cores do tema do resumidor. Tema default (ou sem resumo) = cores do Plasma, como na v1.2;
    // nos outros temas, cor vazia = cor do texto do desktop.
    function levelColor(level) {
        return Fmt.levelColor(theme, level,
            [Kirigami.Theme.textColor, Kirigami.Theme.neutralTextColor, Kirigami.Theme.negativeTextColor]);
    }
    function themeColor(key, fallback) {
        return Fmt.themed(theme, key) || fallback;
    }
    function tr(text) {
        return Fmt.tr(lang, text);
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

    // Fixar/desafixar: roda o resumidor e atualiza na hora.
    Plasma5Support.DataSource {
        id: pinExec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.pinError = (data.stderr || "claude-status-summary.sh failed").trim();
                console.warn("claude-status: " + source + ": " + root.pinError);
            }
            exec.connectSource(root.command);
        }
    }
    function togglePin(w) {
        pinError = "";
        pinExec.connectSource('PATH="$HOME/.local/bin:$PATH" ' + Fmt.pinCommand(w));
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
            text: root.tr("Open data folder")
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

        // Barra com a cor do tema (bar / warn / crit); no tema default fica a do Breeze.
        // O estilo do Plasma desenha a barra com SVG e ignora palette.highlight: com cor de tema,
        // um retângulo cobre o preenchimento.
        component ThemedBar: PlasmaComponents.ProgressBar {
            id: themedBar
            property int level: 0
            readonly property string tint: Fmt.barColor(root.theme, level)
            from: 0; to: 100
            Rectangle {
                visible: !!themedBar.tint && themedBar.visualPosition > 0 && !!themedBar.contentItem
                z: 10
                x: themedBar.contentItem ? themedBar.contentItem.x : 0
                y: themedBar.contentItem ? themedBar.contentItem.y : 0
                height: themedBar.contentItem ? themedBar.contentItem.height : 0
                width: themedBar.contentItem ? Math.max(height, themedBar.contentItem.width * themedBar.visualPosition) : 0
                radius: height / 2
                color: themedBar.tint || "transparent"
            }
        }

        component QuotaRow: RowLayout {
            property string title
            property var quota
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            PlasmaComponents.Label {
                text: parent.title
                color: root.themeColor("label", Kirigami.Theme.textColor)
                opacity: root.themeColor("label", "") ? 1 : 0.75
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            }
            ThemedBar {
                Layout.fillWidth: true
                value: parent.quota ? parent.quota.pct : 0
                level: Fmt.level(parent.quota ? parent.quota.pct : null, root.summary)
                visible: !!parent.quota
            }
            PlasmaComponents.Label {
                text: Fmt.quotaDetail(parent.quota, root.lang)
                color: root.levelColor(Fmt.level(parent.quota ? parent.quota.pct : null, root.summary))
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
            visible: !!root.pinError
            text: root.pinError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            visible: !root.error && (!root.summary || root.summary.empty)
            text: root.tr("no active windows")
            opacity: 0.6
        }

        ColumnLayout {
            visible: !!root.summary && !root.summary.empty
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // Uma seção por conta; com uma conta só, sem cabeçalho (igual à v1.2).
            Repeater {
                model: root.summary && root.summary.accounts ? root.summary.accounts : []
                delegate: ColumnLayout {
                    id: account
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.topMargin: index > 0 ? Kirigami.Units.largeSpacing : 0
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Separator { visible: account.index > 0; Layout.fillWidth: true }
                    Kirigami.Heading {
                        visible: !!root.summary.multi
                        level: 5
                        text: account.modelData.label
                        color: root.themeColor("accent", Kirigami.Theme.textColor)
                        font.weight: Font.Bold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    QuotaRow { title: root.tr("session"); quota: account.modelData.session }
                    QuotaRow { title: root.tr("weekly"); quota: account.modelData.weekly }
                    PlasmaComponents.Label {
                        text: root.tr("compacts this week") + ": " + (account.modelData.week_compacts || 0)
                        color: root.themeColor("label", Kirigami.Theme.textColor)
                        opacity: root.themeColor("label", "") ? 1 : 0.75
                    }

                    Repeater {
                        model: account.modelData.windows || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            spacing: 0

                            Kirigami.Separator { Layout.fillWidth: true; Layout.bottomMargin: Kirigami.Units.smallSpacing; opacity: 0.5 }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Label {
                                    text: Fmt.windowTitle(modelData, root.lang)
                                    font.bold: true
                                    elide: Text.ElideRight
                                    color: modelData.pinned ? root.themeColor("accent", Kirigami.Theme.textColor) : Kirigami.Theme.textColor
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.ToolButton {
                                    icon.name: "window-pin"  // o do Breeze (view-pin-symbolic é do Adwaita)
                                    checked: !!modelData.pinned
                                    display: QQC2.AbstractButton.IconOnly
                                    text: root.tr(modelData.pinned ? "Unpin" : "Pin to panel")
                                    QQC2.ToolTip.text: text
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    onClicked: root.togglePin(modelData)
                                }
                            }
                            PlasmaComponents.Label {
                                text: (modelData.model || "—") + " · " + root.tr("compacts") + " " + modelData.compacts
                                color: root.themeColor("label", Kirigami.Theme.textColor)
                                opacity: root.themeColor("label", "") ? 1 : 0.65
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                PlasmaComponents.Label {
                                    text: "ctx"
                                    color: root.themeColor("label", Kirigami.Theme.textColor)
                                    opacity: root.themeColor("label", "") ? 1 : 0.75
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                ThemedBar {
                                    Layout.fillWidth: true
                                    value: modelData.ctx || 0
                                    level: modelData.level || 0
                                }
                                PlasmaComponents.Label {
                                    text: Fmt.pct(modelData.ctx) + "  " + Fmt.tokens(modelData.tokens) + " / " + Fmt.tokens(modelData.window)
                                    color: root.levelColor(modelData.level)
                                }
                            }
                        }
                    }
                }
            }
        }

        PlasmaComponents.Button {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Kirigami.Units.smallSpacing
            icon.name: "folder-open"
            text: root.tr("Open data folder")
            onClicked: Qt.openUrlExternally(root.dataDir)
        }
    }
}
