#!/usr/bin/env python3
"""
Generate Qt .ts translation source files and compile .qm binaries for OpenUTV.
Supports: English (en), Spanish (es), French (fr), German (de), Italian (it),
Japanese (ja), Korean (ko), Simplified Chinese (zh, zh_CN).
"""

import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import xml.sax.saxutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Master translations dictionary:
# key: (context, english_source) -> {lang_code: translated_string}
TRANSLATIONS = {
    # -------------------------------------------------------------------------
    # Menus
    # -------------------------------------------------------------------------
    ("Menu", "File"): {
        "es": "Archivo",
        "fr": "Fichier",
        "de": "Datei",
        "it": "File",
        "ja": "ファイル",
        "ko": "파일",
        "zh": "文件",
        "zh_CN": "文件",
    },
    ("Menu", "New Session"): {
        "es": "Nueva sesión",
        "fr": "Nouvelle session",
        "de": "Neue Sitzung",
        "it": "Nuova sessione",
        "ja": "新規セッション",
        "ko": "새 세션",
        "zh": "新建会话",
        "zh_CN": "新建会话",
    },
    ("Menu", "Open..."): {
        "es": "Abrir...",
        "fr": "Ouvrir...",
        "de": "Öffnen...",
        "it": "Apri...",
        "ja": "開く...",
        "ko": "열기...",
        "zh": "打开...",
        "zh_CN": "打开...",
    },
    ("Menu", "Open Directory..."): {
        "es": "Abrir directorio...",
        "fr": "Ouvrir le dossier...",
        "de": "Verzeichnis öffnen...",
        "it": "Apri cartella...",
        "ja": "ディレクトリを開く...",
        "ko": "디렉토리 열기...",
        "zh": "打开目录...",
        "zh_CN": "打开目录...",
    },
    ("Menu", "Merge..."): {
        "es": "Combinar...",
        "fr": "Fusionner...",
        "de": "Zusammenführen...",
        "it": "Unisci...",
        "ja": "結合...",
        "ko": "병합...",
        "zh": "合并...",
        "zh_CN": "合并...",
    },
    ("Menu", "Open into Layer..."): {
        "es": "Abrir en capa...",
        "fr": "Ouvrir dans un calque...",
        "de": "In Ebene öffnen...",
        "it": "Apri nel livello...",
        "ja": "レイヤーに開く...",
        "ko": "레이어로 열기...",
        "zh": "打开到图层...",
        "zh_CN": "打开到图层...",
    },
    ("Menu", "Open in New Session..."): {
        "es": "Abrir en nueva sesión...",
        "fr": "Ouvrir dans une nouvelle session...",
        "de": "In neuer Sitzung öffnen...",
        "it": "Apri in nuova sessione...",
        "ja": "新しいセッションで開く...",
        "ko": "새 세션에서 열기...",
        "zh": "在新会话中打开...",
        "zh_CN": "在新会话中打开...",
    },
    ("Menu", "Clone Session"): {
        "es": "Clonar sesión",
        "fr": "Cloner la session",
        "de": "Sitzung klonen",
        "it": "Clona sessione",
        "ja": "セッションを複製",
        "ko": "세션 복제",
        "zh": "克隆会话",
        "zh_CN": "克隆会话",
    },
    ("Menu", "Save Session"): {
        "es": "Guardar sesión",
        "fr": "Enregistrer la session",
        "de": "Sitzung speichern",
        "it": "Salva sessione",
        "ja": "セッションを保存",
        "ko": "세션 저장",
        "zh": "保存会话",
        "zh_CN": "保存会话",
    },
    ("Menu", "Save Session As..."): {
        "es": "Guardar sesión como...",
        "fr": "Enregistrer la session sous...",
        "de": "Sitzung speichern unter...",
        "it": "Salva sessione con nome...",
        "ja": "名前を付けてセッションを保存...",
        "ko": "다른 이름으로 세션 저장...",
        "zh": "会话另存为...",
        "zh_CN": "会话另存为...",
    },
    ("Menu", "Import"): {
        "es": "Importar",
        "fr": "Importer",
        "de": "Importieren",
        "it": "Importa",
        "ja": "インポート",
        "ko": "가져오기",
        "zh": "导入",
        "zh_CN": "导入",
    },
    ("Menu", "Export"): {
        "es": "Exportar",
        "fr": "Exporter",
        "de": "Exportieren",
        "it": "Esporta",
        "ja": "エクスポート",
        "ko": "내보내기",
        "zh": "导出",
        "zh_CN": "导出",
    },
    ("Menu", "Clear"): {
        "es": "Limpiar",
        "fr": "Effacer",
        "de": "Löschen",
        "it": "Cancella",
        "ja": "クリア",
        "ko": "지우기",
        "zh": "清除",
        "zh_CN": "清除",
    },
    ("Menu", "Close Session"): {
        "es": "Cerrar sesión",
        "fr": "Fermer la session",
        "de": "Sitzung schließen",
        "it": "Chiudi sessione",
        "ja": "セッションを閉じる",
        "ko": "세션 닫기",
        "zh": "关闭会话",
        "zh_CN": "关闭会话",
    },
    ("Menu", "Edit"): {
        "es": "Edición",
        "fr": "Édition",
        "de": "Bearbeiten",
        "it": "Modifica",
        "ja": "編集",
        "ko": "편집",
        "zh": "编辑",
        "zh_CN": "编辑",
    },
    ("Menu", "Undo"): {
        "es": "Deshacer",
        "fr": "Annuler",
        "de": "Rückgängig",
        "it": "Annulla",
        "ja": "元に戻す",
        "ko": "실행 취소",
        "zh": "撤销",
        "zh_CN": "撤销",
    },
    ("Menu", "Redo"): {
        "es": "Rehacer",
        "fr": "Rétablir",
        "de": "Wiederholen",
        "it": "Ripeti",
        "ja": "やり直し",
        "ko": "다시 실행",
        "zh": "重做",
        "zh_CN": "重做",
    },
    ("Menu", "Cut"): {
        "es": "Cortar",
        "fr": "Couper",
        "de": "Ausschneiden",
        "it": "Taglia",
        "ja": "切り取り",
        "ko": "잘라내기",
        "zh": "剪切",
        "zh_CN": "剪切",
    },
    ("Menu", "Copy"): {
        "es": "Copiar",
        "fr": "Copier",
        "de": "Kopieren",
        "it": "Copia",
        "ja": "コピー",
        "ko": "복사",
        "zh": "复制",
        "zh_CN": "复制",
    },
    ("Menu", "Paste"): {
        "es": "Pegar",
        "fr": "Coller",
        "de": "Einfügen",
        "it": "Incolla",
        "ja": "貼り付け",
        "ko": "붙여넣기",
        "zh": "粘贴",
        "zh_CN": "粘贴",
    },
    ("Menu", "Select All"): {
        "es": "Seleccionar todo",
        "fr": "Tout sélectionner",
        "de": "Alles auswählen",
        "it": "Seleziona tutto",
        "ja": "すべて選択",
        "ko": "모두 선택",
        "zh": "全选",
        "zh_CN": "全选",
    },
    ("Menu", "Mark Frame"): {
        "es": "Marcar fotograma",
        "fr": "Marquer l'image",
        "de": "Frame markieren",
        "it": "Contrassegna fotogramma",
        "ja": "フレームをマーク",
        "ko": "프레임 표시",
        "zh": "标记帧",
        "zh_CN": "标记帧",
    },
    ("Menu", "Clear All Marks"): {
        "es": "Borrar todas las marcas",
        "fr": "Effacer toutes les marques",
        "de": "Alle Markierungen löschen",
        "it": "Cancella tutti i contrassegni",
        "ja": "すべてのマークをクリア",
        "ko": "모든 표시 지우기",
        "zh": "清除所有标记",
        "zh_CN": "清除所有标记",
    },
    ("Menu", "Mark Sequence Boundaries"): {
        "es": "Marcar límites de secuencia",
        "fr": "Marquer les limites de séquence",
        "de": "Sequenzgrenzen markieren",
        "it": "Contrassegna limiti sequenza",
        "ja": "シーケンス境界をマーク",
        "ko": "시퀀스 경계 표시",
        "zh": "标记序列边界",
        "zh_CN": "标记序列边界",
    },
    ("Menu", "Mark Annotated Frames"): {
        "es": "Marcar fotogramas anotados",
        "fr": "Marquer les images annotées",
        "de": "Kommentierte Frames markieren",
        "it": "Contrassegna fotogrammi annotati",
        "ja": "注釈付きフレームをマーク",
        "ko": "주석 달린 프레임 표시",
        "zh": "标记有注释的帧",
        "zh_CN": "标记有注释的帧",
    },
    ("Menu", "Set Range In Point"): {
        "es": "Establecer punto de entrada del rango",
        "fr": "Définir le point d'entrée de plage",
        "de": "Bereich-Startpunkt setzen",
        "it": "Imposta punto di attacco intervallo",
        "ja": "インポイントを設定",
        "ko": "시작점 설정",
        "zh": "设置入点",
        "zh_CN": "设置入点",
    },
    ("Menu", "Set Range Out Point"): {
        "es": "Establecer punto de salida del rango",
        "fr": "Définir le point de sortie de plage",
        "de": "Bereich-Endpunkt setzen",
        "it": "Imposta punto di stacco intervallo",
        "ja": "アウトポイントを設定",
        "ko": "끝점 설정",
        "zh": "设置出点",
        "zh_CN": "设置出点",
    },
    ("Menu", "View"): {
        "es": "Ver",
        "fr": "Affichage",
        "de": "Ansicht",
        "it": "Vista",
        "ja": "表示",
        "ko": "보기",
        "zh": "视图",
        "zh_CN": "视图",
    },
    ("Menu", "Full Screen"): {
        "es": "Pantalla completa",
        "fr": "Plein écran",
        "de": "Vollbild",
        "it": "Schermo intero",
        "ja": "フルスクリーン",
        "ko": "전체 화면",
        "zh": "全屏",
        "zh_CN": "全屏",
    },
    ("Menu", "Fit to Window"): {
        "es": "Ajustar a la ventana",
        "fr": "Ajuster à la fenêtre",
        "de": "An Fenster anpassen",
        "it": "Adatta alla finestra",
        "ja": "ウィンドウに合わせる",
        "ko": "창에 맞추기",
        "zh": "适应窗口",
        "zh_CN": "适应窗口",
    },
    ("Menu", "Center"): {
        "es": "Centrar",
        "fr": "Centrer",
        "de": "Zentrieren",
        "it": "Centra",
        "ja": "中央揃え",
        "ko": "가운데 맞춤",
        "zh": "居中",
        "zh_CN": "居中",
    },
    ("Menu", "Show Controls"): {
        "es": "Mostrar controles",
        "fr": "Afficher les contrôles",
        "de": "Steuerelemente anzeigen",
        "it": "Mostra controlli",
        "ja": "コントロールを表示",
        "ko": "컨트롤 표시",
        "zh": "显示控件",
        "zh_CN": "显示控件",
    },
    ("Menu", "Show Timeline"): {
        "es": "Mostrar línea de tiempo",
        "fr": "Afficher la timeline",
        "de": "Timeline anzeigen",
        "it": "Mostra timeline",
        "ja": "タイムラインを表示",
        "ko": "타임라인 표시",
        "zh": "显示时间线",
        "zh_CN": "显示时间线",
    },
    ("Menu", "Show HUD"): {
        "es": "Mostrar HUD",
        "fr": "Afficher le HUD",
        "de": "HUD anzeigen",
        "it": "Mostra HUD",
        "ja": "HUDを表示",
        "ko": "HUD 표시",
        "zh": "显示HUD",
        "zh_CN": "显示HUD",
    },
    ("Menu", "Image"): {
        "es": "Imagen",
        "fr": "Image",
        "de": "Bild",
        "it": "Immagine",
        "ja": "画像",
        "ko": "이미지",
        "zh": "图像",
        "zh_CN": "图像",
    },
    ("Menu", "Color"): {
        "es": "Color",
        "fr": "Couleur",
        "de": "Farbe",
        "it": "Colore",
        "ja": "カラー",
        "ko": "색상",
        "zh": "颜色",
        "zh_CN": "颜色",
    },
    ("Menu", "Gamma"): {
        "es": "Gamma",
        "fr": "Gamma",
        "de": "Gamma",
        "it": "Gamma",
        "ja": "ガンマ",
        "ko": "감마",
        "zh": "伽玛",
        "zh_CN": "伽玛",
    },
    ("Menu", "Exposure"): {
        "es": "Exposición",
        "fr": "Exposition",
        "de": "Belichtung",
        "it": "Esposizione",
        "ja": "露出",
        "ko": "노출",
        "zh": "曝光",
        "zh_CN": "曝光",
    },
    ("Menu", "Channel"): {
        "es": "Canal",
        "fr": "Canal",
        "de": "Kanal",
        "it": "Canale",
        "ja": "チャンネル",
        "ko": "채널",
        "zh": "通道",
        "zh_CN": "通道",
    },
    ("Menu", "Playback"): {
        "es": "Reproducción",
        "fr": "Lecture",
        "de": "Wiedergabe",
        "it": "Riproduzione",
        "ja": "再生",
        "ko": "재생",
        "zh": "播放",
        "zh_CN": "播放",
    },
    ("Menu", "Play"): {
        "es": "Reproducir",
        "fr": "Lire",
        "de": "Abspielen",
        "it": "Riproduci",
        "ja": "再生",
        "ko": "재생",
        "zh": "播放",
        "zh_CN": "播放",
    },
    ("Menu", "Stop"): {
        "es": "Detener",
        "fr": "Arrêter",
        "de": "Stopp",
        "it": "Interrompi",
        "ja": "停止",
        "ko": "정지",
        "zh": "停止",
        "zh_CN": "停止",
    },
    ("Menu", "Step Forward"): {
        "es": "Avanzar un fotograma",
        "fr": "Image suivante",
        "de": "Einen Frame vorwärts",
        "it": "Fotogramma successivo",
        "ja": "1フレーム進む",
        "ko": "1프레임 앞으로",
        "zh": "前进一帧",
        "zh_CN": "前进一帧",
    },
    ("Menu", "Step Backward"): {
        "es": "Retroceder un fotograma",
        "fr": "Image précédente",
        "de": "Einen Frame zurück",
        "it": "Fotogramma precedente",
        "ja": "1フレーム戻る",
        "ko": "1프레임 뒤로",
        "zh": "后退一帧",
        "zh_CN": "后退一帧",
    },
    ("Menu", "Loop"): {
        "es": "Bucle",
        "fr": "Boucle",
        "de": "Schleife",
        "it": "Ripeti",
        "ja": "ループ",
        "ko": "반복",
        "zh": "循环",
        "zh_CN": "循环",
    },
    ("Menu", "Session"): {
        "es": "Sesión",
        "fr": "Session",
        "de": "Sitzung",
        "it": "Sessione",
        "ja": "セッション",
        "ko": "세션",
        "zh": "会话",
        "zh_CN": "会话",
    },
    ("Menu", "Session Manager"): {
        "es": "Gestor de sesiones",
        "fr": "Gestionnaire de sessions",
        "de": "Sitzungsmanager",
        "it": "Gestore sessioni",
        "ja": "セッションマネージャー",
        "ko": "세션 관리자",
        "zh": "会话管理器",
        "zh_CN": "会话管理器",
    },
    ("Menu", "Help"): {
        "es": "Ayuda",
        "fr": "Aide",
        "de": "Hilfe",
        "it": "Aiuto",
        "ja": "ヘルプ",
        "ko": "도움말",
        "zh": "帮助",
        "zh_CN": "帮助",
    },
    ("Menu", "Check for Updates..."): {
        "es": "Buscar actualizaciones...",
        "fr": "Vérifier les mises à jour...",
        "de": "Nach Updates suchen...",
        "it": "Controlla aggiornamenti...",
        "ja": "アップデートを確認...",
        "ko": "업데이트 확인...",
        "zh": "检查更新...",
        "zh_CN": "检查更新...",
    },
    ("Menu", "Report Issue on GitHub..."): {
        "es": "Reportar problema en GitHub...",
        "fr": "Signaler un problème sur GitHub...",
        "de": "Problem auf GitHub melden...",
        "it": "Segnala problema su GitHub...",
        "ja": "GitHubで問題を報告...",
        "ko": "GitHub에서 문제 신고...",
        "zh": "在GitHub上报告问题...",
        "zh_CN": "在GitHub上报告问题...",
    },
    ("Menu", "Online Resources"): {
        "es": "Recursos en línea",
        "fr": "Ressources en ligne",
        "de": "Online-Ressourcen",
        "it": "Risorse online",
        "ja": "オンラインリソース",
        "ko": "온라인 리소스",
        "zh": "在线资源",
        "zh_CN": "在线资源",
    },
    ("Menu", "Utilities"): {
        "es": "Utilidades",
        "fr": "Utilitaires",
        "de": "Dienstprogramme",
        "it": "Utilità",
        "ja": "ユーティリティ",
        "ko": "유틸리티",
        "zh": "实用工具",
        "zh_CN": "实用工具",
    },
    ("Menu", "Preferences..."): {
        "es": "Preferencias...",
        "fr": "Préférences...",
        "de": "Einstellungen...",
        "it": "Preferenze...",
        "ja": "環境設定...",
        "ko": "환경설정...",
        "zh": "首选项...",
        "zh_CN": "首选项...",
    },
    # -------------------------------------------------------------------------
    # RvPreferences Dialog
    # -------------------------------------------------------------------------
    ("RvPreferences", "General"): {
        "es": "General",
        "fr": "Général",
        "de": "Allgemein",
        "it": "Generale",
        "ja": "一般",
        "ko": "일반",
        "zh": "常规",
        "zh_CN": "常规",
    },
    ("RvPreferences", "Language"): {
        "es": "Idioma",
        "fr": "Langue",
        "de": "Sprache",
        "it": "Lingua",
        "ja": "言語",
        "ko": "언어",
        "zh": "语言",
        "zh_CN": "语言",
    },
    ("RvPreferences", "Font Size"): {
        "es": "Tamaño de fuente",
        "fr": "Taille de police",
        "de": "Schriftgröße",
        "it": "Dimensione carattere",
        "ja": "フォントサイズ",
        "ko": "글꼴 크기",
        "zh": "字体大小",
        "zh_CN": "字体大小",
    },
    ("RvPreferences", "Session Manager Font Size"): {
        "es": "Tamaño de fuente del gestor de sesiones",
        "fr": "Taille de police du gestionnaire de sessions",
        "de": "Schriftgröße des Sitzungsmanagers",
        "it": "Dimensione carattere gestore sessioni",
        "ja": "セッションマネージャーのフォントサイズ",
        "ko": "세션 관리자 글꼴 크기",
        "zh": "会话管理器字体大小",
        "zh_CN": "会话管理器字体大小",
    },
    ("RvPreferences", "Default Playback Mode"): {
        "es": "Modo de reproducción predeterminado",
        "fr": "Mode de lecture par défaut",
        "de": "Standard-Wiedergabemodus",
        "it": "Modalità di riproduzione predefinita",
        "ja": "デフォルトの再生モード",
        "ko": "기본 재생 모드",
        "zh": "默认播放模式",
        "zh_CN": "默认播放模式",
    },
    ("RvPreferences", "Default Stereo Mode"): {
        "es": "Modo estéreo predeterminado",
        "fr": "Mode stéréo par défaut",
        "de": "Standard-Stereomodus",
        "it": "Modalità stereo predefinita",
        "ja": "デフォルトのステレオモード",
        "ko": "기본 스테레오 모드",
        "zh": "默认立体模式",
        "zh_CN": "默认立体模式",
    },
    ("RvPreferences", "Default FPS"): {
        "es": "FPS predeterminado",
        "fr": "IPS par défaut",
        "de": "Standard-FPS",
        "it": "FPS predefinito",
        "ja": "デフォルトFPS",
        "ko": "기본 FPS",
        "zh": "默认FPS",
        "zh_CN": "默认FPS",
    },
    ("RvPreferences", "Startup Screen"): {
        "es": "Pantalla de inicio",
        "fr": "Écran de démarrage",
        "de": "Startbildschirm",
        "it": "Schermo di avvio",
        "ja": "起動画面",
        "ko": "시작 화면",
        "zh": "启动屏幕",
        "zh_CN": "启动屏幕",
    },
    ("RvPreferences", "Play on Start Up"): {
        "es": "Reproducir al iniciar",
        "fr": "Lire au démarrage",
        "de": "Beim Start abspielen",
        "it": "Riproduci all'avvio",
        "ja": "起動時に再生",
        "ko": "시작 시 재생",
        "zh": "启动时播放",
        "zh_CN": "启动时播放",
    },
    ("RvPreferences", "Start in Fullscreen Mode"): {
        "es": "Iniciar en modo pantalla completa",
        "fr": "Démarrer en mode plein écran",
        "de": "Im Vollbildmodus starten",
        "it": "Avvia a schermo intero",
        "ja": "フルスクリーンモードで起動",
        "ko": "전체 화면으로 시작",
        "zh": "全屏模式启动",
        "zh_CN": "全屏模式启动",
    },
    ("RvPreferences", "Desktop Aware"): {
        "es": "Sensible al escritorio",
        "fr": "Conscience du bureau",
        "de": "Desktop-orientiert",
        "it": "Rileva desktop",
        "ja": "デスクトップ対応",
        "ko": "데스크톱 인식",
        "zh": "识别桌面环境",
        "zh_CN": "识别桌面环境",
    },
    ("RvPreferences", "Click in View to Play"): {
        "es": "Hacer clic en la vista para reproducir",
        "fr": "Cliquer dans la vue pour lire",
        "de": "Zum Abspielen in Ansicht klicken",
        "it": "Clicca nella vista per riprodurre",
        "ja": "ビュー内をクリックして再生",
        "ko": "뷰를 클릭하여 재생",
        "zh": "点击视图进行播放",
        "zh_CN": "点击视图进行播放",
    },
    ("RvPreferences", "Fit Window to First Media Loaded"): {
        "es": "Ajustar ventana al primer medio cargado",
        "fr": "Ajuster la fenêtre au premier média chargé",
        "de": "Fenster an erstes geladenes Medium anpassen",
        "it": "Adatta finestra al primo supporto caricato",
        "ja": "最初に読み込んだメディアにウィンドウを合わせる",
        "ko": "처음 로드된 미디어에 창 맞추기",
        "zh": "将窗口调整到首个加载媒体大小",
        "zh_CN": "将窗口调整到首个加载媒体大小",
    },
    ("RvPreferences", "Hide Menu Bar by Default"): {
        "es": "Ocultar barra de menú por defecto",
        "fr": "Masquer la barre de menu par défaut",
        "de": "Menüleiste standardmäßig ausblenden",
        "it": "Nascondi barra menu per impostazione predefinita",
        "ja": "デフォルトでメニューバーを非表示",
        "ko": "기본적으로 메뉴 바 숨기기",
        "zh": "默认隐藏菜单栏",
        "zh_CN": "默认隐藏菜单栏",
    },
    ("RvPreferences", "Auto-Retime Mismatched FPS Media"): {
        "es": "Ajustar automáticamente medios con FPS discordantes",
        "fr": "Recaler automatiquement les médias à IPS discordant",
        "de": "Medien mit abweichender FPS automatisch anpassen",
        "it": "Regola automaticamente media con FPS non corrispondenti",
        "ja": "不一致なFPSメディアを自動リタイム",
        "ko": "일치하지 않는 FPS 미디어 자동 리타임",
        "zh": "自动重定时不同帧率的媒体",
        "zh_CN": "自动重定时不同帧率的媒体",
    },
    ("RvPreferences", "System Default"): {
        "es": "Predeterminado del sistema",
        "fr": "Langue du système",
        "de": "Systemstandard",
        "it": "Predefinito di sistema",
        "ja": "システムのデフォルト",
        "ko": "시스템 기본값",
        "zh": "系统默认",
        "zh_CN": "系统默认",
    },
    ("RvPreferences", "English"): {
        "es": "Inglés",
        "fr": "Anglais",
        "de": "Englisch",
        "it": "Inglese",
        "ja": "英語",
        "ko": "영어",
        "zh": "英语",
        "zh_CN": "英语",
    },
    ("RvPreferences", "Language Changed"): {
        "es": "Idioma cambiado",
        "fr": "Langue modifiée",
        "de": "Sprache geändert",
        "it": "Lingua modificata",
        "ja": "言語が変更されました",
        "ko": "언어가 변경되었습니다",
        "zh": "语言已更改",
        "zh_CN": "语言已更改",
    },
    (
        "RvPreferences",
        "The user interface language has been changed. Please restart OpenUTV for all changes to take full effect.",
    ): {
        "es": "Se ha cambiado el idioma de la interfaz. Reinicie OpenUTV para que todos los cambios surtan efecto.",
        "fr": "La langue de l'interface utilisateur a été modifiée. Veuillez redémarrer OpenUTV pour appliquer les modifications.",
        "de": "Die Sprache der Benutzeroberfläche wurde geändert. Bitte starten Sie OpenUTV neu, damit alle Änderungen wirksam werden.",
        "it": "La lingua dell'interfaccia utente è stata modificata. Riavviare OpenUTV affinché tutte le modifiche abbiano effetto.",
        "ja": "UIの言語が変更されました。変更を完全に適用するにはOpenUTVを再起動してください。",
        "ko": "사용자 인터페이스 언어가 변경되었습니다. 모든 변경 사항을 적용하려면 OpenUTV를 다시 시작하십시오.",
        "zh": "用户界面语言已更改。请重启 OpenUTV 以使所有更改完全生效。",
        "zh_CN": "用户界面语言已更改。请重启 OpenUTV 以使所有更改完全生效。",
    },
    # -------------------------------------------------------------------------
    # Toolbars & Tooltips
    # -------------------------------------------------------------------------
    ("RvBottomViewToolBar", "Toggle Session Manager"): {
        "es": "Alternar gestor de sesiones",
        "fr": "Basculer le gestionnaire de sessions",
        "de": "Sitzungsmanager umschalten",
        "it": "Attiva/disattiva gestore sessioni",
        "ja": "セッションマネージャーの切り替え",
        "ko": "세션 관리자 전환",
        "zh": "切换会话管理器",
        "zh_CN": "切换会话管理器",
    },
    ("RvBottomViewToolBar", "Toggle Annotation tools"): {
        "es": "Alternar herramientas de anotación",
        "fr": "Basculer les outils d'annotation",
        "de": "Anmerkungswerkzeuge umschalten",
        "it": "Attiva/disattiva strumenti di annotazione",
        "ja": "注釈ツールの切り替え",
        "ko": "주석 도구 전환",
        "zh": "切换注释工具",
        "zh_CN": "切换注释工具",
    },
    ("RvBottomViewToolBar", "Toggle Image Info"): {
        "es": "Alternar información de imagen",
        "fr": "Basculer les informations de l'image",
        "de": "Bildinformationen umschalten",
        "it": "Attiva/disattiva informazioni immagine",
        "ja": "画像情報の切り替え",
        "ko": "이미지 정보 전환",
        "zh": "切换图像信息",
        "zh_CN": "切换图像信息",
    },
    ("RvBottomViewToolBar", "Toggle RV Networking Dialog"): {
        "es": "Alternar diálogo de red RV",
        "fr": "Basculer le dialogue réseau RV",
        "de": "RV-Netzwerkdialog umschalten",
        "it": "Attiva/disattiva finestra di rete RV",
        "ja": "RVネットワークダイアログの切り替え",
        "ko": "RV 네트워킹 대화상자 전환",
        "zh": "切换RV网络对话框",
        "zh_CN": "切换RV网络对话框",
    },
    ("RvBottomViewToolBar", "Toggle Timeline Magnifier"): {
        "es": "Alternar lupa de línea de tiempo",
        "fr": "Basculer la loupe de timeline",
        "de": "Timeline-Lupe umschalten",
        "it": "Attiva/disattiva lente di ingrandimento timeline",
        "ja": "タイムライン拡大鏡の切り替え",
        "ko": "타임라인 돋보기 전환",
        "zh": "切换时间线放大镜",
        "zh_CN": "切换时间线放大镜",
    },
    ("RvBottomViewToolBar", "Toggle Timeline"): {
        "es": "Alternar línea de tiempo",
        "fr": "Basculer la timeline",
        "de": "Timeline umschalten",
        "it": "Attiva/disattiva timeline",
        "ja": "タイムラインの切り替え",
        "ko": "타임라인 전환",
        "zh": "切换时间线",
        "zh_CN": "切换时间线",
    },
    ("RvBottomViewToolBar", "Ghost"): {
        "es": "Fantasma",
        "fr": "Fantôme",
        "de": "Geisterbild",
        "it": "Fantasma",
        "ja": "ゴースト",
        "ko": "고스트",
        "zh": "残影",
        "zh_CN": "残影",
    },
    ("RvBottomViewToolBar", "Hold"): {
        "es": "Mantener",
        "fr": "Maintien",
        "de": "Halten",
        "it": "Mantieni",
        "ja": "ホールド",
        "ko": "고정",
        "zh": "定格",
        "zh_CN": "定格",
    },
    ("RvBottomViewToolBar", "Step back one frame"): {
        "es": "Retroceder un fotograma",
        "fr": "Reculer d'une image",
        "de": "Einen Frame zurück",
        "it": "Indietro di un fotogramma",
        "ja": "1フレーム戻る",
        "ko": "1프레임 뒤로",
        "zh": "后退一帧",
        "zh_CN": "后退一帧",
    },
    ("RvBottomViewToolBar", "Step forward one frame"): {
        "es": "Avanzar un fotograma",
        "fr": "Avancer d'une image",
        "de": "Einen Frame vorwärts",
        "it": "Avanti di un fotogramma",
        "ja": "1フレーム進む",
        "ko": "1프레임 앞으로",
        "zh": "前进一帧",
        "zh_CN": "前进一帧",
    },
    ("RvBottomViewToolBar", "Play backwards"): {
        "es": "Reproducir hacia atrás",
        "fr": "Lecture arrière",
        "de": "Rückwärts abspielen",
        "it": "Riproduci all'indietro",
        "ja": "逆再生",
        "ko": "뒤로 재생",
        "zh": "倒序播放",
        "zh_CN": "倒序播放",
    },
    ("RvBottomViewToolBar", "Play forwards"): {
        "es": "Reproducir hacia adelante",
        "fr": "Lecture avant",
        "de": "Vorwärts abspielen",
        "it": "Riproduci in avanti",
        "ja": "前方に再生",
        "ko": "앞으로 재생",
        "zh": "顺向播放",
        "zh_CN": "顺向播放",
    },
    ("RvBottomViewToolBar", "Skip to start of sequence"): {
        "es": "Ir al inicio de la secuencia",
        "fr": "Aller au début de la séquence",
        "de": "Zum Anfang der Sequenz springen",
        "it": "Vai all'inizio della sequenza",
        "ja": "シーケンスの先頭へスキップ",
        "ko": "시퀀스 시작 위치로 이동",
        "zh": "跳至序列起始",
        "zh_CN": "跳至序列起始",
    },
    ("RvBottomViewToolBar", "Skip to end of sequence"): {
        "es": "Ir al final de la secuencia",
        "fr": "Aller à la fin de la séquence",
        "de": "Zum Ende der Sequenz springen",
        "it": "Vai alla fine della sequenza",
        "ja": "シーケンスの最後へスキップ",
        "ko": "시퀀스 끝 위치로 이동",
        "zh": "跳至序列末尾",
        "zh_CN": "跳至序列末尾",
    },
    ("RvBottomViewToolBar", "Audio control"): {
        "es": "Control de audio",
        "fr": "Contrôle audio",
        "de": "Audiosteuerung",
        "it": "Controllo audio",
        "ja": "オーディオコントロール",
        "ko": "오디오 제어",
        "zh": "音频控制",
        "zh_CN": "音频控制",
    },
    ("RvTopViewToolBar", "Switch to previous View"): {
        "es": "Cambiar a la vista anterior",
        "fr": "Passer à la vue précédente",
        "de": "Zur vorherigen Ansicht wechseln",
        "it": "Passa alla vista precedente",
        "ja": "前のビューに切り替え",
        "ko": "이전 뷰로 전환",
        "zh": "切换到上一个视图",
        "zh_CN": "切换到上一个视图",
    },
    ("RvTopViewToolBar", "Switch to next View"): {
        "es": "Cambiar a la vista siguiente",
        "fr": "Passer à la vue suivante",
        "de": "Zur nächsten Ansicht wechseln",
        "it": "Passa alla vista successiva",
        "ja": "次のビューに切り替え",
        "ko": "다음 뷰로 전환",
        "zh": "切换到下一个视图",
        "zh_CN": "切换到下一个视图",
    },
    ("RvTopViewToolBar", "Select a View"): {
        "es": "Seleccionar una vista",
        "fr": "Sélectionner une vue",
        "de": "Ansicht auswählen",
        "it": "Seleziona una vista",
        "ja": "ビューを選択",
        "ko": "뷰 선택",
        "zh": "选择视图",
        "zh_CN": "选择视图",
    },
    ("RvTopViewToolBar", "Toggle full-screen mode"): {
        "es": "Alternar modo de pantalla completa",
        "fr": "Basculer en mode plein écran",
        "de": "Vollbildmodus umschalten",
        "it": "Attiva/disattiva schermo intero",
        "ja": "フルスクリーンモードの切り替え",
        "ko": "전체 화면 모드 전환",
        "zh": "切换全屏模式",
        "zh_CN": "切换全屏模式",
    },
    ("RvTopViewToolBar", "Frame image in view"): {
        "es": "Encuadrar imagen en vista",
        "fr": "Cadrer l'image dans la vue",
        "de": "Bild in Ansicht einpassen",
        "it": "Inquadra immagine nella vista",
        "ja": "画像をビューに収める",
        "ko": "뷰에 이미지 맞추기",
        "zh": "在视图中居中框选图像",
        "zh_CN": "在视图中居中框选图像",
    },
    ("RvTopViewToolBar", "Select background style"): {
        "es": "Seleccionar estilo de fondo",
        "fr": "Sélectionner le style d'arrière-plan",
        "de": "Hintergrundstil auswählen",
        "it": "Seleziona stile sfondo",
        "ja": "背景スタイルを選択",
        "ko": "배경 스타일 선택",
        "zh": "选择背景样式",
        "zh_CN": "选择背景样式",
    },
    ("RvTopViewToolBar", "Select stereoscopic output style"): {
        "es": "Seleccionar estilo de salida estereoscópica",
        "fr": "Sélectionner le style de sortie stéréoscopique",
        "de": "Stereoskopischen Ausgabestil auswählen",
        "it": "Seleziona stile output stereoscopico",
        "ja": "立体視出力スタイルを選択",
        "ko": "입체 출력 스타일 선택",
        "zh": "选择立体输出样式",
        "zh_CN": "选择立体输出样式",
    },
    ("RvTopViewToolBar", "Color channel view control"): {
        "es": "Control de vista de canales de color",
        "fr": "Contrôle de visualisation des canaux de couleur",
        "de": "Farbkanal-Ansichtssteuerung",
        "it": "Controllo vista canali colore",
        "ja": "カラーチャンネル表示制御",
        "ko": "색상 채널 뷰 제어",
        "zh": "颜色通道视图控制",
        "zh_CN": "颜色通道视图控制",
    },
    ("RvTopViewToolBar", "Configure display device"): {
        "es": "Configurar dispositivo de pantalla",
        "fr": "Configurer le périphérique d'affichage",
        "de": "Anzeigegerät konfigurieren",
        "it": "Configura dispositivo di visualizzazione",
        "ja": "ディスプレイデバイスを設定",
        "ko": "디스플레이 장치 구성",
        "zh": "配置显示设备",
        "zh_CN": "配置显示设备",
    },
    # -------------------------------------------------------------------------
    # RvApplication / Dialogs
    # -------------------------------------------------------------------------
    ("RvApplication", "Preferences..."): {
        "es": "Preferencias...",
        "fr": "Préférences...",
        "de": "Einstellungen...",
        "it": "Preferenze...",
        "ja": "環境設定...",
        "ko": "환경설정...",
        "zh": "首选项...",
        "zh_CN": "首选项...",
    },
    ("RvApplication", "Configure RV for this computer"): {
        "es": "Configurar RV para este ordenador",
        "fr": "Configurer RV pour cet ordinateur",
        "de": "RV für diesen Computer konfigurieren",
        "it": "Configura RV per questo computer",
        "ja": "このコンピューター用にRVを設定",
        "ko": "이 컴퓨터에 맞게 RV 구성",
        "zh": "为此计算机配置RV",
        "zh_CN": "为此计算机配置RV",
    },
    ("RvApplication", "Network..."): {
        "es": "Red...",
        "fr": "Réseau...",
        "de": "Netzwerk...",
        "it": "Rete...",
        "ja": "ネットワーク...",
        "ko": "네트워크...",
        "zh": "网络...",
        "zh_CN": "网络...",
    },
    ("RvDocument", "Audio Failure"): {
        "es": "Fallo de audio",
        "fr": "Échec audio",
        "de": "Audiofehler",
        "it": "Errore audio",
        "ja": "オーディオの障害",
        "ko": "오디오 오류",
        "zh": "音频故障",
        "zh_CN": "音频故障",
    },
    ("RvDocument", "Audio Device is Currently Unavailable"): {
        "es": "El dispositivo de audio no está disponible actualmente",
        "fr": "Le périphérique audio est actuellement indisponible",
        "de": "Das Audiogerät ist derzeit nicht verfügbar",
        "it": "Il dispositivo audio non è attualmente disponibile",
        "ja": "オーディオデバイスは現在使用できません",
        "ko": "오디오 장치를 현재 사용할 수 없습니다",
        "zh": "音频设备当前不可用",
        "zh_CN": "音频设备当前不可用",
    },
    ("RvDocument", "Change Preferences Manually"): {
        "es": "Cambiar preferencias manualmente",
        "fr": "Modifier les préférences manuellement",
        "de": "Einstellungen manuell ändern",
        "it": "Modifica preferenze manualmente",
        "ja": "環境設定を手動で変更",
        "ko": "수동으로 환경설정 변경",
        "zh": "手动更改首选项",
        "zh_CN": "手动更改首选项",
    },
    ("QObject", "Default Sequence"): {
        "es": "Secuencia predeterminada",
        "fr": "Séquence par défaut",
        "de": "Standardsequenz",
        "it": "Sequenza predefinita",
        "ja": "デフォルトシーケンス",
        "ko": "기본 시퀀스",
        "zh": "默认序列",
        "zh_CN": "默认序列",
    },
    ("MainWindow", "Default Sequence"): {
        "es": "Secuencia predeterminada",
        "fr": "Séquence par défaut",
        "de": "Standardsequenz",
        "it": "Sequenza predefinita",
        "ja": "デフォルトシーケンス",
        "ko": "기본 시퀀스",
        "zh": "默认序列",
        "zh_CN": "默认序列",
    },
}

