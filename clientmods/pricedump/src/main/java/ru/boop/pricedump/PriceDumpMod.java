package ru.boop.pricedump;

import cpw.mods.fml.common.FMLCommonHandler;
import cpw.mods.fml.common.FMLLog;
import cpw.mods.fml.common.Mod;
import cpw.mods.fml.common.eventhandler.SubscribeEvent;
import net.minecraft.client.Minecraft;
import net.minecraft.client.entity.EntityClientPlayerMP;
import net.minecraft.command.CommandBase;
import net.minecraft.command.ICommandSender;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;
import net.minecraft.item.crafting.CraftingManager;
import net.minecraft.item.crafting.FurnaceRecipes;
import net.minecraft.item.crafting.IRecipe;
import net.minecraft.item.crafting.ShapedRecipes;
import net.minecraft.item.crafting.ShapelessRecipes;
import net.minecraft.util.ChatComponentText;
import net.minecraftforge.client.ClientCommandHandler;
import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.event.entity.EntityJoinWorldEvent;
import net.minecraftforge.event.entity.player.ItemTooltipEvent;
import net.minecraftforge.oredict.OreDictionary;
import net.minecraftforge.oredict.ShapedOreRecipe;
import net.minecraftforge.oredict.ShapelessOreRecipe;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * PriceDump — клиентский Forge-мод 1.7.10.
 * Команда /dumpprices: итерирует все ItemStack из реестра, вызывает
 * getTooltip(player, true) и собирает строки вида "Минимальная цена: N$"
 * в JSON-файл {modid:meta -> price}.
 */
@Mod(
    modid = PriceDumpMod.MODID,
    name = "PriceDump",
    version = PriceDumpMod.VERSION,
    acceptableRemoteVersions = "*"
)
public class PriceDumpMod {

    public static final String MODID = "pricedump";
    public static final String VERSION = "1.0";

    private boolean greeted = false;

    // Конструктор без аргументов — требование jar-to-dll: весь init здесь,
    // обычный FMLInitializationEvent в native-injection режиме не отрабатывает.
    public PriceDumpMod() {
        try {
            if (FMLCommonHandler.instance().getSide().isClient()) {
                ClientCommandHandler.instance.registerCommand(new DumpCommand());
                MinecraftForge.EVENT_BUS.register(this);
                FMLLog.info("[PriceDump %s] init done (constructor), /dumpprices registered",
                            VERSION);
            }
        } catch (Throwable t) {
            FMLLog.severe("[PriceDump] constructor failed: " + t);
            t.printStackTrace();
        }
    }

    @SubscribeEvent
    public void onPlayerJoinWorld(EntityJoinWorldEvent event) {
        if (greeted) return;
        if (event.world == null || !event.world.isRemote) return;
        if (!(event.entity instanceof EntityClientPlayerMP)) return;
        greeted = true;
        ((EntityClientPlayerMP) event.entity).addChatMessage(
            new ChatComponentText("§a[PriceDump " + VERSION +
                "] загружен. Команда: §e/dumpprices"));
    }

    public static class DumpCommand extends CommandBase {

        // Гибкая регулярка: терпит цветовые §-коды (которые удаляем заранее),
        // переменные пробелы, точку или запятую как десятичный разделитель,
        // опциональный пробел перед "$".
        private static final Pattern PRICE_RX = Pattern.compile(
            "Минимальная\\s+цена\\s*:\\s*([0-9]+(?:[.,][0-9]+)?)\\s*\\$"
        );
        private static final Pattern COLOR_RX = Pattern.compile("§[0-9a-fk-or]");

        @Override
        public String getCommandName() {
            return "dumpprices";
        }

        @Override
        public String getCommandUsage(ICommandSender sender) {
            return "/dumpprices [path]   (по умолчанию prices.json в .minecraft/)";
        }

        @Override
        public int getRequiredPermissionLevel() {
            return 0;
        }

        @Override
        public boolean canCommandSenderUseCommand(ICommandSender sender) {
            return true;
        }

        // Удаляет format-коды Forge типа §a §l из строки
        private static String stripCodes(String s) {
            if (s == null) return "";
            return s.replaceAll("§[0-9a-fklmnor]", "");
        }

