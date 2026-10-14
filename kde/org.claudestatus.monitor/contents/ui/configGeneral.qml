import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "format.js" as Fmt

KCM.SimpleKCM {
    id: page

    property alias cfg_warnThreshold: warn.value
    property alias cfg_critThreshold: crit.value
    property alias cfg_inactiveMinutes: inactive.value
    property alias cfg_intervalSeconds: interval.value
    property string cfg_language

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
        QQC2.SpinBox {
            id: interval
            Kirigami.FormData.label: page.tr("Refresh every (seconds):")
            from: 1; to: 300
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: page.tr("Values shown as \"from config\" follow ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang).")
            wrapMode: Text.Wrap
            opacity: 0.7
        }
    }
}
