import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_warnThreshold: warn.value
    property alias cfg_critThreshold: crit.value
    property alias cfg_inactiveMinutes: inactive.value
    property alias cfg_intervalSeconds: interval.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: warn
            Kirigami.FormData.label: "Warning (%):"
            from: 1; to: 100
            // Crítico nunca fica abaixo do aviso.
            onValueModified: if (crit.value < value) crit.value = value
        }
        QQC2.SpinBox {
            id: crit
            Kirigami.FormData.label: "Critical (%):"
            from: 1; to: 100
            onValueModified: if (warn.value > value) warn.value = value
        }
        QQC2.SpinBox {
            id: inactive
            Kirigami.FormData.label: "Inactive after (minutes):"
            from: 1; to: 1440
        }
        QQC2.SpinBox {
            id: interval
            Kirigami.FormData.label: "Refresh every (seconds):"
            from: 1; to: 300
        }
    }
}
