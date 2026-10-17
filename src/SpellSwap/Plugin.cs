using System;
using System.Collections.Generic;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using Il2CppInterop.Runtime.Injection;
using UnityEngine;
using UnityEngine.InputSystem;

namespace SpellSwap
{
    internal static class PluginInfo
    {
        public const string Guid = "pikselyt.belmontscurse.spellswap";
        public const string Name = "Spell Swap";
        public const string Version = "0.1.0";
    }

    /// <summary>
    /// D-pad left/right cycles through the spells you own while playing; the D-pad no longer walks
    /// (the left stick still does). Uses the game's own Inventory.EquipSpellFromInventory.
    /// </summary>
    [BepInPlugin(PluginInfo.Guid, PluginInfo.Name, PluginInfo.Version)]
    public class Plugin : BasePlugin
    {
        internal static ManualLogSource Logger;
        internal static ConfigEntry<bool> Enabled;
        internal static ConfigEntry<bool> FreeDpad;
        internal static ConfigEntry<bool> InvertDirection;
        internal static ConfigEntry<bool> Verbose;

        public override void Load()
        {
            Logger = Log;
            Enabled = Config.Bind("General", "Enabled", true, "Master switch for the whole plugin.");
            FreeDpad = Config.Bind("General", "FreeDpadFromMovement", true,
                "Remove the D-pad from the 'Move' action so left/right can switch spells instead of walking. The left stick still moves.");
            InvertDirection = Config.Bind("General", "InvertDirection", false, "Swap which D-pad direction goes to the previous/next spell.");
            Verbose = Config.Bind("Debug", "Verbose", true, "Log what the plugin sees (useful while testing; turn off later).");

            ClassInjector.RegisterTypeInIl2Cpp<SpellSwapRunner>();
            AddComponent<SpellSwapRunner>();
            Logger.LogInfo($"{PluginInfo.Name} {PluginInfo.Version} loaded");
        }
    }

    public class SpellSwapRunner : MonoBehaviour
    {
        public SpellSwapRunner(IntPtr ptr) : base(ptr) { }

        private InventoryComponent _invComp;
        private InputActionAsset _actions;
        private float _nextScan;
        private float _nextOverrideCheck;
        private bool _errorLogged;

        public void Update()
        {
            if (!Plugin.Enabled.Value) return;
            try
            {
                float now = Time.unscaledTime;
                if (now >= _nextScan)
                {
                    _nextScan = now + 1f;
                    Rescan();
                }
                // The D-pad never walks; the left stick does that. Re-checked every second because
                // the game can reload its bindings.
                if (_actions != null && Plugin.FreeDpad.Value && now >= _nextOverrideCheck)
                {
                    _nextOverrideCheck = now + 1f;
                    EnsureDpadFreed();
                }

                var pad = Gamepad.current;
                if (pad == null) return;
                int dir = 0;
                if (pad.dpad.left.wasPressedThisFrame) dir = -1;
                else if (pad.dpad.right.wasPressedThisFrame) dir = 1;
                if (dir == 0) return;

                if (!GameplayActive(out string why))
                {
                    if (Plugin.Verbose.Value) Plugin.Logger.LogInfo($"D-pad pressed but ignored: {why}");
                    return;
                }
                Cycle(Plugin.InvertDirection.Value ? -dir : dir);
            }
            catch (Exception e)
            {
                if (!_errorLogged)
                {
                    _errorLogged = true;
                    Plugin.Logger.LogError($"Update failed (logged once): {e}");
                }
            }
        }

        private Inventory PlayerInventory()
        {
            return _invComp == null ? null : _invComp.inventory;
        }

        private void Rescan()
        {
            if (_invComp == null)
            {
                foreach (var comp in UnityEngine.Object.FindObjectsOfType<InventoryComponent>())
                {
                    var inv = comp.inventory;
                    if (inv == null) continue;
                    // the player is the entity that owns spells
                    if (inv.GetEquippedSpell() != null || CountSpells(inv) > 0)
                    {
                        _invComp = comp;
                        break;
                    }
                }
                if (_invComp != null && Plugin.Verbose.Value)
                {
                    var inv = _invComp.inventory;
                    var eq = inv.GetEquippedSpell();
                    Plugin.Logger.LogInfo($"Found player inventory: {CountSpells(inv)} spell(s), equipped = {(eq == null ? "none" : eq.itemID)}");
                }
            }
            if (_actions == null)
            {
                var settings = UnityEngine.Object.FindObjectOfType<InputSettings>();
                if (settings != null) _actions = settings.actions;
                if (_actions != null && Plugin.Verbose.Value) Plugin.Logger.LogInfo("Found the game's InputActionAsset");
            }
        }

        private static int CountSpells(Inventory inv)
        {
            var items = inv.GetAllItemsInInventory();
            int n = 0;
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                if (it != null && it.TryCast<SpellItemData>() != null) n++;
            }
            return n;
        }

        private bool GameplayActive(out string why)
        {
            why = "";
            if (PlayerInventory() == null) { why = "player inventory not found yet"; return false; }
            if (Time.timeScale < 0.5f) { why = $"time scale is {Time.timeScale:0.##} (paused?)"; return false; }
            if (_actions != null)
            {
                var player = _actions.FindActionMap("Player", false);
                if (player != null && !player.enabled) { why = "'Player' input map is disabled (menu/cutscene?)"; return false; }
            }
            return true;
        }

        private void EnsureDpadFreed()
        {
            var move = _actions.FindAction("Player/Move", false);
            if (move == null) return;
            var bindings = move.bindings;
            for (int i = 0; i < bindings.Count; i++)
            {
                if (bindings[i].effectivePath == "<Gamepad>/dpad")
                {
                    InputActionRebindingExtensions.ApplyBindingOverride(move, i, "");
                    if (Plugin.Verbose.Value) Plugin.Logger.LogInfo($"Removed the D-pad from Player/Move (binding #{i})");
                }
            }
        }

        private void Cycle(int dir)
        {
            var inv = PlayerInventory();
            var items = inv.GetAllItemsInInventory();
            var spells = new List<SpellItemData>();
            var seen = new HashSet<string>();
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                if (it == null) continue;
                var s = it.TryCast<SpellItemData>();
                if (s == null || !seen.Add(s.itemID)) continue;
                spells.Add(s);
            }
            if (spells.Count < 2)
            {
                if (Plugin.Verbose.Value) Plugin.Logger.LogInfo($"Only {spells.Count} spell(s) owned - nothing to switch");
                return;
            }

            var current = inv.GetEquippedSpell();
            int idx = -1;
            if (current != null)
                idx = spells.FindIndex(s => s.itemID == current.itemID);
            int next = idx < 0 ? (dir > 0 ? 0 : spells.Count - 1) : (idx + dir + spells.Count) % spells.Count;

            inv.EquipSpellFromInventory(spells[next]);
            if (Plugin.Verbose.Value)
                Plugin.Logger.LogInfo($"Spell {(current == null ? "none" : current.itemID)} -> {spells[next].itemID} ({next + 1}/{spells.Count})");
        }
    }
}
