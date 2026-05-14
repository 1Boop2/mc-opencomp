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
import net.minecraft.util.ChatComponentText;
import net.minecraftforge.client.ClientCommandHandler;
import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.event.entity.EntityJoinWorldEvent;
import net.minecraftforge.event.entity.player.ItemTooltipEvent;

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

            try (Writer w = new OutputStreamWriter(
                    new FileOutputStream(outFile), StandardCharsets.UTF_8)) {
                w.write("{\n");
                int i = 0, size = result.size();
                for (Map.Entry<String, Double> e : result.entrySet()) {
                    String k = e.getKey().replace("\\", "\\\\").replace("\"", "\\\"");
                    w.write("  \"" + k + "\": " + e.getValue());
                    if (++i < size) w.write(",");
                    w.write("\n");
                }
                w.write("}\n");
            } catch (IOException ex) {
                sender.addChatMessage(new ChatComponentText(
                    "[PriceDump] write failed: " + ex.getMessage()));
                return;
            }

            sender.addChatMessage(new ChatComponentText(String.format(
                "[PriceDump] %d items with price out of %d scanned → %s | sample → %s",
                hits, scanned, outFile.getName(), debugFile.getName()
            )));
        }
    }
}
