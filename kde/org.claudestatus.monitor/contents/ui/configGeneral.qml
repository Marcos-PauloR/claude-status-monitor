import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support

import "format.js" as Fmt

KCM.SimpleKCM {
    id: page

    property alias cfg_warnThreshold: warn.value
    property alias cfg_critThreshold: crit.value
    property alias cfg_inactiveMinutes: inactive.value
    property alias cfg_intervalSeconds: interval.value
    property string cfg_language
    property string cfg_theme
    property string cfg_panelAccounts

    // Temas disponíveis (embutidos + da pessoa), lidos do resumidor ao abrir a tela.
    property var themes: []
    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: ['PATH="$HOME/.local/bin:$PATH" claude-status-summary.sh --list-themes']
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                if (data["exit code"] === 0)
                    page.themes = JSON.parse(data.stdout);
            } catch (e) {
                console.warn("claude-status: --list-themes inválido: " + e);
            }
        }
    }

    readonly property string lang: Fmt.fallbackLang(cfg_language, Qt.locale().name)
    function tr(text) {
        return Fmt.tr(lang, text);
    }

    // 0 = segue o config único; mostra "do config" no lugar do número.
    component ConfigSpinBox: QQC2.SpinBox {
        textFromValue: (value, locale) => value === 0 ? page.tr("from config") : String(value)
        valueFromText: (text, locale) => text === page.tr("from config") ? 0 : (parseInt(text) || 0)
    }

    Kirigami.FormLayout {
        ConfigSpinBox {
            id: warn
            Kirigami.FormData.label: page.tr("Yellow from (%):")
            from: 0; to: 100
            // Vermelho nunca fica abaixo do amarelo (quando os dois são próprios do plasmoid).
            onValueModified: if (value > 0 && crit.value > 0 && crit.value < value) crit.value = value
        }
        ConfigSpinBox {
            id: crit
            Kirigami.FormData.label: page.tr("Red from (%):")
            from: 0; to: 100
            onValueModified: if (value > 0 && warn.value > value) warn.value = value
        }
        ConfigSpinBox {
            id: inactive
            Kirigami.FormData.label: page.tr("Hide windows after (minutes):")
            from: 0; to: 1440
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: page.tr("Language:")
            readonly property var values: ["", "en", "pt"]
            model: [page.tr("from config"), "English", "Português"]
            currentIndex: Math.max(0, values.indexOf(page.cfg_language))
            onActivated: index => page.cfg_language = values[index]
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: page.tr("Theme:")
            // Tema salvo que não está na lista (apagado?) continua aparecendo para não sumir calado.
            readonly property var values: {
                const ids = [""].concat(page.themes.map(t => t.id));
                if (page.cfg_theme && ids.indexOf(page.cfg_theme) < 0)
                    ids.push(page.cfg_theme);
                return ids;
            }
            model: values.map(id => {
                if (id === "")
                    return page.tr("from config");
                const t = page.themes.find(x => x.id === id);
                return t ? t.name : id;
            })
            currentIndex: Math.max(0, values.indexOf(page.cfg_theme))
            onActivated: index => page.cfg_theme = values[index]
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: page.tr("Accounts in panel:")
            readonly property var values: ["", "focus", "all"]
            model: [page.tr("from config"), page.tr("Account of the focused window"), page.tr("All accounts")]
            currentIndex: Math.max(0, values.indexOf(page.cfg_panelAccounts))
            onActivated: index => page.cfg_panelAccounts = values[index]
        }
        QQC2.SpinBox {
            id: interval
            Kirigami.FormData.label: page.tr("Refresh every (seconds):")
            from: 1; to: 300
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: page.tr("Values shown as \"from config\" follow ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang, --theme, --panel-accounts).")
            wrapMode: Text.Wrap
            opacity: 0.7
        }
    }
}