        @Override
        public void processCommand(ICommandSender sender, String[] args) {
            String relPath = args.length > 0 ? args[0] : "prices.json";

            Minecraft mc = Minecraft.getMinecraft();
            File outFile = new File(mc.mcDataDir, relPath);
            File debugFile = new File(mc.mcDataDir, "tooltips_sample.txt");

            Map<String, Double> result = new LinkedHashMap<>();
            int hits = 0, scanned = 0;
            int sampleCount = 0;
            final int SAMPLE_LIMIT = 100;

            Writer dbg = null;
            try {
                dbg = new OutputStreamWriter(
                    new FileOutputStream(debugFile), StandardCharsets.UTF_8);

                for (Object keyObj : Item.itemRegistry.getKeys()) {
                    String id = keyObj.toString();
                    Item item = (Item) Item.itemRegistry.getObject(id);
                    if (item == null) continue;

                    List<ItemStack> stacks = new ArrayList<>();
                    try {
                        item.getSubItems(item, item.getCreativeTab(), stacks);
                    } catch (Throwable ignored) {}
                    if (stacks.isEmpty()) {
                        stacks.add(new ItemStack(item));
                    }

                    for (ItemStack stack : stacks) {
                        if (stack == null) continue;
                        scanned++;
                        List<String> tooltip;
                        try {
                            tooltip = stack.getTooltip(mc.thePlayer, true);
                        } catch (Throwable t) {
                            continue;
                        }
                        if (tooltip == null) continue;

                        // Сохраняем первые SAMPLE_LIMIT элементов целиком для отладки
                        if (sampleCount < SAMPLE_LIMIT) {
                            sampleCount++;
                            dbg.write("=== " + id + ":" + stack.getItemDamage() + " ===\n");
                            for (String line : tooltip) {
                                dbg.write("  raw : " + line + "\n");
                                dbg.write("  bare: " + stripCodes(line) + "\n");
                            }
                            dbg.write("\n");
                        }

                        for (String line : tooltip) {
                            if (line == null) continue;
                            String clean = stripCodes(line);
                            Matcher m = PRICE_RX.matcher(clean);
                            if (m.find()) {
                                String mapKey = id + ":" + stack.getItemDamage();
                                double price = Double.parseDouble(m.group(1));
                                result.put(mapKey, price);
                                hits++;
                                break;
                            }
                        }
                    }
                }
            } catch (IOException ex) {
                sender.addChatMessage(new ChatComponentText(
                    "[PriceDump] debug write failed: " + ex.getMessage()));
            } finally {
                if (dbg != null) try { dbg.close(); } catch (IOException ignored) {}
            }

            writeJson(outFile, result, sender);

            // Дополнительно — расчёт цен по рецептам для предметов без tooltip-цены
            Map<String, Double> computed = computeFromRecipes(result);
            File computedFile = new File(mc.mcDataDir, "computed_prices.json");
            writeJson(computedFile, computed, sender);

            // Display names — для всех просканированных предметов
            Map<String, String> names = collectDisplayNames();
            File namesFile = new File(mc.mcDataDir, "display_names.json");
            writeJsonStr(namesFile, names, sender);

            sender.addChatMessage(new ChatComponentText(String.format(
                "[PriceDump] tooltip: %d/%d → %s | computed: %d → %s | names: %d → %s",
                hits, scanned, outFile.getName(),
                computed.size(), computedFile.getName(),
                names.size(), namesFile.getName()
            )));
        }

        // ── Собрать display_name для всех предметов реестра ─────────
        private static Map<String, String> collectDisplayNames() {
            Map<String, String> names = new LinkedHashMap<>();
            for (Object keyObj : Item.itemRegistry.getKeys()) {
                String id = keyObj.toString();
                Item item = (Item) Item.itemRegistry.getObject(id);
                if (item == null) continue;
                List<ItemStack> stacks = new ArrayList<>();
                try {
                    item.getSubItems(item, item.getCreativeTab(), stacks);
                } catch (Throwable ignored) {}
                if (stacks.isEmpty()) stacks.add(new ItemStack(item));
                for (ItemStack stack : stacks) {
                    if (stack == null) continue;
                    try {
                        String name = stack.getDisplayName();
                        if (name != null && !name.isEmpty()) {
                            names.put(id + ":" + stack.getItemDamage(), name);
                        }
                    } catch (Throwable ignored) {}
                }
            }
            return names;
        }

