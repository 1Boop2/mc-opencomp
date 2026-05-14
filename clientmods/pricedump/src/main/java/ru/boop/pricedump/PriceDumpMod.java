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

        private static final Pattern PRICE_RX = Pattern.compile(
            "Минимальная цена:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*\\$"
        );

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

        @Override
        public void processCommand(ICommandSender sender, String[] args) {
            String relPath = args.length > 0 ? args[0] : "prices.json";

            Minecraft mc = Minecraft.getMinecraft();
            File outFile = new File(mc.mcDataDir, relPath);

            Map<String, Double> result = new LinkedHashMap<>();
            int hits = 0, scanned = 0;

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
                    for (String line : tooltip) {
                        if (line == null) continue;
                        Matcher m = PRICE_RX.matcher(line);
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
                "[PriceDump] %d items with price out of %d scanned → %s",
                hits, scanned, outFile.getAbsolutePath()
            )));
        }
    }
}
