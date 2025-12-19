import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class ToolchainCli {
    public static void main(String[] args) {
        CliOptions options = CliOptions.parse(args);
        if (options.showHelp) {
            printUsage();
            return;
        }

        String spec = resolveSpec(options);
        ToolchainService service = new ToolchainService();
        ToolchainResult result = service.generateAndValidate(spec, options.type);

        System.out.println("success=" + result.success);
        System.out.println("dslLength=" + (result.dsl == null ? 0 : result.dsl.length()));
        System.out.println("log=" + result.logPath);
        System.out.println("svg=" + result.svgPath);

        if (!result.success) {
            System.err.println("failureReason=" + result.failureReason);
            System.exit(1);
        }
    }

    private static String resolveSpec(CliOptions options) {
        if (options.spec != null && !options.spec.isBlank()) {
            return options.spec;
        }
        if (options.specFile != null && !options.specFile.isBlank()) {
            try {
                return Files.readString(Path.of(options.specFile), StandardCharsets.UTF_8);
            } catch (IOException e) {
                throw new IllegalStateException("无法读取 spec 文件: " + options.specFile, e);
            }
        }
        throw new IllegalArgumentException("缺少 --spec 或 --spec-file 参数。");
    }

    private static void printUsage() {
        System.out.println("""
                用法:
                  java -cp target/classes ToolchainCli --spec \"...\" --type \"功能模型\"
                  java -cp target/classes ToolchainCli --spec-file ./spec.txt --type \"消息规则\"

                参数:
                  --spec           直接提供自然语言需求
                  --spec-file      从文件读取自然语言需求
                  --type           类型标签 (例如: 功能模型 / 规则 / 消息规则)
                  --help           显示帮助
                """);
    }

    private static class CliOptions {
        private final String spec;
        private final String specFile;
        private final String type;
        private final boolean showHelp;

        private CliOptions(String spec, String specFile, String type, boolean showHelp) {
            this.spec = spec;
            this.specFile = specFile;
            this.type = type;
            this.showHelp = showHelp;
        }

        private static CliOptions parse(String[] args) {
            String spec = null;
            String specFile = null;
            String type = "";
            boolean showHelp = false;

            for (int i = 0; i < args.length; i++) {
                String arg = args[i];
                switch (arg) {
                    case "--spec" -> spec = readValue(arg, args, ++i);
                    case "--spec-file" -> specFile = readValue(arg, args, ++i);
                    case "--type" -> type = readValue(arg, args, ++i);
                    case "--help", "-h" -> showHelp = true;
                    default -> throw new IllegalArgumentException("未知参数: " + arg);
                }
            }
            return new CliOptions(spec, specFile, type, showHelp);
        }

        private static String readValue(String arg, String[] args, int index) {
            if (index >= args.length) {
                throw new IllegalArgumentException(arg + " 缺少参数值。");
            }
            return args[index];
        }
    }
}
