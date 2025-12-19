import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.tree.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

public class Link16ParserRunner {

    // ==========================================
    // ⚙️ 配置区域
    // ==========================================
    private static final String INPUT_DIR_NAME = "dsl";
    private static final String OUTPUT_DIR_NAME = "output";

    // 🎯 自定义文件选择：
    // 1. 如果列表为空 {}，程序会自动扫描 dsl 文件夹下的所有 .dsl 文件。
    // 2. 如果列表不为空，程序只处理这里指定的文件。
    // 3. 支持处理功能模型(.dsl) 和 消息规则(.dsl) 两种文件
    private static final String[] TARGET_FILES = {
//             "信息管理.dsl",
//            "平台定位与识别.dsl",
//            "平台状态.dsl",
//            "指挥控制.dsl",
//            "武器协同.dsl",
            "目标监视.dsl",
//             "J3.2_Rules.dsl"
    };
    // ==========================================

    public static void main(String[] args) {
        setupDirectories();

        // 1. 获取要处理的文件列表
        List<File> filesToProcess = getFilesToProcess();
        if (filesToProcess.isEmpty()) {
            System.err.println("⚠️ 没有找到需要处理的 DSL 文件。");
            return;
        }

        System.out.println("🚀 准备处理 " + filesToProcess.size() + " 个文件...\n");

        // 2. 循环处理
        for (File dslFile : filesToProcess) {
            parseFile(dslFile);
        }
    }

    public static ParseResult parseFile(File inputFile) {
        return run(inputFile);
    }

