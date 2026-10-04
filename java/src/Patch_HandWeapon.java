package me.zed_0xff.itemtiers;

import me.zed_0xff.zombie_buddy.annotations.Patch;

import zombie.inventory.types.HandWeapon;

public class Patch_HandWeapon {
    @Patch(className = "zombie.inventory.types.HandWeapon", methodName = "getActualWeight")
    public static class Patch_getActualWeight {
        @Patch.OnExit
        public static void onExit(
                @Patch.This HandWeapon self,
                @Patch.Field float actualWeight,
                @Patch.Return(readOnly = false) float result
        ) {
            float scriptWeight = self.getScriptItem().getActualWeight();
            if (actualWeight > 0.0f && actualWeight < scriptWeight) {
                result = result - (scriptWeight - actualWeight);
            }
        }
    }
}