        // ── Запись Map<String, String> в JSON ────────────────────────
        private static void writeJsonStr(File f, Map<String, String> data,
                                         ICommandSender sender) {
            try (Writer w = new OutputStreamWriter(
                    new FileOutputStream(f), StandardCharsets.UTF_8)) {
                w.write("{\n");
                int i = 0, size = data.size();
                for (Map.Entry<String, String> e : data.entrySet()) {
                    String k = escapeJson(e.getKey());
                    String v = escapeJson(e.getValue());
                    w.write("  \"" + k + "\": \"" + v + "\"");
                    if (++i < size) w.write(",");
                    w.write("\n");
                }
                w.write("}\n");
            } catch (IOException ex) {
                sender.addChatMessage(new ChatComponentText(
                    "[PriceDump] write failed for " + f.getName() + ": " + ex.getMessage()));
            }
        }

        private static String escapeJson(String s) {
            if (s == null) return "";
            return s.replace("\\", "\\\\").replace("\"", "\\\"")
                    .replace("\n", "\\n").replace("\t", "\\t")
                    .replace("\r", "\\r");
        }

        // ── Запись Map в JSON-файл ────────────────────────────────────
        private static void writeJson(File f, Map<String, Double> data,
                                      ICommandSender sender) {
            try (Writer w = new OutputStreamWriter(
                    new FileOutputStream(f), StandardCharsets.UTF_8)) {
                w.write("{\n");
                int i = 0, size = data.size();
                for (Map.Entry<String, Double> e : data.entrySet()) {
                    String k = e.getKey().replace("\\", "\\\\").replace("\"", "\\\"");
                    w.write("  \"" + k + "\": " + e.getValue());
                    if (++i < size) w.write(",");
                    w.write("\n");
                }
                w.write("}\n");
            } catch (IOException ex) {
                sender.addChatMessage(new ChatComponentText(
                    "[PriceDump] write failed for " + f.getName() + ": " + ex.getMessage()));
            }
        }

        // ── Ключ ItemStack → "modid:item:meta" ──────────────────────
        private static String stackKey(ItemStack s) {
            Object name = Item.itemRegistry.getNameForObject(s.getItem());
            if (name == null) return null;
            return name + ":" + s.getItemDamage();
        }

        // ── Найти цену стака в known/computed, или через OreDict-альтернативы
        private static Double priceOf(ItemStack stack,
                                      Map<String, Double> known,
                                      Map<String, Double> computed) {
            if (stack == null || stack.getItem() == null) return null;
            String key = stackKey(stack);
            if (key == null) return null;

            Double p = known.get(key);
            if (p != null) return p;
            p = computed.get(key);
            if (p != null) return p;

            // wildcard meta или meta!=0 — пробуем :0 fallback
            if (stack.getItemDamage() != 0) {
                Object name = Item.itemRegistry.getNameForObject(stack.getItem());
                String key0 = name + ":0";
                p = known.get(key0);
                if (p != null) return p;
                p = computed.get(key0);
                if (p != null) return p;
            }

            // OreDict — минимум среди альтернатив
            try {
                int[] oreIds = OreDictionary.getOreIDs(stack);
                Double min = null;
                for (int id : oreIds) {
                    String oreName = OreDictionary.getOreName(id);
                    for (ItemStack alt : OreDictionary.getOres(oreName)) {
                        if (alt == null || alt.getItem() == null) continue;
                        String altKey = stackKey(alt);
                        if (altKey == null) continue;
                        Double ap = known.get(altKey);
                        if (ap == null) ap = computed.get(altKey);
                        if (ap != null && (min == null || ap < min)) min = ap;
                    }
                }
                return min;
            } catch (Throwable t) {
                return null;
            }
        }

