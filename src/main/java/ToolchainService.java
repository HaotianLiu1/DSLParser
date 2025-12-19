import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;

public class ToolchainService {
    private static final String DSL_DIR = "dsl";
    private static final String OUTPUT_DIR = "output";
    private static final Path GRAMMAR_PATH = Path.of("src", "main", "antlr4", "Link16DSL.g4");
    private static final Path LEXER_PATH = Path.of("src", "main", "antlr4", "Link16DSLLexer.g4");
    private static final Path FUNCTION_MODEL_PROMPT_PATH = Path.of(
            "src", "main", "resources", "prompts", "系统提示_功能模型_BNF.txt");
    private static final int MAX_RETRIES = 3;

    private final LlmClient llmClient;

    public ToolchainService(LlmClient llmClient) {
        this.llmClient = llmClient;
    }

    public ToolchainService() {
        this(new OpenAiLlmClient());
    }

    public ToolchainResult generateAndValidate(String nlSpec, String type) {
        ensureDirectories();
        String feedback = "";
        List<GenerationAttempt> attempts = new java.util.ArrayList<>();
        String failureReason = "";
        String baseName = buildDslFileName(type);

        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            String prompt = buildPrompt(nlSpec, type, feedback);
            String dsl = llmClient.generate(prompt, type);
            if (dsl == null || dsl.isBlank()) {
                throw new IllegalStateException("LLM 返回空 DSL 内容。");
            }

            String fileName = baseName + "-attempt-" + attempt;
            Path dslFile = Path.of(DSL_DIR).resolve(fileName + ".dsl");
            Path attemptCopy = Path.of(OUTPUT_DIR).resolve(fileName + ".dsl");
            writeDslFile(dslFile, dsl);
            writeDslFile(attemptCopy, dsl);

            ParseResult parseResult = Link16ParserRunner.parseFile(dslFile.toFile());
            writeAttemptSummary(fileName, parseResult);
            attempts.add(new GenerationAttempt(attempt, dsl, parseResult.errors, attemptCopy.toString(), parseResult.logPath));

            if (parseResult.success) {
                return new ToolchainResult(true, dsl, parseResult.logPath, parseResult.svgPath, parseResult.errors, attempts, "");
            }

            feedback = buildSyntaxFeedback(parseResult.syntaxErrors);
            if (feedback.isBlank()) {
                failureReason = String.join(System.lineSeparator(), parseResult.errors);
            } else {
                failureReason = feedback;
            }
        }

        return new ToolchainResult(false, "", "", "", List.of(failureReason), attempts, failureReason);
    }

    private String buildPrompt(String nlSpec, String type, String feedback) {
        if ("功能模型".equals(type)) {
            return buildFunctionModelPrompt(nlSpec, feedback);
        }

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

        String feedbackBlock = feedback == null || feedback.isBlank()
                ? ""
                : """
                [语法错误反馈]
                %s
                """.formatted(feedback);

        return """
                你是一个 DSL 生成助手。请根据自然语言需求生成 Link16 DSL。
                约束: 仅输出 DSL 内容，不要附加解释。
                必须严格满足 ANTLR Grammar/Lexer 语法约束，否则会被拒绝并要求重试。

                [类型]
                %s

                [Grammar]
                %s

                [Lexer]
                %s

                [Few-shot]
                %s
                %s

                [需求]
                %s
                """.formatted(type == null ? "" : type, grammar, lexer, examples, feedbackBlock, nlSpec == null ? "" : nlSpec);
    }

    private String buildFunctionModelPrompt(String nlSpec, String feedback) {
        String basePrompt = readResource(FUNCTION_MODEL_PROMPT_PATH).trim();
        String feedbackBlock = feedback == null || feedback.isBlank()
                ? ""
                : """
                [语法错误反馈]
                %s
                """.formatted(feedback);

        return """
                %s

                %s

                [需求]
                %s
                """.formatted(basePrompt, feedbackBlock, nlSpec == null ? "" : nlSpec);
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

    private void ensureDirectories() {
        try {
            Files.createDirectories(Path.of(DSL_DIR));
            Files.createDirectories(Path.of(OUTPUT_DIR));
        } catch (IOException e) {
            throw new IllegalStateException("无法创建输出目录。", e);
        }
    }

    private void writeDslFile(Path target, String dsl) {
        try {
            Files.writeString(target, dsl.trim() + System.lineSeparator(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("无法写入 DSL 文件: " + target.toAbsolutePath(), e);
        }
    }

    private void writeAttemptSummary(String fileName, ParseResult parseResult) {
        Path summaryPath = Path.of(OUTPUT_DIR).resolve(fileName + "-errors.txt");
        StringBuilder summary = new StringBuilder();
        summary.append("解析结果: ").append(parseResult.success ? "成功" : "失败").append(System.lineSeparator());
        summary.append("错误数量: ").append(parseResult.errorCount).append(System.lineSeparator());
        summary.append("错误列表:").append(System.lineSeparator());
        for (String error : parseResult.errors) {
            summary.append("- ").append(error).append(System.lineSeparator());
        }
        try {
            Files.writeString(summaryPath, summary.toString(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("无法写入错误摘要文件: " + summaryPath.toAbsolutePath(), e);
        }
    }

    private String buildSyntaxFeedback(List<SyntaxErrorDetail> syntaxErrors) {
        if (syntaxErrors == null || syntaxErrors.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder("请修正以下语法错误后重新生成：\n");
        for (SyntaxErrorDetail detail : syntaxErrors) {
            sb.append("- ").append(detail.toPromptLine()).append("\n");
        }
        return sb.toString().trim();
    }
}