    public static ParseResult run(File inputFile) {
        setupDirectories();

        String baseName = getBaseName(inputFile.getName());
        File logFile = new File(OUTPUT_DIR_NAME, baseName + "解析日志.txt");
        File dotFile = new File(OUTPUT_DIR_NAME, baseName + ".dot");
        File svgFile = new File(OUTPUT_DIR_NAME, baseName + ".svg");

        // 保存原始控制台流
        PrintStream originalOut = System.out;
        PrintStream originalErr = System.err;
        ByteArrayOutputStream logBuffer = new ByteArrayOutputStream();
        List<String> errors = new ArrayList<>();
        List<SyntaxErrorDetail> syntaxErrors = new ArrayList<>();
        boolean success = false;
        String svgPath = null;
        String dotPath = null;

        // 开启双路输出 (控制台 + 日志文件)
        try (PrintStream logFileStream = new PrintStream(new FileOutputStream(logFile), true, StandardCharsets.UTF_8);
             PrintStream logBufferStream = new PrintStream(logBuffer, true, StandardCharsets.UTF_8)) {
            MultiPrintStream teeOut = new MultiPrintStream(originalOut, logFileStream, logBufferStream);
            MultiPrintStream teeErr = new MultiPrintStream(originalErr, logFileStream, logBufferStream);

            System.setOut(teeOut);
            System.setErr(teeErr);

            // === 核心处理 ===
            System.out.println("==================================================");
            System.out.println("📂 开始解析任务: " + inputFile.getName());
            System.out.println("🕒 时间: " + new java.util.Date());
            System.out.println("--------------------------------------------------");

            try {
                // ANTLR 解析准备
                CharStream input = CharStreams.fromFileName(inputFile.getAbsolutePath());
                Link16DSLLexer lexer = new Link16DSLLexer(input);
                CommonTokenStream tokens = new CommonTokenStream(lexer);
                Link16DSLParser parser = new Link16DSLParser(tokens);

                parser.removeErrorListeners();
                parser.addErrorListener(new BaseErrorListener() {
                    @Override
                    public void syntaxError(Recognizer<?, ?> recognizer, Object offendingSymbol, int line, int charPositionInLine, String msg, RecognitionException e) {
                        String error = "❌ [语法错误] 行 " + line + ":" + charPositionInLine + " -> " + msg;
                        errors.add(error);
                        SyntaxErrorDetail detail = SyntaxErrorDetail.fromSyntaxError(line, charPositionInLine, offendingSymbol, msg);
                        syntaxErrors.add(detail);
                        System.err.println(error);
                    }
                });

                ParseTree tree;
                String modeName;

                // 🧠 智能模式识别逻辑
                // 只要文件名包含 "规则" 或 "Rules"，就自动切换到消息规则解析模式
                if (inputFile.getName().contains("规则") || inputFile.getName().contains("Rules")) {
                    modeName = "消息处理规则 (Message Rules)";
                    System.out.println("ℹ️ 识别模式: " + modeName);
                    tree = parser.trRulesModel(); // 调用新入口
                } else {
                    modeName = "功能模型 (Function Model)";
                    System.out.println("ℹ️ 识别模式: " + modeName);
                    tree = parser.functionModel(); // 调用旧入口
                }

                // 结果判定
                if (parser.getNumberOfSyntaxErrors() == 0) {
                    System.out.println("✅ 语法解析通过 (Zero Syntax Errors)");

                    // 1. 调用 Visitor 提取数据
                    System.out.println("\n--- [Visitor 数据提取结果] ---");
                    Link16ModelVisitor visitor = new Link16ModelVisitor();
                    visitor.visit(tree);
                    System.out.println("------------------------------\n");

                    // 2. 生成 DOT
                    generateDotFile(tree, parser, dotFile);
                    dotPath = dotFile.getAbsolutePath();

                    // 3. 转换为 SVG
                    convertDotToSvg(dotFile, svgFile);
                    svgPath = svgFile.getAbsolutePath();

                    System.out.println("🎉 所有任务完成！");
                    System.out.println("   - 可视化图: " + svgFile.getAbsolutePath());
                    System.out.println("   - 详细日志: " + logFile.getAbsolutePath());
                    success = true;
                } else {
                    System.err.println("⛔ 解析失败，跳过后续步骤。");
                }

            } catch (IOException e) {
                System.err.println("❌ 文件读取异常: " + e.getMessage());
                errors.add("文件读取异常: " + e.getMessage());
            }
            System.out.println();
        } catch (Exception e) {
            e.printStackTrace();
            errors.add("解析异常: " + e.getMessage());
        } finally {
            // 恢复控制台
            System.setOut(originalOut);
            System.setErr(originalErr);
        }
        String logText = logBuffer.toString(StandardCharsets.UTF_8);
        String visitorOutput = extractVisitorOutput(logText);
        int errorCount = errors.size();
        return new ParseResult(success, errors, errorCount, logText, visitorOutput, dotPath, svgPath, logFile.getAbsolutePath(), syntaxErrors);
    }

    // ==========================================
    // 辅助工具方法
    // ==========================================

    private static void setupDirectories() {
        File outDir = new File(OUTPUT_DIR_NAME);
        if (!outDir.exists()) outDir.mkdirs();

        File inDir = new File(INPUT_DIR_NAME);
        if (!inDir.exists()) {
            System.err.println("❌ 错误: 请创建 '" + INPUT_DIR_NAME + "' 文件夹并放入 .dsl 文件");
            System.exit(1);
        }
    }

    private static List<File> getFilesToProcess() {
        List<File> files = new ArrayList<>();
        File inputDir = new File(INPUT_DIR_NAME);

        if (TARGET_FILES.length > 0) {
            // 使用用户自定义列表
            for (String name : TARGET_FILES) {
                File f = new File(inputDir, name);
                if (f.exists()) files.add(f);
                else System.err.println("⚠️ 警告: 指定的文件不存在 -> " + name);
            }
        } else {
            // 扫描全部
            File[] allFiles = inputDir.listFiles((dir, name) -> name.endsWith(".dsl"));
            if (allFiles != null) files.addAll(Arrays.asList(allFiles));
        }
        return files;
    }

