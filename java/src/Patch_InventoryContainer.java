package me.zed_0xff.itemtiers;

import me.zed_0xff.zombie_buddy.annotations.Patch;
import zombie.inventory.types.InventoryContainer;

public class Patch_InventoryContainer {
    @Patch(className = "zombie.inventory.types.InventoryContainer", methodName = "getMaxItemSize")
    public static class Patch_getMaxItemSize {
        @Patch.OnExit
        public static void onExit(@Patch.This InventoryContainer self, @Patch.Return(readOnly = false) float returnValue) {
            returnValue = CustomAttributeStorage.getOrDefault(self.getID(), "MaxItemSize", returnValue);
        }
    }
}
