package me.zed_0xff.itemtiers;

import me.zed_0xff.zombie_buddy.annotations.Patch;

import zombie.inventory.types.Clothing;

public class Patch_Clothing {
    @Patch(className = "zombie.inventory.types.Clothing", methodName = "getCorpseSicknessDefense")
    public static class Patch_getCorpseSicknessDefense {
        @Patch.OnExit
        public static void onExit(@Patch.This Clothing self, @Patch.Return(readOnly = false) float result) {
            if (result > 0) {
                float scriptValue = self.getScriptItem().getCorpseSicknessDefense();
                if (result == scriptValue) {
                    result = CustomAttributeStorage.getOrDefault(self.getID(), "CorpseSicknessDefense", result);
                }
            }
        }
    }
}