LANGUAGES = ["en", "es", "fr", "de", "it", "ja", "ko", "zh", "zh_CN"]
CACHE_FILE = os.path.join(SCRIPT_DIR, "translations_cache.json")


def load_cache():
    cache = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                cache = json.load(f)
        except Exception as e:
            print(f"Warning: Failed to load cache: {e}")

    # Seed with curated TRANSLATIONS
    for (ctx, src), lang_map in TRANSLATIONS.items():
        if src not in cache:
            cache[src] = {}
        for lang_code, val in lang_map.items():
            cache[src][lang_code] = val
    return cache


def scan_repo():
    repo_root = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "..", "..", "..", ".."))
    contexts = {}

    def add_string(ctx, s):
        if not s:
            return
        s = s.strip()
        if not s or s == "_" or len(s) < 2:
            return
        if re.match(r"^[0-9\.\,\:\;\s\-\+\*\/\#\@\$\%\^\&\(\)\[\]\{\}\<\>\=\_\'\|\`\~\?\!]+$", s):
            return
        if s.startswith("key-") or s.startswith("event-") or s.startswith("http://") or s.startswith("https://"):
            return
        if s.startswith("internal_"):
            return
        if ctx not in contexts:
            contexts[ctx] = set()
        contexts[ctx].add(s)

    # 1. UI files
    for root, dirs, files in os.walk(os.path.join(repo_root, "src")):
        for f in files:
            if f.endswith(".ui"):
                path = os.path.join(root, f)
                try:
                    tree = ET.parse(path)
                    cls_elem = tree.find("class")
                    ctx = cls_elem.text if cls_elem is not None and cls_elem.text else os.path.splitext(f)[0]
                    for elem in tree.iter("string"):
                        if elem.text:
                            add_string(ctx, elem.text)
                except Exception:
                    pass

    # 2. Mu and Python menus
    patterns = [
        re.compile(r"menuItem\s*\(\s*\"([^\"]+)\""),
        re.compile(r"subMenu\s*\(\s*\"([^\"]+)\""),
        re.compile(r"addMenu\s*\(\s*\"([^\"]+)\""),
        re.compile(r"insertMenu\s*\(\s*\"([^\"]+)\""),
        re.compile(r"defineMenu\s*\(\s*\"([^\"]+)\""),
        re.compile(r"\{\s*\"([A-Za-z][A-Za-z0-9\s\.\_\-\/\:\?\!\(\)\'\,\+\%]*)\"\s*\,"),
    ]

    for root, dirs, files in os.walk(os.path.join(repo_root, "src")):
        for f in files:
            if f.endswith(".mu") or f.endswith(".py"):
                path = os.path.join(root, f)
                with open(path, "r", errors="ignore") as fp:
                    for line in fp:
                        for p in patterns:
                            for m in p.finditer(line):
                                add_string("Menu", m.group(1))

    # 3. C++ tr()
    tr_pattern = re.compile(r"\btr\s*\(\s*\"([^\"]+)\"\s*\)")
    for root, dirs, files in os.walk(os.path.join(repo_root, "src")):
        for f in files:
            if f.endswith(".cpp") or f.endswith(".h"):
                path = os.path.join(root, f)
                ctx = os.path.splitext(f)[0]
                with open(path, "r", errors="ignore") as fp:
                    for line in fp:
                        for m in tr_pattern.finditer(line):
                            add_string(ctx, m.group(1))

    # Add existing curated translations
    for ctx, src in TRANSLATIONS:
        add_string(ctx, src)

    # Universal QObject fallback
    contexts["QObject"] = set()
    for c, s_set in contexts.items():
        if c != "QObject":
            contexts["QObject"].update(s_set)

    return contexts


