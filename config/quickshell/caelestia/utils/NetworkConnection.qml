pragma Singleton

import QtQuick
import qs.services

QtObject {
    id: root

    function triggerPasswordDialog(network, session, onPasswordNeeded): void {
        if (Nmcli.pendingConnection) {
            Nmcli.connectionCheckTimer.stop();
            Nmcli.immediateCheckTimer.stop();
            Nmcli.immediateCheckTimer.checkCount = 0;
            Nmcli.pendingConnection = null;
        }

        if (session && session.network) {
            session.network.showPasswordDialog = true;
            session.network.pendingNetwork = network;
        } else if (onPasswordNeeded) {
            onPasswordNeeded(network);
        }
    }

    function handleConnect(network, session, onPasswordNeeded, onResult): void {
        if (!network) {
            return;
        }
        root.connectToNetwork(network, session, onPasswordNeeded, onResult);
    }

    function connectToNetwork(network, session, onPasswordNeeded, onResult): void {
        if (!network) {
            return;
        }

        if (network.isSecure) {
            const hasSavedProfile = Nmcli.hasSavedProfile(network.ssid);
            const savedSec = Nmcli.savedSecurityFor(network.ssid);
            // If network is secured, only trust the saved profile if it actually has a security key-mgmt
            // (or if savedConnectionSecurity hasn't finished loading yet).
            const hasValidSaved = hasSavedProfile && (savedSec !== "" || Object.keys(Nmcli.savedConnectionSecurity).length === 0);

            if (!hasValidSaved) {
                // Immediately open the password dialog without hanging on a passwordless nmcli call!
                root.triggerPasswordDialog(network, session, onPasswordNeeded);
                if (onResult)
                    onResult({
                        success: false,
                        needsPassword: true
                    });
                return;
            }

            // Try activating the saved profile; if it fails or needs a password, prompt the user.
            Nmcli.connectToNetwork(network.ssid, "", network.bssid, result => {
                if (result && result.success) {
                    if (onResult)
                        onResult(result);
                } else {
                    root.triggerPasswordDialog(network, session, onPasswordNeeded);
                    if (onResult)
                        onResult(result || {
                            success: false,
                            needsPassword: true
                        });
                }
            });
        } else {
            Nmcli.connectToNetwork(network.ssid, "", network.bssid, result => {
                if (onResult)
                    onResult(result);
            });
        }
    }

    function connectWithPassword(network, password, onResult): void {
        if (!network) {
            return;
        }

        Nmcli.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}
