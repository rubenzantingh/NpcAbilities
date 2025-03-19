local addonName = ...

_G["NpcAbilitiesTranslations"] = {}
local translationsFrame = CreateFrame("Frame")

local function addonLoaded(self, event, addonLoadedName)
    if addonLoadedName == addonName then
        _G["NpcAbilitiesTranslations"]["en"] = {
            options = {
                generalOptionsTitle = "General options",
                languageDropdownLabel = "Select language:",
                languages = {
                    en = "English",
                    es = "Spanish",
                    fr = "French",
                    de = "German",
                    pt = "Portuguese",
                    ru = "Russian",
                    ko = "Korean",
                    cn = "Chinese"
                },
                displayAbilitiesMechanicLabel = "Display ability mechanic",
                hotkeyModeLabel = "Select hotkey mode (on hold, some keys may not work as expected):",
                hotkeyModes = {
                    toggle = "Toggle",
                    hold = "Hold"
                },
                hotkeyButtonLabel = "Register toggle abilities description hotkey (Right-click to unbind)",
                hotkeyButtonInstructionText = "Press button..",
                hotkeyButtonNotBoundText = "Not Bound",
                hideOptionsTitle = "Hide abilities",
                hideOptionsHotkeyModeLabel = "Register hide abilities hotkey (Right-click to unbind)",
                hideAbilitiesInInstanceLabel = "Hide abilities in instances (PVP and PVE)",
            },
             game = {
                 hotkeyExplanatoryTextOne = "Press",
                 hotkeyExplanatoryTextTwo = "for details",
                 hotkeyNotBoundText = "Hotkey not bound",
             }
        }

        _G["NpcAbilitiesTranslations"]["es"] = {
            options = {
                generalOptionsTitle = "Opciones generales",
                languageDropdownLabel = "Seleccionar idioma:",
                languages = {
                    en = "Inglés",
                    es = "Español",
                    fr = "Francés",
                    de = "Alemán",
                    pt = "Portugués",
                    ru = "Ruso",
                    ko = "Coreano",
                    cn = "Chino"
                },
                displayAbilitiesMechanicLabel = "Mostrar mecánica de habilidades",
                hotkeyModeLabel = "Seleccionar modo de tecla rápida (al mantener, algunas teclas pueden no funcionar como se espera):",
                hotkeyModes = {
                    toggle = "Alternar",
                    hold = "Mantener"
                },
                hotkeyButtonLabel = "Registrar tecla rápida para la descripción de habilidades de alternancia (Clic derecho para desvincular)",
                hotkeyButtonInstructionText = "Pulsa el botón..",
                hotkeyButtonNotBoundText = "No obligado",
                hideOptionsTitle = "Ocultar habilidades",
                hideOptionsHotkeyModeLabel = "Registrar tecla rápida para ocultar habilidades (Clic derecho para desvincular)",
                hideAbilitiesInInstanceLabel = "Ocultar habilidades en instancias (PVP y PVE)"
            },
            game = {
                hotkeyExplanatoryTextOne = "Presione",
                hotkeyExplanatoryTextTwo = "para más detalles",
                hotkeyNotBoundText = "Tecla de acceso rápido no vinculado",
            }
        }

        _G["NpcAbilitiesTranslations"]["de"] = {
            options = {
                generalOptionsTitle = "Allgemeine Optionen",
                languageDropdownLabel = "Sprache auswählen:",
                languages = {
                    en = "Englisch",
                    es = "Spanisch",
                    fr = "Französisch",
                    de = "Deutsch",
                    pt = "Portugiesisch",
                    ru = "Russisch",
                    ko = "Koreanisch",
                    cn = "Chinesisch"
                },
                displayAbilitiesMechanicLabel = "Fähigkeitsmechanik anzeigen",
                hotkeyModeLabel = "Hotkey-Modus auswählen (bei Halten funktionieren einige Tasten möglicherweise nicht wie erwartet):",
                hotkeyModes = {
                    toggle = "Umschalten",
                    hold = "Halten"
                },
                hotkeyButtonLabel = "Hotkey für Umschaltfähigkeitenbeschreibung registrieren (Rechtsklick zum Aufheben der Bindung)",
                hotkeyButtonInstructionText = "Taste drücken..",
                hotkeyButtonNotBoundText = "Nicht gebunden",
                hideOptionsTitle = "Fähigkeiten ausblenden",
                hideOptionsHotkeyModeLabel = "Hotkey zum Ausblenden von Fähigkeiten registrieren (Rechtsklick zum Aufheben der Bindung)",
                hideAbilitiesInInstanceLabel = "Fähigkeiten in Instanzen ausblenden (PVP und PVE)",
            },
            game = {
                hotkeyExplanatoryTextOne = "Drücken Sie",
                hotkeyExplanatoryTextTwo = "für Details",
                hotkeyNotBoundText = "Hotkey nicht gebunden",
            }
        }

        _G["NpcAbilitiesTranslations"]["fr"] = {
            options = {
                generalOptionsTitle = "Options générales",
                languageDropdownLabel = "Sélectionner la langue :",
                languages = {
                    en = "Anglais",
                    es = "Espagnol",
                    fr = "Français",
                    de = "Allemand",
                    pt = "Portugais",
                    ru = "Russe",
                    ko = "Coréen",
                    cn = "Chinois"
                },
                displayAbilitiesMechanicLabel = "Afficher la mécanique des capacités",
                hotkeyModeLabel = "Sélectionner le mode de raccourci (en maintenant, certaines touches peuvent ne pas fonctionner comme prévu) :",
                hotkeyModes = {
                    toggle = "Basculer",
                    hold = "Maintenir"
                },
                hotkeyButtonLabel = "Enregistrer le raccourci pour la description des capacités à bascule (clic droit pour dissocier)",
                hotkeyButtonInstructionText = "Appuyez sur le bouton..",
                hotkeyButtonNotBoundText = "Non lié",
                hideOptionsTitle = "Masquer les capacités",
                hideOptionsHotkeyModeLabel = "Enregistrer le raccourci pour masquer les capacités (clic droit pour dissocier)",
                hideAbilitiesInInstanceLabel = "Masquer les capacités en instance (PVP et PVE)"
            },
            game = {
                hotkeyExplanatoryTextOne = "Appuyez sur",
                hotkeyExplanatoryTextTwo = "pour plus de détails",
                hotkeyNotBoundText = "Raccourci clavier non lié",
            }
        }

        _G["NpcAbilitiesTranslations"]["pt"] = {
            options = {
                generalOptionsTitle = "Opções gerais",
                languageDropdownLabel = "Selecionar idioma:",
                languages = {
                    en = "Inglês",
                    es = "Espanhol",
                    fr = "Francês",
                    de = "Alemão",
                    pt = "Português",
                    ru = "Russo",
                    ko = "Coreano",
                    cn = "Chinês"
                },
                displayAbilitiesMechanicLabel = "Exibir mecânica das habilidades",
                hotkeyModeLabel = "Selecionar modo de atalho (ao segurar, algumas teclas podem não funcionar como esperado):",
                hotkeyModes = {
                    toggle = "Alternar",
                    hold = "Segurar"
                },
                hotkeyButtonLabel = "Registrar atalho para descrição das habilidades de alternância (Clique com o botão direito para desvincular)",
                hotkeyButtonInstructionText = "Pressione o botão ..",
                hotkeyButtonNotBoundText = "Não vinculado",
                hideOptionsTitle = "Ocultar habilidades",
                hideOptionsHotkeyModeLabel = "Registrar atalho para ocultar habilidades (Clique com o botão direito para desvincular)",
                hideAbilitiesInInstanceLabel = "Ocultar habilidades em instâncias (PVP e PVE)"
            },
            game = {
                hotkeyExplanatoryTextOne = "Prima",
                hotkeyExplanatoryTextTwo = "para detalhes",
                hotkeyNotBoundText = "Tecla de atalho não ligada",
            }
        }

        _G["NpcAbilitiesTranslations"]["ru"] = {
            options = {
                generalOptionsTitle = "Общие настройки",
                languageDropdownLabel = "Выберите язык:",
                languages = {
                    en = "Английский",
                    es = "Испанский",
                    fr = "Французский",
                    de = "Немецкий",
                    pt = "Португальский",
                    ru = "Русский",
                    ko = "Корейский",
                    cn = "Китайский"
                },
                displayAbilitiesMechanicLabel = "Показывать механику способностей",
                hotkeyModeLabel = "Выберите режим горячих клавиш (при удержании некоторые клавиши могут работать некорректно):",
                hotkeyModes = {
                    toggle = "Переключение",
                    hold = "Удерживание"
                },
                hotkeyButtonLabel = "Назначить горячую клавишу для переключения описания способностей (Правый клик для сброса)",
                hotkeyButtonInstructionText = "Нажмите кнопку...",
                hotkeyButtonNotBoundText = "Не связан",
                hideOptionsTitle = "Скрытие способностей",
                hideOptionsHotkeyModeLabel = "Назначить горячую клавишу для скрытия способностей (Правый клик для сброса)",
                hideAbilitiesInInstanceLabel = "Скрывать способности в подземельях (PVP и PVE)"
            },
            game = {
                hotkeyExplanatoryTextOne = "Нажмите",
                hotkeyExplanatoryTextTwo = "чтобы узнать подробности",
                hotkeyNotBoundText = "Горячая клавиша не привязана",
            }
        }

        _G["NpcAbilitiesTranslations"]["ko"] = {
            options = {
                generalOptionsTitle = "일반 옵션",
                languageDropdownLabel = "언어 선택:",
                languages = {
                    en = "영어",
                    es = "스페인어",
                    fr = "프랑스어",
                    de = "독일어",
                    pt = "포르투갈어",
                    ru = "러시아어",
                    ko = "한국어",
                    cn = "중국어"
                },
                displayAbilitiesMechanicLabel = "능력 메커니즘 표시",
                hotkeyModeLabel = "단축키 모드 선택 (누르고 있을 때 일부 키가 예상대로 작동하지 않을 수 있음):",
                hotkeyModes = {
                    toggle = "전환",
                    hold = "누르기"
                },
                hotkeyButtonLabel = "전환 능력 설명 단축키 등록 (우클릭으로 해제)",
                hotkeyButtonInstructionText = "버튼을 누르세요..",
                hotkeyButtonNotBoundText = "구속되지 않음",
                hideOptionsTitle = "능력 숨기기",
                hideOptionsHotkeyModeLabel = "능력 숨기기 단축키 등록 (우클릭으로 해제)",
                hideAbilitiesInInstanceLabel = "인스턴스( PVP 및 PVE)에서 능력 숨기기"
            },
            game = {
                hotkeyExplanatoryTextOne = "자세한 내용을 보려면",
                hotkeyExplanatoryTextTwo = "를 누르세요.",
                hotkeyNotBoundText = "단축키가 바인딩되지 않았습니다.",
            }
        }

        _G["NpcAbilitiesTranslations"]["cn"] = {
            options = {
                generalOptionsTitle = "通用选项",
                languageDropdownLabel = "选择语言：",
                languages = {
                    en = "英语",
                    es = "西班牙语",
                    fr = "法语",
                    de = "德语",
                    pt = "葡萄牙语",
                    ru = "俄语",
                    ko = "韩语",
                    cn = "中文"
                },
                displayAbilitiesMechanicLabel = "显示技能机制",
                hotkeyModeLabel = "选择快捷键模式（按住时，某些按键可能无法正常工作）：",
                hotkeyModes = {
                    toggle = "切换",
                    hold = "按住"
                },
                hotkeyButtonLabel = "注册切换技能描述快捷键（右键单击解绑",
                hotkeyButtonInstructionText = "按按钮..",
                hotkeyButtonNotBoundText = "未绑定",
                hideOptionsTitle = "隐藏技能",
                hideOptionsHotkeyModeLabel = "注册隐藏技能快捷键（右键单击解绑）",
                hideAbilitiesInInstanceLabel = "在副本（PVP 和 PVE）中隐藏技能"
            },
            game = {
                hotkeyExplanatoryTextOne = "按",
                hotkeyExplanatoryTextTwo = "了解详细信息",
                hotkeyNotBoundText = "热键未绑定",
            }
        }
    end
end


translationsFrame:RegisterEvent("ADDON_LOADED")
translationsFrame:SetScript("OnEvent", addonLoaded)