    private static String getBaseName(String fileName) {
        return fileName.endsWith(".dsl") ? fileName.substring(0, fileName.length() - 4) : fileName;
    }

    private static void convertDotToSvg(File dotFile, File svgFile) {
        try {
            ProcessBuilder pb = new ProcessBuilder("dot", "-Tsvg", dotFile.getAbsolutePath(), "-o", svgFile.getAbsolutePath());
            pb.redirectErrorStream(true);
            Process process = pb.start();
            boolean finished = process.waitFor(15, TimeUnit.SECONDS);

            if (finished && process.exitValue() == 0) {
                // Success
            } else {
                System.err.println("   ⚠️ Graphviz 转换失败 (请检查 PATH 环境变量)");
            }
        } catch (Exception e) {
            System.err.println("   ⚠️ 无法运行 dot 命令: " + e.getMessage());
        }
    }

    private static void generateDotFile(ParseTree tree, Parser parser, File outputFile) {
        StringBuilder sb = new StringBuilder();
        sb.append("digraph G {\n");
        sb.append("  rankdir=TB;\n");
        sb.append("  splines=polyline;\n");
        sb.append("  node [shape=box, style=\"filled,rounded\", fillcolor=white, fontname=\"Microsoft YaHei\", fontsize=12, height=0.3];\n");
        sb.append("  edge [color=\"#444444\", arrowsize=0.8];\n");
        explore(tree, parser, sb);
        sb.append("}\n");
        try (FileWriter writer = new FileWriter(outputFile, StandardCharsets.UTF_8)) {
            writer.write(sb.toString());
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private static void explore(Tree tree, Parser parser, StringBuilder sb) {
        String nodeText = Trees.getNodeText(tree, parser);
        if (nodeText != null) {
            nodeText = nodeText.replace("\"", "\\\"").replace("\n", "\\n");
            if (nodeText.length() > 30) nodeText = nodeText.substring(0, 27) + "...";
        }
        int id = System.identityHashCode(tree);
        if (tree instanceof TerminalNode) {
            sb.append(String.format("  node%d [label=\"%s\", fillcolor=\"#e2f0d9\", color=\"#38761d\"];\n", id, nodeText));
        } else {
            sb.append(String.format("  node%d [label=\"%s\", fillcolor=\"#dae8fc\", color=\"#6c8ebf\"];\n", id, nodeText));
        }
        for (int i = 0; i < tree.getChildCount(); i++) {
            Tree child = tree.getChild(i);
            int childId = System.identityHashCode(child);
            sb.append(String.format("  node%d -> node%d;\n", id, childId));
            explore(child, parser, sb);
        }
    }

    private static String extractVisitorOutput(String logText) {
        String startMarker = "--- [Visitor 数据提取结果] ---";
        String endMarker = "------------------------------";
        int start = logText.indexOf(startMarker);
        if (start < 0) {
            return "";
        }
        int contentStart = logText.indexOf("\n", start + startMarker.length());
        if (contentStart < 0) {
            return "";
        }
        contentStart += 1;
        int end = logText.indexOf(endMarker, contentStart);
        if (end < 0) {
            end = logText.length();
        }
        return logText.substring(contentStart, end).trim();
    }

    // 多路输出流辅助类
    static class MultiPrintStream extends PrintStream {
        private final List<PrintStream> streams;

        public MultiPrintStream(PrintStream... streams) {
            super(OutputStream.nullOutputStream(), true, StandardCharsets.UTF_8);
            this.streams = Arrays.asList(streams);
        }

        @Override
        public void write(byte[] buf, int off, int len) {
            for (PrintStream stream : streams) {
                stream.write(buf, off, len);
            }
        }

        @Override
        public void write(int b) {
            for (PrintStream stream : streams) {
                stream.write(b);
            }
        }

        @Override
        public void flush() {
            for (PrintStream stream : streams) {
                stream.flush();
            }
        }
    }
}
