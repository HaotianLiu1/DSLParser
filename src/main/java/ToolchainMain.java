import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Collectors;

public class ToolchainMain {
    private static final Path NL_SPEC_DIR = Path.of("nl-specs");
    private static final String DEFAULT_TYPE = "功能模型";

    public static void main(String[] args) {
        ToolchainService service = new ToolchainService();
        ensureNlDir();
        List<Path> nlFiles = loadNlFiles();
        if (nlFiles.isEmpty()) {
            System.err.println("nl-specs 目录为空，请放入自然语言需求文本 (.txt)");
            return;
        }

        for (Path nlFile : nlFiles) {
            System.out.println("==== 处理文件: " + nlFile.getFileName());
            String nlSpec = readTrimmed(nlFile);
            if (nlSpec.isBlank()) {
                System.err.println("   跳过，文件内容为空: " + nlFile.getFileName());
                continue;
            }

            ToolchainResult result = service.generateAndValidate(nlSpec, DEFAULT_TYPE);
            System.out.println("success=" + result.success);
            System.out.println("log=" + result.logPath);
            System.out.println("svg=" + result.svgPath);
            if (!result.success) {
                System.err.println("failureReason=" + result.failureReason);
            }
            System.out.println();
        }
    }

    private static void ensureNlDir() {
        try {
            Files.createDirectories(NL_SPEC_DIR);
        } catch (IOException e) {
            throw new IllegalStateException("无法创建 nl-specs 目录", e);
        }
    }

    private static List<Path> loadNlFiles() {
        try {
            return Files.list(NL_SPEC_DIR)
                    .filter(Files::isRegularFile)
                    .filter(p -> p.toString().toLowerCase().endsWith(".txt"))
                    .sorted()
                    .collect(Collectors.toList());
        } catch (IOException e) {
            throw new IllegalStateException("读取 nl-specs 目录失败", e);
        }
    }

    private static String readTrimmed(Path file) {
        try {
            return Files.readString(file, StandardCharsets.UTF_8).trim();
        } catch (IOException e) {
            throw new IllegalStateException("读取文件失败: " + file.toAbsolutePath(), e);
        }
    }
}
