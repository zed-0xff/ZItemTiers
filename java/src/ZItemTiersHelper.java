package me.zed_0xff.itemtiers;

import me.zed_0xff.zombie_buddy.Exposer;

import zombie.inventory.InventoryItem;

@Exposer.LuaClass
public class ZItemTiersHelper {
    public static void Reset() {
        CustomAttributeStorage.clear();
    }

    public static void SetCustomAttribute(InventoryItem item, String attributeName, float value) {
        if (item == null || attributeName == null) {
            return;
        }
        CustomAttributeStorage.set(item.getID(), attributeName, value);
    }

    public static float GetCustomAttribute(InventoryItem item, String attributeName, float defaultValue) {
        if (item == null || attributeName == null) {
            return defaultValue;
        }
        return CustomAttributeStorage.getOrDefault(item.getID(), attributeName, defaultValue);
    }
}
