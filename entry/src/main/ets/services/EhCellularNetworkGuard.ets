import { connection } from '@kit.NetworkKit';
import { ehSettingsStore } from './EhSettingsStore';

const CELLULAR_WARNING_CONFIRMED_KEY: string = 'ehviewer_cellular_warning_confirmed';

export function cellularNetworkWarningEnabled(): boolean {
  return ehSettingsStore.getValue('cellular_network_warning', 'Off') === 'On';
}

export function hasConfirmedCellularNetworkWarning(): boolean {
  return AppStorage.get<boolean>(CELLULAR_WARNING_CONFIRMED_KEY) === true;
}

export function confirmCellularNetworkWarningForSession(): void {
  AppStorage.setOrCreate<boolean>(CELLULAR_WARNING_CONFIRMED_KEY, true);
}

export function resetCellularNetworkWarningConfirmation(): void {
  AppStorage.setOrCreate<boolean>(CELLULAR_WARNING_CONFIRMED_KEY, false);
}

export function shouldWarnForCellularNetwork(): boolean {
  if (!cellularNetworkWarningEnabled()) {
    return false;
  }
  return isDefaultNetworkCellular();
}

export function shouldConfirmCellularNetworkOperation(): boolean {
  return shouldWarnForCellularNetwork() && !hasConfirmedCellularNetworkWarning();
}

export function isDefaultNetworkCellular(): boolean {
  try {
    const netHandle = connection.getDefaultNetSync();
    if (netHandle.netId === 0) {
      return false;
    }
    const capabilities = connection.getNetCapabilitiesSync(netHandle);
    const bearerTypes = capabilities.bearerTypes;
    const cellular = bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
    const wifi = bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
    return cellular && !wifi;
  } catch (error) {
    return false;
  }
}