        // ── Достать ингредиенты из IRecipe всех известных типов ─────
        @SuppressWarnings("unchecked")
        private static List<ItemStack> extractIngredients(IRecipe r,
                                                          Map<String, Double> known,
                                                          Map<String, Double> computed) {
            List<ItemStack> out = new ArrayList<>();
            try {
                if (r instanceof ShapedRecipes) {
                    ItemStack[] items = ((ShapedRecipes) r).recipeItems;
                    if (items != null) {
                        for (ItemStack s : items) {
                            if (s != null) out.add(s);
                        }
                    }
                } else if (r instanceof ShapelessRecipes) {
                    List<ItemStack> items = ((ShapelessRecipes) r).recipeItems;
                    if (items != null) {
                        for (ItemStack s : items) {
                            if (s != null) out.add(s);
                        }
                    }
                } else if (r instanceof ShapedOreRecipe) {
                    Object[] input = ((ShapedOreRecipe) r).getInput();
                    for (Object o : input) {
                        ItemStack picked = pickOreAlt(o, known, computed);
                        if (picked != null) out.add(picked);
                    }
                } else if (r instanceof ShapelessOreRecipe) {
                    ArrayList<Object> input = ((ShapelessOreRecipe) r).getInput();
                    for (Object o : input) {
                        ItemStack picked = pickOreAlt(o, known, computed);
                        if (picked != null) out.add(picked);
                    }
                } else {
                    return null; // незнакомый тип рецепта
                }
            } catch (Throwable t) {
                return null;
            }
            return out;
        }

        // Из OreDict-альтернативы выбрать ту, у которой уже есть цена (минимум),
        // или первую попавшуюся ItemStack если ни у одной нет цены.
        @SuppressWarnings("unchecked")
        private static ItemStack pickOreAlt(Object o,
                                            Map<String, Double> known,
                                            Map<String, Double> computed) {
            if (o == null) return null;
            if (o instanceof ItemStack) return (ItemStack) o;
            if (o instanceof List) {
                List<ItemStack> alts = (List<ItemStack>) o;
                if (alts.isEmpty()) return null;
                ItemStack best = null;
                Double bestP = null;
                for (ItemStack alt : alts) {
                    if (alt == null) continue;
                    Double p = priceOf(alt, known, computed);
                    if (p != null && (bestP == null || p < bestP)) {
                        bestP = p;
                        best = alt;
                    }
                }
                return best != null ? best : alts.get(0);
            }
            return null;
        }

        // ── Главный проход — считаем цены через рецепты ───────────────
        @SuppressWarnings("unchecked")
        private static Map<String, Double> computeFromRecipes(Map<String, Double> known) {
            Map<String, Double> computed = new LinkedHashMap<>();

            List<IRecipe> recipes;
            try {
                recipes = CraftingManager.getInstance().getRecipeList();
            } catch (Throwable t) {
                return computed;
            }

            // Многопроходный алгоритм: пока в одном проходе хоть один
            // новый предмет получает цену — продолжаем.
            for (int pass = 0; pass < 20; pass++) {
                boolean changed = false;
                for (IRecipe r : recipes) {
                    if (r == null) continue;
                    ItemStack o;
                    try { o = r.getRecipeOutput(); }
                    catch (Throwable t) { continue; }
                    if (o == null || o.getItem() == null || o.stackSize <= 0) continue;
                    String key = stackKey(o);
                    if (key == null) continue;
                    if (known.containsKey(key) || computed.containsKey(key)) continue;

                    List<ItemStack> ings = extractIngredients(r, known, computed);
                    if (ings == null || ings.isEmpty()) continue;

                    double total = 0;
                    boolean ok = true;
                    for (ItemStack ing : ings) {
                        Double p = priceOf(ing, known, computed);
                        if (p == null) { ok = false; break; }
                        total += p * Math.max(1, ing.stackSize);
                    }
                    if (ok) {
                        computed.put(key, total / o.stackSize);
                        changed = true;
                    }
                }
                if (!changed) break;
            }

            // FurnaceRecipes — переплавка: out.qty обычно 1, цена = цена input
            try {
                Map<ItemStack, ItemStack> smelting =
                    (Map<ItemStack, ItemStack>) FurnaceRecipes.smelting().getSmeltingList();
                for (Map.Entry<ItemStack, ItemStack> e : smelting.entrySet()) {
                    ItemStack out = e.getValue();
                    if (out == null || out.getItem() == null) continue;
                    String key = stackKey(out);
                    if (key == null) continue;
                    if (known.containsKey(key) || computed.containsKey(key)) continue;
                    Double p = priceOf(e.getKey(), known, computed);
                    if (p != null && out.stackSize > 0) {
                        computed.put(key, p / out.stackSize);
                    }
                }
            } catch (Throwable t) {
                FMLLog.warning("[PriceDump] smelting walk failed: " + t);
            }

            return computed;
        }
    }
}