def generate_ts(lang, contexts, cache):
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        "<!DOCTYPE TS>",
        f'<TS version="2.1" language="{lang}">',
    ]

    for ctx, s_set in sorted(contexts.items()):
        lines.append("<context>")
        lines.append(f"    <name>{xml.sax.saxutils.escape(ctx)}</name>")
        for src in sorted(s_set):
            esc_src = xml.sax.saxutils.escape(src)
            trans = src if lang == "en" else ""
            if lang in cache.get(src, {}):
                trans = cache[src][lang]
            esc_trans = xml.sax.saxutils.escape(trans)
            lines.append("    <message>")
            lines.append(f"        <source>{esc_src}</source>")
            if trans:
                lines.append(f"        <translation>{esc_trans}</translation>")
            else:
                lines.append('        <translation type="unfinished"></translation>')
            lines.append("    </message>")
        lines.append("</context>")

    lines.append("</TS>\n")
    return "\n".join(lines)


def translate_batch(strings, target_lang):
    if not strings:
        return {}
    api_lang = "zh-CN" if target_lang in ("zh", "zh_CN") else target_lang
    numbered = [f"{i}@@@{s}" for i, s in enumerate(strings)]
    combined = "\n".join(numbered)
    url = (
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl="
        + api_lang
        + "&dt=t&q="
        + urllib.parse.quote(combined)
    )
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})

    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                full_text = "".join([part[0] for part in data[0] if part[0]])
                results = {}
                for line in full_text.split("\n"):
                    if "@@@" in line:
                        parts = line.split("@@@", 1)
                        try:
                            idx = int(parts[0].strip())
                            if idx < len(strings):
                                results[strings[idx]] = parts[1].strip()
                        except Exception:
                            pass
                return results
        except Exception:
            time.sleep(1 + attempt)
    return {}


