pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> searchResults: []
    property bool searchingCity: false

    readonly property list<var> presetCities: [
        { label: "Can Tho", loc: "10.0452,105.7469" },
        { label: "Vinh Long", loc: "10.2537,105.9722" },
        { label: "Ho Chi Minh City", loc: "10.8231,106.6297" },
        { label: "Ha Noi", loc: "21.0285,105.8542" },
        { label: "Da Nang", loc: "16.0544,108.2022" },
        { label: "Nha Trang", loc: "12.2388,109.1967" },
        { label: "Da Lat", loc: "11.9404,108.4583" }
    ]

    function searchCity(query: string): void {
        const q = query.trim();
        if (!q) {
            root.searchResults = [];
            return;
        }
        root.searchingCity = true;
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=5&language=en&format=json`;
        Requests.get(url, text => {
            root.searchingCity = false;
            try {
                const json = JSON.parse(text);
                root.searchResults = json.results ?? [];
            } catch (e) {
                root.searchResults = [];
            }
        }, () => {
            root.searchingCity = false;
            root.searchResults = [];
        });
    }

    function applyLocation(locStr: string, cityName: string): void {
        if (cityName && locStr.indexOf(",") !== -1) {
            Weather.cacheCity(locStr, cityName);
            Weather.city = cityName;
        }
        GlobalConfig.services.weatherLocation = locStr;
        Weather.reload();
        Weather.fetchWeatherData();
        root.searchResults = [];
    }

    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: Tr.tr("Auto")
            value: TemperatureUnit.Auto
        },
        MenuItem {
            text: "°C (Celsius)"
            value: TemperatureUnit.Celsius
        },
        MenuItem {
            text: "°F (Fahrenheit)"
            value: TemperatureUnit.Fahrenheit
        },
        MenuItem {
            text: "K (Kelvin)"
            value: TemperatureUnit.Kelvin
        }
    ]

    readonly property list<MenuItem> dataItems: [
        MenuItem {
            text: Tr.tr("Binary (KiB, MiB, GiB)")
            value: DataUnit.Binary
        },
        MenuItem {
            text: Tr.tr("Decimal (KB, MB, GB)")
            value: DataUnit.Decimal
        }
    ]

    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: Tr.tr("Auto")
            value: ClockFormat.Auto
        },
        MenuItem {
            text: Tr.tr("12-hour")
            value: ClockFormat.TwelveHour
        },
        MenuItem {
            text: Tr.tr("24-hour")
            value: ClockFormat.TwentyFourHour
        }
    ]

    title: Tr.tr("Language, Region & Weather")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Language
        SectionHeader {
            first: true
            text: Tr.tr("Language")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("UI language")
            subtext: Tr.tr("The language used across the Caelestia shell interface")
            active: menuItems.find(i => i.modelData === Tr.language) ?? autoLang
            onSelected: item => {
                Tr.language = item.modelData ?? "en_US"; // qmllint disable missing-property
            }

            menuItems: [autoLang, ...langItems.instances]

            MenuItem {
                id: autoLang

                text: Tr.tr("English (Default)")
            }

            Variants {
                id: langItems

                model: Tr.supportedLanguages

                MenuItem {
                    required property string modelData

                    text: {
                        const locale = Qt.locale(modelData);
                        return locale.name === "C" ? modelData : locale.nativeLanguageName || locale.name;
                    }
                }
            }
        }

        // ---- Weather Configuration -------------------------------------------
        SectionHeader {
            text: Tr.tr("Weather & Location")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: weatherHero.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: weatherHero

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: Weather.icon
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.extraLarge
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: Weather.temp
                                font: Tokens.font.headline.small
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                text: `• ${Weather.description}`
                                font: Tokens.font.title.medium
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `Location: ${Weather.city || "..."} (${Weather.loc || "IP Auto"})`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `Feels like ${Weather.feelsLike} • Humidity ${Weather.humidity}% • Wind ${Math.round(Weather.windSpeed)} km/h • ☀ ${Weather.sunrise} – ${Weather.sunset}`
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconTextButton {
                        icon: "refresh"
                        text: "Refresh"
                        type: IconTextButton.Tonal
                        isRound: true
                        onClicked: {
                            Weather.reload();
                            Weather.fetchWeatherData();
                        }
                    }
                }
            }
        }

        ToggleRow {
            text: "Auto-detect location via IP"
            subtext: GlobalConfig.services.weatherLocation
                ? `Using custom coordinates: ${GlobalConfig.services.weatherLocation}`
                : "Automatically detect city from your internet connection"
            checked: !GlobalConfig.services.weatherLocation
            onToggled: {
                if (checked) {
                    GlobalConfig.services.weatherLocation = "";
                    Weather.reload();
                } else if (Weather.loc) {
                    GlobalConfig.services.weatherLocation = Weather.loc;
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: searchCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: searchCol

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.medium

                StyledText {
                    text: "Search city or enter coordinates (lat,lon)"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: cityInput

                        Layout.fillWidth: true
                        placeholderText: "Type city name (e.g. Can Tho, Ho Chi Minh, Ha Noi)..."
                        leadingIcon: "location_on"
                        text: GlobalConfig.services.weatherLocation
                        onAccepted: root.searchCity(text)
                    }

                    IconTextButton {
                        icon: "search"
                        text: root.searchingCity ? "..." : "Search"
                        type: IconTextButton.Tonal
                        isRound: true
                        disabled: root.searchingCity || cityInput.text.trim().length === 0
                        onClicked: root.searchCity(cityInput.text)
                    }

                    IconTextButton {
                        icon: "check"
                        text: "Set"
                        type: IconTextButton.Filled
                        isRound: true
                        disabled: cityInput.text.trim().length === 0
                        onClicked: root.applyLocation(cityInput.text.trim(), "")
                    }
                }

                ColumnLayout {
                    visible: root.searchResults.length > 0
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.searchResults

                        StyledRect {
                            id: resItem

                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: resRow.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.medium
                            color: Colours.palette.m3surfaceContainerHighest

                            StateLayer {
                                radius: parent.radius
                                onClicked: {
                                    const coords = `${resItem.modelData.latitude},${resItem.modelData.longitude}`;
                                    cityInput.text = coords;
                                    root.applyLocation(coords, resItem.modelData.name);
                                }
                            }

                            RowLayout {
                                id: resRow

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.small
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: "place"
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: `${resItem.modelData.name}${resItem.modelData.admin1 ? ", " + resItem.modelData.admin1 : ""}${resItem.modelData.country ? " (" + resItem.modelData.country + ")" : ""}`
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: `${Number(resItem.modelData.latitude).toFixed(2)}, ${Number(resItem.modelData.longitude).toFixed(2)}`
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.mono.small
                                }
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.presetCities

                        TextButton {
                            id: presetChip

                            required property var modelData
                            readonly property bool isSelected: GlobalConfig.services.weatherLocation === modelData.loc

                            isRound: true
                            type: isSelected ? TextButton.Filled : TextButton.Tonal
                            text: modelData.label
                            horizontalPadding: Tokens.padding.medium
                            verticalPadding: Tokens.padding.extraSmall
                            onClicked: {
                                cityInput.text = presetChip.modelData.loc;
                                root.applyLocation(presetChip.modelData.loc, presetChip.modelData.label);
                            }
                        }
                    }
                }
            }
        }

        ToggleRow {
            text: "Show weather on desktop clock"
            subtext: "Display weather icon, temperature and city alongside the desktop clock"
            checked: ExtraConfig.desktopWeatherEnabled && Config.background.desktopClock.enabled
            onToggled: {
                ExtraConfig.desktopWeatherEnabled = checked;
                if (checked && !Config.background.desktopClock.enabled) {
                    GlobalConfig.background.desktopClock.enabled = true;
                }
            }
        }

        ToggleRow {
            last: true
            text: "Show weather tab in Dashboard"
            subtext: "Include the weather forecast tab in the Dashboard panel"
            checked: Config.dashboard.showWeather
            onToggled: GlobalConfig.dashboard.showWeather = checked
        }

        // Units
        SectionHeader {
            text: Tr.tr("Units")
        }

        SelectRow {
            first: true
            label: Tr.tr("Temperature")
            subtext: Tr.tr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.weatherUnits)
            onSelected: item => GlobalConfig.services.weatherUnits = item.value
        }

        SelectRow {
            label: Tr.tr("System temperatures")
            subtext: Tr.tr("Units for CPU and GPU temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.sensorUnits)
            onSelected: item => GlobalConfig.services.sensorUnits = item.value
        }

        SelectRow {
            last: true
            label: Tr.tr("Data sizes")
            subtext: Tr.tr("Units for data sizes and network speeds")
            menuItems: root.dataItems
            active: root.dataItems.find(i => i.value === GlobalConfig.services.dataUnits)
            onSelected: item => GlobalConfig.services.dataUnits = item.value
        }

        // Time & date
        SectionHeader {
            text: Tr.tr("Time & date")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("Clock format")
            subtext: Tr.tr("How times are shown across the shell")
            menuItems: root.clockItems
            active: root.clockItems.find(i => i.value === GlobalConfig.services.clockFormat)
            onSelected: item => GlobalConfig.services.clockFormat = item.value
        }
    }
}
