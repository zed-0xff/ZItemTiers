package me.zed_0xff.itemtiers;

import me.zed_0xff.zombie_buddy.annotations.Patch;
import zombie.inventory.InventoryItem;

public class Patch_InventoryItem {
    @Patch(className = "zombie.inventory.InventoryItem", methodName = "getDiscomfortModifier")
    public static class Patch_getDiscomfortModifier {
        @Patch.OnExit
        public static void onExit(@Patch.This InventoryItem self, @Patch.Return(readOnly = false) float returnValue) {
            returnValue = CustomAttributeStorage.getOrDefault(self.getID(), "DiscomfortModifier", returnValue);
        }
    }

    @Patch(className = "zombie.inventory.InventoryItem", methodName = "getHearingModifier")
    public static class Patch_getHearingModifier {
        @Patch.OnExit
        public static void onExit(@Patch.This InventoryItem self, @Patch.Return(readOnly = false) float returnValue) {
            returnValue = CustomAttributeStorage.getOrDefault(self.getID(), "HearingModifier", returnValue);
        }
    }

    @Patch(className = "zombie.inventory.InventoryItem", methodName = "getVisionModifier")
    public static class Patch_getVisionModifier {
        @Patch.OnExit
        public static void onExit(@Patch.This InventoryItem self, @Patch.Return(readOnly = false) float returnValue) {
            returnValue = CustomAttributeStorage.getOrDefault(self.getID(), "VisionModifier", returnValue);
        }
    }

}