def ensure_translations(contexts, cache):
    all_strings = set()
    for s_set in contexts.values():
        all_strings.update(s_set)

    target_langs = ["fr", "es", "de", "it", "ja", "ko", "zh"]
    updated = False
    for lang in target_langs:
        missing = [s for s in sorted(all_strings) if s not in cache or lang not in cache[s] or not cache[s][lang]]
        if missing:
            print(f"[{lang}] Auto-translating {len(missing)} missing strings...")
            batch_size = 25
            for i in range(0, len(missing), batch_size):
                chunk = missing[i : i + batch_size]
                res = translate_batch(chunk, lang)
                for s in chunk:
                    if s not in cache:
                        cache[s] = {}
                    if s in res and res[s]:
                        cache[s][lang] = res[s]
                    else:
                        cache[s][lang] = s
                time.sleep(0.1)
            updated = True

    for s in all_strings:
        if s in cache and "zh" in cache[s]:
            cache[s]["zh_CN"] = cache[s]["zh"]

    if updated:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2)
        print("Updated cache saved.")


def main():
    cache = load_cache()
    contexts = scan_repo()
    ensure_translations(contexts, cache)

    lrelease_bin = "/opt/homebrew/bin/lrelease"
    if not os.path.exists(lrelease_bin):
        import shutil

        lrelease_bin = shutil.which("lrelease") or "lrelease"

    for lang in LANGUAGES:
        ts_path = os.path.join(SCRIPT_DIR, f"i18n_{lang}.ts")
        qm_path = os.path.join(SCRIPT_DIR, f"i18n_{lang}.qm")

        content = generate_ts(lang, contexts, cache)
        with open(ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Wrote {ts_path}")

        try:
            res = subprocess.run([lrelease_bin, ts_path, "-qm", qm_path], check=True, capture_output=True, text=True)
            print(f"Compiled {qm_path}: {res.stdout.strip()}")
        except Exception as e:
            print(f"Warning: Failed to compile {qm_path}: {e}")


if __name__ == "__main__":
    main()
