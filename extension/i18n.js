// Textos da extensão em inglês (chave) e português. Não depende do GNOME Shell: roda nos testes.
// O idioma vem da chave `language` (auto, en, pt); auto segue o idioma da sessão (pt_* -> pt).

import GLib from 'gi://GLib';

const PT = {
    // painel
    'model': 'modelo',
    'session': 'sessão',
    'resets': 'reinicia',
    'compacts': 'compactações',
    'weekly': 'semana',
    // menu
    'no active windows': 'nenhuma janela ativa',
    'Open data folder': 'Abrir pasta de dados',
    'Preferences': 'Preferências',
    'just reset': 'reiniciada',
    'resets in': 'reinicia em',
    'compacts this week': 'compactações na semana',
    'no data yet': 'sem dados ainda',
    '(no project)': '(sem projeto)',
    // preferências: abas
    'General': 'Geral',
    'Indicators': 'Indicadores',
    'About': 'Sobre',
    // preferências: geral
    'Colors': 'Cores',
    'Applies to every indicator that does not use its own thresholds.': 'Vale para todo indicador que não usa limiares próprios.',
    'Yellow from (%)': 'Amarelo a partir de (%)',
    'Red from (%)': 'Vermelho a partir de (%)',
    'Language': 'Idioma',
    'Automatic (system)': 'Automático (do sistema)',
    'Windows': 'Janelas',
    'Hide after (minutes)': 'Esconder após (minutos)',
    'A Claude Code window without updates for this long disappears': 'Uma janela do Claude Code sem atualização por esse tempo some',
    'Panel position': 'Posição no painel',
    'Area': 'Área',
    'Left': 'Esquerda',
    'Center': 'Centro',
    'Right': 'Direita',
    'Order': 'Ordem',
    'Position inside the area (0 = first)': 'Posição dentro da área (0 = primeiro)',
    // preferências: indicadores
    'Panel indicators': 'Indicadores do painel',
    'Drag to reorder. Changes apply immediately.': 'Arraste para reordenar. As mudanças valem na hora.',
    'Model of the most recent window': 'Modelo da janela mais recente',
    'Context used by the most recent window': 'Contexto usado pela janela mais recente',
    'Account usage in the current 5-hour session': 'Uso da conta na sessão atual de 5 horas',
    'Time until the session usage resets': 'Tempo até a cota da sessão reiniciar',
    'Compacts in the most recent window': 'Compactações na janela mais recente',
    'Account usage in the current week': 'Uso da conta na semana atual',
    'Use general thresholds': 'Usar limiares gerais',
    'Color follows the session indicator': 'A cor acompanha o indicador sessão',
    'Show in panel': 'Mostrar no painel',
    // preferências: sobre
    'Context and plan usage of your Claude Code sessions, right in the top panel.': 'Contexto e uso do plano das suas sessões do Claude Code, direto no painel.',
    'Version': 'Versão',
    'Source code': 'Código-fonte',
    'Report an issue': 'Relatar um problema',
    'No network access, no credentials: the data comes from the Claude Code statusline.': 'Sem acesso à rede nem a credenciais: os dados vêm da statusline do Claude Code.',
};

// 'auto' | 'en' | 'pt' -> 'en' | 'pt'
export function resolveLanguage(setting, languageNames = GLib.get_language_names()) {
    if (setting === 'en' || setting === 'pt')
        return setting;
    return languageNames.some(n => n === 'pt' || n.startsWith('pt_')) && !languageNames[0].startsWith('en')
        ? 'pt' : 'en';
}

// Função de tradução para um idioma: chave em inglês -> texto.
export function translator(lang) {
    return key => (lang === 'pt' ? PT[key] ?? key : key);
}

export const PT_KEYS = Object.keys(PT);
