import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;

public class ToolchainService {
    private static final String DSL_DIR = "dsl";
    private static final Path GRAMMAR_PATH = Path.of("src", "main", "antlr4", "Link16DSL.g4");
    private static final Path LEXER_PATH = Path.of("src", "main", "antlr4", "Link16DSLLexer.g4");

    private final LlmClient llmClient;

    public ToolchainService(LlmClient llmClient) {
        this.llmClient = llmClient;
    }

    public ToolchainService() {
        this(new DefaultLlmClient());
    }

    public ToolchainResult generateAndValidate(String nlSpec, String type) {
        String prompt = buildPrompt(nlSpec, type);
        String dsl = llmClient.generate(prompt, type);
        if (dsl == null || dsl.isBlank()) {
            throw new IllegalStateException("LLM 返回空 DSL 内容。");
        }

        Path dslDir = Path.of(DSL_DIR);
        try {
            Files.createDirectories(dslDir);
        } catch (IOException e) {
            throw new IllegalStateException("无法创建 DSL 目录: " + dslDir.toAbsolutePath(), e);
        }

        String fileName = buildDslFileName(type);
        Path dslFile = dslDir.resolve(fileName + ".dsl");
        try {
            Files.writeString(dslFile, dsl.trim() + System.lineSeparator(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("无法写入 DSL 文件: " + dslFile.toAbsolutePath(), e);
        }

        ParseResult parseResult = Link16ParserRunner.parseFile(dslFile.toFile());
        return new ToolchainResult(dsl, parseResult.logPath, parseResult.svgPath, parseResult.errors);
    }

    private String buildPrompt(String nlSpec, String type) {
        String grammar = readResource(GRAMMAR_PATH);
        String lexer = readResource(LEXER_PATH);
        String examples = """
                [示例 1]
                输入: 平台需要具备目标监视能力，包含搜索、跟踪和上报。
                输出:
                功能模型 目标监视 {
                    功能 搜索;
                    功能 跟踪;
                    功能 上报;
                }

                [示例 2]
                输入: 规则要求当检测到目标时自动发送告警。
                输出:
                消息处理规则 告警规则 {
                    触发 目标检测;
                    动作 发送告警;
                }
                """;

        return """
                你是一个 DSL 生成助手。请根据自然语言需求生成 Link16 DSL。
                约束: 仅输出 DSL 内容，不要附加解释。

                [类型]
                %s

                [Grammar]
                %s

                [Lexer]
                %s

                [Few-shot]
                %s

                [需求]
                %s
                """.formatted(type == null ? "" : type, grammar, lexer, examples, nlSpec == null ? "" : nlSpec);
    }

    private String readResource(Path path) {
        try {
            return Files.readString(path, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("无法读取文件: " + path.toAbsolutePath(), e);
        }
    }

    private String buildDslFileName(String type) {
        String base = (type == null || type.isBlank()) ? "generated" : type;
        base = base.replaceAll("[^\\p{IsAlphabetic}\\p{IsDigit}_-]+", "_");
        return base + "-" + Instant.now().toEpochMilli();
    }
}

class DefaultLlmClient implements LlmClient {
    @Override
    public String generate(String prompt, String type) {
        throw new IllegalStateException("未配置 LLM 客户端，请注入实际实现。");
    }
}
