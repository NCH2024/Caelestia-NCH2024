pragma Singleton

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common
import qs.modules.nexus.pages
import qs.modules.nexus.pages.apps
import qs.modules.nexus.pages.audio
import qs.modules.nexus.pages.bluetooth
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.panels.taskbar

QtObject {
    id: root

    readonly property list<Component> pageComps: [
        // 0: AI Automation
        Component {
            StackPage {
                Component {
                    AiAutomationPage {}
                }
            }
        },

        // 1: Modes & Routines
        Component {
            StackPage {
                Component {
                    ModesAndRoutinesPage {}
                }
            }
        },

        // 2: Power, Fans & Device Care
        Component {
            StackPage {
                Component {
                    DeviceCarePage {}
                }
            }
        },

        // 3: Wallpaper & style
        Component {
            StackPage {
                Component {
                    WallpaperAndStyle {}
                }
                Component {
                    WallpaperSelect {}
                }
                Component {
                    WallpaperCategory {}
                }
                Component {
                    ColourSelect {}
                }
            }
        },

        // 4: Network
        Component {
            StackPage {
                Component {
                    NetworkPage {}
                }
                Component {
                    EthernetDetailPage {}
                }
                Component {
                    AddNetworkPage {}
                }
                Component {
                    NetworkDetailPage {}
                }
                Component {
                    AddVpnPage {}
                }
                Component {
                    AllNetworksPage {}
                }
                Component {
                    SavedNetworksPage {}
                }
                Component {
                    ConnectWifiPage {}
                }
            }
        },

        // 5: Bluetooth & Connected devices
        Component {
            StackPage {
                Component {
                    BluetoothPage {}
                }
                Component {
                    BtDeviceInfo {}
                }
                Component {
                    BluetoothPairing {}
                }
            }
        },

        // 6: Audio & Studio Equalizer
        Component {
            StackPage {
                Component {
                    AudioPage {}
                }
                Component {
                    AppVolumes {}
                }
            }
        },

        // 7: Disks & Storage
        Component {
            StackPage {
                Component {
                    DisksPage {}
                }
            }
        },

        // 8: Updates & Drivers
        Component {
            StackPage {
                Component {
                    UpdatesPage {}
                }
            }
        },

        // 9: Daemons, Scheduled Timers & Processes
        Component {
            StackPage {
                Component {
                    PluginsPage {}
                }
            }
        },

        // 10: Panels
        Component {
            StackPage {
                Component {
                    PanelsPage {}
                }
                Component {
                    DashboardPanel {}
                }
                Component {
                    TaskbarPanel {}
                }
                Component {
                    LauncherPanel {}
                }
                Component {
                    SidebarPanel {}
                }
                Component {
                    UtilitiesPanel {}
                }
                Component {
                    BarWorkspaces {}
                }
                Component {
                    BarActiveWindow {}
                }
                Component {
                    BarTray {}
                }
                Component {
                    BarStatusIcons {}
                }
                Component {
                    BarClock {}
                }
            }
        },

        // 11: Apps
        Component {
            StackPage {
                Component {
                    AppsPage {}
                }
                Component {
                    AllApps {}
                }
                Component {
                    AppInfo {}
                }
            }
        },

        // 12: Services
        Component {
            StackPage {
                Component {
                    ServicesPage {}
                }
                Component {
                    NotificationsPage {}
                }
            }
        },

        // 13: Language & region
        Component {
            StackPage {
                Component {
                    LanguageAndRegion {}
                }
            }
        },

        // 14: Keybinds & Shortcuts
        Component {
            StackPage {
                Component {
                    ShortcutsPage {}
                }
            }
        },

        // 15: About
        Component {
            StackPage {
                Component {
                    AboutPage {}
                }
            }
        }
    ]
}
